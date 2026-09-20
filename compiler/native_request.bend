import Base
import ./model.bend as M
import ./cst.bend as Cst

type Operation is Data:
  Analyze{}
  Compile{}
  CompileEcs{}

type Request is Data:
  Request{operation: Operation, fuel: Nat, steps: Nat, root: Cst.Cst, prelude: Cst.Cst}

type Cursor is Data:
  Cursor{words: List<&2, U32>, offset: Nat}

type Parsed<-A: Data> is Data:
  Parsed{value: A, cursor: Cursor}

def value_of(-A: Data, parsed: Parsed<A>) -> A:
  Parsed{value, cursor} = parsed
  value

def cursor_of(-A: Data, parsed: Parsed<A>) -> Cursor:
  Parsed{value, cursor} = parsed
  cursor

def offset_of(cursor: Cursor) -> Nat:
  Cursor{words, offset} = cursor
  offset

def diagnostic(offset: Nat, message: String) -> M.Diagnostic:
  M.Diagnostic{"native_protocol", "word:" ++ Nat.show(offset), message}

def word(cursor: Cursor, label: String) -> Result<&2, &2, M.Diagnostic, Parsed<U32>>:
  match cursor:
    case Cursor{Nil{}, offset}:
      Fail{diagnostic(offset, "truncated request while reading " ++ label)}
    case Cursor{head <> tail, offset}:
      Done{Parsed{head, Cursor{tail, 1n+offset}}}

