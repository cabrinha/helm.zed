# helm.zed

Syntax highlighting for Helm templates using tree-sitter, plus [helm-ls](https://github.com/mrjosh/helm-ls).

## Installation

Install from the [Zed extension store](https://zed.dev/extensions/helm).

The extension looks for `helm_ls`, then `helm-ls`, on PATH. If neither is there it downloads a helm-ls release. [yaml-language-server](https://github.com/redhat-developer/yaml-language-server) is optional; helm-ls uses it for Kubernetes schema diagnostics when it is installed.

You can also pin a binary:

```json
{
  "lsp": {
    "helm_ls": {
      "binary": {
        "path": "/usr/local/bin/helm_ls",
        "arguments": ["serve"]
      }
    }
  }
}
```

## File detection

`.tpl`, `.gotmpl`, `helmfile.yaml`, and `helmfile.yml` are Helm out of the box. Chart templates still share `.yaml` with ordinary YAML, so map those in `settings.json`:

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

Leave `Chart.yaml` as YAML. It is chart metadata, not a template.

If a `.yaml` file still opens as YAML, pick Helm in the language selector once, or add the glob above. helm-ls will not start on files that stay tagged as YAML, and yaml-language-server will flag `{{ }}` as errors.

## Language server settings

helm-ls reads the `helm-ls` section of workspace configuration. Put that nested object under `lsp.helm_ls.settings` (`lsp.helm` and `lsp.helm-ls` also work). These two shapes are equivalent:

```json
{
  "lsp": {
    "helm_ls": {
      "settings": {
        "yamlls": {
          "enabled": false
        }
      }
    }
  }
}
```

```json
{
  "lsp": {
    "helm_ls": {
      "settings": {
        "helm-ls": {
          "logLevel": "info",
          "yamlls": {
            "enabled": true,
            "enabledForFilesGlob": "*.{yaml,yml}"
          }
        }
      }
    }
  }
}
```

`yamlls.enabled` only controls the yaml-language-server process that helm-ls starts. It does not disable Zed's own YAML language server. If CRDs are still underlined, the buffer is probably still language YAML. Use the `file_types` globs above.

Full helm-ls options: [helm-ls configuration](https://github.com/mrjosh/helm-ls/?tab=readme-ov-file#configuration-options).

## Empty mappings (`emptyDir: {}`)

The grammar pin keeps `{}` as one text node, so a full parse highlights YAML correctly. Typing next to that mapping can still drop injected YAML highlighting until you reload the buffer. That is [zed#57341](https://github.com/zed-industries/zed/issues/57341): Zed's combined injection layer does not re-stitch `(text)` fragments on incremental parse. Neovim does. Reloading the file restores highlighting.

## Credits

Highlighting uses [tree-sitter-go-template](https://github.com/ngalaiko/tree-sitter-go-template), including the empty-mapping lexer fix from [tree-sitter-go-template#53](https://github.com/ngalaiko/tree-sitter-go-template/pull/53).

## Release process

1. Bump the version in `Cargo.toml` and `extension.toml`.
2. After release, update the entry in [zed-industries/extensions](https://github.com/zed-industries/extensions/).
