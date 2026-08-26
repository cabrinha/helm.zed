; YAML highlighting for template text. Combined so fragments around {{ }}
; stitch into one YAML document. Do not inject yaml_no_injection_text; that
; node exists so a lone "-" after }} does not break the YAML grammar.
((text) @content @injection.content
 (#set! "language" "yaml")
 (#set! "injection.language" "yaml")
 (#set! "combined")
 (#set! "injection.combined"))
