import Base
import ./model.bend as M
import ./cst.bend as Cst
import ./native_session.bend as Session
import ./native_io.bend as NativeIO
import ./native_response.bend as Response

type Operation is Data:
  Analyze{}
  Compile{}

type Request is Data:
  Request{operation: Operation, fuel: Nat, steps: Nat, root: Cst.Cst, prelude: Cst.Cst}
  OpenSession{prelude: Cst.Cst, fuel: Nat}
  SessionRequest{operation: Operation, fuel: Nat, steps: Nat, root: Cst.Cst}
  SessionPatch{operation: Operation, fuel: Nat, steps: Nat, declarations: List<&2, Session.Declaration>}

# Array indices wrap in Bend. remaining is the validated frame length, not
# the power-of-two allocation size; every read consumes it before indexing.
type Cursor is Type:
  Cursor{words: Array<U32>, offset: Nat, remaining: Nat, strings: Array<String>, string_count: U32}

type Parsed<-A: Data> is Type:
  Parsed{value: A, cursor: Cursor}

# Keep diagnostic formatting out of the scan. Otherwise one cold String.append
# branch makes every successful word read use Bend's continuation machinery.
type ScanFailure is Data:
  MissingWord{offset: Nat, label: String}
  Rejected{offset: Nat, message: String}

def diagnostic(offset: Nat, message: String) -> M.Diagnostic:
  M.Diagnostic{"native_protocol", "word:" ++ Nat.show(offset), message}

def scan_failure(failure: ScanFailure) -> M.Diagnostic:
  match failure:
    case MissingWord{offset, label}:
      diagnostic(offset, "truncated request while reading " ++ label)
    case Rejected{offset, message}:
      diagnostic(offset, message)

def word_read(read: Array<U32> & U32, offset: Nat, remaining: Nat, strings: Array<String>, string_count: U32) -> Result<&2, &1, ScanFailure, Parsed<U32>>:
  (words, value) = read
  Done{Parsed{value, Cursor{words, offset, remaining, strings, string_count}}}

def word(cursor: Cursor, label: String) -> Result<&2, &1, ScanFailure, Parsed<U32>>:
  match cursor:
    case Cursor{words, offset, 0n, strings, string_count}:
      Fail{MissingWord{offset, label}}
    case Cursor{words, +offset, 1n+remaining, strings, string_count}:
      word_read(Array.get(U32, words, U32.from_nat(offset)), 1n+offset, remaining, strings, string_count)

def natural_checked(valid: Bool, low: U32, high: U32, cursor: Cursor, offset: Nat) -> Result<&2, &1, ScanFailure, Parsed<Nat>>:
  match valid:
    case False{}:
      Fail{Rejected{offset, "Nat high word exceeds 16 bits"}}
    case True{}:
      Done{Parsed{Nat.add(U32.to_nat(low), Nat.mul(U32.to_nat(high), Nat.mul(U32.to_nat(65536), U32.to_nat(65536)))), cursor}}

def natural_high(parsed: Result<&2, &1, ScanFailure, Parsed<U32>>, low: U32, offset: Nat) -> Result<&2, &1, ScanFailure, Parsed<Nat>>:
  match parsed:
    case Fail{error}:
      Fail{error}
    case Done{Parsed{+high, cursor}}:
      natural_checked(U32.is_le(high, 65535), low, high, cursor, offset)

def natural_low(parsed: Result<&2, &1, ScanFailure, Parsed<U32>>, label: String, offset: Nat) -> Result<&2, &1, ScanFailure, Parsed<Nat>>:
  match parsed:
    case Fail{error}:
      Fail{error}
    case Done{Parsed{low, cursor}}:
      natural_high(word(cursor, label), low, offset)

def natural_words(cursor: Cursor, low_label: String, high_label: String) -> Result<&2, &1, ScanFailure, Parsed<Nat>>:
  Cursor{words, +offset, remaining, strings, string_count} = cursor
  natural_low(word(Cursor{words, offset, remaining, strings, string_count}, low_label), high_label, 1n+offset)

def natural(cursor: Cursor, +label: String) -> Result<&2, &1, ScanFailure, Parsed<Nat>>:
  natural_words(cursor, label ++ " low word", label ++ " high word")

type ScannedString is Type:
  CompleteString{value: String, cursor: Cursor}
  TruncatedString{offset: Nat}
  InvalidCharacter{offset: Nat}

# No labels or Result closures in the per-scalar loop. The owned buffer is
# released even when a malformed character aborts the scan.
type CharacterScan is Type:
  CharacterScan{cursor: Cursor, reversed: String, valid: Bool}

