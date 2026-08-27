# Zed language_registry checks that tree-sitter query does not perform.
# Sourced by scripts/check-zed-queries.sh.

# Capture names in a query file, skipping comment lines.
query_capture_names() {
  local file="$1"
  grep -vE '^\s*;' "$file" | grep -oE '@[A-Za-z0-9_.]+' | sed 's/^@//' | sort -u
}

query_has_capture() {
  local file="$1" name="$2"
  query_capture_names "$file" | grep -qx "$name"
}

# Mirrors crates/language/src/language.rs with_injection_query:
# mixing old (@content) and new (@injection.content) styles is a hard error
# ("Error loading injection query: both content and injection.content captures are present").
zed_injection_query_ok() {
  local file="$1"
  if query_has_capture "$file" content \
    && query_has_capture "$file" injection.content; then
    echo "both content and injection.content captures are present" >&2
    return 1
  fi
  if query_has_capture "$file" language \
    && query_has_capture "$file" injection.language; then
    echo "both language and injection.language captures are present" >&2
    return 1
  fi
  if ! query_has_capture "$file" content \
    && ! query_has_capture "$file" injection.content; then
    echo "missing required capture: content or injection.content" >&2
    return 1
  fi
  return 0
}

# Required captures Zed looks up after Query::new succeeds.
# Missing ones log an error and skip that feature; we still fail CI so
# registration does not silently drop brackets/indents/outline.
zed_required_captures_ok() {
  local file="$1"
  local name
  name="$(basename "$file")"
  case "$name" in
    brackets.scm)
      query_has_capture "$file" open && query_has_capture "$file" close
      ;;
    indents.scm)
      query_has_capture "$file" indent
      ;;
    outline.scm)
      query_has_capture "$file" item && query_has_capture "$file" name
      ;;
    injections.scm)
      zed_injection_query_ok "$file"
      ;;
    *)
      return 0
      ;;
  esac
}
