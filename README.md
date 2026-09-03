# helm.zed

Syntax highlighting for Helm templates using tree-sitter, plus [helm-ls](https://github.com/mrjosh/helm-ls).

## Installation

Install from the [Zed extension store](https://zed.dev/extensions/helm).

You do not need to install helm-ls first. The extension looks for `helm_ls`, then `helm-ls`, on PATH. If neither is there, it downloads a pinned helm-ls release and reuses that binary on later Zed starts.

[yaml-language-server](https://github.com/redhat-developer/yaml-language-server) is still required for full LSP. helm-ls shells out to it for Kubernetes schema validation. Without it you get Helm template intelligence only.

You can also pin a binary:

```json
{
  "lsp": {
    "helm": {
      "binary": {
        "path": "/usr/local/bin/helm_ls",
        "arguments": ["serve"]
      }
    }
  }
}
```

## File detection

`.tpl`, `*.yaml.gotmpl`, `*.yml.gotmpl`, `helmfile.yaml`, and `helmfile.yml` are Helm out of the box. Bare `.gotmpl` files belong to the gotmpl extension, so they are intentionally not claimed. Chart templates still share `.yaml` with ordinary YAML, so map those in `settings.json`:

```json
{
  "file_types": {
    "Helm": [
      "**/templates/**/*.tpl",
      "**/templates/**/*.yaml",
      "**/templates/**/*.yml",
      "**/templates/**/*.gotmpl",
      "**/helmfile.d/**/*.yaml",
      "**/helmfile.d/**/*.yml",
      "helmfile.yaml",
      "helmfile.yml",
      "**/values*.yaml",
      "**/values*.yml"
    ]
  }
}
```

Leave `Chart.yaml` as YAML. It is chart metadata, not a template. Path globs such as `charts/*/templates/*.yaml` are not valid in `languages/helm/config.toml` `path_suffixes`; those stay in `file_types`.

If a `.yaml` file still opens as YAML, pick Helm in the language selector once, or add the glob above. helm-ls will not start on files that stay tagged as YAML, and yaml-language-server will flag `{{ }}` as errors.

`**/values*.yaml` is included because helm-ls understands values files.

## Language server settings

helm-ls reads the `helm-ls` section of workspace configuration. Put your settings flat under `lsp.helm.settings` (the language server ID from `extension.toml`); the extension nests them under `helm-ls` before sending:

```json
{
  "lsp": {
    "helm": {
      "settings": {
        "logLevel": "info",
        "yamlls": {
          "enabled": true,
          "enabledForFilesGlob": "*.{yaml,yml}"
        }
      }
    }
  }
}
```

If `yaml-language-server` is on your PATH, the extension passes its absolute path through as `yamlls.path` and `YAMLLS_PATH` (both are helm-ls's documented knobs for finding it). An explicit `yamlls.path` in your settings still wins.

`yamlls.enabled` only controls the yaml-language-server process that helm-ls starts. It does not disable Zed's own YAML language server. If CRDs are still underlined, the buffer is probably still language YAML. Use the `file_types` globs above.

Full helm-ls options: [helm-ls configuration](https://github.com/mrjosh/helm-ls/?tab=readme-ov-file#configuration-options).

## Empty mappings (`emptyDir: {}`)

The vendored helm grammar keeps `{}`, the rest of that line, and the trailing newline as one text token so typing at EOL after `emptyDir: {}` does not sit on the next node's start. YAML is injected per `(text)` node, not combined ([zed#57341](https://github.com/zed-industries/zed/issues/57341)).

## Testing

```sh
cargo test
./scripts/check-queries.sh
./scripts/check-grammar.sh
./scripts/check-grammar-pin.sh
./scripts/check-zed-queries.sh
```

CI also packages with the `zed-extension` CLI and runs `ts_query_ls format --check languages`.

## Credits

Highlighting uses [tree-sitter-go-template](https://github.com/ngalaiko/tree-sitter-go-template), including the empty-mapping lexer fix from [tree-sitter-go-template#53](https://github.com/ngalaiko/tree-sitter-go-template/pull/53).

## Release process

1. Bump the version in `Cargo.toml` and `extension.toml`.
2. After release, update the entry in [zed-industries/extensions](https://github.com/zed-industries/extensions/).
