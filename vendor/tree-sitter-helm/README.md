Helm dialect of [tree-sitter-go-template](https://github.com/ngalaiko/tree-sitter-go-template), based on [tree-sitter-go-template#53](https://github.com/ngalaiko/tree-sitter-go-template/pull/53).

The text lexer keeps `{}`, the rest of that line, and the trailing newline in one token (`/[^{]+\{\}[^\n{]*\n?/`). Stopping at `}` put an EOL insert on the next `(text)` node's start, so Zed dropped YAML injection for keys below `emptyDir: {}`.
