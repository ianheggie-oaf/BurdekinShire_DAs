# frozen_string_literal: true

require "json"
require "anthropic"
require_relative "pdf_text_extractor"

class AiAddressExtractor
  def initialize
    @text_extractor = PdfTextExtractor.new
    @prompt_template = load_prompt_template
  end

  def extract_from_url(pdf_url, retry_request: true)
    pdf_text = @text_extractor.extract_text_from_url(pdf_url)

    if pdf_text.empty?
      puts "  No text could be extracted from PDF" if ENV["DEBUG"]
      raise "retrying pdf download and extraction (no text detected)" if retry_request

      return []
    end

    filename = extract_filename(pdf_url)

    # Truncate text if too large (keep under ~40KB for token efficiency)
    clean_text = clean_and_truncate_text(pdf_text)

    ai_response = call_ai_api(clean_text, filename, !retry_request)

    parse_addresses(ai_response)
  rescue StandardError => e
    raise unless retry_request

    puts "Retrying in 30 seconds - due to: #{e}"
    sleep(30)
    extract_from_url(pdf_url, retry_request: false)
  end

  private

  def load_prompt_template
    template_path = File.join(File.dirname(__FILE__), "..", "config", "ai_address_prompt.txt")
    File.read(template_path)
  end

  def extract_filename(pdf_url)
    File.basename(pdf_url, ".pdf").gsub(/_+/, " ")
  end

  def clean_and_truncate_text(text)
    # Remove excessive whitespace
    cleaned = text.gsub(/\s+/, " ").strip

    # Truncate if too large (aim for ~40KB to stay well under token limits)
    if cleaned.length > 40_000
      puts "  Truncating large PDF text (#{cleaned.length} chars)" if ENV["DEBUG"]
      cleaned = cleaned[0, 40_000] + "\n[... text truncated ...]"
    end

    cleaned
  end

  def call_ai_api(text, filename, retrying)
    client = Anthropic::Client.new(
      access_token: ENV.fetch("MORPH_ANTHROPIC_API_KEY") do
        raise "MORPH_ANTHROPIC_API_KEY environment variable required"
      end
    )

    retry_message = if retrying
                      "\n\nIMPORTANT: This is second attempt! " \
                        "Double check your response matches the exact JSON format specified above. " \
                        "The previous attempt failed to parse - ensure you return only valid JSON with no extra text or formatting."
                    else
                      ""
                    end
    prompt = @prompt_template.sub("FILENAME", filename).sub("RETRY_MESSAGE", retry_message) + "\n\n" + text

    response = client.messages(
      parameters: {
        model: ENV.fetch("MORPH_AI_MODEL", "claude-3-sonnet-20240229"),
        max_tokens: ENV.fetch("MORPH_AI_MAX_TOKENS", "1000").to_i,
        temperature: ENV.fetch("MORPH_AI_TEMPERATURE", "0").to_i,
        messages: [
          {
            role: "user",
            content: prompt,
          },
        ],
      }
    )

    response.dig("content", 0, "text") || ""
  end

  def parse_addresses(ai_response)
    return [] if ai_response.empty?

    # Try to extract JSON from response
    json_match = ai_response.match(/\{.*\}/m)
    return [] unless json_match

    parsed = JSON.parse(json_match[0])
    addresses_data = parsed["addresses"] || []

    # Convert to simple array of address strings (preserve existing interface)
    addresses = addresses_data.map { |addr_data| addr_data["address"] }.compact

    # Log confidence scores if debugging
    if ENV["DEBUG"] && addresses_data.any?
      addresses_data.each do |addr_data|
        puts "  AI found: #{addr_data['address']} (confidence: #{addr_data['confidence']}%)"
      end
    end

    addresses
  rescue JSON::ParserError => e
    puts "Failed to parse AI JSON response: #{e.message}"
    puts "Response was: #{ai_response[0, 200]}..." if ENV["DEBUG"]
    raise
  end
end
