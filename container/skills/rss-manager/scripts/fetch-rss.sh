#!/bin/sh
set -eu

if [ "$#" -lt 1 ]; then
  echo "Usage: bash scripts/fetch-rss.sh <feed-url> [feed-url...]" >&2
  exit 1
fi

node --input-type=module - "$@" <<'NODE'
const urls = process.argv.slice(2);

const results = { feeds: [], errors: [] };

for (const sourceUrl of urls) {
  try {
    const response = await fetch(sourceUrl, {
      redirect: 'follow',
      signal: AbortSignal.timeout(30000),
      headers: {
        'user-agent': 'nanoclaw-rss-manager/1.0',
        'accept': 'application/rss+xml, application/atom+xml, application/xml, text/xml;q=0.9, */*;q=0.1',
      },
    });

    if (!response.ok) {
      results.errors.push({
        sourceUrl,
        error: `HTTP ${response.status} ${response.statusText}`.trim(),
      });
      continue;
    }

    results.feeds.push({
      sourceUrl,
      status: response.status,
      contentType: response.headers.get('content-type') || null,
      xml: await response.text(),
    });
  } catch (error) {
    results.errors.push({
      sourceUrl,
      error: error instanceof Error ? error.message : String(error),
    });
  }
}

process.stdout.write(JSON.stringify(results, null, 2));
NODE
