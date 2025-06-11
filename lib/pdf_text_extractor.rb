# pdf_address_extractor.rb
# Extracts addresses from Burdekin Shire Council planning application PDFs
# Uses pdftotext (available via poppler-utils in morph.io)

require "open3"
require "tempfile"
require "net/http"
require "uri"

class PdfTextExtractor
  def extract_text_from_url(pdf_url, redirection_count = 0)
    # Download PDF to temporary file and extract text
    uri = URI(pdf_url)

    # Download PDF with redirect following
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
      request = Net::HTTP::Get.new(uri)
      response = http.request(request)

      # Follow redirects
      case response.code
      when "301", "302", "303", "307", "308"
        if response["Location"]
          if redirection_count > 10
            puts "WARNING: Redirected #{redirection_count} times - cannot get pdf from #{pdf_url}!"
            return ""
          end
          redirect_url = response["Location"]
          redirect_url = "#{BurdekinPlanningScraper::BASE_URL}#{redirect_url}" if redirect_url.start_with? "/"
          puts "  Following redirect to: #{redirect_url}" if ENV["DEBUG"]
          return extract_text_from_url(redirect_url, redirection_count + 1)
        end
      when "200"
        # Write to temporary file
        temp_file = Tempfile.new(%w[planning_app .pdf])
        temp_file.binmode
        temp_file.write(response.body)
        temp_file.close

        # Extract text
        text = extract_text_from_pdf(temp_file.path)
        temp_file.unlink
        return text
      else
        puts "Failed to download PDF: HTTP #{response.code}"
        return ""
      end
    end
  rescue StandardError => e
    puts "Error downloading PDF from #{pdf_url}: #{e.message}"
    ""
  end

  private

  def extract_text_from_pdf(pdf_path)
    # Use pdftotext which is available in morph.io via poppler-utils
    stdout, stderr, status = Open3.capture3("pdftotext", pdf_path, "-")

    return stdout if status.success?

    puts "Error extracting text from #{pdf_path}: #{stderr}"
    ""
  rescue StandardError => e
    puts "Error running pdftotext: #{e.message}"
    ""
  end
end
