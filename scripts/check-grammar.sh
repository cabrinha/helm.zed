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

echo "tree-sitter $(tree-sitter --version)"

if [[ -f "$ROOT/vendor/tree-sitter-helm/grammar.js" ]]; then
  echo "Using local vendor/tree-sitter-helm"
  DIALECT="$ROOT/vendor/tree-sitter-helm"
else
  echo "Using $GRAMMAR_REPO @$GRAMMAR_COMMIT ($GRAMMAR_PATH)"
  git clone --quiet "$GRAMMAR_REPO" "$WORK/grammar"
  git -C "$WORK/grammar" checkout --quiet "$GRAMMAR_COMMIT"
  DIALECT="$WORK/grammar/$GRAMMAR_PATH"
fi
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

# The wasm Zed compiles is dialects/helm/src/parser.c. Fail if the pin
# lost the empty-brace tokens from tree-sitter-go-template#53.
if ! grep -F '[^{]+\\{\\}[^\\n{]*\\n?' "$DIALECT/src/grammar.json" >/dev/null; then
  echo "helm grammar.json is missing the empty-brace rest-of-line+newline text token"
  fail=1
else
  echo "ok  grammar.json keeps rest of line and newline after {}"
fi

# Issue #22 / grammar half: `{` must not be its own text node.
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

# Same check after an incremental edit immediately after `{}`.
# The grammar pin must survive tree-sitter's edit API; Zed combined
# injection dropping after that point is zed-industries/zed#57341.
fixture="$ROOT/tests/fixtures/empty-mapping.yaml"
after_brace="$(python3 -c "
from pathlib import Path
t = Path('$fixture').read_text()
i = t.index('{}', t.index('emptyDir: {}'))
print(i + 2)
")"
inc_xml="$(tree-sitter parse --xml -q "$fixture" --edits "$after_brace 0 x" 2>/dev/null || true)"
if [[ -z "$inc_xml" ]]; then
  echo "incremental parse after {} produced no tree"
  fail=1
elif grep -q '<text[^>]*>{</text>' <<<"$inc_xml"; then
  echo "incremental edit after {} split a lone '{' text node"
  echo "$inc_xml"
  fail=1
else
  echo "ok  incremental edit after {} keeps braces in one text node"
fi

# The {} line's text node must include the trailing newline so an EOL
# insert is inside that node, not on the following keys' node start.
full_xml="$(tree-sitter parse --xml -q "$ROOT/tests/fixtures/empty-mapping.yaml" 2>/dev/null || true)"
if grep -q 'emptyDir: {}</text>' <<<"$full_xml"; then
  echo "emptyDir {} text node stops at } (EOL insert would hit the next node)"
  fail=1
else
  echo "ok  emptyDir {} text node includes the trailing newline"
fi

# Typing at EOL after {} must not prefix the following keys' text node.
# That fragment is injected as YAML; a leading "x" makes the YAML invalid
# and keys such as configMap go plain (the #22 tail-wipe).
if ! grep -q 'configMap' <<<"$inc_xml"; then
  echo "incremental parse lost configMap text"
  fail=1
elif python3 -c "
import re, sys
xml = sys.stdin.read()
nodes = re.findall(r'<text[^>]*>(.*?)</text>', xml, re.S)
bad = [n for n in nodes if 'configMap' in n and n.lstrip().startswith('x')]
sys.exit(1 if bad else 0)
" <<<"$inc_xml"; then
  echo "ok  keys below {} are not in a text node prefixed by the edit"
else
  echo "incremental edit after {} prefixed the following keys with x"
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

# Zed's language_registry rejects mixed old/new injection capture names
# (`both content and injection.content captures are present`). tree-sitter
# query compiles that file; this check is what actually matches Zed.log.
injection_has_capture() {
  local file="$1" name="$2"
  grep -vE '^\s*;' "$file" | grep -oE '@[A-Za-z0-9_.]+' | sed 's/^@//' | grep -qx "$name"
}

zed_injection_query_ok() {
  local file="$1"
  if injection_has_capture "$file" content \
    && injection_has_capture "$file" injection.content; then
    echo "both content and injection.content captures are present" >&2
    return 1
  fi
  if injection_has_capture "$file" language \
    && injection_has_capture "$file" injection.language; then
    echo "both language and injection.language captures are present" >&2
    return 1
  fi
  if ! injection_has_capture "$file" content \
    && ! injection_has_capture "$file" injection.content; then
    echo "missing required capture: content or injection.content" >&2
    return 1
  fi
  # Combined YAML injection is zed#57341 / helm.zed#22: typing next to
  # emptyDir: {} drops every YAML key. Inject each (text) node separately.
  if grep -vE '^\s*;' "$file" | grep -Eq '(^|[^A-Za-z0-9_.])(injection\.)?combined($|[^A-Za-z0-9_.])'; then
    echo "combined injection drops YAML on incremental parse in Zed (zed#57341)" >&2
    return 1
  fi
  return 0
}

injections="$ROOT/languages/helm/injections.scm"
if zed_injection_query_ok "$injections" 2>"$WORK/inj.err"; then
  echo "ok  injections use one content capture style"
else
  echo "QUERY FAILED injections.scm: $(tr '\n' ' ' <"$WORK/inj.err")"
  fail=1
fi

# The exact dual-capture query Zed rejected must not pass this check.
cat >"$WORK/dual-injections.scm" <<'EOF'
((text) @content @injection.content
 (#set! "language" "yaml")
 (#set! "injection.language" "yaml")
 (#set! "combined")
 (#set! "injection.combined"))
EOF
if tree-sitter query "$WORK/dual-injections.scm" "$sample" >/dev/null 2>&1; then
  echo "ok  tree-sitter query accepts dual captures (Zed does not)"
else
  echo "unexpected: tree-sitter query rejected dual captures"
  fail=1
fi
if zed_injection_query_ok "$WORK/dual-injections.scm" 2>"$WORK/dual.err"; then
  echo "QUERY CHECK MISSED dual content captures"
  fail=1
else
  echo "ok  detector rejects dual captures: $(tr '\n' ' ' <"$WORK/dual.err")"
fi

# Combined injection is the #22 incremental drop in Zed. Must not ship.
cat >"$WORK/combined-injections.scm" <<'EOF'
((text) @content
 (#set! "language" "yaml")
 (#set! "combined"))
EOF
if zed_injection_query_ok "$WORK/combined-injections.scm" 2>"$WORK/comb.err"; then
  echo "QUERY CHECK MISSED combined injection"
  fail=1
else
  echo "ok  detector rejects combined injection: $(tr '\n' ' ' <"$WORK/comb.err")"
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
