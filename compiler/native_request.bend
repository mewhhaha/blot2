import Base
import ./model.bend as M
import ./cst.bend as Cst
import ./native_session.bend as Session

type Operation is Data:
  Analyze{}
  Compile{}

type Request is Data:
  Request{operation: Operation, fuel: Nat, steps: Nat, root: Cst.Cst, prelude: Cst.Cst}
  OpenSession{prelude: Cst.Cst, fuel: Nat}
  SessionRequest{operation: Operation, fuel: Nat, steps: Nat, root: Cst.Cst}
  SessionPatch{operation: Operation, fuel: Nat, steps: Nat, declarations: List<&2, Session.Declaration>}

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

type ScannedString is Data:
  CompleteString{value: String, cursor: Cursor}
  TruncatedString{offset: Nat}
  InvalidCharacter{offset: Nat}

# Result.bind and diagnostic string construction make a loop non-flat in Bend.
# Keep both outside the per-character loop, including ownership of the label.
# A rejected scalar is discarded before any string can leave this decoder.
def scan_string(count: Nat, cursor: Cursor, reversed: String, valid: Bool) -> ScannedString:
  match count cursor valid:
    case _ Cursor{words, offset} False{}:
      InvalidCharacter{Nat.sub(offset, 1n)}
    case 0n remaining True{}:
      CompleteString{String.reverse(reversed), remaining}
    case 1n+rest Cursor{Nil{}, offset} True{}:
      TruncatedString{offset}
    case 1n+rest Cursor{+code <> tail, offset} True{}:
      scan_string(rest, Cursor{tail, 1n+offset}, SCon{Chr{code}, reversed}, Bool.and(U32.is_le(code, 1114111), Bool.or(U32.is_lt(code, 55296), U32.is_gt(code, 57343))))

type ScanFailure is Data:
  MissingWord{offset: Nat, label: String}
  InvalidScalar{offset: Nat}
  InvalidHighWord{offset: Nat}
  ExhaustedTree{offset: Nat}

def scan_failure(failure: ScanFailure) -> M.Diagnostic:
  match failure:
    case MissingWord{offset, label}:
      diagnostic(offset, "truncated request while reading " ++ label)
    case InvalidScalar{offset}:
      diagnostic(offset, "string contains an invalid Unicode scalar value")
    case InvalidHighWord{offset}:
      diagnostic(offset, "Nat high word exceeds 16 bits")
    case ExhaustedTree{offset}:
      diagnostic(offset, "CST traversal exceeded its request word-count bound")

def scanned_string(scanned: ScannedString, label: String) -> Result<&2, &2, ScanFailure, Parsed<String>>:
  match scanned:
    case CompleteString{value, cursor}:
      Done{Parsed{value, cursor}}
    case TruncatedString{offset}:
      Fail{MissingWord{offset, label}}
    case InvalidCharacter{offset}:
      Fail{InvalidScalar{offset}}

def scan_field(cursor: Cursor, length_label: String, character_label: String) -> Result<&2, &2, ScanFailure, Parsed<String>>:
  match cursor:
    case Cursor{Nil{}, offset}:
      Fail{MissingWord{offset, length_label}}
    case Cursor{count <> tail, offset}:
      scanned_string(scan_string(U32.to_nat(count), Cursor{tail, 1n+offset}, SNil{}, True{}), character_label)

type Header is Data:
  Header{kind: String, field: String, text: String, offset: Nat, children: Nat}

def header_children(cursor: Cursor, kind: String, field: String, text: String, offset: Nat) -> Result<&2, &2, ScanFailure, Parsed<Header>>:
  match cursor:
    case Cursor{Nil{}, position}:
      Fail{MissingWord{position, "CST child count"}}
    case Cursor{children <> tail, position}:
      Done{Parsed{Header{kind, field, text, offset, U32.to_nat(children)}, Cursor{tail, 1n+position}}}

