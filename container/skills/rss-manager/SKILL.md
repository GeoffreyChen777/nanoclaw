---
name: rss-manager
description: Fetch one or more user-provided RSS or Atom feed URLs, parse articles from XML into JSON, and filter the parsed articles based on the user's requirements. Use when the user wants feed monitoring, article extraction, or feed-based summaries.
---

# RSS Feed Fetching, Parsing, and Filtering

Use this skill when the user gives one or more RSS/Atom URLs and wants feed items turned into structured JSON, optionally filtered by topic, keywords, dates, source, or any other requirement.

## Bundled scripts

Use the helper scripts in `scripts/` instead of rewriting the pipeline manually:

```bash
bash scripts/fetch-rss.sh <url1> [url2...]
bash scripts/parse-rss.sh fetched.json
bash scripts/filter-rss.sh --include "ai" --since "2026-03-01" parsed.json
```

Typical pipeline:

```bash
bash scripts/fetch-rss.sh https://example.com/feed.xml https://example.com/atom.xml > /tmp/feeds.json
bash scripts/parse-rss.sh /tmp/feeds.json > /tmp/articles.json
bash scripts/filter-rss.sh --include "openai" --limit 10 /tmp/articles.json
```

Script roles:
- `scripts/fetch-rss.sh`: fetches one or more feed URLs and returns JSON with `feeds` and `errors`
- `scripts/parse-rss.sh`: parses fetched JSON into normalized article JSON objects; also supports `--xml <file> --url <feed-url>`
- `scripts/filter-rss.sh`: applies simple structured filters like include/exclude text, source, date bounds, and limit

## Core workflow

1. Confirm the inputs:
   - One or more RSS/Atom feed URLs
   - The user's filtering requirement
   - Optional output preferences like article limit, date range, or fields to include
2. Fetch the raw XML from every feed URL.
3. Parse each feed into article JSON objects.
4. Filter the parsed articles against the user's requirement.
5. Return:
   - the filtered article JSON objects
   - a short summary of what matched
   - any fetch/parse failures per URL

## Input handling

- Accept either a single URL or multiple URLs.
- If the user provides multiple feeds, keep the source feed attached to every parsed item.
- If the requirement is vague, infer a sensible filter from the user's wording instead of blocking on clarification unless the ambiguity would materially change the result.

## Parsing target

Normalize feed items into JSON objects with this shape when the data exists:

```json
{
  "sourceUrl": "https://example.com/feed.xml",
  "feedTitle": "Example Feed",
  "title": "Article title",
  "link": "https://example.com/article",
  "publishedAt": "2026-03-14T08:00:00Z",
  "author": "Author name",
  "guid": "unique-id",
  "summary": "Short summary or description",
  "content": "Full content if present",
  "categories": ["AI", "Startups"]
}
```

Rules:
- Prefer ISO-8601 for dates when you can normalize them reliably.
- Preserve the original string if a date cannot be normalized safely.
- Omit fields that do not exist instead of inventing values.
- Keep one JSON object per article.

## Filtering behavior

Filter only by the user's stated requirement. Common examples:
- keyword/topic matching in title, summary, content, or categories
- source/feed-level matching
- published date or recency
- include/exclude rules
- deduplication by `link` or `guid` when multiple feeds overlap

When filtering:
- Be conservative and easy to explain.
- If the user asks for relevance, prefer high-precision matches over broad fuzzy matches.
- If nothing matches, say that clearly and return an empty result set rather than forcing weak matches.
- Use `scripts/filter-rss.sh` for straightforward structured filtering first, then do any final semantic narrowing in-model if the user's requirement is more nuanced than keyword/date/source rules.

## Output format

Default to:
- a short summary line with match count
- the filtered articles as JSON

Example:

```json
{
  "matchedCount": 2,
  "articles": [
    {
      "sourceUrl": "https://example.com/feed.xml",
      "feedTitle": "Example Feed",
      "title": "AI startup raises new round",
      "link": "https://example.com/a1",
      "publishedAt": "2026-03-14T08:00:00Z",
      "summary": "Funding news for an AI startup"
    }
  ],
  "errors": []
}
```

If some feeds fail:
- still return successful results from other feeds
- include the failed URLs in an `errors` list with a short reason

## Practical guidance

- Fetch the XML directly from the provided URLs; do not browse the site homepage unless the feed URL fails and the user asked for recovery help.
- Handle both RSS and Atom if possible.
- If the user asks for ongoing monitoring, treat this as feed extraction first; scheduling or persistence is a separate task.
- Keep the response focused on the user's filter requirement rather than dumping every feed item unless they asked for the full parsed output.
