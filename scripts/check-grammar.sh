#!/usr/bin/env bash
# Parse Helm fixtures with the grammar pinned in extension.toml.
# Fails if any fixture produces an ERROR node, or if `{}` splits into
# separate text nodes (the issue #22 lexer bug).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GRAMMAR_REPO="$(awk '/\[grammars.helm\]/{f=1} f && /^repository =/{gsub(/"/, "", $3); print $3; exit}' "$ROOT/extension.toml")"
GRAMMAR_COMMIT="$(awk '/\[grammars.helm\]/{f=1} f && /^commit =/{gsub(/"/, "", $3); print $3; exit}' "$ROOT/extension.toml")"
GRAMMAR_PATH="$(awk '/\[grammars.helm\]/{f=1} f && /^path =/{gsub(/"/, "", $3); print $3; exit}' "$ROOT/extension.toml")"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if ! command -v tree-sitter >/dev/null 2>&1; then
  npm install --silent --no-fund --no-audit --prefix "$WORK" tree-sitter-cli@0.25.10
  PATH="$WORK/node_modules/.bin:$PATH"
fi

echo "Using $GRAMMAR_REPO @$GRAMMAR_COMMIT ($GRAMMAR_PATH)"
echo "tree-sitter $(tree-sitter --version)"
git clone --quiet "$GRAMMAR_REPO" "$WORK/grammar"
git -C "$WORK/grammar" checkout --quiet "$GRAMMAR_COMMIT"

DIALECT="$WORK/grammar/$GRAMMAR_PATH"
if [[ ! -f "$DIALECT/grammar.js" ]]; then
  echo "missing grammar.js in $GRAMMAR_PATH" >&2
  exit 1
fi

cd "$DIALECT"
fail=0

check_fixture() {
  local file="$1"
  local out
  if ! out="$(tree-sitter parse --rebuild "$file" -q 2>&1)"; then
    echo "PARSE FAILED $file"
    tree-sitter parse --rebuild "$file" 2>/dev/null | grep ERROR || true
    echo "$out"
    fail=1
    return
  fi
  echo "ok  parse  $(basename "$file")"
}

for fixture in "$ROOT"/tests/fixtures/*; do
  check_fixture "$fixture"
done

# Issue #22: `{` must not be its own text node.
xml="$(printf 'emptyDir: {}\nfoo: bar\n' | tree-sitter parse --rebuild --xml 2>/dev/null)"
if grep -q '<text[^>]*>{</text>' <<<"$xml"; then
  echo "empty mapping still split: '{' is its own text node"
  echo "$xml"
  fail=1
else
  echo "ok  empty mapping keeps {} in one text node"
fi

if grep -q ERROR <<<"$xml"; then
  echo "empty mapping produced ERROR"
  fail=1
fi

# Compile every query against the pinned helm grammar. Zed refuses to
# register the language if any query names a node type the grammar lacks
# (that is how a backtick pair in brackets.scm made Helm vanish).
sample="$ROOT/tests/fixtures/empty-mapping.yaml"
for query in "$ROOT"/languages/helm/*.scm; do
  name="$(basename "$query")"
  if ! tree-sitter query "$query" "$sample" >/dev/null 2>"$WORK/query.err"; then
    echo "QUERY FAILED $name"
    cat "$WORK/query.err"
    fail=1
  else
    echo "ok  query  $name"
  fi
done

# Zed also refuses to load Helm if injections.scm uses both @content and
# @injection.content. tree-sitter query accepts that; Zed does not.
injections="$ROOT/languages/helm/injections.scm"
if grep -E '^[^;]*@content' "$injections" >/dev/null \
  && grep -E '^[^;]*@injection\.content' "$injections" >/dev/null; then
  echo "QUERY FAILED injections.scm: both content and injection.content captures"
  fail=1
else
  echo "ok  injections use one content capture style"
fi

# Builtin captures for include/tpl/sha512sum, which the old regex list missed.
query_out="$(tree-sitter query "$ROOT/languages/helm/highlights.scm" \
  "$ROOT/tests/fixtures/range-with-define.yaml" 2>/dev/null || true)"
for fn in include tpl sha512sum nindent required; do
  if grep -q "function.builtin.*text: \`$fn\`" <<<"$query_out"; then
    echo "ok  highlight $fn as function.builtin"
  else
    echo "missing function.builtin capture for $fn"
    fail=1
  fi
done

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi

echo "All fixtures parsed without ERROR nodes."