def header_natural(valid: Bool, low: U32, high: U32, cursor: Cursor, kind: String, field: String, text: String) -> Result<&2, &2, ScanFailure, Parsed<Header>>:
  match valid cursor:
    case False{} Cursor{words, position}:
      Fail{InvalidHighWord{Nat.sub(position, 1n)}}
    case True{} remaining:
      header_children(remaining, kind, field, text, Nat.add(U32.to_nat(low), Nat.mul(U32.to_nat(high), Nat.mul(U32.to_nat(65536), U32.to_nat(65536)))))

def header_offset(cursor: Cursor, kind: String, field: String, text: String) -> Result<&2, &2, ScanFailure, Parsed<Header>>:
  match cursor:
    case Cursor{Nil{}, position}:
      Fail{MissingWord{position, "CST offset low word"}}
    case Cursor{low <> Nil{}, position}:
      Fail{MissingWord{1n+position, "CST offset high word"}}
    case Cursor{low <> +high <> tail, position}:
      header_natural(U32.is_le(high, 65535), low, high, Cursor{tail, Nat.add(position, 2n)}, kind, field, text)

# Explicit matches keep the scan flat and transfer each cursor exactly once;
# Result.bind closures and paired projections retain the unconsumed word list.
def header_text(parsed: Result<&2, &2, ScanFailure, Parsed<String>>, kind: String, field: String) -> Result<&2, &2, ScanFailure, Parsed<Header>>:
  match parsed:
    case Fail{error}:
      Fail{error}
    case Done{Parsed{text, cursor}}:
      header_offset(cursor, kind, field, text)

def header_field(parsed: Result<&2, &2, ScanFailure, Parsed<String>>, kind: String) -> Result<&2, &2, ScanFailure, Parsed<Header>>:
  match parsed:
    case Fail{error}:
      Fail{error}
    case Done{Parsed{field, cursor}}:
      header_text(scan_field(cursor, "CST text length", "CST text character"), kind, field)

def header_kind(parsed: Result<&2, &2, ScanFailure, Parsed<String>>) -> Result<&2, &2, ScanFailure, Parsed<Header>>:
  match parsed:
    case Fail{error}:
      Fail{error}
    case Done{Parsed{kind, cursor}}:
      header_field(scan_field(cursor, "CST field length", "CST field character"), kind)

def scan_header(cursor: Cursor) -> Result<&2, &2, ScanFailure, Parsed<Header>>:
  header_kind(scan_field(cursor, "CST kind length", "CST kind character"))

# remaining counts siblings after the child currently being read. Accumulated
# children are reversed exactly once, when their parent is complete.
type Parent is Data:
  Parent{kind: String, field: String, text: String, offset: Nat, remaining: Nat, reversed: List<&2, Cst.Cst>}

type TreeWork is Data:
  ReadNode{parsed: Result<&2, &2, ScanFailure, Parsed<Header>>, parents: List<&2, Parent>}
  FinishNode{node: Cst.Cst, parents: List<&2, Parent>, cursor: Cursor}

def begin_node(header: Header, parents: List<&2, Parent>, cursor: Cursor) -> TreeWork:
  match header:
    case Header{kind, field, text, offset, 0n}:
      FinishNode{Cst.Cst{kind, field, text, offset, Nil{}}, parents, cursor}
    case Header{kind, field, text, offset, 1n+remaining}:
      ReadNode{scan_header(cursor), Parent{kind, field, text, offset, remaining, Nil{}} <> parents}

