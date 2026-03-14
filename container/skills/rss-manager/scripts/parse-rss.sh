#!/bin/sh
set -eu

usage() {
  echo "Usage:" >&2
  echo "  bash scripts/parse-rss.sh [fetched-feeds.json]" >&2
  echo "  bash scripts/parse-rss.sh --xml <feed.xml> --url <feed-url>" >&2
  exit 1
}

xml_file=""
source_url=""
input_file=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --xml)
      [ "$#" -ge 2 ] || usage
      xml_file="$2"
      shift 2
      ;;
    --url)
      [ "$#" -ge 2 ] || usage
      source_url="$2"
      shift 2
      ;;
    -*)
      usage
      ;;
    *)
      [ -z "$input_file" ] || usage
      input_file="$1"
      shift
      ;;
  esac
done

if [ -n "$xml_file" ] && [ -z "$source_url" ]; then
  echo "--url is required with --xml" >&2
  exit 1
fi

node --input-type=module - "$xml_file" "$source_url" "$input_file" <<'NODE'
import fs from 'node:fs';

const [xmlFile, sourceUrlArg, inputFile] = process.argv.slice(2);

function readInput() {
  if (xmlFile) {
    return {
      feeds: [
        {
          sourceUrl: sourceUrlArg,
          xml: fs.readFileSync(xmlFile, 'utf8'),
        },
      ],
      errors: [],
    };
  }

  const raw = inputFile
    ? fs.readFileSync(inputFile, 'utf8')
    : fs.readFileSync(0, 'utf8');

  return JSON.parse(raw);
}

function escapeRegex(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function decodeEntities(text) {
  return text
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&#x27;/g, "'")
    .replace(/&#(\d+);/g, (_, code) => String.fromCharCode(Number(code)))
    .replace(/&#x([0-9a-f]+);/gi, (_, code) =>
      String.fromCharCode(parseInt(code, 16)),
    );
}

function stripTags(text) {
  return decodeEntities(text)
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function extractTag(block, tagNames) {
  for (const tagName of tagNames) {
    const pattern = new RegExp(
      `<${escapeRegex(tagName)}(?:\\s[^>]*)?>([\\s\\S]*?)<\\/${escapeRegex(tagName)}>`,
      'i',
    );
    const match = block.match(pattern);
    if (match) return stripTags(match[1]);
  }
  return null;
}

function extractTags(block, tagName) {
  const pattern = new RegExp(
    `<${escapeRegex(tagName)}(?:\\s[^>]*)?>([\\s\\S]*?)<\\/${escapeRegex(tagName)}>`,
    'gi',
  );
  return [...block.matchAll(pattern)]
    .map((match) => stripTags(match[1]))
    .filter(Boolean);
}

function extractAtomLink(block) {
  const alternate = block.match(
    /<link\b[^>]*href=["']([^"']+)["'][^>]*rel=["']alternate["'][^>]*\/?>/i,
  );
  if (alternate) return alternate[1];

  const generic = block.match(/<link\b[^>]*href=["']([^"']+)["'][^>]*\/?>/i);
  if (generic) return generic[1];

  return extractTag(block, ['link']);
}

function normalizeDate(rawDate) {
  if (!rawDate) return null;
  const parsed = new Date(rawDate);
  return Number.isNaN(parsed.getTime()) ? rawDate : parsed.toISOString();
}

function parseRssFeed(xml, sourceUrl) {
  const feedTitle =
    extractTag(xml, ['channel']) &&
    extractTag(xml.match(/<channel(?:\s[^>]*)?>([\s\S]*?)<\/channel>/i)?.[1] || '', ['title']);
  const items = [...xml.matchAll(/<item(?:\s[^>]*)?>([\s\S]*?)<\/item>/gi)];

  return items.map((match) => {
    const block = match[1];
    return {
      sourceUrl,
      feedTitle: feedTitle || null,
      title: extractTag(block, ['title']),
      link: extractTag(block, ['link']),
      publishedAt: normalizeDate(extractTag(block, ['pubDate', 'dc:date', 'published', 'updated'])),
      author: extractTag(block, ['author', 'dc:creator']),
      guid: extractTag(block, ['guid']),
      summary: extractTag(block, ['description', 'summary']),
      content: extractTag(block, ['content:encoded', 'content']),
      categories: extractTags(block, 'category'),
    };
  });
}

function parseAtomFeed(xml, sourceUrl) {
  const feedMatch = xml.match(/<feed(?:\s[^>]*)?>([\s\S]*?)<\/feed>/i);
  const feedBlock = feedMatch ? feedMatch[1] : xml;
  const feedTitle = extractTag(feedBlock, ['title']);
  const entries = [...xml.matchAll(/<entry(?:\s[^>]*)?>([\s\S]*?)<\/entry>/gi)];

  return entries.map((match) => {
    const block = match[1];
    const categories = [
      ...extractTags(block, 'category'),
      ...[...block.matchAll(/<category\b[^>]*term=["']([^"']+)["'][^>]*\/?>/gi)].map(
        (m) => m[1].trim(),
      ),
    ].filter(Boolean);

    const authorBlock = block.match(/<author(?:\s[^>]*)?>([\s\S]*?)<\/author>/i)?.[1] || '';

    return {
      sourceUrl,
      feedTitle: feedTitle || null,
      title: extractTag(block, ['title']),
      link: extractAtomLink(block),
      publishedAt: normalizeDate(extractTag(block, ['updated', 'published', 'issued'])),
      author: extractTag(authorBlock, ['name']) || extractTag(block, ['author']),
      guid: extractTag(block, ['id']),
      summary: extractTag(block, ['summary', 'subtitle']),
      content: extractTag(block, ['content']),
      categories: [...new Set(categories)],
    };
  });
}

function compactArticle(article) {
  return Object.fromEntries(
    Object.entries(article).filter(([, value]) => {
      if (value == null) return false;
      if (Array.isArray(value)) return value.length > 0;
      return String(value).trim() !== '';
    }),
  );
}

const input = readInput();
const output = {
  articles: [],
  errors: Array.isArray(input.errors) ? [...input.errors] : [],
};

for (const feed of input.feeds || []) {
  try {
    const xml = String(feed.xml || '');
    const sourceUrl = feed.sourceUrl || sourceUrlArg || null;

    let articles = [];
    if (/<feed[\s>]/i.test(xml) && /<entry[\s>]/i.test(xml)) {
      articles = parseAtomFeed(xml, sourceUrl);
    } else if (/<rss[\s>]/i.test(xml) || /<channel[\s>]/i.test(xml) || /<item[\s>]/i.test(xml)) {
      articles = parseRssFeed(xml, sourceUrl);
    } else {
      throw new Error('Unrecognized feed format');
    }

    output.articles.push(...articles.map(compactArticle));
  } catch (error) {
    output.errors.push({
      sourceUrl: feed.sourceUrl || sourceUrlArg || null,
      error: error instanceof Error ? error.message : String(error),
    });
  }
}

process.stdout.write(JSON.stringify(output, null, 2));
NODE
