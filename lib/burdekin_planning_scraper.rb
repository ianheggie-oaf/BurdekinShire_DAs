# lib/burdekin_planning_scraper.rb
# Main scraper class for Burdekin Shire Council planning applications
#

require "scraperwiki"
require "mechanize"
require_relative "ai_address_extractor"

class BurdekinPlanningScraper
  BASE_URL = "https://www.burdekin.qld.gov.au".freeze

  def initialize
    @agent = Mechanize.new
    @agent.user_agent_alias = "Windows Mozilla"

    @address_extractor = AiAddressExtractor.new
    @date_scraped = Date.today.to_s
  end

  def scrape
    url = "#{BASE_URL}/Planning-building-and-development/Planning-and-Development/Development-applications/Current-development-applications"

    puts "Fetching: #{url}"
    page = @agent.get(url)

    # Find all PDF links in the related-information-list
    pdf_links = page.search("ul.related-information-list li a").select do |link|
      link["href"] && link["href"].match(/\.pdf$/i)
    end

    puts "Found #{pdf_links.length} PDF links"

    processed_count = 0
    cached_count = 0
    empty_count = 0
    skipped_count = 0

    @has_reference = {}

    pdf_links.reverse.each do |link|
      result = process_application_pdf(link, url)
      case result
      when :cached
        cached_count += 1
      when :processed
        processed_count += 1
      when :empty
        empty_count += 1
      when :skipped
        skipped_count += 1
      end
    end

    puts "Scraping completed. #{pdf_links.length} total applications: #{skipped_count} skipped, #{processed_count} processed, #{cached_count} cached, #{empty_count} without street address."
    {
      processed_count: processed_count,
      cached_count: cached_count,
      empty_count: empty_count,
      skipped_count: skipped_count,
    }
  end

  private

  def process_application_pdf(link, index_url)
    full_url = @agent.resolve(link["href"]).to_s
    full_url = "#{BASE_URL}#{full_url}" if full_url.start_with? "/"
    link_text = link.text.strip
    title = link["title"] || link_text

    title_parts = title.split(" - ", 2)
    council_reference = title_parts.first&.strip
    unless council_reference
      puts "Skipping: No council reference found in title"
      return :skipped
    end

    description = title_parts.length >= 2 ? title_parts[1..-1].join(" - ").strip : "Development Application"
    # Clean up description - remove file size info and document type suffixes
    description = description.gsub(/\s*\([^)]*\d+\s*[KMG]?B[^)]*\)\s*/, " ")
    description = description.gsub(
      /\s*-\s*(Application|Confirmation Notice|Information Request|Response|Public Notification|Lodgement Documents?)\s*$/i, ""
    )
    description = description.strip.gsub(/\s+/, " ")

    if ENV["COUNCIL_REFERENCE"] && council_reference != ENV["COUNCIL_REFERENCE"]
      puts "Skipping #{council_reference} - not #{ENV['COUNCIL_REFERENCE']}" if ENV["DEBUG"].to_i > 0
      return :skipped
    end

    puts "-" * 100 if ENV["DEBUG"]
    multiple_records = @has_reference[council_reference]
    puts "Processing: #{council_reference}#{multiple_records ? ' (Multiple records)' : ''} - #{description}",
         "\t#{full_url}"

    record = {
      "council_reference" => council_reference,
      "description" => description,
      "info_url" => multiple_records ? index_url : full_url,
      "date_scraped" => @date_scraped,
    }
    @has_reference[council_reference] = true

    # Check if we have existing record with the same title and unchanged PDF
    existing_record = get_existing_record(council_reference)
    pdf_changed = has_pdf_changed?(full_url, existing_record)
    title_changed = existing_record.nil? || existing_record["title"] != title

    if existing_record && (multiple_records || (!title_changed && !pdf_changed))
      puts "  Using cached address (PDF and title unchanged)" if ENV["DEBUG"]

      # Copy address from existing record
      record["address"] = existing_record["address"]

      # Copy caching fields if they exist
      record["pdf_etag"] = existing_record["pdf_etag"] if existing_record["pdf_etag"]
      record["pdf_last_modified"] = existing_record["pdf_last_modified"] if existing_record["pdf_last_modified"]

      ScraperWiki.save_sqlite(["council_reference"], record)
      :cached

    else
      # Need to extract address from PDF
      reason = if !existing_record
                 "new record"
               elsif title_changed
                 "title changed"
               else
                 "PDF changed"
               end

      puts "  Extracting address from PDF (#{reason})..." if ENV["DEBUG"]

      # Extract address from PDF content
      pdf_addresses, pdf_metadata = extract_addresses_with_metadata(full_url)

      # Store PDF metadata for future comparisons (only if they exist)
      record["pdf_etag"] = pdf_metadata[:etag] if pdf_metadata[:etag]
      record["pdf_last_modified"] = pdf_metadata[:last_modified] if pdf_metadata[:last_modified]

      if pdf_addresses.any?
        address = pdf_addresses.first
        has_qld = address.end_with?(" QLD") || address.include?(" QLD ")
        has_qld ||= address.end_with?(" Queensland") || address.include?(" Queensland ")
        record["address"] = has_qld ? address : "#{address}, QLD"

        puts "  ✓ Found address: #{pdf_addresses.first}"
      else
        record["address"] = ""
        puts "  Warning: no address found in PDF (recorded to avoid reprocessing pdf)"
      end

      ScraperWiki.save_sqlite(["council_reference"], record)
      sleep(1) # Be nice to the server
      pdf_addresses.any? ? :processed : :empty
    end
  end

  def has_pdf_changed?(pdf_url, existing_record)
    return true unless existing_record # No existing record = changed

    # Get current PDF headers
    current_metadata = get_pdf_metadata(pdf_url)
    return true unless current_metadata # Can't check = assume changed

    # Compare ETag first (most reliable)
    if current_metadata[:etag] && existing_record["pdf_etag"]
      return current_metadata[:etag] != existing_record["pdf_etag"]
    end

    # Fall back to Last-Modified
    if current_metadata[:last_modified] && existing_record["pdf_last_modified"]
      return current_metadata[:last_modified] != existing_record["pdf_last_modified"]
    end

    # Can't determine, assume changed
    true
  end

  def get_pdf_metadata(pdf_url)
    begin
      pdf_url = "#{BASE_URL}#{pdf_url}" if pdf_url.start_with? "/"
      puts "  DEBUG: Checking metadata for URL: #{pdf_url}" if ENV["DEBUG"]
      uri = URI(pdf_url)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        request = Net::HTTP::Head.new(uri)
        response = http.request(request)

        # Follow redirects for HEAD requests too
        case response.code
        when "301", "302", "303", "307", "308"
          return get_pdf_metadata(response["Location"]) if response["Location"]
        end

        if response.code == "200"
          return {
            etag: response["ETag"],
            last_modified: response["Last-Modified"],
          }
        end
      end
    rescue StandardError => e
      puts "  Warning: Could not get PDF metadata: #{e.message} from #{pdf_url}"
    end

    nil
  end

  def extract_addresses_with_metadata(pdf_url)
    metadata = get_pdf_metadata(pdf_url) || {}
    addresses = @address_extractor.extract_from_url(pdf_url)

    [addresses, metadata]
  end

  def get_existing_record(council_reference)
    result = ScraperWiki.select("* from data where council_reference = ?", [council_reference])
    result.first
  rescue StandardError
    nil
  end
end
