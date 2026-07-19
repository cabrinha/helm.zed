; Identifiers

[
    (field)
    (field_identifier)
] @property

(variable) @variable

; Function calls

(function_call
  function: (identifier) @function)

(method_call
  method: (selector_expression
    field: (field_identifier) @function))

; Operators

"|" @operator
":=" @operator

; Builtin functions

((identifier) @function.builtin
 (#match? @function.builtin "^(abbrev|abbrevboth|add|add1|add1f|addf|adler32sum|ago|and|append|atoi|b32dec|b32enc|b64dec|b64enc|base|buildCustomCert|camelcase|call|cat|ceil|chunk|clean|coalesce|compact|concat|contains|date|dateInZone|dateModify|decryptAES|deepCopy|deepEqual|default|derivePassword|dict|dig|dir|div|divf|duration|durationRound|empty|encryptAES|eq|ext|fail|first|float64|floor|fromJson|fromJsonArray|fromYaml|fromYamlArray|ge|genCA|genPrivateKey|genSelfSignedCert|genSignedCert|get|getHostByName|gt|has|hasKey|hasPrefix|hasSuffix|html|htmlDate|htmlDateInZone|htpasswd|index|indent|initials|int|int64|isAbs|js|kebabcase|keys|kindIs|kindOf|last|le|len|list|lookup|lower|lt|max|maxf|merge|mergeOverwrite|min|minf|mod|mul|mulf|mustAppend|mustCompact|mustDateModify|mustDeepCopy|mustFirst|mustHas|mustInitial|mustLast|mustMerge|mustMergeOverwrite|mustPrepend|mustRegexFind|mustRegexFindAll|mustRegexMatch|mustRegexReplaceAll|mustRegexReplaceAllLiteral|mustRegexSplit|mustRest|mustReverse|mustSlice|mustToDate|mustToJson|mustToPrettyJson|mustToRawJson|mustToToml|mustUniq|mustWithout|ne|nindent|nospace|not|now|omit|or|pick|pluck|plural|prepend|print|printf|println|quote|randAlpha|randAlphaNum|randAscii|randBytes|randNumeric|regexFind|regexFindAll|regexMatch|regexReplaceAll|regexReplaceAllLiteral|regexSplit|repeat|replace|required|rest|reverse|round|semver|semverCompare|seq|set|sha1sum|sha256sum|shuffle|slice|snakecase|squote|sub|subf|substr|swapcase|ternary|title|toDate|toDecimal|toJson|toPrettyJson|toRawJson|toString|toStrings|toToml|toYaml|toYamlPretty|trim|trimAll|trimPrefix|trimSuffix|trunc|typeIs|typeIsLike|typeOf|uniq|unixEpoch|unset|until|untilStep|untitle|upper|urlJoin|urlParse|urlquery|uuidv4|values|without|wrap|wrapWith)$"))

; Delimiters

"." @punctuation.delimiter
"," @punctuation.delimiter

"{{" @punctuation.bracket
"}}" @punctuation.bracket
"{{-" @punctuation.bracket
"-}}" @punctuation.bracket
")" @punctuation.bracket
"(" @punctuation.bracket

; Keywords

"else" @keyword
"if" @keyword
"range" @keyword
"with" @keyword
"end" @keyword
"template" @keyword
"define" @keyword
"block" @keyword

; Literals

[
  (interpreted_string_literal)
  (raw_string_literal)
  (rune_literal)
] @string

(escape_sequence) @string.special

[
  (int_literal)
  (float_literal)
  (imaginary_literal)
] @number

[
  (true)
  (false)
  (nil)
] @constant.builtin

(comment) @comment
(ERROR) @error
