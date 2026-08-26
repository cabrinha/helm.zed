#!/usr/bin/env bash
# Parse the example chart templates with the grammar pinned in extension.toml
# and check that Helm query files are valid against that grammar.
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

check_parse() {
  local file="$1"
  local out
  if ! out="$(tree-sitter parse --rebuild "$file" -q 2>&1)"; then
    echo "PARSE FAILED $file"
    tree-sitter parse --rebuild "$file" 2>/dev/null | grep ERROR || true
    echo "$out"
    fail=1
    return
  fi
  echo "ok  parse  ${file#"$ROOT/"}"
}

shopt -s nullglob
templates=("$ROOT"/tests/charts/example/templates/*)
if [[ ${#templates[@]} -eq 0 ]]; then
  echo "no chart templates under tests/charts/example/templates" >&2
  exit 1
fi

for fixture in "${templates[@]}"; do
  check_parse "$fixture"
done

QUERIES=(
  highlights.scm
  injections.scm
  outline.scm
  indents.scm
  brackets.scm
  textobjects.scm
)

sample="${templates[0]}"
for query in "${QUERIES[@]}"; do
  path="$ROOT/languages/helm/$query"
  if [[ ! -f "$path" ]]; then
    echo "missing query file $query" >&2
    fail=1
    continue
  fi
  if ! tree-sitter query "$path" "$sample" >/dev/null 2>"$WORK/query.err"; then
    echo "QUERY FAILED $query"
    cat "$WORK/query.err"
    fail=1
  else
    echo "ok  query  $query"
  fi
done

# Everyday Helm captures that should survive query refactors.
query_out="$(tree-sitter query "$ROOT/languages/helm/highlights.scm" \
  "$ROOT/tests/charts/example/templates/deployment.yaml" 2>/dev/null || true)"
for cap in \
  "keyword.*text: \`if\`" \
  "keyword.*text: \`range\`" \
  "keyword.*text: \`else\`" \
  "keyword.*text: \`end\`" \
  "function.*text: \`include\`" \
  "function.builtin.*text: \`nindent\`"
do
  if grep -Eq "$cap" <<<"$query_out"; then
    echo "ok  highlight $cap"
  else
    echo "missing highlight capture: $cap"
    fail=1
  fi
done

outline_out="$(tree-sitter query "$ROOT/languages/helm/outline.scm" \
  "$ROOT/tests/charts/example/templates/_helpers.tpl" 2>/dev/null || true)"
if grep -Eq 'name.*text: `"example.name"`' <<<"$outline_out"; then
  echo "ok  outline define example.name"
else
  echo "missing outline capture for define example.name"
  echo "$outline_out"
  fail=1
fi

indent_out="$(tree-sitter query "$ROOT/languages/helm/indents.scm" \
  "$ROOT/tests/charts/example/templates/deployment.yaml" 2>/dev/null || true)"
if grep -Eq 'capture: indent' <<<"$indent_out" && grep -Eq 'text: `end`' <<<"$indent_out"; then
  echo "ok  indent if/range and outdent end"
else
  echo "missing @indent / @outdent captures"
  echo "$indent_out"
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi

echo "Chart fixtures parsed and queries matched expected captures."
