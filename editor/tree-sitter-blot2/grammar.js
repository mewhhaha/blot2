// A permissive highlighting grammar for the design specimen, not a validator.
// Shallow headers and balanced delimiters keep unsettled forms highlightable
// without duplicating the compiler's layout or expression grammar.
export default grammar({
  name: "blot",

  extras: ($) => [/\s+/, $.comment],
  word: ($) => $.identifier,

  conflicts: (
    $,
  ) => [[$.function_binding, $._syntax], [$.import_declaration, $.keyword]],

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
        $.constructor_marker,
        $.where_clause,
        $.parenthesized,
        $.bracketed,
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

    // `entry` is contextual: a declaration modifier only when `const` or `let`
    // follows on the same line, and an ordinary identifier everywhere else.
    // One token keeps `fn entry => entry` and a trailing `entry` before the
    // next declaration's line out of it.
    entry_binding: (_) =>
      token(prec(1, seq("entry", /[ \t]+/, choice("const", "let")))),

    ever_loop: ($) => seq("for", "ever", alias(":", $.separator)),

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

    declaration_tag: ($) =>
      seq(
        "#",
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
    operator: (_) => choice(":=", "=>", "..", "...", /[+\-*\/%=!<>|&^~?$]+/),
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
