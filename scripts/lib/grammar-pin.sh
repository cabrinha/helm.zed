# Shared pin for tree-sitter-go-template. Sourced by CI scripts.
# Keep GRAMMAR_COMMIT in sync with extension.toml [grammars.helm] commit
# and tests/grammar-pin.sha.

helm_zed_root() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  printf '%s\n' "$here"
}

load_grammar_pin() {
  ROOT="$(helm_zed_root)"
  GRAMMAR_REPO="$(awk '/\[grammars.helm\]/{f=1} f && /^repository =/{gsub(/"/, "", $3); print $3; exit}' "$ROOT/extension.toml")"
  GRAMMAR_COMMIT="$(awk '/\[grammars.helm\]/{f=1} f && /^commit =/{gsub(/"/, "", $3); print $3; exit}' "$ROOT/extension.toml")"
  GRAMMAR_PATH="$(awk '/\[grammars.helm\]/{f=1} f && /^path =/{gsub(/"/, "", $3); print $3; exit}' "$ROOT/extension.toml")"

  if [[ -z "$GRAMMAR_REPO" || -z "$GRAMMAR_COMMIT" || -z "$GRAMMAR_PATH" ]]; then
    echo "failed to read [grammars.helm] from extension.toml" >&2
    return 1
  fi
  if [[ ! "$GRAMMAR_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
    echo "extension.toml grammars.helm.commit must be a full 40-char SHA, got: $GRAMMAR_COMMIT" >&2
    return 1
  fi
}

assert_grammar_pin_lock() {
  local lock
  lock="$(tr -d '[:space:]' <"$ROOT/tests/grammar-pin.sha")"
  if [[ "$lock" != "$GRAMMAR_COMMIT" ]]; then
    echo "grammar pin mismatch:" >&2
    echo "  extension.toml [grammars.helm] commit = $GRAMMAR_COMMIT" >&2
    echo "  tests/grammar-pin.sha                 = $lock" >&2
    echo "Bump both together so queries compile against the grammar Zed downloads." >&2
    return 1
  fi
}

ensure_tree_sitter() {
  if command -v tree-sitter >/dev/null 2>&1; then
    return 0
  fi
  local prefix="${1:?need npm prefix}"
  npm install --silent --no-fund --no-audit --prefix "$prefix" tree-sitter-cli@0.25.10
  PATH="$prefix/node_modules/.bin:$PATH"
  export PATH
}

clone_pinned_grammar() {
  local dest="${1:?need clone dest}"
  git clone --quiet "$GRAMMAR_REPO" "$dest"
  git -C "$dest" checkout --quiet "$GRAMMAR_COMMIT"
  local head
  head="$(git -C "$dest" rev-parse HEAD)"
  if [[ "$head" != "$GRAMMAR_COMMIT" ]]; then
    echo "cloned HEAD $head does not match pin $GRAMMAR_COMMIT" >&2
    return 1
  fi
  if [[ ! -f "$dest/$GRAMMAR_PATH/grammar.js" ]]; then
    echo "missing grammar.js in $GRAMMAR_PATH at $GRAMMAR_COMMIT" >&2
    return 1
  fi
}
