# frozen_string_literal: true

require "timecop"

RSpec.describe BurdekinPlanningScraper do
  before do
    # When the fixtures/site-2025-06-09 was grabbed
    Timecop.freeze(Time.local(2025, 6, 9))
  end

  after do
    Timecop.return
  end

  describe ".scrape", :webmock_burdekin do
    after do
      ENV.delete("COUNCIL_REFERENCE")
    end

    def test_ml_extraction(council_ref, expected_good_addresses, expected_bad_addresses = [])
      ENV["COUNCIL_REFERENCE"] = council_ref
      if File.exist?("./data.sqlite")
        ScraperWiki.close_sqlite
        File.delete("./data.sqlite")
      end
      VCR.use_cassette("scrape-#{council_ref}") do
        results = BurdekinPlanningScraper.new.scrape
        expect(results[:processed_count]).to eq(1),
                                             "Expected one not #{results[:processed_count]} record to be processed"
      end

      results = begin
        ScraperWiki.select("* from data order by council_reference")
      ensure
        ScraperWiki.close_sqlite
      end

      # Check that we found the expected good addresses
      found_addresses = results.map { |r| r["address"] }.compact
      expect(found_addresses.size).to eq(1), "Expected exactly one record to be created"
      expected_good_addresses.each do |expected_addr|
        expect(found_addresses).to include(expected_addr)
      end
      expect(found_addresses).to be_empty if expected_good_addresses.empty?
      expect(found_addresses.size).to eq(expected_good_addresses.size)

      # Check that we didn't find any bad addresses
      expected_bad_addresses.each do |bad_addr|
        expect(found_addresses).not_to include(bad_addr)
      end
    rescue SqliteMagic::NoSuchTable
      raise unless expected_good_addresses.empty? && expected_bad_addresses.empty?
    end

    it "extracts address from RAL24/0008" do
      test_ml_extraction("RAL24/0008", ["1 Mulgrave Road, Ayr QLD 4807"], []) # NONE expected
    end

    it "extracts MCU24/0005 addresses" do
      test_ml_extraction("MCU24/0005", ["239 Queen Street, Ayr QLD 4807"], [])
    end

    it "extracts MCU23/0013 addresses" do
      test_ml_extraction("MCU23/0013", ["5 Little Drysdale Street & 177 Macmillan Street, Ayr QLD 4807"], [])
    end

    it "extracts MCU24/0008 addresses" do
      test_ml_extraction("MCU24/0008", ["Lot 1 RP 700388 Parish of Jarvisfield, Jarvisfield, QLD"], []) # NONE expected
    end

    it "extracts MCU23/0016 addresses" do
      test_ml_extraction("MCU23/0016", ["182 and 213 Homestead Road, Fredericksfield, QLD"], [])
    end

    it "extracts MCU24/0005 addresses" do
      test_ml_extraction("MCU24/0005", ["239 Queen Street, Ayr QLD 4807"], [])
    end

    it "extracts MCU24/0006 addresses" do
      test_ml_extraction("MCU24/0006", ["829 Keith Venables Road, Upper Haughton, QLD"], []) # NONE expected (Lot#)
    end

    it "extracts MCU24/0017 addresses" do
      test_ml_extraction("MCU24/0017", ["194 Phillips Camp Road, Jarvisfield, QLD"], [])
    end

    it "extracts RAL24/0014 addresses" do
      test_ml_extraction("RAL24/0014", ["512 Hurney Road, Osborne, QLD"], [])
    end

    it "extracts RAL24/0015 addresses" do
      test_ml_extraction("RAL24/0015", ["4225 Ayr Dalbeg Road, Mulgrave, QLD"], [])
    end

    it "extracts RAL24/0016 addresses" do
      test_ml_extraction("RAL24/0016", ["342 School Road and 348 McDonald Road, Clare QLD 4807"], [])
    end

    it "extracts RAL24/0017 addresses" do
      test_ml_extraction("RAL24/0017", ["206 & 226 Airdmillan Road, Airdmillan, QLD"], [])
    end

    it "extracts MCU24/0009 addresses" do
      test_ml_extraction("MCU24/0009", ["275 & 223 Comiskey Road, Horseshoe Lagoon, QLD"], [])
    end

    it "scrapes pdfs better than scrape" do
      if File.exist?("./data.sqlite")
        ScraperWiki.close_sqlite
        File.delete("./data.sqlite")
      end
      cassette = "scrape_everything"
      VCR.use_cassette(cassette) do
        BurdekinPlanningScraper.new.scrape
      end

      expected = if File.exist?("spec/expected/#{cassette}.yml")
                   YAML.safe_load(File.read("spec/expected/#{cassette}.yml"))
                 else
                   []
                 end
      results = begin
        ScraperWiki.select("* from data order by council_reference")
      ensure
        ScraperWiki.close_sqlite
      end

      ScraperWiki.close_sqlite

      if results != expected
        # Overwrite expected so that we can compare with version control
        # (and maybe commit if it is correct)
        FileUtils.mkdir_p "spec/expected"
        File.open("spec/expected/#{cassette}.yml", "w") do |f|
          f.write(results.to_yaml)
        end
      end

      expect(results).to eq expected

      total = WebmockBurdekinFixtures.pdf_files.size
      addresses = results.map { |rec| rec["address"] }.sort

      addresses_with_street_types = addresses.select do |a|
        a.match(/\b(Highway|Street|STREET|Road|PL|St|Rd|Avenue)\b/)
      end
      addresses_with_lga_suburbs = addresses.select do |a|
        a.match(/\b(airdmillan|airville|alva|ayr|barratta|brandon|carstairs|clare|colevale|cromarty|dalbeg|fredericksfield|giru|inkerman|jarvisfield|jerona|kirknie|mcdesme|millaroo|mulgrave|osborne|rangemore|shirbourne|wangaratta|wunjunga|home hill|upper haughton|mount kelly|mount surround|mona park|majors creek|groper creek|eight mile creek|horseshoe lagoon|rita island|swans lagoon)\b/i)
      end

      # puts "Addresses:", addresses.to_yaml
      puts "Without street_types:", (addresses - addresses_with_street_types).to_yaml
      puts "Without lga suburbs:", (addresses - addresses_with_lga_suburbs).to_yaml

      percent_addresses = (addresses.size * 100.0 / total).round(2)
      percent_addresses_with_street_types = (addresses_with_street_types.size * 100.0 / addresses.size).round(2)
      percent_addresses_with_lga_suburbs = (addresses_with_lga_suburbs.size * 100.0 / addresses.size).round(2)
      puts "#{percent_addresses}% pdfs have addresses"
      puts "#{percent_addresses_with_street_types}% addresses have street types"
      puts "#{percent_addresses_with_lga_suburbs}% addresses have lga suburbs"

      expect(percent_addresses_with_street_types).to be > 95.0, "Wanted > 95% of addresses to have street types"
      expect(percent_addresses_with_lga_suburbs).to be > 95.0, "Wanted > 95% of addresses to have lga suburbs"
      expect(percent_addresses).to be >= 71, "Wanted > 71% of pdfs to have addresses"
    end
  end
end
