import Base
import ./model.bend as M
import ./numeric_literal.bend as Numeric

# Baba's field-labelled tree crosses the host boundary without interpretation.
type Cst is Data:
  Cst{kind: String, field: String, text: String, offset: Nat, children: List<&2, Cst>}

def children_of(node: Cst) -> List<&2, Cst>:
  Cst{kind, field, text, offset, children} = node
  children

def kind_of(node: Cst) -> String:
  Cst{kind, field, text, offset, children} = node
  kind

def text_of(node: Cst) -> String:
  Cst{kind, field, text, offset, children} = node
  text

def offset_of(node: Cst) -> Nat:
  Cst{kind, field, text, offset, children} = node
  offset

def diagnostic(node: Cst, code: String, message: String) -> M.Diagnostic:
  M.Diagnostic{code, "offset:" ++ Nat.show(offset_of(node)), message}

def fields_reversed(nodes: List<&2, Cst>, +label: String, +reversed: List<&2, Cst>) -> List<&2, Cst>:
  match nodes:
    case Nil{}:
      List.reverse(&2, Cst, reversed)
    case Cst{kind, +field, text, offset, children} <> tail:
      next = Bool.pick(List<&2, Cst>, M.name_equal(field, label), Cst{kind, field, text, offset, children} <> reversed, reversed)
      fields_reversed(tail, label, next)

def fields(nodes: List<&2, Cst>, label: String) -> List<&2, Cst>:
  fields_reversed(nodes, label, Nil{})

def field_values(node: Cst, label: String) -> List<&2, Cst>:
  fields(children_of(node), label)

def one(nodes: List<&2, Cst>) -> Result<&2, &2, M.Diagnostic, Cst>:
  match nodes:
    case node <> Nil{}:
      Done{node}
    case _:
      Fail{M.Diagnostic{"internal_cst", "parser", "expected exactly one Baba field value"}}

def texts(nodes: List<&2, Cst>) -> String:
  match nodes:
    case Nil{}:
      ""
    case head <> tail:
      text_of(head) ++ texts(tail)

def name_of(node: Cst) -> String:
  texts(children_of(node))

def present(nodes: List<&2, Cst>) -> Bool:
  match nodes:
    case Nil{}:
      False{}
    case head <> tail:
      True{}

def type_name(+node: Cst) -> String:
  Bool.pick(String, M.name_equal(kind_of(node), "qualified_name"), name_of(node), text_of(node))

def scalar_type(+node: Cst) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  +name = type_name(node)
  Bool.pick(Result<&2, &2, M.Diagnostic, M.Ty>, M.name_equal(name, "U32"), Done{M.U32Ty{}},
    Bool.pick(Result<&2, &2, M.Diagnostic, M.Ty>, M.name_equal(name, "F32"), Done{M.F32Ty{}},
    Bool.pick(Result<&2, &2, M.Diagnostic, M.Ty>, M.name_equal(name, "Bool"), Done{M.BoolTy{}},
      Bool.pick(Result<&2, &2, M.Diagnostic, M.Ty>, M.name_equal(name, "Unit"), Done{M.UnitTy{}},
      Bool.pick(Result<&2, &2, M.Diagnostic, M.Ty>, M.name_equal(name, "EffectDescriptor"), Done{M.EffectDescriptorTy{}},
      Bool.pick(Result<&2, &2, M.Diagnostic, M.Ty>, M.name_equal(name, "EffectSet"), Done{M.EffectSetTy{}},
        Fail{diagnostic(node, "unsupported_type", "unknown or unsupported type: " ++ name)}))))))

def literal_character(code: U32, node: Cst) -> Result<&2, &2, M.Diagnostic, Char>:
  match code:
    case 34:
      Done{Chr{34}}
    case 92:
      Done{Chr{92}}
    case 110:
      Done{Chr{10}}
    case 114:
      Done{Chr{13}}
    case 116:
      Done{Chr{9}}
    case _:
      Fail{diagnostic(node, "text_literal", "unsupported string escape; use escaped quote, backslash, n, r, or t")}

