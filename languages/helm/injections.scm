; YAML highlighting for each (text) node. Use only @content: Zed errors
; if @content and @injection.content are both set on the same pattern.
;
; Do not set combined. Zed drops a combined YAML layer on incremental
; edits (zed-industries/zed#57341). Per-node injection keeps other
; fragments on their own YAML layer.
;
; The helm lexer keeps `{}` plus the rest of that line in one text
; node so typing at EOL after emptyDir: {} does not prefix the next
; node's YAML (keys below) with the typed characters.
((text) @content
 (#set! "language" "yaml"))
