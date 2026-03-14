#!/bin/sh
set -eu

usage() {
  echo "Usage: bash scripts/filter-rss.sh [options] [parsed-articles.json]" >&2
  echo "Options:" >&2
  echo "  --include <text>   Match text in title/summary/content/categories (repeatable)" >&2
  echo "  --exclude <text>   Exclude text matches (repeatable)" >&2
  echo "  --source <text>    Match feed title or source URL (repeatable)" >&2
  echo "  --since <date>     Keep articles on or after this date/time" >&2
  echo "  --until <date>     Keep articles on or before this date/time" >&2
  echo "  --limit <n>        Return at most n articles" >&2
  exit 1
}

json_file=""
include_terms=""
exclude_terms=""
source_terms=""
since=""
until=""
limit=""

append_term() {
  value="$1"
  list="$2"
  if [ -z "$list" ]; then
    printf '%s' "$value"
  else
    printf '%s\n%s' "$list" "$value"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --include)
      [ "$#" -ge 2 ] || usage
      include_terms="$(append_term "$2" "$include_terms")"
      shift 2
      ;;
    --exclude)
      [ "$#" -ge 2 ] || usage
      exclude_terms="$(append_term "$2" "$exclude_terms")"
      shift 2
      ;;
    --source)
      [ "$#" -ge 2 ] || usage
      source_terms="$(append_term "$2" "$source_terms")"
      shift 2
      ;;
    --since)
      [ "$#" -ge 2 ] || usage
      since="$2"
      shift 2
      ;;
    --until)
      [ "$#" -ge 2 ] || usage
      until="$2"
      shift 2
      ;;
    --limit)
      [ "$#" -ge 2 ] || usage
      limit="$2"
      shift 2
      ;;
    -*)
      usage
      ;;
    *)
      [ -z "$json_file" ] || usage
      json_file="$1"
      shift
      ;;
  esac
done

node --input-type=module - "$json_file" "$include_terms" "$exclude_terms" "$source_terms" "$since" "$until" "$limit" <<'NODE'
import fs from 'node:fs';

const [jsonFile, includeRaw, excludeRaw, sourceRaw, sinceRaw, untilRaw, limitRaw] =
  process.argv.slice(2);

const raw = jsonFile ? fs.readFileSync(jsonFile, 'utf8') : fs.readFileSync(0, 'utf8');
const input = JSON.parse(raw);

const includeTerms = includeRaw ? includeRaw.split('\n').filter(Boolean) : [];
const excludeTerms = excludeRaw ? excludeRaw.split('\n').filter(Boolean) : [];
const sourceTerms = sourceRaw ? sourceRaw.split('\n').filter(Boolean) : [];
const limit = limitRaw ? Number(limitRaw) : null;

function parseDate(value) {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.getTime();
}

const since = parseDate(sinceRaw);
const until = parseDate(untilRaw);

function articleText(article) {
  return [
    article.feedTitle,
    article.title,
    article.summary,
    article.content,
    ...(article.categories || []),
  ]
    .filter(Boolean)
    .join('\n')
    .toLowerCase();
}

function sourceText(article) {
  return [article.feedTitle, article.sourceUrl].filter(Boolean).join('\n').toLowerCase();
}

function matchesAllTerms(text, terms) {
  return terms.every((term) => text.includes(term.toLowerCase()));
}

function matchesAnyTerms(text, terms) {
  return terms.some((term) => text.includes(term.toLowerCase()));
}

const articles = Array.isArray(input.articles) ? input.articles : [];

const filtered = articles.filter((article) => {
  const text = articleText(article);
  const source = sourceText(article);
  const publishedAt = parseDate(article.publishedAt);

  if (includeTerms.length > 0 && !matchesAllTerms(text, includeTerms)) {
    return false;
  }
  if (excludeTerms.length > 0 && matchesAnyTerms(text, excludeTerms)) {
    return false;
  }
  if (sourceTerms.length > 0 && !matchesAllTerms(source, sourceTerms)) {
    return false;
  }
  if (since !== null && publishedAt !== null && publishedAt < since) {
    return false;
  }
  if (until !== null && publishedAt !== null && publishedAt > until) {
    return false;
  }

  return true;
});

const limited = Number.isFinite(limit) && limit >= 0 ? filtered.slice(0, limit) : filtered;

process.stdout.write(
  JSON.stringify(
    {
      matchedCount: limited.length,
      articles: limited,
      errors: Array.isArray(input.errors) ? input.errors : [],
    },
    null,
    2,
  ),
);
NODE
