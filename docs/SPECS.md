# Scraper AI ADDRESS EXTRACTION - SPECIFICATIONS

See Also:
- IMPLEMENTATION.md - Implementation decisions made
- README.md - Setup and usage

## Project Overview

Burdekin Shire Council planning application scraper that extracts site addresses from planning application PDFs using AI API for document understanding.

## Core Requirements

- **Primary Objective**: Extract application addresses from development application PDFs
- **Success Criteria**:
    - 90%+ PDFs identified with addresses where geocodable address specified
    - 95%+ accuracy on addresses extracted (correct site address, not consultant/builder addresses)
    - Addresses geocoded so no particular format required, aside from having suburb and appending QLD if Queensland not present
    - Council and consultant addresses excluded by AI understanding of context
- **Quality over Quantity**: Better to extract no address than wrong address (high precision preferred)
- **Target Format**: "123 Street Name, Suburb" or "123 Street Name, Suburb QLD 4XXX"

**Current baseline**: Previous hard-coded approach extracted 7 geocodable addresses from 46 applications (15% success rate). Target: 40+ addresses from 46 applications (87%+ success rate).

## AI API Approach

**Simple Two-Component System**

1. **PDF Text Extraction**: Extract clean text without layout formatting
2. **AI Document Understanding**: Use structured prompt to identify site addresses with confidence scores

**Key Principle**: Leverage AI's natural language understanding rather than pattern matching.

## Configuration Files

### config/ai_address_prompt.txt

Contains the structured prompt template with FILENAME token for replacement.

### Environment Variables

- `MORPH_ANTHROPIC_API_KEY` - Required API key for Anthropic Claude
- `MORPH_AI_MODEL` - Optional model override (default: claude-3-sonnet-20240229)
- `MORPH_AI_MAX_TOKENS` - Optional response limit (default: 1000)

## Implementation

### File Organization

```
lib/
├── ai_address_extractor.rb       # Main AI interface (replaces MlPdfAddressExtractor)
├── pdf_text_extractor.rb         # Text extraction (remove -layout flag)
└── burdekin_planning_scraper.rb  # Main scraper (unchanged interface)

config/
└── ai_address_prompt.txt         # AI prompt template
```

### Integration with Existing Scraper

- `AiAddressExtractor` is a drop-in replacement for existing `PdfAddressExtractor`
- Same interface: `extract_from_url(pdf_url)`
- Uses `config/ai_address_prompt.txt` for structured prompting
- Returns array of address strings (same as existing)

### Data Storage

Existing SQLite schema 
- add records where no address was found so we don't keep processing pdfs
- Add address_confidence for analysis

### Performance Parameters

- **AI Response**: JSON format with address and confidence
- **Error Handling**: Retry once after a 30 second delay on AI/network/missing JSON errors, abort if the error occurs twice in a row
- **JSON parsing**:

## Environment Behavior

### Production Mode (Morph.io)

- **API Calls**: Real Anthropic API calls
- **Error Handling**: Log errors, continue scraping other PDFs
- **Rate Limiting**: Respect API rate limits

### Development Mode

- **Local Testing**: Use same API (small cost for development)
- **Debugging**: Log AI responses for analysis
- **Fixtures**: Test with known PDF examples

## Success Metrics

- **Primary**: F1-score on test set (developer-verified examples)
- **Secondary**: Precision (avoid false positives)
- **Tertiary**: Recall (find all real addresses)
- **Cost**: Under $1 for full 46 PDF processing

## Risk Mitigation

### API Failure Handling
- **Network errors**: Return empty array, log error, continue
- **Invalid JSON**: Parse what's possible, log malformed response
- **Rate limiting**: Implement simple backoff

### Cost Management
- **Token limits**: Truncate large PDFs if needed
- **Model selection**: Use cost-effective model (Claude Sonnet)
- **Monitoring**: Track API usage

## Future Enhancements

If AI API approach proves successful:
- **Batch processing**: Multiple PDFs per API call
- **Local model**: Self-hosted option for cost reduction
- **Confidence tuning**: Adjust confidence thresholds based on results
