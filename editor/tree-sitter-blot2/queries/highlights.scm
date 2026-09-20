"fn" @keyword.function
["import" "export" "from" "as"] @keyword.control.import
["data" "type" "effect" "const" "let" "use"] @keyword.storage.type
["infixl" "infixr" "infix" "prefix"] @keyword.directive
"rec" @keyword.storage.modifier
["if" "else" "case"] @keyword.control.conditional
["for" "in" "continue"] @keyword.control.repeat
["return" "break"] @keyword.control.return
["do" "test"] @keyword.control

(self) @variable.builtin
(intrinsic) @function.builtin
(boolean) @constant.builtin.boolean
(type_identifier) @type
(identifier) @variable
(integer) @constant.numeric.integer
(float) @constant.numeric.float
(operator) @operator
"~" @operator
(separator) @punctuation.delimiter
(comment) @comment
"." @punctuation.delimiter
["(" ")" "[" "]" "{" "}"] @punctuation.bracket

(function_header name: (identifier) @function)
(qualified_function_name name: (identifier) @function)
(infix_function "`" @operator)
(infix_function name: (identifier) @function)
(infix_function qualifier: (identifier) @namespace)
(function_header parameter: (identifier) @variable.parameter)
(lambda_header parameter: (identifier) @variable.parameter)
(deferred_parameter (identifier) @variable.parameter)
(function_header parameter: (parenthesized (identifier) @variable.parameter))
(lambda_header parameter: (parenthesized (identifier) @variable.parameter))
(record_field name: (identifier) @variable.other.member)
(member name: (_) @variable.other.member)
(declaration_tag name: (identifier) @attribute)
"#" @punctuation.special
(forward_return "$" @punctuation.special)

(text_literal "\"" @string)
(text_fragment) @string
(escape_sequence) @constant.character.escape
(interpolation "${" @punctuation.special "}" @punctuation.special)
