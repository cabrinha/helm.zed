; YAML highlighting for template text. Combined so fragments around {{ }}
; stitch into one YAML document. Use only @content: Zed errors if
; @content and @injection.content are both set on the same pattern.
;
; Combined injection is required for a single YAML document. Zed still
; drops that layer on incremental edits (zed-industries/zed#57341), even
; when `{}` is one text node. Do not remove combined to paper over that.
((text) @content
 (#set! "language" "yaml")
 (#set! "combined"))
