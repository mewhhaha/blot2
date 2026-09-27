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
":" @punctuation.delimiter
":=" @operator
"<-" @operator
"=" @operator
"=>" @operator
"[" @punctuation.bracket
"]" @punctuation.bracket
"^" @operator
"`" @operator
"{" @punctuation.bracket
"|" @operator
"}" @punctuation.bracket
(atom "False" @keyword)
(atom "True" @keyword)
(binding_else "else" @keyword)
(binding "let" @keyword)
(case_expression "case" @keyword)
(case_expression "of" @keyword)
(conditional "if" @keyword)
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
(import_binding alias: "as" @keyword)
(import_declaration "from" @keyword)
(import_declaration "import" @keyword)
(lambda "fn" @keyword)
(named_fixity associativity: "infix" @keyword)
(named_fixity associativity: "infixl" @keyword)
(named_fixity associativity: "infixr" @keyword)
(namespace_import "as" @keyword)
(pattern_conditional "if" @keyword)
(pattern_conditional "let" @keyword)
(pattern "False" @keyword)
(pattern "True" @keyword)
(range_statement "for" @keyword)
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
(type_atom) @type
(type_group) @type
(member_access) @variable.other.member
(record) @type
(record_values) @type
(record_value) @type
(record_pattern) @type
(record_pattern_field) @variable.other.member
(TYPE_IDENT) @type
(INTEGER) @number
(FLOAT) @number
(STRING) @string
(INTRINSIC) @function.builtin
(COMMENT) @comment
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