# Every CST node consumes at least six words and at most two work steps. The
# frame's word count therefore supplies a bound without limiting valid nesting.
def scan_tree(fuel: Nat, work: TreeWork) -> Result<&2, &2, ScanFailure, Parsed<Cst.Cst>>:
  match fuel work:
    case _ FinishNode{node, Nil{}, cursor}:
      Done{Parsed{node, cursor}}
    case _ ReadNode{Fail{error}, parents}:
      Fail{error}
    case 0n ReadNode{Done{Parsed{header, Cursor{words, position}}}, parents}:
      Fail{ExhaustedTree{position}}
    case 0n FinishNode{node, parents, Cursor{words, position}}:
      Fail{ExhaustedTree{position}}
    case 1n+rest ReadNode{Done{Parsed{header, cursor}}, parents}:
      scan_tree(rest, begin_node(header, parents, cursor))
    case 1n+rest FinishNode{node, Parent{kind, field, text, offset, 0n, reversed} <> parents, cursor}:
      scan_tree(rest, FinishNode{Cst.Cst{kind, field, text, offset, List.reverse(&2, Cst.Cst, node <> reversed)}, parents, cursor})
    case 1n+rest FinishNode{node, Parent{kind, field, text, offset, 1n+remaining, reversed} <> parents, cursor}:
      scan_tree(rest, ReadNode{scan_header(cursor), Parent{kind, field, text, offset, remaining, node <> reversed} <> parents})

def scanned_tree(result: Result<&2, &2, ScanFailure, Parsed<Cst.Cst>>) -> Result<&2, &2, M.Diagnostic, Parsed<Cst.Cst>>:
  match result:
    case Fail{error}:
      Fail{scan_failure(error)}
    case Done{parsed}:
      Done{parsed}

def tree(fuel: Nat, cursor: Cursor) -> Result<&2, &2, M.Diagnostic, Parsed<Cst.Cst>>:
  scanned_tree(scan_tree(fuel, ReadNode{scan_header(cursor), Nil{}}))

def end(cursor: Cursor) -> Result<&2, &2, M.Diagnostic, Unit>:
  match cursor:
    case Cursor{Nil{}, offset}:
      Done{Unit{}}
    case Cursor{head <> tail, offset}:
      Fail{diagnostic(offset, "trailing words after the request CST")}

def stateless(selected: Operation, +bound: Nat, cursor: Cursor) -> Result<&2, &2, M.Diagnostic, Request>:
  do Result<&2, &2, M.Diagnostic, Request>:
    +fuel : Parsed<Nat> <- natural(cursor, "frontend fuel")
    +steps : Parsed<Nat> <- natural(cursor_of(Nat, fuel), "const steps")
    +root : Parsed<Cst.Cst> <- tree(bound, cursor_of(Nat, steps))
    +prelude : Parsed<Cst.Cst> <- tree(bound, cursor_of(Cst.Cst, root))
    complete : Unit <- end(cursor_of(Cst.Cst, prelude))
    return Request{selected, value_of(Nat, fuel), value_of(Nat, steps), value_of(Cst.Cst, root), value_of(Cst.Cst, prelude)}

def cached(selected: Operation, bound: Nat, cursor: Cursor) -> Result<&2, &2, M.Diagnostic, Request>:
  do Result<&2, &2, M.Diagnostic, Request>:
    +fuel : Parsed<Nat> <- natural(cursor, "frontend fuel")
    +steps : Parsed<Nat> <- natural(cursor_of(Nat, fuel), "const steps")
    +root : Parsed<Cst.Cst> <- tree(bound, cursor_of(Nat, steps))
    complete : Unit <- end(cursor_of(Cst.Cst, root))
    return SessionRequest{selected, value_of(Nat, fuel), value_of(Nat, steps), value_of(Cst.Cst, root)}

def declaration(tag: U32, bound: Nat, cursor: Cursor, offset: Nat) -> Result<&2, &2, M.Diagnostic, Parsed<Session.Declaration>>:
  match tag:
    case 0:
      do Result<&2, &2, M.Diagnostic, Parsed<Session.Declaration>>:
        +identity : Parsed<Nat> <- natural(cursor, "retained declaration identity")
        return Parsed{Session.Retained{value_of(Nat, identity)}, cursor_of(Nat, identity)}
    case 1:
      do Result<&2, &2, M.Diagnostic, Parsed<Session.Declaration>>:
        +node : Parsed<Cst.Cst> <- tree(bound, cursor)
        return Parsed{Session.Replaced{value_of(Cst.Cst, node)}, cursor_of(Cst.Cst, node)}
    case other:
      Fail{diagnostic(offset, "unknown declaration tag; expected 0 retained or 1 replaced")}

