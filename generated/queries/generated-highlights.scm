"!" @operator
"#" @operator
"$" @operator
"(" @punctuation.bracket
")" @punctuation.bracket
"*" @operator
"," @punctuation.delimiter
"->" @operator
"." @punctuation.delimiter
".." @operator
"..." @operator
":" @punctuation.delimiter
":=" @operator
"<-" @operator
"=" @operator
"=>" @operator
"@" @operator
"[" @punctuation.bracket
"]" @punctuation.bracket
"^" @operator
"`" @operator
"{" @punctuation.bracket
"|" @operator
"}" @punctuation.bracket
"~" @operator
"·" @operator
(binding_else "else" @keyword)
(binding "let" @keyword)
(boolean_constructor_pattern value: "False" @keyword)
(boolean_constructor_pattern value: "True" @keyword)
(case_arm "if" @keyword)
(case_expression "case" @keyword)
(case_expression "of" @keyword)
(collection_if "else" @keyword)
(collection_if "if" @keyword)
(collection_if "then" @keyword)
(collection_lambda "fn" @keyword)
(comprehension_binding "let" @keyword)
(conditional "if" @keyword)
(constructor_reference value: "False" @keyword)
(constructor_reference value: "True" @keyword)
(data_type "data" @keyword)
(data_type "is" @keyword)
(data_type "type" @keyword)
(do_block "do" @keyword)
(effect_binding "use" @keyword)
(effect_declaration "effect" @keyword)
(effect_step "use" @keyword)
(effect_type "effect" @keyword)
(effect_type "is" @keyword)
(effect_type "type" @keyword)
(else_clause "else" @keyword)
(ever_statement "ever" @keyword)
(ever_statement "for" @keyword)
(for_statement "for" @keyword)
(for_statement "in" @keyword)
(for_statement "let" @keyword)
(if_expression "else" @keyword)
(if_expression "if" @keyword)
(if_expression "then" @keyword)
(import_binding alias: "as" @keyword)
(import_declaration "froM" @keyword)
(import_declaration "import" @keyword)
(lambda "fn" @keyword)
(named_fixity associativity: "infix" @keyword)
(named_fixity associativity: "infixl" @keyword)
(named_fixity associativity: "infixr" @keyword)
(namespace_import "as" @keyword)
(pattern_conditional "if" @keyword)
(pattern_conditional "let" @keyword)
(range_statement "for" @keyword)
(reply "yield" @keyword)
(request_arm kind: "complete" @keyword)
(request_arm kind: "effect" @keyword)
(request_case "case" @keyword)
(request_case "of" @keyword)
(result "return" @keyword)
(symbolic_fixity associativity: "infix" @keyword)
(symbolic_fixity associativity: "infixl" @keyword)
(symbolic_fixity associativity: "infixr" @keyword)
(value_declaration kind: "const" @keyword)
(value_declaration kind: "let" @keyword)
(where_clause marker: "wherE" @keyword)
(effect_type) @type
(data_type) @type
(type_array) @type
(type_record) @type
(type_field) @variable.other.member
(type_expression) @type
(type_application) @type
(demand_type) @type
(type_atom) @type
(type_group) @type
(member_access) @variable.other.member
(type_witness) @type
(record) @type
(record_values) @type
(record_value) @type
(boolean_constructor_pattern) @constant.builtin
(record_pattern) @type
(record_pattern_field) @variable.other.member
(TYPE_IDENT) @type
(INTEGER) @number
(FLOAT) @number
(STRING) @string
(INTRINSIC) @function.builtin
(COMMENT) @comment
(comprehension_binding name: (IDENT) @variable)
(data_type name: (TYPE_IDENT) @type)
(effect_binding name: (IDENT) @variable)
(effect_type name: (TYPE_IDENT) @type)
(import_binding name: (IDENT) @variable)
(import_binding name: (TYPE_IDENT) @variable)
(member_access name: (IDENT) @variable.other.member)
(member_access name: (TYPE_IDENT) @variable.other.member)
(named_fixity target: (qualified_name) @variable)
(parameter name: (IDENT) @variable)
(record_pattern_field name: (IDENT) @type)
(record_value name: (IDENT) @type)
(record name: (qualified_name) @type)
(symbolic_fixity target: (qualified_name) @variable)
(type_field name: (IDENT) @type)