def character_read(read: Array<U32> & U32, offset: Nat, remaining: Nat, reversed: String, strings: Array<String>, string_count: U32) -> CharacterScan:
  (words, +code) = read
  CharacterScan{Cursor{words, offset, remaining, strings, string_count}, SCon{Chr{code}, reversed}, Bool.and(U32.is_le(code, 1114111), Bool.or(U32.is_lt(code, 55296), U32.is_gt(code, 57343)))}

def scan_characters(count: Nat, scan: CharacterScan) -> ScannedString:
  match count scan:
    case _ CharacterScan{Cursor{words, offset, remaining, strings, string_count}, reversed, False{}}:
      InvalidCharacter{Nat.sub(offset, 1n)}
    case 0n CharacterScan{remaining, reversed, True{}}:
      CompleteString{String.reverse(reversed), remaining}
    case 1n+rest CharacterScan{Cursor{words, offset, 0n, strings, string_count}, reversed, True{}}:
      TruncatedString{offset}
    case 1n+rest CharacterScan{Cursor{words, +offset, 1n+remaining, strings, string_count}, reversed, True{}}:
      scan_characters(rest, character_read(Array.get(U32, words, U32.from_nat(offset)), 1n+offset, remaining, reversed, strings, string_count))

def scan_string(count: Nat, cursor: Cursor, reversed: String, valid: Bool) -> ScannedString:
  scan_characters(count, CharacterScan{cursor, reversed, valid})

def scanned_string(scanned: ScannedString, label: String) -> Result<&2, &1, ScanFailure, Parsed<String>>:
  match scanned:
    case CompleteString{value, cursor}:
      Done{Parsed{value, cursor}}
    case TruncatedString{offset}:
      Fail{MissingWord{offset, label}}
    case InvalidCharacter{offset}:
      Fail{Rejected{offset, "string contains an invalid Unicode scalar value"}}

def field_length(parsed: Result<&2, &1, ScanFailure, Parsed<U32>>, character_label: String) -> Result<&2, &1, ScanFailure, Parsed<String>>:
  match parsed:
    case Fail{error}:
      Fail{error}
    case Done{Parsed{count, cursor}}:
      scanned_string(scan_string(U32.to_nat(count), cursor, SNil{}, True{}), character_label)

def scan_field(cursor: Cursor, length_label: String, character_label: String) -> Result<&2, &1, ScanFailure, Parsed<String>>:
  field_length(word(cursor, length_label), character_label)

def string_read(read: Array<String> & String, words: Array<U32>, offset: Nat, remaining: Nat, string_count: U32) -> Result<&2, &1, ScanFailure, Parsed<String>>:
  (strings, value) = read
  Done{Parsed{value, Cursor{words, offset, remaining, strings, string_count}}}

def string_checked(valid: Bool, identity: U32, cursor: Cursor) -> Result<&2, &1, ScanFailure, Parsed<String>>:
  match valid cursor:
    case False{} Cursor{words, offset, remaining, strings, string_count}:
      Fail{Rejected{Nat.sub(offset, 1n), "CST string ID is outside the request dictionary"}}
    case True{} Cursor{words, offset, remaining, strings, string_count}:
      string_read(Array.get(String, strings, identity), words, offset, remaining, string_count)

def string_identity(parsed: Result<&2, &1, ScanFailure, Parsed<U32>>) -> Result<&2, &1, ScanFailure, Parsed<String>>:
  match parsed:
    case Fail{error}:
      Fail{error}
    case Done{Parsed{+identity, Cursor{words, offset, remaining, strings, +string_count}}}:
      string_checked(U32.is_lt(identity, string_count), identity, Cursor{words, offset, remaining, strings, string_count})

def string_reference(cursor: Cursor, label: String) -> Result<&2, &1, ScanFailure, Parsed<String>>:
  string_identity(word(cursor, label))

type Header is Data:
  Header{kind: String, field: String, text: String, offset: Nat, children: Nat}

def header_children(parsed: Result<&2, &1, ScanFailure, Parsed<U32>>, kind: String, field: String, text: String, offset: Nat) -> Result<&2, &1, ScanFailure, Parsed<Header>>:
  match parsed:
    case Fail{error}:
      Fail{error}
    case Done{Parsed{children, cursor}}:
      Done{Parsed{Header{kind, field, text, offset, U32.to_nat(children)}, cursor}}

