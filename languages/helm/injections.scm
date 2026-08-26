; YAML highlighting for template text. Combined so fragments around {{ }}
; stitch into one YAML document. Zed errors if @content and
; @injection.content are both set on the same pattern.
((text) @content
 (#set! "language" "yaml")
 (#set! "combined"))
