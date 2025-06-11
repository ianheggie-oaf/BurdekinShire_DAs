#!/usr/bin/env ruby

require "dotenv/load"
require_relative "lib/burdekin_planning_scraper"

# Run the scraper
if __FILE__ == $0
  scraper = BurdekinPlanningScraper.new
  scraper.scrape
end
