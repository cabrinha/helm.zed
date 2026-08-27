; YAML highlighting for each (text) node. Use only @content: Zed errors
; if @content and @injection.content are both set on the same pattern.
;
; Do not set combined. Zed drops a combined YAML layer on incremental
; edits (zed-industries/zed#57341).
;
; The helm lexer keeps `{}`, the rest of that line, and the trailing
; newline in one text node. An EOL insert after emptyDir: {} stays
; inside that node, so YAML for keys on later lines is not dropped.
((text) @content
  (#set! "language" "yaml"))
