// A permissive highlighting grammar for the design specimen, not a validator.
// Shallow headers and balanced delimiters keep unsettled forms highlightable
// without duplicating the compiler's layout or expression grammar.
export default grammar({
  name: "blot",

  extras: ($) => [/\s+/, $.comment],
  word: ($) => $.identifier,

  rules: {
    source_file: ($) => repeat($._syntax),

    _syntax: ($) =>
      choice(
        $.function_header,
        $.lambda_header,
        $.infix_function,
        $.forward_return,
        $.declaration_tag,
        $.parenthesized,
        $.bracketed,
        $.braced,
        $.member,
        $.text_literal,
        $.intrinsic,
        $.float,
        $.integer,
        $.boolean,
        $.self,
        $.keyword,
        $.identifier,
        $.type_identifier,
        $.operator,
        $.separator,
      ),

    function_header: ($) =>
      prec(
        2,
        seq(
          "fn",
          field("name", choice($.identifier, $.qualified_function_name)),
          field("parameter", $._parameter),
        ),
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

    deferred_parameter: ($) => seq("~", $.identifier),

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

    declaration_tag: ($) =>
      seq("#", "[", field("name", $.identifier), repeat($._syntax), "]"),

    parenthesized: ($) => seq("(", repeat($._syntax), ")"),
    bracketed: ($) => seq("[", repeat($._syntax), "]"),
    braced: ($) => seq("{", repeat(choice($.record_field, $._syntax)), "}"),
    record_field: ($) => prec(1, seq(field("name", $.identifier), ":")),
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
          $.interpolation,
          alias(token.immediate("$"), $.text_fragment),
        )),
        '"',
      ),
    text_fragment: (_) => token.immediate(prec(1, /[^"\\$]+/)),
    escape_sequence: (_) => token.immediate(/\\[ntr"\\$]/),
    interpolation: ($) => seq("${", repeat($._syntax), "}"),

    float: (_) =>
      token(
        /[0-9](_?[0-9])*(\.[0-9](_?[0-9])*([eE][+-]?[0-9](_?[0-9])*)?|[eE][+-]?[0-9](_?[0-9])*)/,
      ),
    integer: (_) => token(/0[xX][0-9A-Fa-f](_?[0-9A-Fa-f])*|[0-9](_?[0-9])*/),
    boolean: (_) => choice("True", "False"),
    self: (_) => "self",
    intrinsic: (_) => token(/@[a-z_][A-Za-z0-9_]*(\.[a-z_][A-Za-z0-9_]*)*/),
    identifier: (_) => /[a-z_][A-Za-z0-9_]*/,
    type_identifier: (_) => /[A-Z][A-Za-z0-9_]*/,
    operator: (_) => choice(":=", "..", "...", /[+\-*\/%=!<>|&^~?]+/),
    separator: (_) => choice(":", ",", ";"),
    keyword: (_) =>
      choice(
        "import",
        "export",
        "from",
        "as",
        "data",
        "type",
        "infixl",
        "infixr",
        "infix",
        "prefix",
        "effect",
        "const",
        "let",
        "use",
        "rec",
        "do",
        "return",
        "if",
        "else",
        "case",
        "for",
        "in",
        "break",
        "continue",
        "test",
      ),
    comment: (_) => token(/\/\/[^\r\n]*/),
  },
});