def header_offset(parsed: Result<&2, &1, ScanFailure, Parsed<Nat>>, kind: String, field: String, text: String) -> Result<&2, &1, ScanFailure, Parsed<Header>>:
  match parsed:
    case Fail{error}:
      Fail{error}
    case Done{Parsed{offset, cursor}}:
      header_children(word(cursor, "CST child count"), kind, field, text, offset)

def header_text(parsed: Result<&2, &1, ScanFailure, Parsed<String>>, kind: String, field: String) -> Result<&2, &1, ScanFailure, Parsed<Header>>:
  match parsed:
    case Fail{error}:
      Fail{error}
    case Done{Parsed{text, cursor}}:
      header_offset(natural_words(cursor, "CST offset low word", "CST offset high word"), kind, field, text)

def header_field(parsed: Result<&2, &1, ScanFailure, Parsed<String>>, kind: String) -> Result<&2, &1, ScanFailure, Parsed<Header>>:
  match parsed:
    case Fail{error}:
      Fail{error}
    case Done{Parsed{field, cursor}}:
      header_text(string_reference(cursor, "CST text ID"), kind, field)

def header_kind(parsed: Result<&2, &1, ScanFailure, Parsed<String>>) -> Result<&2, &1, ScanFailure, Parsed<Header>>:
  match parsed:
    case Fail{error}:
      Fail{error}
    case Done{Parsed{kind, cursor}}:
      header_field(string_reference(cursor, "CST field ID"), kind)

def scan_header(cursor: Cursor) -> Result<&2, &1, ScanFailure, Parsed<Header>>:
  header_kind(string_reference(cursor, "CST kind ID"))

type Parent is Data:
  Parent{kind: String, field: String, text: String, offset: Nat, remaining: Nat, reversed: List<&2, Cst.Cst>}

type TreeWork is Type:
  ReadNode{parsed: Result<&2, &1, ScanFailure, Parsed<Header>>, parents: List<&2, Parent>}
  FinishNode{node: Cst.Cst, parents: List<&2, Parent>, cursor: Cursor}

def begin_node(header: Header, parents: List<&2, Parent>, cursor: Cursor) -> TreeWork:
  match header:
    case Header{kind, field, text, offset, 0n}:
      FinishNode{Cst.Cst{kind, field, text, offset, Nil{}}, parents, cursor}
    case Header{kind, field, text, offset, 1n+remaining}:
      ReadNode{scan_header(cursor), Parent{kind, field, text, offset, remaining, Nil{}} <> parents}

# Every node consumes at least six words and at most two work steps.
def scan_tree(fuel: Nat, work: TreeWork) -> Result<&2, &1, ScanFailure, Parsed<Cst.Cst>>:
  match fuel work:
    case _ FinishNode{node, Nil{}, cursor}:
      Done{Parsed{node, cursor}}
    case _ ReadNode{Fail{error}, parents}:
      Fail{error}
    case 0n ReadNode{Done{Parsed{header, Cursor{words, position, remaining, strings, string_count}}}, parents}:
      Fail{Rejected{position, "CST traversal exceeded its request word-count bound"}}
    case 0n FinishNode{node, parents, Cursor{words, position, remaining, strings, string_count}}:
      Fail{Rejected{position, "CST traversal exceeded its request word-count bound"}}
    case 1n+rest ReadNode{Done{Parsed{header, cursor}}, parents}:
      scan_tree(rest, begin_node(header, parents, cursor))
    case 1n+rest FinishNode{node, Parent{kind, field, text, offset, 0n, reversed} <> parents, cursor}:
      scan_tree(rest, FinishNode{Cst.Cst{kind, field, text, offset, List.reverse(&2, Cst.Cst, node <> reversed)}, parents, cursor})
    case 1n+rest FinishNode{node, Parent{kind, field, text, offset, 1n+remaining, reversed} <> parents, cursor}:
      scan_tree(rest, ReadNode{scan_header(cursor), Parent{kind, field, text, offset, remaining, node <> reversed} <> parents})

def tree(fuel: Nat, cursor: Cursor) -> Result<&2, &1, ScanFailure, Parsed<Cst.Cst>>:
  scan_tree(fuel, ReadNode{scan_header(cursor), Nil{}})

def end(cursor: Cursor) -> Result<&2, &1, ScanFailure, Unit>:
  match cursor:
    case Cursor{words, offset, 0n, strings, string_count}:
      Done{Unit{}}
    case Cursor{words, offset, 1n+remaining, strings, string_count}:
      Fail{Rejected{offset, "trailing words after the request CST"}}