def literal_body(chars: String, +node: Cst) -> Result<&2, &2, M.Diagnostic, String>:
  match chars:
    case SCon{Chr{34}, SNil{}}:
      Done{SNil{}}
    case SCon{Chr{92}, SCon{Chr{code}, tail}}:
      do Result<&2, &2, M.Diagnostic, String>:
        character : Char <- literal_character(code, node)
        rest : String <- literal_body(tail, node)
        return SCon{character, rest}
    case SCon{character, tail}:
      do Result<&2, &2, M.Diagnostic, String>:
        rest : String <- literal_body(tail, node)
        return SCon{character, rest}
    case SNil{}:
      Fail{diagnostic(node, "text_literal", "unterminated string literal")}

def literal_text(chars: String, node: Cst) -> Result<&2, &2, M.Diagnostic, String>:
  match chars:
    case SCon{Chr{34}, tail}:
      literal_body(tail, node)
    case _:
      Fail{diagnostic(node, "text_literal", "expected a quoted string literal")}

def literal(+node: Cst) -> Result<&2, &2, M.Diagnostic, String>:
  literal_text(text_of(node), node)

def float_characters(text: String) -> String:
  match text:
    case SNil{}:
      SNil{}
    case SCon{Chr{95}, tail}:
      float_characters(tail)
    case SCon{character, tail}:
      SCon{character, float_characters(tail)}

def float_finite(valid: Bool, value: F32, node: Cst) -> Result<&2, &2, M.Diagnostic, F32>:
  match valid:
    case True{}:
      Done{value}
    case False{}:
      Fail{diagnostic(node, "float_range", "floating-point literal exceeds finite F32 range")}

def float_value(parsed: Maybe<&2, F32>, node: Cst) -> Result<&2, &2, M.Diagnostic, F32>:
  match parsed:
    case Some{+value}:
      float_finite(U32.is_ne(U32.and(F32.bits(value), 2139095040), 2139095040), value, node)
    case None{}:
      Fail{diagnostic(node, "float_literal", "invalid F32 literal")}

def float(+node: Cst) -> Result<&2, &2, M.Diagnostic, F32>:
  float_value(Numeric.read(float_characters(text_of(node))), node)

def digit(+code: U32) -> U32:
  Bool.pick(U32, U32.is_le(code, 57), U32.sub(code, 48),
    Bool.pick(U32, U32.is_le(code, 70), U32.sub(code, 55), U32.sub(code, 87)))

def accumulate(valid: Bool, number: U32, number_digit: U32, radix: U32, node: Cst) -> Result<&2, &2, M.Diagnostic, U32>:
  match valid:
    case True{}:
      Done{U32.add(U32.mul(number, radix), number_digit)}
    case False{}:
      Fail{diagnostic(node, "integer_range", "integer literal exceeds U32 (4294967295)" )}

def integer_digits(chars: String, number: U32, +radix: U32, +node: Cst) -> Result<&2, &2, M.Diagnostic, U32>:
  match chars:
    case SNil{}:
      Done{number}
    case SCon{Chr{95}, tail}:
      integer_digits(tail, number, radix, node)
    case SCon{Chr{code}, tail}:
      +d = digit(code)
      +n = number
      do Result<&2, &2, M.Diagnostic, U32>:
        next : U32 <- accumulate(U32.is_le(n, U32.div(U32.sub(4294967295, d), radix)), n, d, radix, node)
        integer_digits(tail, next, radix, node)

def integer(+node: Cst) -> Result<&2, &2, M.Diagnostic, U32>:
  +value = text_of(node)
  +hex = Bool.or(String.starts_with(value, "0x"), String.starts_with(value, "0X"))
  integer_digits(Bool.pick(String, hex, String.drop(value, 2n), value), 0, Bool.pick(U32, hex, 16, 10), node)
