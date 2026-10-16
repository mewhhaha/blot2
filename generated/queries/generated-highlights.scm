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
(code_type "code" @keyword)
(code_type "row" @keyword)
(collection_if "else" @keyword)
(collection_if "if" @keyword)
(collection_if "then" @keyword)
(collection_lambda "fn" @keyword)
(comprehension_binding "let" @keyword)
(conditional "if" @keyword)
(constructor_reference value: "False" @keyword)
(constructor_reference value: "True" @keyword)
(contract_type_member "type" @keyword)
(contract_type "is" @keyword)
(contract_type "type" @keyword)
(contract_value_member "const" @keyword)
(data_type "data" @keyword)
(data_type "is" @keyword)
(data_type "type" @keyword)
(declaration visibility: "privatE" @keyword)
(descriptor_type "descriptor" @keyword)
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
(export_declaration "exporT" @keyword)
(export_declaration "froM" @keyword)
(for_statement "for" @keyword)
(for_statement "in" @keyword)
(for_statement "let" @keyword)
(if_expression "else" @keyword)
(if_expression "if" @keyword)
(if_expression "then" @keyword)
(implementation_declaration "type" @keyword)
(implementation_declaration marker: "impL" @keyword)
(implementation_type_member "type" @keyword)
(implementation_value_member "const" @keyword)
(import_binding alias: "as" @keyword)
(import_declaration "froM" @keyword)
(import_declaration "import" @keyword)
(lambda "fn" @keyword)
(named_fixity associativity: "infix" @keyword)
(named_fixity associativity: "infixl" @keyword)
(named_fixity associativity: "infixr" @keyword)
(namespace_import "as" @keyword)
(opaque_type "opaquE" @keyword)
(package_pack "as" @keyword)
(package_pack "pack" @keyword)
(package_unpack "as" @keyword)
(package_unpack "in" @keyword)
(package_unpack "unpack" @keyword)
(pattern_conditional "if" @keyword)
(pattern_conditional "let" @keyword)
(quantified_binder name: "borrow" @keyword)
(quantified_binder name: "borrow_mut" @keyword)
(quantified_binder name: "cleanup" @keyword)
(quantified_binder name: "concurrent" @keyword)
(quantified_binder name: "exists" @keyword)
(quantified_binder name: "forall" @keyword)
(quantified_binder name: "many" @keyword)
(quantified_binder name: "once" @keyword)
(quantified_binder name: "pack" @keyword)
(quantified_binder name: "shared" @keyword)
(quantified_binder name: "unique" @keyword)
(quantified_binder name: "unpack" @keyword)
(quantified_binder name: "where" @keyword)
(quantified_binder sort: "region" @keyword)
(quantified_binder sort: "row" @keyword)
(quantified_type kind: "exists" @keyword)
(quantified_type kind: "forall" @keyword)
(quantified_where "where" @keyword)
(quantified_where "wherE" @keyword)
(range_statement "for" @keyword)
(reply "yield" @keyword)
(request_arm kind: "complete" @keyword)
(request_arm kind: "effect" @keyword)
(request_case "case" @keyword)
(request_case "of" @keyword)
(result "return" @keyword)
(source_identifier "borrow" @keyword)
(source_identifier "borrow_mut" @keyword)
(source_identifier "cleanup" @keyword)
(source_identifier "code" @keyword)
(source_identifier "concurrent" @keyword)
(source_identifier "descriptor" @keyword)
(source_identifier "exists" @keyword)
(source_identifier "forall" @keyword)
(source_identifier "many" @keyword)
(source_identifier "once" @keyword)
(source_identifier "pack" @keyword)
(source_identifier "region" @keyword)
(source_identifier "row" @keyword)
(source_identifier "shared" @keyword)
(source_identifier "unique" @keyword)
(source_identifier "unpack" @keyword)
(source_identifier "where" @keyword)
(symbolic_fixity associativity: "infix" @keyword)
(symbolic_fixity associativity: "infixl" @keyword)
(symbolic_fixity associativity: "infixr" @keyword)
(type_alias "type" @keyword)
(usage_type kind: "borrow" @keyword)
(usage_type kind: "borrow_mut" @keyword)
(usage_type kind: "cleanup" @keyword)
(usage_type kind: "concurrent" @keyword)
(usage_type kind: "many" @keyword)
(usage_type kind: "once" @keyword)
(usage_type kind: "shared" @keyword)
(usage_type kind: "unique" @keyword)
(value_declaration kind: "const" @keyword)
(value_declaration kind: "let" @keyword)
(where_clause marker: "wherE" @keyword)
(opaque_type) @type
(type_alias) @type
(contract_type) @type
(implementation_member) @variable.other.member
(implementation_type_member) @variable.other.member
(implementation_value_member) @variable.other.member
(effect_type) @type
(data_type) @type
(type_array) @type
(type_record) @type
(type_field) @variable.other.member
(type_expression) @type
(contract_member) @variable.other.member
(contract_type_member) @variable.other.member
(contract_value_member) @variable.other.member
(type_application) @type
(demand_type) @type
(type_atom) @type
(code_type) @type
(descriptor_type) @type
(proof_type) @type
(usage_type) @type
(type_binder) @type
(type_group) @type
(member_access) @variable.other.member
(type_witness) @type
(record) @type
(record_values) @type
(record_value) @type
(boolean_constructor_pattern) @constant.builtin
(record_pattern) @type
(record_pattern_field) @variable.other.member
(quantified_type) @type
(TYPE_IDENT) @type
(INTEGER) @number
(FLOAT) @number
(STRING) @string
(INTRINSIC) @function.builtin
(PROOF_TYPE) @type
(COMMENT) @comment
(comprehension_binding name: (source_identifier) @variable)
(contract_type_member name: (TYPE_IDENT) @type)
(contract_type name: (TYPE_IDENT) @type)
(contract_value_member name: (source_identifier) @variable.other.member)
(contract_value_member name: (TYPE_IDENT) @variable.other.member)
(data_type name: (TYPE_IDENT) @type)
(effect_binding name: (source_identifier) @variable)
(effect_type name: (TYPE_IDENT) @type)
(implementation_type_member name: (TYPE_IDENT) @type)
(implementation_value_member name: (source_identifier) @variable.other.member)
(implementation_value_member name: (TYPE_IDENT) @variable.other.member)
(import_binding name: (source_identifier) @variable)
(import_binding name: (TYPE_IDENT) @variable)
(member_access name: (source_identifier) @variable.other.member)
(member_access name: (TYPE_IDENT) @variable.other.member)
(named_fixity target: (qualified_name) @variable)
(parameter name: (source_identifier) @variable)
(record_pattern_field name: (source_identifier) @type)
(record_value name: (source_identifier) @type)
(record name: (qualified_name) @type)
(symbolic_fixity target: (qualified_name) @variable)
(type_alias name: (TYPE_IDENT) @type)
(type_binder name: (source_identifier) @type)
(type_field name: (source_identifier) @type)
(typed_parameter name: (source_identifier) @variable)