def bind(-A: Data, -B: Type, parsed: Result<&2, &1, ScanFailure, Parsed<A>>, next: A -> Cursor -> Result<&2, &1, ScanFailure, B>) -> Result<&2, &1, ScanFailure, B>:
  match parsed:
    case Fail{error}:
      Fail{error}
    case Done{Parsed{value, cursor}}:
      next(value, cursor)

def dictionary_depth(fuel: Nat, count: U32, depth: Nat) -> Nat:
  match fuel count:
    case _ 0:
      depth
    case _ 1:
      depth
    case 0n _:
      depth
    case 1n+rest more:
      dictionary_depth(rest, U32.shr(U32.add(more, 1)), 1n+depth)

def dictionary_store(index: U32, value: String, cursor: Cursor) -> Cursor:
  Cursor{words, offset, remaining, strings, string_count} = cursor
  Cursor{words, offset, remaining, Array.set(String, strings, index, value), string_count}

def dictionary_entries(count: Nat, +index: U32, cursor: Cursor) -> Result<&2, &1, ScanFailure, Parsed<Unit>>:
  match count:
    case 0n:
      Done{Parsed{Unit{}, cursor}}
    case 1n+rest:
      bind(String, Parsed<Unit>, scan_field(cursor, "dictionary string length", "dictionary string character"), value => cursor =>
        dictionary_entries(rest, U32.add(index, 1), dictionary_store(index, value, cursor)))

def dictionary_checked(valid: Bool, +count: U32, cursor: Cursor) -> Result<&2, &1, ScanFailure, Parsed<Unit>>:
  match valid cursor:
    case False{} Cursor{words, offset, remaining, strings, string_count}:
      Fail{Rejected{Nat.sub(offset, 1n), "dictionary count exceeds remaining request words"}}
    case True{} Cursor{words, offset, remaining, strings, string_count}:
      dictionary_entries(U32.to_nat(count), 0, Cursor{words, offset, remaining, Array.new(String, dictionary_depth(32n, count, 0n), SNil{}), count})

def dictionary_count(parsed: Result<&2, &1, ScanFailure, Parsed<U32>>) -> Result<&2, &1, ScanFailure, Parsed<Unit>>:
  match parsed:
    case Fail{error}:
      Fail{error}
    case Done{Parsed{+count, Cursor{words, offset, +remaining, strings, string_count}}}:
      dictionary_checked(Nat.is_le(U32.to_nat(count), remaining), count, Cursor{words, offset, remaining, strings, string_count})

def dictionary(cursor: Cursor) -> Result<&2, &1, ScanFailure, Parsed<Unit>>:
  dictionary_count(word(cursor, "dictionary count"))

def finish(complete: Result<&2, &1, ScanFailure, Unit>, request: Request) -> Result<&2, &1, ScanFailure, Request>:
  match complete:
    case Fail{error}:
      Fail{error}
    case Done{unit}:
      Done{request}

def stateless(selected: Operation, +bound: Nat, cursor: Cursor) -> Result<&2, &1, ScanFailure, Request>:
  bind(Nat, Request, natural(cursor, "frontend fuel"), fuel => cursor =>
    bind(Nat, Request, natural(cursor, "const steps"), steps => cursor =>
      bind(Unit, Request, dictionary(cursor), unit => cursor =>
        bind(Cst.Cst, Request, tree(bound, cursor), root => cursor =>
          bind(Cst.Cst, Request, tree(bound, cursor), prelude => cursor =>
            finish(end(cursor), Request{selected, fuel, steps, root, prelude}))))))

def cached(selected: Operation, bound: Nat, cursor: Cursor) -> Result<&2, &1, ScanFailure, Request>:
  bind(Nat, Request, natural(cursor, "frontend fuel"), fuel => cursor =>
    bind(Nat, Request, natural(cursor, "const steps"), steps => cursor =>
      bind(Unit, Request, dictionary(cursor), unit => cursor =>
        bind(Cst.Cst, Request, tree(bound, cursor), root => cursor =>
          finish(end(cursor), SessionRequest{selected, fuel, steps, root})))))

def declaration(tag: U32, bound: Nat, cursor: Cursor, offset: Nat) -> Result<&2, &1, ScanFailure, Parsed<Session.Declaration>>:
  match tag:
    case 0:
      bind(Nat, Parsed<Session.Declaration>, natural(cursor, "retained declaration identity"), identity => cursor => Done{Parsed{Session.Retained{identity}, cursor}})
    case 1:
      bind(Cst.Cst, Parsed<Session.Declaration>, tree(bound, cursor), node => cursor => Done{Parsed{Session.Replaced{node}, cursor}})
    case other:
      Fail{Rejected{offset, "unknown declaration tag; expected 0 retained or 1 replaced"}}

