"!" @operator
"#" @operator
"$" @operator
"(" @punctuation.bracket
")" @punctuation.bracket
"*" @operator
"," @punctuation.delimiter
"->" @operator
"." @punctuation.delimiter
":" @punctuation.delimiter
"<-" @operator
"=" @operator
"=>" @operator
"[" @punctuation.bracket
"]" @punctuation.bracket
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
(constant "const" @keyword)
(data_type "data" @keyword)
(declaration exported: "export" @keyword)
(do_block "do" @keyword)
(effect_binding "use" @keyword)
(effect_declaration "effect" @keyword)
(effect_step "use" @keyword)
(else_clause "else" @keyword)
(function "fn" @keyword)
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
(result "return" @keyword)
(symbolic_fixity associativity: "infix" @keyword)
(symbolic_fixity associativity: "infixl" @keyword)
(symbolic_fixity associativity: "infixr" @keyword)
(constant) @constant.builtin
(data_type) @type
(record_fields) @type
(record_field) @variable.other.member
(type_expression) @type
(type_application) @type
(type_atom) @type
(type_group) @type
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
(function name: (qualified_name) @function)
(import_binding name: (IDENT) @variable)
(import_binding name: (TYPE_IDENT) @variable)
(named_fixity target: (qualified_name) @variable)
(parameter name: (IDENT) @variable)
(record_field name: (IDENT) @type)
(record_pattern_field name: (IDENT) @type)
(record_value name: (IDENT) @type)
(record name: (qualified_name) @type)
(symbolic_fixity target: (qualified_name) @variable)
