// Parse-specific error identities to merge into blot_error::Error.
namespace blot_parse_error;
enum ParseError { source_limit, symbol_limit, syntax, invalid_integer, integer_range, invalid_float, float_range, invalid_utf8 }
