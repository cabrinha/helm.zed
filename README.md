# helm.zed

Syntax highlighting for Helm templates using tree-sitter and integration of [helm-ls](https://github.com/mrjosh/helm-ls).

## Installation

The extension relies on the PATH environment variable and first looks for
`helm_ls`, then `helm-ls`. If neither is available, an error is shown.

## File Type Association

Helm template files share the `.yaml`/`.yml` extension with plain YAML files.
Because Zed matches file extensions globally, the extension does **not**
register `.yaml`/`.yml` automatically (doing so would override the built-in YAML
language for every YAML file).

To get syntax highlighting and the language server for your chart templates,
add the following to your Zed `settings.json`:

```json
{
  "file_types": {
    "Helm": ["yaml", "yml"]
  }
}
```

> **Tip:** If you work with both plain YAML and Helm files, you can keep the
> default YAML association and switch individual files manually via the
> language selector in the status bar.

## Configuration

This is an example of providing configuration for the language server via Zed's `settings.json`. For full reference of possible values, refer to [helm-ls configuration section](https://github.com/mrjosh/helm-ls/?tab=readme-ov-file#configuration-options).

```json
{
  ...
  "lsp": {
    "helm_ls": {
      "settings": {
        "helm-ls": {
          "logLevel": "info",
          "yamlls": {
            "enabled": true
          }
        }
      }
    }
  }
}
```

## Credits

https://github.com/ngalaiko/tree-sitter-go-template

## Release Process

Every time the extension is released:

1. **Bump the Version:**
   Update the version number in Cargo.toml and extension.toml.

2. **Update Extension Index:**
   After releasing, update the extension entry in [zed-industries/extensions](http://github.com/zed-industries/extensions/) to reflect the new version.

This ensures users always have access to the latest
