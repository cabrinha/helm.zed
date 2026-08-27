; YAML highlighting for each (text) node. Use only @content: Zed errors
; if @content and @injection.content are both set on the same pattern.
;
; Do not set combined. Zed drops a combined YAML layer on incremental
; edits (zed-industries/zed#57341). That is helm.zed#22: after typing
; next to emptyDir: {}, every YAML key went plain while {{ }} stayed
; colored. Per-node injection keeps other fragments on their own YAML
; layer so an edit does not wipe the whole file.
((text) @content
 (#set! "language" "yaml"))