def require(valid: Bool, offset: Nat, message: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match valid:
    case True{}:
      Done{Unit{}}
    case False{}:
      Fail{diagnostic(offset, message)}

def nat_value(valid: Bool, low: U32, high: U32, offset: Nat) -> Result<&2, &2, M.Diagnostic, Nat>:
  match valid:
    case False{}:
      Fail{diagnostic(offset, "Nat high word exceeds 16 bits")}
    case True{}:
      Done{Nat.add(U32.to_nat(low), Nat.mul(U32.to_nat(high), Nat.mul(U32.to_nat(65536), U32.to_nat(65536))))}

def natural(cursor: Cursor, +label: String) -> Result<&2, &2, M.Diagnostic, Parsed<Nat>>:
  do Result<&2, &2, M.Diagnostic, Parsed<Nat>>:
    +low : Parsed<U32> <- word(cursor, label ++ " low word")
    +high : Parsed<U32> <- word(cursor_of(U32, low), label ++ " high word")
    decoded : Nat <- nat_value(U32.is_le(value_of(U32, high), 65535), value_of(U32, low), value_of(U32, high), offset_of(cursor_of(U32, low)))
    return Parsed{decoded, cursor_of(U32, high)}

def scalar_value(valid: Bool, value: U32, offset: Nat) -> Result<&2, &2, M.Diagnostic, Char>:
  match valid:
    case False{}:
      Fail{diagnostic(offset, "string contains an invalid Unicode scalar value")}
    case True{}:
      Done{Chr{value}}

def string_characters(count: Nat, +cursor: Cursor, reversed: String, +label: String) -> Result<&2, &2, M.Diagnostic, Parsed<String>>:
  match count:
    case 0n:
      Done{Parsed{String.reverse(reversed), cursor}}
    case 1n+rest:
      do Result<&2, &2, M.Diagnostic, Parsed<String>>:
        +encoded : Parsed<U32> <- word(cursor, label ++ " character")
        +code : U32 = value_of(U32, encoded)
        character : Char <- scalar_value(Bool.and(U32.is_le(code, 1114111), Bool.or(U32.is_lt(code, 55296), U32.is_gt(code, 57343))), code, offset_of(cursor))
        string_characters(rest, cursor_of(U32, encoded), SCon{character, reversed}, label)

def string(cursor: Cursor, +label: String) -> Result<&2, &2, M.Diagnostic, Parsed<String>>:
  do Result<&2, &2, M.Diagnostic, Parsed<String>>:
    +count : Parsed<U32> <- word(cursor, label ++ " length")
    string_characters(U32.to_nat(value_of(U32, count)), cursor_of(U32, count), SNil{}, label)

type Header is Data:
  Header{kind: String, field: String, text: String, offset: Nat, children: Nat}

def header(cursor: Cursor) -> Result<&2, &2, M.Diagnostic, Parsed<Header>>:
  do Result<&2, &2, M.Diagnostic, Parsed<Header>>:
    +kind : Parsed<String> <- string(cursor, "CST kind")
    +field : Parsed<String> <- string(cursor_of(String, kind), "CST field")
    +text : Parsed<String> <- string(cursor_of(String, field), "CST text")
    +offset : Parsed<Nat> <- natural(cursor_of(String, text), "CST offset")
    +children : Parsed<U32> <- word(cursor_of(Nat, offset), "CST child count")
    return Parsed{Header{value_of(String, kind), value_of(String, field), value_of(String, text), value_of(Nat, offset), U32.to_nat(value_of(U32, children))}, cursor_of(U32, children)}

# remaining counts siblings after the child currently being read. Accumulated
# children are reversed exactly once, when their parent is complete.
type Parent is Data:
  Parent{kind: String, field: String, text: String, offset: Nat, remaining: Nat, reversed: List<&2, Cst.Cst>}

type TreeWork is Data:
  ReadNode{parents: List<&2, Parent>}
  FinishNode{node: Cst.Cst, parents: List<&2, Parent>}

def begin_node(header: Header, parents: List<&2, Parent>) -> TreeWork:
  match header:
    case Header{kind, field, text, offset, 0n}:
      FinishNode{Cst.Cst{kind, field, text, offset, Nil{}}, parents}
    case Header{kind, field, text, offset, 1n+remaining}:
      ReadNode{Parent{kind, field, text, offset, remaining, Nil{}} <> parents}

# Every CST node consumes at least six words and at most two work steps. The
# frame's word count therefore supplies a bound without limiting valid nesting.
def tree(fuel: Nat, work: TreeWork, +cursor: Cursor) -> Result<&2, &2, M.Diagnostic, Parsed<Cst.Cst>>:
  match fuel work:
    case _ FinishNode{node, Nil{}}:
      Done{Parsed{node, cursor}}
    case 0n _:
      Fail{diagnostic(offset_of(cursor), "CST traversal exceeded its request word-count bound")}
    case 1n+rest ReadNode{parents}:
      do Result<&2, &2, M.Diagnostic, Parsed<Cst.Cst>>:
        +parsed : Parsed<Header> <- header(cursor)
        tree(rest, begin_node(value_of(Header, parsed), parents), cursor_of(Header, parsed))
    case 1n+rest FinishNode{node, Parent{kind, field, text, offset, 0n, reversed} <> parents}:
      tree(rest, FinishNode{Cst.Cst{kind, field, text, offset, List.reverse(&2, Cst.Cst, node <> reversed)}, parents}, cursor)
    case 1n+rest FinishNode{node, Parent{kind, field, text, offset, 1n+remaining, reversed} <> parents}:
      tree(rest, ReadNode{Parent{kind, field, text, offset, remaining, node <> reversed} <> parents}, cursor)

def operation(value: U32) -> Result<&2, &2, M.Diagnostic, Operation>:
  match value:
    case 0:
      Done{Analyze{}}
    case 1:
      Done{Compile{}}
    case 2:
      Done{CompileEcs{}}
    case other:
      Fail{diagnostic(2n, "unknown operation; expected 0 (analyze), 1 (compile), or 2 (compile_ecs)")}

def end(cursor: Cursor) -> Result<&2, &2, M.Diagnostic, Unit>:
  match cursor:
    case Cursor{Nil{}, offset}:
      Done{Unit{}}
    case Cursor{head <> tail, offset}:
      Fail{diagnostic(offset, "trailing words after the prelude CST")}

def decode(+words: List<&2, U32>) -> Result<&2, &2, M.Diagnostic, Request>:
  +bound = List.length(&2, U32, words)
  do Result<&2, &2, M.Diagnostic, Request>:
    +magic : Parsed<U32> <- word(Cursor{words, 0n}, "protocol magic")
    valid_magic : Unit <- require(U32.is_eq(value_of(U32, magic), 1112297300), 0n, "invalid protocol magic; expected BLOT")
    +version : Parsed<U32> <- word(cursor_of(U32, magic), "protocol version")
    valid_version : Unit <- require(U32.is_eq(value_of(U32, version), 1), 1n, "unsupported native protocol version; expected 1")
    +opcode : Parsed<U32> <- word(cursor_of(U32, version), "operation")
    selected : Operation <- operation(value_of(U32, opcode))
    +fuel : Parsed<Nat> <- natural(cursor_of(U32, opcode), "frontend fuel")
    +steps : Parsed<Nat> <- natural(cursor_of(Nat, fuel), "const steps")
    +root : Parsed<Cst.Cst> <- tree(bound, ReadNode{Nil{}}, cursor_of(Nat, steps))
    +prelude : Parsed<Cst.Cst> <- tree(bound, ReadNode{Nil{}}, cursor_of(Cst.Cst, root))
    complete : Unit <- end(cursor_of(Cst.Cst, prelude))
    return Request{selected, value_of(Nat, fuel), value_of(Nat, steps), value_of(Cst.Cst, root), value_of(Cst.Cst, prelude)}
