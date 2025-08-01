#!/bin/bash

# Script to test Firecrawl API
echo "🔍 Testing Firecrawl API..."

# You'll need to set your Firecrawl API key here or pass it as an argument
FIRECRAWL_API_KEY="${1:-YOUR_API_KEY_HERE}"

if [ "$FIRECRAWL_API_KEY" = "YOUR_API_KEY_HERE" ]; then
    echo "❌ Please provide your Firecrawl API key as an argument:"
    echo "   ./test-firecrawl.sh YOUR_ACTUAL_API_KEY"
    exit 1
fi

# Test URL - using a simple, fast-loading page
TEST_URL="https://example.com"

echo "📡 Testing Firecrawl with URL: $TEST_URL"
echo "🔑 Using API key: ${FIRECRAWL_API_KEY:0:10}..."

# Make the request
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST https://api.firecrawl.dev/v0/scrape \
  -H "Authorization: Bearer $FIRECRAWL_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "url": "'"$TEST_URL"'",
    "formats": ["markdown", "html"],
    "onlyMainContent": true,
    "includeHtml": true,
    "includeMarkdown": true,
    "waitFor": 5000,
    "screenshot": false
  }')

# Extract HTTP status code (last line)
HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)
# Extract JSON response (all but last line)
JSON_RESPONSE=$(echo "$RESPONSE" | head -n -1)

echo "📊 HTTP Status: $HTTP_STATUS"

if [ "$HTTP_STATUS" -eq 200 ]; then
    echo "✅ Firecrawl API is working!"
    
    # Pretty print the response if jq is available
    if command -v jq &> /dev/null; then
        echo "📄 Response:"
        echo "$JSON_RESPONSE" | jq '.'
    else
        echo "📄 Raw Response:"
        echo "$JSON_RESPONSE"
    fi
else
    echo "❌ Firecrawl API request failed!"
    echo "📄 Error Response:"
    echo "$JSON_RESPONSE"
    
    # Common error codes
    case $HTTP_STATUS in
        401)
            echo "🔐 Error: Invalid API key"
            ;;
        429)
            echo "⏰ Error: Rate limit exceeded"
            ;;
        500|502|503)
            echo "🔥 Error: Firecrawl server error"
            ;;
        000)
            echo "🌐 Error: Network timeout or connection failed"
            ;;
    esac
fi

# Test with a Reddit URL too
echo ""
echo "📡 Testing with a Reddit URL..."
REDDIT_URL="https://www.reddit.com/r/technology/comments/1234567/example"

REDDIT_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST https://api.firecrawl.dev/v0/scrape \
  -H "Authorization: Bearer $FIRECRAWL_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "url": "'"$REDDIT_URL"'",
    "formats": ["markdown"],
    "onlyMainContent": true,
    "waitFor": 5000
  }')

REDDIT_STATUS=$(echo "$REDDIT_RESPONSE" | tail -n 1)
echo "📊 Reddit URL HTTP Status: $REDDIT_STATUS"

# Measure response time
echo ""
echo "⏱️  Measuring API response time..."
curl -s -o /dev/null -w "Response time: %{time_total}s\n" \
  --max-time 10 \
  -X POST https://api.firecrawl.dev/v0/scrape \
  -H "Authorization: Bearer $FIRECRAWL_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://example.com",
    "formats": ["markdown"],
    "onlyMainContent": true
  }'