# Gemini Prompts History

## Original Structured Summary Prompt (JSON Format)

This prompt was designed to extract structured information with quick facts and a detailed story.

```
Your SOLE task is to analyze the provided news article content and extract specific information.

Article Content:
"""
[ARTICLE TEXT HERE]
"""

Instructions:
1. Read the "Article Content" carefully.
2. Focus ONLY on the main textual content of the article. Ignore sidebars, navigation links, advertisements, comments, and other non-article elements.
3. Extract the information requested in the JSON format below.
4. For "quickFacts", provide concise answers. If a specific piece of information for a quickFact is not clearly available in the article, use "N/A".
5. For "theStory", provide a two-paragraph summary based EXCLUSIVELY on the provided "Article Content".

Response Format (JSON Object ONLY):
- If you can successfully extract the information and summarize the "Article Content":
  {
    "quickFacts": {
      "whatHappened": "Brief description of the core event.",
      "who": "Main people or organizations involved.",
      "whenWhere": "Time and location of the event.",
      "keyNumbers": "Any significant numbers, statistics, or monetary amounts, or 'N/A'.",
      "mostStrikingDetail": "The most interesting or surprising single fact from the article."
    },
    "theStory": "Your two-paragraph summary here. The first paragraph should cover the main event and immediate context. The second paragraph should provide background or broader implications if available in the text."
  }
- If the provided "Article Content" is insufficient, unclear, not a news article, or if you cannot reasonably extract the required fields:
  Respond ONLY with this exact JSON object:
  {
    "error": "The provided content could not be processed to extract the required information or generate a news summary."
  }
ABSOLUTELY DO NOT provide 'quickFacts' or 'theStory' if you are returning an 'error'. Do NOT use external knowledge.
Your response MUST be one of these two JSON structures.
```

## Current Simple Prompt (Plain Text)

```
Summarize the following article in approximately 200-300 words. 
Focus on the key facts, main events, and important context.
Write in clear, conversational language suitable for text-to-speech.
Do not include any JSON, markdown, or formatting - just plain text.

Article:
[ARTICLE TEXT]

Summary:
```

## Proposed Enhanced Prompt (Plain Text with Structure)

This combines the structured extraction with plain text output for reliability:

```
Analyze this article and provide a summary that cuts through any clickbait to deliver the core facts.

Article:
[ARTICLE TEXT]

Create a summary (200-300 words) that includes:
1. WHO is involved (key people, organizations)
2. WHAT actually happened (the real story behind the headline)
3. WHEN and WHERE it occurred
4. WHY it matters (context and implications)
5. KEY NUMBERS or statistics if relevant

Start with the most important fact that the headline might be hiding or sensationalizing. 
Write in clear, conversational language suitable for text-to-speech.
Avoid speculation - stick to facts presented in the article.
```