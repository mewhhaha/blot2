"#[" @operator
"$" @operator
"(" @punctuation.bracket
")" @punctuation.bracket
"->" @operator
"." @punctuation.delimiter
":" @punctuation.delimiter
"<-" @operator
"=" @operator
"=>" @operator
"]" @punctuation.bracket
"`" @operator
"|" @operator
(atom "False" @keyword)
(atom "True" @keyword)
(binding_else "else" @keyword)
(binding "let" @keyword)
(case_expression "case" @keyword)
(conditional "if" @keyword)
(constant "const" @keyword)
(data_type "data" @keyword)
(declaration exported: "export" @keyword)
(do_block "do" @keyword)
(effect_binding "use" @keyword)
(effect_step "use" @keyword)
(else_clause "else" @keyword)
(function "fn" @keyword)
(lambda "fn" @keyword)
(named_fixity associativity: "infix" @keyword)
(named_fixity associativity: "infixl" @keyword)
(named_fixity associativity: "infixr" @keyword)
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
(type_expression) @type
(type_application) @type
(type_atom) @type
(type_group) @type
(TYPE_IDENT) @type
(INTEGER) @number
(INTRINSIC) @function.builtin
(COMMENT) @comment
(data_type name: (TYPE_IDENT) @type)
(effect_binding name: (IDENT) @variable)
(function name: (qualified_name) @function)
(named_fixity target: (qualified_name) @variable)
(parameter name: (IDENT) @variable)
(symbolic_fixity target: (qualified_name) @variable)
