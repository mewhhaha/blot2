// A permissive highlighting grammar for Blot, not a validating compiler parser.
// Shallow headers and balanced delimiters keep unsettled forms highlightable
// without duplicating the compiler's layout or expression grammar.
export default grammar({
  name: "blot",

  extras: ($) => [/\s+/, $.comment],
  word: ($) => $._identifier,

  conflicts: (
    $,
  ) => [
    [$.function_binding, $._syntax],
    [$.import_declaration, $.keyword],
    [$.export_declaration, $.identifier],
    [$.entry_binding, $.identifier],
    [$.io_function_header, $.identifier],
    [$.io_function_header, $.private_binding, $.identifier],
    [$.private_binding, $.identifier],
    [$.private_effect_header, $.identifier],
    [$.request_complete_header, $.identifier],
    [$.handler_header, $.identifier],
  ],

  rules: {
    source_file: ($) => repeat($._syntax),

    _syntax: ($) =>
      choice(
        $.import_declaration,
        $.export_declaration,
        $.function_binding,
        $.entry_kernel_function_header,
        $.entry_kernel_binding,
        $.entry_process_binding,
        $.io_function_header,
        $.named_function_header,
        $.lambda_header,
        $.type_header,
        $.curried_type_header,
        $.forward_break,
        $.declaration_tag,
        $.constructor_reference,
        $.staging_marker,
        $.where_clause,
        $.contract_header,
        $.opaque_header,
        $.implementation_header,
        $.parenthesized,
        $.bracketed,
        $.array,
        $.spread,
        $.braced,
        $.reflected_member,
        $.method_call,
        $.member,
        $.byte_string_literal,
        $.char_literal,
        $.text_literal,
        $.intrinsic,
        $.float,
        $.integer,
        $.boolean,
        $.self,
        $.entry_binding,
        $.private_binding,
        $.private_effect_header,
        $.ever_loop,
        $.request_effect_header,
        $.request_complete_header,
        $.handler_header,
        $.binding_keyword,
        $.keyword,
        $.identifier,
        $.type_identifier,
        $.operator,
        $.separator,
      ),

    import_declaration: ($) =>
      prec.dynamic(
        3,
        seq(
          "import",
          choice(seq("*", "as", $.identifier), $.braced),
          "from",
          $.text_literal,
        ),
      ),

    export_declaration: ($) =>
      prec.dynamic(3, seq("export", $.braced, "from", $.text_literal)),

    function_binding: ($) =>
      prec.dynamic(
        2,
        prec.right(seq(
          choice($.binding_keyword, $.entry_binding, $.private_binding),
          field(
            "name",
            choice($.identifier, $.qualified_function_name, $.operator_name),
          ),
          optional($.binding_annotation),
          alias("=", $.operator),
          choice($.lambda_header, $.grouped_lambda),
        )),
      ),

    grouped_lambda: ($) =>
      seq(
        "(",
        choice($.lambda_header, $.grouped_lambda),
        repeat($._syntax),
        ")",
      ),

    qualified_function_name: ($) =>
      prec(
        3,
        seq(
          field("owner", choice($.identifier, $.type_identifier)),
          repeat(
            seq(".", field("owner", choice($.identifier, $.type_identifier))),
          ),
          ".",
          field("name", $.identifier),
        ),
      ),

    lambda_header: ($) =>
      prec.right(
        2,
        seq(
          "func",
          field("parameter", $._parameter),
          repeat(seq("->", field("parameter", $._parameter))),
        ),
      ),

    entry_kernel_function_header: ($) =>
      prec.dynamic(
        4,
        prec.right(
          3,
          seq(
            $.kernel_modifier,
            "func",
            field("name", choice($.identifier, $.qualified_function_name)),
            field("parameter", $._parameter),
            repeat(seq("->", field("parameter", $._parameter))),
          ),
        ),
      ),

    entry_kernel_binding: ($) =>
      prec.dynamic(
        2,
        seq(
          $.kernel_modifier,
          "const",
          field("name", $.identifier),
          alias(":", $.separator),
        ),
      ),

    entry_process_binding: ($) =>
      prec.dynamic(
        2,
        seq(
          $.process_modifier,
          "const",
          field("name", $.identifier),
          alias(":", $.separator),
        ),
      ),

    io_function_header: ($) =>
      choice(
        prec.dynamic(
          2,
          seq(
            alias("private", $.private_modifier),
            alias("io", $.io_modifier),
            field("name", choice($.identifier, $.qualified_function_name)),
            field("parameter", $._parameter),
            repeat(seq("->", field("parameter", $._parameter))),
            optional($.binding_annotation),
            optional($.where_clause),
            alias("=>", $.operator),
          ),
        ),
        prec.dynamic(
          1,
          seq(
            alias("io", $.io_modifier),
            field("name", choice($.identifier, $.qualified_function_name)),
            field("parameter", $._parameter),
            repeat(seq("->", field("parameter", $._parameter))),
            optional($.binding_annotation),
            optional($.where_clause),
            alias("=>", $.operator),
          ),
        ),
      ),

    named_function_header: ($) =>
      prec.dynamic(
        3,
        prec.right(
          3,
          seq(
            optional(alias("private", $.private_modifier)),
            "func",
            field(
              "name",
              choice($.identifier, $.qualified_function_name, $.operator_name),
            ),
            field("parameter", $._parameter),
            repeat(seq("->", field("parameter", $._parameter))),
          ),
        ),
      ),

    operator_name: ($) => prec(2, seq("(", field("symbol", $.operator), ")")),

    _parameter: ($) =>
      choice(
        $.identifier,
        $.type_identifier,
        $.parenthesized,
        $.bracketed,
        $.braced,
      ),

    binding_keyword: (_) => choice("const", "let"),

    kernel_modifier: (_) => "#kernel",
    process_modifier: (_) => "#process",

    entry_binding: ($) =>
      prec.dynamic(1, seq(alias("io", $.io_modifier), $.binding_keyword)),

    private_binding: ($) =>
      prec.dynamic(
        1,
        seq(
          alias("private", $.private_modifier),
          choice($.entry_binding, $.binding_keyword),
        ),
      ),

    private_effect_header: ($) =>
      seq(alias("private", $.private_modifier), "effect"),

    ever_loop: ($) => seq("for", "ever", alias(":", $.separator)),

    handler_header: ($) =>
      prec.dynamic(
        2,
        seq("handler", field("name", $.identifier), alias(":", $.separator)),
      ),

    // Keep request clauses shallow, like function and type headers. `complete`
    // is contextual, so bindings and function parameters can still use it.
    request_effect_header: ($) =>
      prec(
        4,
        seq(
          "effect",
          field(
            "operation",
            choice(
              $.request_operation_name,
              $.parenthesized,
            ),
          ),
        ),
      ),

    request_operation_name: ($) =>
      prec.right(seq(
        choice($.identifier, $.type_identifier),
        repeat(seq(".", choice($.identifier, $.type_identifier))),
      )),

    request_complete_header: ($) =>
      prec.dynamic(
        1,
        seq(
          "complete",
          field(
            "parameter",
            choice(
              $.identifier,
              $.integer,
              $.parenthesized,
              $.bracketed,
              $.braced,
              $.completion_constructor_pattern,
            ),
          ),
          alias("=>", $.operator),
        ),
      ),

    completion_constructor_pattern: ($) =>
      seq(
        $.constructor_reference,
        optional(choice(
          $.identifier,
          $.integer,
          $.parenthesized,
          $.braced,
          $.completion_constructor_pattern,
        )),
      ),

    binding_annotation: ($) =>
      seq(
        alias(":", $.separator),
        repeat1(choice(
          $.identifier,
          $.type_identifier,
          $.parenthesized,
          $.bracketed,
          $.array,
          $.braced,
          $.member,
          alias("->", $.operator),
          alias("!", $.operator),
          alias("|", $.operator),
        )),
      ),

    // Highlight the contextual clause without treating `where` as a global
    // keyword: `const where` and `func where =>` remain ordinary identifiers.
    where_clause: ($) => prec(4, seq("where", $.braced)),
    contract_header: ($) => prec(4, seq("is", choice("contract", "trait"), "=")),
    opaque_header: ($) => prec(4, seq("is", "opaque", "=")),
    implementation_header: ($) =>
      prec(
        4,
        seq(
          optional(alias("private", $.private_modifier)),
          "impl",
          field("name", $.type_identifier),
          optional($._type_parameter),
          repeat(seq("=>", "type", $._type_parameter)),
          alias(":", $.separator),
        ),
      ),

    type_header: ($) =>
      prec.right(
        2,
        seq(
          optional(alias("private", $.private_modifier)),
          choice("type", "data"),
          field("name", $.type_identifier),
          optional(field("parameter", $._type_parameter)),
        ),
      ),

    curried_type_header: ($) =>
      prec(1, seq("=>", "type", field("parameter", $._type_parameter))),

    _type_parameter: ($) =>
      choice(
        alias($.identifier, $.type_parameter),
        $.type_parameter_tuple,
        $.type_parameter_array,
        $.type_parameter_record,
      ),

    type_parameter_tuple: ($) =>
      seq("(", commaSeparated($._type_parameter), ")"),
    type_parameter_array: ($) =>
      seq("[", commaSeparated($._type_parameter), "]"),
    type_parameter_record: ($) =>
      seq(
        "{",
        commaSeparated(choice(
          $.type_parameter_field,
          alias($.identifier, $.type_parameter),
        )),
        "}",
      ),
    type_parameter_field: ($) =>
      seq(field("name", $.identifier), ":", $._type_parameter),

    forward_break: (_) => seq("break", alias(token(/\$[ \t]+/), "$")),

    constructor_marker: (_) => prec(-1, "$"),
    staging_marker: (_) =>
      token(prec(3, choice("#run", "#do", "#for", "#if", "#else", "#fields", "#variants"))),
    constructor_reference: ($) =>
      prec.right(
        2,
        seq(
          $.constructor_marker,
          repeat(seq(
            field(
              "qualifier",
              choice(
                alias(token.immediate(/[a-z_][A-Za-z_0-9]*/), $.identifier),
                alias($._constructor_type_identifier, $.type_identifier),
              ),
            ),
            token.immediate("."),
          )),
          field(
            "name",
            alias($._constructor_type_identifier, $.type_identifier),
          ),
        ),
      ),

    _constructor_type_identifier: (_) => token.immediate(/[A-Z][A-Za-z_0-9]*/),

    declaration_tag: ($) =>
      seq(
        "@",
        "[",
        optional(field("callee", $.tag_callee)),
        repeat($._syntax),
        "]",
      ),
    tag_callee: ($) =>
      prec.right(
        3,
        seq(
          choice($.identifier, $.type_identifier),
          repeat(seq(".", choice($.identifier, $.type_identifier))),
        ),
      ),

    parenthesized: ($) => seq("(", repeat($._syntax), ")"),
    bracketed: ($) => seq("[", repeat($._syntax), "]"),
    array: ($) => prec(2, seq("#", "[", repeat($._syntax), "]")),
    spread: (_) => "...",
    braced: ($) => seq("{", repeat(choice($.record_field, $._syntax)), "}"),
    record_field: ($) => prec(1, seq(field("name", $.identifier), ":")),
    reflected_member: ($) => prec(2, seq(".", $.parenthesized)),
    method_call: ($) =>
      prec(2, seq(".", field("name", $.identifier), $.parenthesized)),
    member: ($) =>
      seq(
        ".",
        field("name", choice($.identifier, $.type_identifier, $.integer)),
      ),

    byte_string_literal: ($) =>
      seq(
        'b"',
        repeat(choice(
          $.text_fragment,
          $.byte_escape_sequence,
        )),
        '"',
      ),
    byte_escape_sequence: (_) =>
      token.immediate(/\\([ntr0"\\]|x[0-9A-Fa-f]{2})/),
    char_literal: (_) =>
      token(/'([^'\\\r\n]|\\(['"\\nrt0]|x[0-9A-Fa-f]{2}))'/),

    text_literal: ($) =>
      seq(
        '"',
        repeat(choice(
          $.text_fragment,
          $.escape_sequence,
        )),
        '"',
      ),
    // Native strings are single-line literals, including any `${...}` text.
    // Keep the accepted escapes in sync with lexer.zig.
    text_fragment: (_) => token.immediate(prec(1, /[^"\\\r\n]+/)),
    escape_sequence: (_) => token.immediate(/\\[ntr"\\]/),

    float: (_) =>
      token(
        /[0-9](_?[0-9])*((\.[0-9](_?[0-9])*([eE][+-]?[0-9](_?[0-9])*)?|[eE][+-]?[0-9](_?[0-9])*)(_?(f32|f64))?|_?(f32|f64))/,
      ),
    integer: (_) =>
      token(
        /(0[xX][0-9A-Fa-f](_?[0-9A-Fa-f])*|[0-9](_?[0-9])*)(_?(u8|u32|i32|u64|i64))?/,
      ),
    boolean: (_) => choice("true", "false"),
    self: (_) => "self",
    intrinsic: (_) =>
      token(/@[a-z_][a-z0-9_]*(\.([a-z_][a-z0-9_]*|[A-Z][A-Za-z0-9_]*))*/),
    _identifier: (_) => /[a-z_][A-Za-z0-9_]*/,
    identifier: ($) =>
      choice(
        $._identifier,
        "io",
        "complete",
        "private",
        "opaque",
        "export",
        "impl",
        "handler",
      ),
    type_identifier: (_) => /[A-Z][A-Za-z0-9_]*/,
    operator: (_) =>
      choice("and", "or", "not", "$", ":=", "=>", "..", /[+\-*\/%=!<>|&^~?$]+/),
    separator: (_) => choice(":", ",", ";"),
    keyword: (_) =>
      choice(
        "import",
        "as",
        "data",
        "type",
        "is",
        "effect",
        "use",
        "rec",
        "do",
        "fork",
        "own",
        "freeze",
        "copy",
        "panic",
        "return",
        "yield",
        "if",
        "then",
        "else",
        "case",
        "of",
        "for",
        "in",
        "break",
        "continue",
        "spark",
        "test",
      ),
    comment: (_) => token(/\/\/[^\r\n]*/),
  },
});

function commaSeparated(rule) {
  return optional(seq(rule, repeat(seq(",", rule)), optional(",")));
}
