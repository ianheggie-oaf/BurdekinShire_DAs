# spec/support/webmock_burdekin_fixtures.rb

require "webmock"

module WebmockBurdekinFixtures
  extend WebMock::API

  FIXTURES_PATH = File.expand_path("spec/fixtures/site-2025-06-09")

  BASE_URL = "https://www.burdekin.qld.gov.au"
  # Main page URL
  CURRENT_APPLICATIONS_URL = "#{BASE_URL}/Planning-building-and-development/Planning-and-Development/Development-applications/Current-development-applications"

  # Base URL for PDF downloads
  PDF_BASE_URL = "#{BASE_URL}/files/assets/public/v/1/planning-and-development/documents/development-applications"

  def self.setup_webmock_stubs
    # Stub the main applications index page
    stub_request(:get, CURRENT_APPLICATIONS_URL)
      .to_return(
        status: 200,
        body: File.read(File.join(FIXTURES_PATH, "index.html")),
        headers: {
          "Content-Type" => "text/html; charset=utf-8",
          "ETag" => '"index-2025-06-09"',
          "Last-Modified" => "Mon, 09 Jun 2025 00:00:00 GMT",
        }
      )

    # Stub all PDF files based on what's in the fixtures directory
    setup_pdf_stubs
  end

  def self.setup_pdf_stubs
    # Get all PDF files in fixtures directory

    pdf_files.each do |pdf_filename|
      pdf_url = "#{PDF_BASE_URL}/#{pdf_filename}"
      pdf_path = File.join(FIXTURES_PATH, pdf_filename)

      # Stub the HEAD request
      stub_request(:head, pdf_url)
        .with(
          headers: {
            "Accept" => "*/*",
            "Accept-Encoding" => "gzip;q=1.0,deflate;q=0.6,identity;q=0.3",
            "Host" => "www.burdekin.qld.gov.au",
            "User-Agent" => "Ruby",
          }
        )
        .to_return(status: 200, body: "", headers: {})
      # Stub the PDF download
      stub_request(:get, pdf_url)
        .to_return(
          status: 200,
          body: File.read(pdf_path),
          headers: {
            "Content-Type" => "application/pdf",
            "Content-Length" => File.size(pdf_path).to_s,
            "ETag" => %("#{pdf_filename}-2025-06-09"),
            "Last-Modified" => "Mon, 09 Jun 2025 00:00:00 GMT",
            "Content-Disposition" => "inline; filename=\"#{pdf_filename}\"",
          }
        )
    end

    puts "WebMock: Stubbed #{pdf_files.count} PDF files from fixtures"
  end

  def self.unstub_all
    WebMock.reset!
  end

  def self.pdf_files
    Dir.glob(File.join(FIXTURES_PATH, "*.pdf")).map { |f| File.basename(f) }
  end
end

# Auto-setup for RSpec
RSpec.configure do |config|
  config.before(:each, :webmock_burdekin) do
    WebmockBurdekinFixtures.setup_webmock_stubs
  end

  config.after(:each, :webmock_burdekin) do
    WebmockBurdekinFixtures.unstub_all
  end
end

# Usage in specs:
#
# RSpec.describe SomeClass, :webmock_burdekin do
#   it "downloads PDFs" do
#     # Your test code here - all URLs will be mocked
#   end
# end
#
# Or manually:
# WebmockBurdekinFixtures.setup_webmock_stubs
