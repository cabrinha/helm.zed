; Indent bodies of template control actions. `end` / `else` outdent so they
; line up with the opening action, matching everyday Helm editing.
(if_action) @indent @start.if
(range_action) @indent @start.range
(with_action) @indent @start.with
(define_action) @indent
(block_action) @indent

"else" @outdent
"end" @outdent
