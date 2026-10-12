"fn" @keyword.function
["import" "from" "as"] @keyword.control.import
(export_declaration "export" @keyword.control.import)
["data" "type" "is" "effect" "const" "let" "use"] @keyword.storage.type
(entry_modifier) @variable
((entry_binding (entry_modifier) @keyword.storage.modifier) @_entry
  (#match? @_entry "^entry[ \t]+(const|let)"))
(entry_binding (binding_keyword) @keyword.storage.type)
(private_modifier) @variable
(opaque_modifier) @variable
((private_binding (private_modifier) @keyword.storage.modifier) @_private
  (#match? @_private "^private[ \t]+(entry[ \t]+)?(const|let)"))
((private_effect_header (private_modifier) @keyword.storage.modifier) @_private_effect
  (#match? @_private_effect "^private[ \t]+effect"))
((type_header . (private_modifier) @keyword.storage.modifier
    (opaque_modifier)? @keyword.storage.modifier) @_private_type
  (#match? @_private_type "^private[ \t]+(opaque[ \t]+)?(type|data)"))
((type_header . (opaque_modifier) @keyword.storage.modifier) @_opaque
  (#match? @_opaque "^opaque[ \t]+type"))
(where_clause "where" @keyword.control)
(contract_header "contract" @keyword.storage.type)
["infixl" "infixr" "infix" "prefix"] @keyword.directive
"rec" @keyword.storage.modifier
["if" "then" "else" "case" "of"] @keyword.control.conditional
["for" "in" "continue"] @keyword.control.repeat
(ever_loop "ever" @keyword.control.repeat)
["return" "break" "yield"] @keyword.control.return
(request_complete_header "complete" @keyword.control)
["do" "test"] @keyword.control

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
"~" @operator
"=>" @operator
(separator) @punctuation.delimiter
(comment) @comment
"." @punctuation.delimiter
["(" ")" "[" "]" "{" "}"] @punctuation.bracket

(function_binding name: (identifier) @function)
(qualified_function_name name: (identifier) @function)
(infix_function "`" @operator)
(infix_function name: (identifier) @function)
(infix_function qualifier: (identifier) @namespace)
(lambda_header parameter: (identifier) @variable.parameter)
(request_complete_header parameter: (identifier) @variable.parameter)
(completion_constructor_pattern (identifier) @variable.parameter)
(deferred_parameter (identifier) @variable.parameter)
(deferred_parameter (parenthesized (identifier) @variable.parameter))
(lambda_header parameter: (parenthesized (identifier) @variable.parameter))
(record_field name: (identifier) @variable.other.member)
(type_parameter_field name: (identifier) @variable.other.member)
(member name: (_) @variable.other.member)
(method_call name: (identifier) @function.method)
(declaration_tag callee: (tag_callee (identifier) @attribute))
(declaration_tag callee: (tag_callee (type_identifier) @attribute))
["#" "@"] @punctuation.special
(spread) @operator
(forward_return "$" @punctuation.special)

(text_literal "\"" @string)
(text_fragment) @string
(escape_sequence) @constant.character.escape

(constructor_marker) @punctuation.special
(constructor_reference qualifier: (_) @namespace)
(constructor_reference name: (type_identifier) @constructor)
