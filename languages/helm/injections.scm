; YAML highlighting for template text. Use only @content: Zed errors
; if @content and @injection.content are both set on the same pattern.
;
; Combined so all (text) fragments around {{ }} form one YAML document.
; Per-node injection parses each fragment on its own; a fragment that
; starts deep in a mapping and then dedents is invalid YAML and loses
; highlighting on load (#35).
;
; Zed can drop combined ranges that only touch an edit
; (zed-industries/zed#57341, fix in zed-industries/zed#63280). The helm
; lexer keeps `{}`, the rest of that line, and the trailing newline in one
; text node to make that less likely next to emptyDir: {}.
((text) @content
  (#set! "language" "yaml")
  (#set! "combined"))
