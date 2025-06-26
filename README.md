# helm.zed

Syntax highlighting for Helm templates by providing integration with https://github.com/mrjosh/helm-ls.

## Installation

The extensions relies on the PATH environment variable and first look for 'helm_ls', then 'helm-ls'. If none is available, an error is showed.

## Configuration

This is an example of providing configuration for the language server via Zed's `settings.json`. For full reference of possible values, refer to https://github.com/mrjosh/helm-ls.

```json
{
  ...
  "lsp": {
    "helm_ls": {
      "settings": {
        "helm-ls": {
          "logLevel": "warning",
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
