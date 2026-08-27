Helm dialect of [tree-sitter-go-template](https://github.com/ngalaiko/tree-sitter-go-template), based on [tree-sitter-go-template#53](https://github.com/ngalaiko/tree-sitter-go-template/pull/53).

The text lexer keeps `{}` in the same token as the rest of that line (`/[^{]+\{\}[^\n{]*/`). Stopping at `}` put typed characters into the next `(text)` node, so YAML for keys below `emptyDir: {}` started with those characters and went plain.
