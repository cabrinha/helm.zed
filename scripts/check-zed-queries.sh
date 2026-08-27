#!/usr/bin/env bash
# Zed-log style query load check.
#
# tree-sitter query compiles mixed @content / @injection.content, but Zed
# refuses to register the language:
#   Error loading injection query: both content and injection.content captures are present
# Invalid node types (a backtick pair in brackets.scm) also fail Query::new
# and Helm disappears from the language selector.
#
# Compile every languages/helm/*.scm against the pinned helm grammar, then
# apply the capture-name rules from PR #32's check-grammar.sh.
set -euo pipefail

# shellcheck source=lib/grammar-pin.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/grammar-pin.sh"
# shellcheck source=lib/zed-queries.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/zed-queries.sh"

load_grammar_pin
assert_grammar_pin_lock

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ensure_tree_sitter "$WORK"

echo "Pin $GRAMMAR_REPO @$GRAMMAR_COMMIT ($GRAMMAR_PATH)"
echo "tree-sitter $(tree-sitter --version)"
echo "Queries compiled against $GRAMMAR_COMMIT (matches tests/grammar-pin.sha)"

stage_helm_grammar "$WORK/dialect"

SAMPLE="$ROOT/tests/charts/example/templates/deployment.yaml"
if [[ ! -f "$SAMPLE" ]]; then
  echo "missing sample fixture $SAMPLE" >&2
  exit 1
fi

cd "$DIALECT"
fail=0

shopt -s nullglob
queries=("$ROOT"/languages/helm/*.scm)
if [[ ${#queries[@]} -eq 0 ]]; then
  echo "no languages/helm/*.scm files" >&2
  exit 1
fi

for query in "${queries[@]}"; do
  name="$(basename "$query")"
  if ! tree-sitter query "$query" "$SAMPLE" >/dev/null 2>"$WORK/query.err"; then
    echo "QUERY FAILED $name (Zed would not register Helm)"
    cat "$WORK/query.err"
    fail=1
    continue
  fi
  echo "ok  compile  $name"

  if ! zed_required_captures_ok "$query" 2>"$WORK/cap.err"; then
    echo "QUERY FAILED $name: $(tr '\n' ' ' <"$WORK/cap.err")"
    fail=1
  else
    echo "ok  zed-load $name"
  fi
done

# The exact dual-capture query Zed rejected must not pass this check.
# tree-sitter query accepts it; that is why a compile-only job is not enough.
cat >"$WORK/dual-injections.scm" <<'EOF'
((text) @content @injection.content
 (#set! "language" "yaml")
 (#set! "injection.language" "yaml")
 (#set! "combined")
 (#set! "injection.combined"))
EOF
if tree-sitter query "$WORK/dual-injections.scm" "$SAMPLE" >/dev/null 2>&1; then
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

# Invalid node type that made Helm vanish: backtick is not a token, raw
# strings are (raw_string_literal).
cat >"$WORK/backtick-brackets.scm" <<'EOF'
("{{" @open "}}" @close)
("`" @open "`" @close)
EOF
if tree-sitter query "$WORK/backtick-brackets.scm" "$SAMPLE" >/dev/null 2>"$WORK/bt.err"; then
  echo "QUERY CHECK MISSED invalid backtick node type"
  fail=1
else
  if grep -qi 'Invalid node type' "$WORK/bt.err"; then
    echo "ok  detector rejects backtick brackets: $(tr '\n' ' ' <"$WORK/bt.err")"
  else
    echo "backtick brackets failed for an unexpected reason:"
    cat "$WORK/bt.err"
    fail=1
  fi
fi

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi

echo "All Helm queries load the way Zed would register them."
