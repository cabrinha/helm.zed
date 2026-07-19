; Named template definitions: {{- define "mychart.labels" -}} ... {{- end }}
; Both quoted ("name") and backtick (`name`) string forms are handled.
(define_action
  name: [
    (interpreted_string_literal)
    (raw_string_literal)
  ] @name) @item

; Block definitions: {{- block "mychart.body" . -}} ... {{- end }}
; `block` is like `define` but with a fallback body — also worth showing in the outline.
(block_action
  name: [
    (interpreted_string_literal)
    (raw_string_literal)
  ] @name) @item
