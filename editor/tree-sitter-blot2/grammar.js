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
    [$.entry_binding, $.identifier],
    [$.request_complete_header, $.identifier],
  ],

  rules: {
    source_file: ($) => repeat($._syntax),

    _syntax: ($) =>
      choice(
        $.import_declaration,
        $.function_binding,
        $.lambda_header,
        $.type_header,
        $.curried_type_header,
        $.infix_function,
        $.forward_return,
        $.declaration_tag,
        $.constructor_reference,
        $.constructor_marker,
        $.where_clause,
        $.parenthesized,
        $.bracketed,
        $.array,
        $.spread,
        $.braced,
        $.method_call,
        $.member,
        $.text_literal,
        $.intrinsic,
        $.float,
        $.integer,
        $.boolean,
        $.self,
        $.entry_binding,
        $.ever_loop,
        $.request_effect_header,
        $.request_complete_header,
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

    function_binding: ($) =>
      prec.dynamic(
        2,
        seq(
          choice($.binding_keyword, $.entry_binding),
          field("name", choice($.identifier, $.qualified_function_name)),
          optional($.binding_annotation),
          alias("=", $.operator),
          choice($.lambda_header, $.grouped_lambda),
        ),
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
          field("owner", $.type_identifier),
          ".",
          field("name", $.identifier),
        ),
      ),

    lambda_header: ($) =>
      prec(
        1,
        seq(
          "fn",
          field("parameter", $._parameter),
        ),
      ),

    _parameter: ($) =>
      choice(
        $.identifier,
        $.type_identifier,
        $.parenthesized,
        $.bracketed,
        $.braced,
        $.deferred_parameter,
      ),

    deferred_parameter: ($) => seq("~", choice($.identifier, $.parenthesized)),

    binding_keyword: (_) => choice("const", "let"),

    // The query checks that both keywords are on the same line. Keeping spaces
    // as ordinary extras avoids stealing whitespace after variable `entry`.
    entry_binding: ($) =>
      prec.dynamic(
        1,
        seq(alias("entry", $.entry_modifier), $.binding_keyword),
      ),

    ever_loop: ($) => seq("for", "ever", alias(":", $.separator)),

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
          $.braced,
          $.member,
          alias("->", $.operator),
          alias("!", $.operator),
        )),
      ),

    // Highlight the contextual clause without treating `where` as a global
    // keyword: `const where` and `fn where =>` remain ordinary identifiers.
    where_clause: ($) => prec(4, seq("where", $.braced)),

    type_header: ($) =>
      prec.right(
        2,
        seq(
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

    infix_function: ($) =>
      seq(
        "`",
        repeat(seq(
          field("qualifier", choice($.identifier, $.type_identifier)),
          ".",
        )),
        field("name", $.identifier),
        "`",
      ),

    forward_return: (_) => seq("return", "$"),

    constructor_marker: (_) => prec(-1, "#"),
    constructor_reference: ($) =>
      prec.right(
        2,
        seq(
          $.constructor_marker,
          repeat(seq(
            field("qualifier", choice($.identifier, $.type_identifier)),
            ".",
          )),
          field("name", choice($.type_identifier, $.boolean)),
        ),
      ),

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
    method_call: ($) =>
      prec(2, seq(".", field("name", $.identifier), $.parenthesized)),
    member: ($) =>
      seq(
        ".",
        field("name", choice($.identifier, $.type_identifier, $.integer)),
      ),

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
        /[0-9](_?[0-9])*(\.[0-9](_?[0-9])*([eE][+-]?[0-9](_?[0-9])*)?|[eE][+-]?[0-9](_?[0-9])*)/,
      ),
    integer: (_) => token(/0[xX][0-9A-Fa-f](_?[0-9A-Fa-f])*|[0-9](_?[0-9])*/),
    boolean: (_) => choice("True", "False"),
    self: (_) => "self",
    intrinsic: (_) => token(/@[a-z_][A-Za-z0-9_]*(\.[a-z_][A-Za-z0-9_]*)*/),
    _identifier: (_) => /[a-z_][A-Za-z0-9_]*/,
    identifier: ($) => choice($._identifier, "complete", "entry"),
    type_identifier: (_) => /[A-Z][A-Za-z0-9_]*/,
    operator: (_) => choice(":=", "=>", "..", /[+\-*\/%=!<>|&^~?$]+/),
    separator: (_) => choice(":", ",", ";"),
    keyword: (_) =>
      choice(
        "import",
        "as",
        "data",
        "type",
        "is",
        "infixl",
        "infixr",
        "infix",
        "prefix",
        "effect",
        "use",
        "rec",
        "do",
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
        "test",
      ),
    comment: (_) => token(/\/\/[^\r\n]*/),
  },
});

function commaSeparated(rule) {
  return optional(seq(rule, repeat(seq(",", rule)), optional(",")));
}