def declarations(count: Nat, +bound: Nat, cursor: Cursor, reversed: List<&2, Session.Declaration>) -> Result<&2, &1, ScanFailure, Parsed<List<&2, Session.Declaration>>>:
  match count:
    case 0n:
      Done{Parsed{List.reverse(&2, Session.Declaration, reversed), cursor}}
    case 1n+rest:
      Cursor{words, +offset, remaining, strings, string_count} = cursor
      bind(U32, Parsed<List<&2, Session.Declaration>>, word(Cursor{words, offset, remaining, strings, string_count}, "declaration tag"), tag => cursor =>
        bind(Session.Declaration, Parsed<List<&2, Session.Declaration>>, declaration(tag, bound, cursor, offset), value => cursor =>
          declarations(rest, bound, cursor, value <> reversed)))

def patch(selected: Operation, bound: Nat, cursor: Cursor) -> Result<&2, &1, ScanFailure, Request>:
  bind(Nat, Request, natural(cursor, "frontend fuel"), fuel => cursor =>
    bind(Nat, Request, natural(cursor, "const steps"), steps => cursor =>
      bind(Unit, Request, dictionary(cursor), unit => cursor =>
        bind(U32, Request, word(cursor, "declaration count"), count => cursor =>
          bind(List<&2, Session.Declaration>, Request, declarations(U32.to_nat(count), bound, cursor, Nil{}), values => cursor =>
            finish(end(cursor), SessionPatch{selected, fuel, steps, values}))))))

def body(opcode: U32, bound: Nat, cursor: Cursor) -> Result<&2, &1, ScanFailure, Request>:
  match opcode:
    case 0:
      stateless(Analyze{}, bound, cursor)
    case 1:
      stateless(Compile{}, bound, cursor)
    case 2:
      bind(Nat, Request, natural(cursor, "prelude fuel"), fuel => cursor =>
        bind(Unit, Request, dictionary(cursor), unit => cursor =>
          bind(Cst.Cst, Request, tree(bound, cursor), prelude => cursor =>
            finish(end(cursor), OpenSession{prelude, fuel}))))
    case 3:
      cached(Analyze{}, bound, cursor)
    case 4:
      cached(Compile{}, bound, cursor)
    case 5:
      patch(Analyze{}, bound, cursor)
    case 6:
      patch(Compile{}, bound, cursor)
    case other:
      Fail{Rejected{2n, "unknown operation; expected 0..6"}}

def expected_word(valid: Bool, cursor: Cursor, offset: Nat, message: String) -> Result<&2, &1, ScanFailure, Parsed<Unit>>:
  match valid:
    case False{}:
      Fail{Rejected{offset, message}}
    case True{}:
      Done{Parsed{Unit{}, cursor}}

def expect(parsed: Result<&2, &1, ScanFailure, Parsed<U32>>, expected: U32, offset: Nat, message: String) -> Result<&2, &1, ScanFailure, Parsed<Unit>>:
  match parsed:
    case Fail{error}:
      Fail{error}
    case Done{Parsed{value, cursor}}:
      expected_word(U32.is_eq(value, expected), cursor, offset, message)

def decode_frame(frame: NativeIO.Frame) -> Result<&2, &1, ScanFailure, Request>:
  NativeIO.Frame{words, length} = frame
  +bound = U32.to_nat(length)
  bind(Unit, Request, expect(word(Cursor{words, 0n, bound, [SNil{} : String*1n], 0}, "protocol magic"), 1112297300, 0n, "invalid protocol magic; expected BLOT"), unit => cursor =>
    bind(Unit, Request, expect(word(cursor, "protocol version"), Response.version(), 1n, "unsupported native protocol version; expected " ++ U32.show(Response.version())), unit => cursor =>
      bind(U32, Request, word(cursor, "operation"), opcode => cursor => body(opcode, bound, cursor))))

def decoded(result: Result<&2, &1, ScanFailure, Request>) -> Result<&2, &2, M.Diagnostic, Request>:
  match result:
    case Fail{error}:
      Fail{scan_failure(error)}
    case Done{request}:
      Done{request}

def decode(frame: NativeIO.Frame) -> Result<&2, &2, M.Diagnostic, Request>:
  decoded(decode_frame(frame))