def declarations(count: Nat, +bound: Nat, +cursor: Cursor, reversed: List<&2, Session.Declaration>) -> Result<&2, &2, M.Diagnostic, Parsed<List<&2, Session.Declaration>>>:
  match count:
    case 0n:
      Done{Parsed{List.reverse(&2, Session.Declaration, reversed), cursor}}
    case 1n+rest:
      do Result<&2, &2, M.Diagnostic, Parsed<List<&2, Session.Declaration>>>:
        +tag : Parsed<U32> <- word(cursor, "declaration tag")
        +parsed : Parsed<Session.Declaration> <- declaration(value_of(U32, tag), bound, cursor_of(U32, tag), offset_of(cursor))
        declarations(rest, bound, cursor_of(Session.Declaration, parsed), value_of(Session.Declaration, parsed) <> reversed)

def patch(selected: Operation, bound: Nat, cursor: Cursor) -> Result<&2, &2, M.Diagnostic, Request>:
  do Result<&2, &2, M.Diagnostic, Request>:
    +fuel : Parsed<Nat> <- natural(cursor, "frontend fuel")
    +steps : Parsed<Nat> <- natural(cursor_of(Nat, fuel), "const steps")
    +count : Parsed<U32> <- word(cursor_of(Nat, steps), "declaration count")
    +parsed : Parsed<List<&2, Session.Declaration>> <- declarations(U32.to_nat(value_of(U32, count)), bound, cursor_of(U32, count), Nil{})
    complete : Unit <- end(cursor_of(List<&2, Session.Declaration>, parsed))
    return SessionPatch{selected, value_of(Nat, fuel), value_of(Nat, steps), value_of(List<&2, Session.Declaration>, parsed)}

def body(opcode: U32, bound: Nat, cursor: Cursor) -> Result<&2, &2, M.Diagnostic, Request>:
  match opcode:
    case 0:
      stateless(Analyze{}, bound, cursor)
    case 1:
      stateless(Compile{}, bound, cursor)
    case 2:
      do Result<&2, &2, M.Diagnostic, Request>:
        +fuel : Parsed<Nat> <- natural(cursor, "prelude fuel")
        +prelude : Parsed<Cst.Cst> <- tree(bound, cursor_of(Nat, fuel))
        complete : Unit <- end(cursor_of(Cst.Cst, prelude))
        return OpenSession{value_of(Cst.Cst, prelude), value_of(Nat, fuel)}
    case 3:
      cached(Analyze{}, bound, cursor)
    case 4:
      cached(Compile{}, bound, cursor)
    case 5:
      patch(Analyze{}, bound, cursor)
    case 6:
      patch(Compile{}, bound, cursor)
    case other:
      Fail{diagnostic(2n, "unknown operation; expected 0..6")}

# Base.List.length is non-tail-recursive in Bend 2.0.21. Counting a large
# protocol frame that way allocates a continuation for every word.
def word_count(words: List<&2, U32>, count: Nat) -> Nat:
  match words:
    case Nil{}:
      count
    case head <> tail:
      word_count(tail, 1n+count)

def decode(+words: List<&2, U32>) -> Result<&2, &2, M.Diagnostic, Request>:
  +bound = word_count(words, 0n)
  do Result<&2, &2, M.Diagnostic, Request>:
    +magic : Parsed<U32> <- word(Cursor{words, 0n}, "protocol magic")
    valid_magic : Unit <- require(U32.is_eq(value_of(U32, magic), 1112297300), 0n, "invalid protocol magic; expected BLOT")
    +version : Parsed<U32> <- word(cursor_of(U32, magic), "protocol version")
    valid_version : Unit <- require(U32.is_eq(value_of(U32, version), 6), 1n, "unsupported native protocol version; expected 6")
    +opcode : Parsed<U32> <- word(cursor_of(U32, version), "operation")
    body(value_of(U32, opcode), bound, cursor_of(U32, opcode))
