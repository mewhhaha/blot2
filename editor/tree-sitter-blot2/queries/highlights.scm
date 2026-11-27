["import" "from" "as"] @keyword.control.import
(export_declaration "export" @keyword.control.import)
["data" "type" "is" "effect" "const" "let" "use"] @keyword.storage.type
[(kernel_modifier) (process_modifier)] @keyword.storage.modifier
(private_modifier) @variable
(io_modifier) @variable
((io_function_header
    (io_modifier) @keyword.storage.modifier) @_io_function
  (#match? @_io_function "^(private[ \t]+)?io[ \t]+"))
((io_function_header
    (private_modifier) @keyword.storage.modifier) @_io_private_function
  (#match? @_io_private_function "^private[ \t]+io[ \t]+"))
((entry_binding
    (io_modifier) @keyword.storage.modifier) @_io_binding
  (#match? @_io_binding "^io[ \t]+(const|let)"))
(entry_binding (binding_keyword) @keyword.storage.type)
((named_function_header
    (private_modifier) @keyword.storage.modifier) @_named_function
  (#match? @_named_function "^(private[ \t]+)?func"))
"func" @keyword.function
((private_binding (private_modifier) @keyword.storage.modifier) @_private
  (#match? @_private "^private[ \t]+(io[ \t]+)?(const|let)"))
((private_effect_header (private_modifier) @keyword.storage.modifier) @_private_effect
  (#match? @_private_effect "^private[ \t]+effect"))
((type_header . (private_modifier) @keyword.storage.modifier) @_private_type
  (#match? @_private_type "^private[ \t]+(type|data)"))
(where_clause "where" @keyword.control)
(contract_header ["contract" "trait"] @keyword.storage.type)
(opaque_header "opaque" @keyword.storage.type)
(implementation_header "impl" @keyword.storage.type)
(implementation_header (private_modifier) @keyword.storage.modifier)
["rec" "own"] @keyword.storage.modifier
["if" "then" "else" "case" "of"] @keyword.control.conditional
["for" "in" "continue"] @keyword.control.repeat
(ever_loop "ever" @keyword.control.repeat)
["return" "break" "yield" "panic"] @keyword.control.return
(request_complete_header "complete" @keyword.control)
(handler_header "handler" @keyword.storage.type)
["do" "fork" "freeze" "copy" "spark" "test"] @keyword.control

(self) @variable.builtin
(intrinsic) @function.builtin
(boolean) @constant.builtin.boolean
(type_identifier) @type
(type_parameter) @type.parameter
(identifier) @variable
(binding_annotation (identifier) @keyword.control
  (#eq? @keyword.control "where"))
(integer) @constant.numeric.integer
(float) @constant.numeric.float
(operator) @operator
["=" "=>" "->"] @operator
[(separator) ":" ","] @punctuation.delimiter
(comment) @comment
"." @punctuation.delimiter
["(" ")" "[" "]" "{" "}"] @punctuation.bracket

(function_binding name: (identifier) @function)
(entry_kernel_function_header name: (identifier) @function)
(entry_kernel_function_header parameter: (identifier) @variable.parameter)
(entry_kernel_function_header parameter: (parenthesized . (keyword "own")? . (identifier) @variable.parameter))
(io_function_header name: (identifier) @function)
(io_function_header parameter: (identifier) @variable.parameter)
(io_function_header parameter: (parenthesized . (keyword "own")? . (identifier) @variable.parameter))
(named_function_header name: (identifier) @function)
(named_function_header parameter: (identifier) @variable.parameter)
(named_function_header parameter: (parenthesized . (keyword "own")? . (identifier) @variable.parameter))
(qualified_function_name name: (identifier) @function)
(qualified_function_name owner: (identifier) @namespace)
(operator_name symbol: (operator) @operator)
(lambda_header parameter: (identifier) @variable.parameter)
(request_complete_header parameter: (identifier) @variable.parameter)
(completion_constructor_pattern (identifier) @variable.parameter)
(lambda_header parameter: (parenthesized . (keyword "own")? . (identifier) @variable.parameter))
(record_field name: (identifier) @variable.other.member)
(type_parameter_field name: (identifier) @variable.other.member)
(member name: (_) @variable.other.member)
(method_call name: (identifier) @function.method)
(declaration_tag callee: (tag_callee (identifier) @attribute))
(declaration_tag callee: (tag_callee (type_identifier) @attribute))
["#" "@"] @punctuation.special
(spread) @operator
(forward_break "$" @punctuation.special)

(byte_string_literal "b\"" @string)
(byte_string_literal "\"" @string)
(byte_escape_sequence) @constant.character.escape
(char_literal) @constant.character
(text_literal "\"" @string)
(text_fragment) @string
(escape_sequence) @constant.character.escape

(constructor_marker) @punctuation.special
(packed_marker) @punctuation.special
(staging_marker) @keyword.directive
(constructor_reference qualifier: (_) @namespace)
(constructor_reference name: (type_identifier) @constructor)
