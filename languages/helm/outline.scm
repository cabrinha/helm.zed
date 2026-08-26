; Named template definitions: {{- define "mychart.labels" -}} ... {{- end }}
(define_action
  name: [
    (interpreted_string_literal)
    (raw_string_literal)
  ] @name) @item

; Block definitions: {{- block "mychart.body" . -}} ... {{- end }}
(block_action
  name: [
    (interpreted_string_literal)
    (raw_string_literal)
  ] @name) @item

; Includes show up constantly in real charts; worth a one-line outline entry.
(function_call
  function: (identifier) @context
  (#eq? @context "include")
  arguments: (argument_list
    .
    [
      (interpreted_string_literal)
      (raw_string_literal)
    ] @name)) @item
