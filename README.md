Welcome to the Burdekin, sugar capital of Australia and one of the most prosperous rural communities in the country.
It's also one of the prettiest districts along the Queensland coast and boasts a stable population of warm, 
friendly and down-to-earth residents.

Unfortunately as noted in issue [Burdekin Shire Council #87](https://github.com/planningalerts-scrapers/issues/issues/87)
since 2021 the page doesn't have addresses on it.
That information is buried in the linked pdfs that do not have a consistent format. 

The pdf list is: http://www.burdekin.qld.gov.au/building-planning-and-infrastructure/town-planning/current-development-applications/

We now call Claude AI API call to extract the site address from the text in pdf files.

This scraper runs on [Morph](https://morph.io). To get started [see the documentation](https://morph.io/documentation)

Add any issues to https://github.com/planningalerts-scrapers/issues/issues

## To run the scraper

```
bundle exec ruby scraper.rb
```

## To run style and coding checks

```
bundle exec rubocop
```

