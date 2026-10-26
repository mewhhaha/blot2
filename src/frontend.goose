// Syntax arenas are mutable completion scratch, never published proof authority.
import .model;
import .intern;
struct FrontOwnedSchema { type_id: u32, next: u32 }
struct FrontListKey { prefix: u32, word: u32 }
fn hash(key: FrontListKey) -> u64 { hash_combine(hash(key.prefix), hash(key.word)) }
struct FrontTypeKey { words: u32[..16] }
fn hash(key: FrontTypeKey) -> u64 { var h: u64 = 0; for word in key.words { h = hash_combine(h, hash(word)); } return h; }
fn front_list(index: KeyIndex<FrontListKey>&, prefix: u32, word: u32) -> u32 { let key = FrontListKey { prefix: prefix, word: word }; let prior = key_index_get(index, key); if prior != 0 { return prior; } let id = index.slots.len as u32 + 1; key_index_insert(index, key, id); return id; }
fn front_type_key(c: Core, t: TypeNode, index: KeyIndex<FrontListKey>&) -> FrontTypeKey { var key = FrontTypeKey { .. }; key.words.append([t.tag, t.region, t.nat, t.capacity, t.domain, t.mode, t.contract, t.binder, t.children.count, t.fields.count, t.binders.count]); var children: u32 = 0; var fields: u32 = 0; var binders: u32 = 0; for i in t.children.count { children = front_list(index, children, c.refs[t.children.start + i]); } for i in t.fields.count { let f = c.fields[c.refs[t.fields.start + i]]; for word in [f.name, f.type_id, f.tag] { fields = front_list(index, fields, word); } } for i in t.binders.count { binders = front_list(index, binders, c.refs[t.binders.start + i]); } key.words.append([children, fields, binders]); return key; }

enum AstTag { Module, Import, Let, Alias, Name, Integer, Float, Bool, Unit, Tuple, Record, Field, Variant, Array, Unary, Binary, Call, Apply, Select, Index, Function, FunctionBody, ValueDo, Suite, Return, Break, Continue, Next, Stop, Seal, Abort, If, Case, Arm, For, Carry, RegionScope, OwnedScope, OwnedOpen, Pack, Open, Pattern, AnnotatedPattern, TypeName, TypeTuple, TypeRecord, TypeField, TypeVariant, TypeSum, TypeApply, TypeArrow, Forall, Exists, Binder, Constraint, Effect, Contract, Fact, Observation, Complement, Resource }
struct AstNode { tag: AstTag, start: u32, end: u32, text_start: u32, text_count: u32, bits: u64, children: Span, flags: u32 }
struct SyntaxToken { kind: u32, start: u32, end: u32, line: u32, indent: u32 }
struct ParseOutcome { root: u32, category: u8[..64], message: u8[..256], start: u32, end: u32 }
fn ast_text(source: const u8[:], node: AstNode) -> const u8[:] { source[node.text_start..node.text_start + node.text_count] }
fn ascii_letter(c: u8) -> bool { (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' }
fn ascii_digit(c: u8) -> bool { c >= '0' && c <= '9' }
fn frontend_utf8(source: const u8[:]) -> bool {
    var i: i64 = 0;
    while i < source.len {
        let c = source[i]; if c < 128 { i++; continue; }
        var n: i64 = 0; var lo: u8 = 128; var hi: u8 = 191;
        if c >= 194 && c <= 223 { n = 1; }
        else if c >= 224 && c <= 239 { n = 2; if c == 224 { lo = 160; } if c == 237 { hi = 159; } }
        else if c >= 240 && c <= 244 { n = 3; if c == 240 { lo = 144; } if c == 244 { hi = 143; } }
        else { return false; }
        if i + n >= source.len || source[i + 1] < lo || source[i + 1] > hi { return false; }
        for j in 2..n + 1 { if source[i + j] < 128 || source[i + j] > 191 { return false; } }
        i += n + 1;
    }
    return true;
}
fn parse_source(source: const u8[:], nodes: AstNode[>..]&, refs: u32[>..]&) -> ParseOutcome {
    if source.len > LIMIT_SOURCE { return ParseOutcome { category: "k1_source_limit", message: "source exceeds 16 MiB", .. }; }
    if !frontend_utf8(source) { return ParseOutcome { category: "k1_syntax", message: "source is not valid UTF-8", .. }; }
    if nodes.len == 0 { nodes.push(AstNode { .. }); }
    var tokens: SyntaxToken[>..] = []; var scratch: u32[>..<] = [];
    var pos: i64 = 0; var depth: u32 = 0; var header_indent: u32 = 0; var continuation_extra: u32 = 4294967295;
    fn fail_at(category: const u8[:], message: const u8[:], start: u32, end: u32) {
        return ParseOutcome { category: category, message: message, start: start, end: end, .. } from parse_source;
    }
    fn lex() {
        var i: i64 = 0; var line: u32 = 1; var indent: u32 = 0; var line_start = true;
        var bracket_count: u32 = 0; var brackets: u8[64] = [0; 64];
        while i < source.len {
            let c = source[i];
            if line_start {
                indent = 0; while i < source.len && source[i] == ' ' { indent++; i++; }
                if i == source.len { break; }
                if source[i] == '\t' { fail_at("k1_syntax", "indentation tabs are forbidden", i as u32, (i + 1) as u32); }
                if indent % 2 != 0 { fail_at("k1_syntax", "indentation must use two spaces per level", (i - indent) as u32, i as u32); }
                line_start = false; continue;
            }
            if c == '\t' { fail_at("k1_syntax", "tabs are not permitted outside comments", i as u32, (i + 1) as u32); }
            if c == ' ' || c == '\r' { i++; continue; }
            if c == '\n' { if bracket_count == 0 { tokens.push(SyntaxToken { kind: 1, start: i as u32, end: (i + 1) as u32, line: line, indent: indent }); } i++; line++; line_start = true; continue; }
            if c == '/' && i + 1 < source.len && source[i + 1] == '/' { while i < source.len && source[i] != '\n' { i++; } continue; }
            let start = i; var kind: u32 = 2;
            if ascii_letter(c) { i++; while i < source.len && (ascii_letter(source[i]) || ascii_digit(source[i])) { i++; } }
            else if ascii_digit(c) {
                kind = 3; i++; while i < source.len && ascii_digit(source[i]) { i++; }
                if i + 1 < source.len && source[i] == '.' && ascii_digit(source[i + 1]) { kind = 4; i++; while i < source.len && ascii_digit(source[i]) { i++; } }
                if i < source.len && (source[i] == 'e' || source[i] == 'E') { kind = 4; i++; if i < source.len && (source[i] == '+' || source[i] == '-') { i++; } let exp = i; while i < source.len && ascii_digit(source[i]) { i++; } if exp == i { fail_at("k1_syntax", "exponent requires digits", start as u32, i as u32); } }
            } else if c == '"' {
                kind = 5; i++; while i < source.len && source[i] != '"' { if source[i] < 32 || source[i] == '\\' { fail_at("k1_syntax", "invalid import path", start as u32, i as u32); } i++; }
                if i == source.len { fail_at("k1_syntax", "unterminated import path", start as u32, i as u32); } i++;
            } else {
                kind = 6; i++; if find("()[]{}.,:#@!~+-*/%<>=&^|", source[start..i]) < 0 { fail_at("k1_syntax", "invalid K1 token", start as u32, i as u32); }
                if i < source.len { let pair = source[start..i + 1]; if pair == "=>" || pair == "->" || pair == ".." || pair == "<<" || pair == ">>" || pair == "<=" || pair == ">=" || pair == "==" || pair == "!=" || pair == "&&" || pair == "||" { i++; } }
                if c == '(' || c == '[' || c == '{' { if bracket_count == 64 { fail_at("k1_source_limit", "syntax nesting exceeds 64", start as u32, i as u32); } brackets[bracket_count] = c; bracket_count++; }
                if c == ')' || c == ']' || c == '}' { if bracket_count == 0 { fail_at("k1_syntax", "unmatched delimiter", start as u32, i as u32); } bracket_count--; let open = brackets[bracket_count]; if (c == ')' && open != '(') || (c == ']' && open != '[') || (c == '}' && open != '{') { fail_at("k1_syntax", "mismatched delimiter", start as u32, i as u32); } }
            }
            tokens.push(SyntaxToken { kind: kind, start: start as u32, end: i as u32, line: line, indent: indent });
        }
        if bracket_count != 0 { fail_at("k1_syntax", "unclosed delimiter", source.len as u32, source.len as u32); }
        tokens.push(SyntaxToken { kind: 0, start: source.len as u32, end: source.len as u32, line: line, indent: 0 });
    }
    fn spelling(i: i64) -> const u8[:] { source[tokens[i].start..tokens[i].end] }
    fn is(s: const u8[:]) -> bool { spelling(pos) == s }
    fn take(s: const u8[:]) -> bool { if is(s) { pos++; return true; } return false; }
    fn fail(message: const u8[:]) { fail_at("k1_syntax", message, tokens[pos].start, tokens[pos].end); }
    fn expect(s: const u8[:]) { if !take(s) { fail("expected required grammar token"); } }
    fn lines() { while tokens[pos].kind == 1 { pos++; } }
    fn continuation() { if tokens[pos].kind == 1 { let saved = pos; lines(); if tokens[pos].indent != header_indent + 2 && tokens[pos].indent != continuation_extra && !(is("=") && tokens[pos].indent == header_indent) { pos = saved; fail("incomplete header must continue one indentation level below its start"); } } }
    fn reserved(s: const u8[:]) -> bool { return s == "import" || s == "as" || s == "pub" || s == "let" || s == "static" || s == "local" || s == "type" || s == "fn" || s == "in" || s == "do" || s == "return" || s == "break" || s == "continue" || s == "next" || s == "stop" || s == "seal" || s == "abort" || s == "if" || s == "else" || s == "case" || s == "for" || s == "carry" || s == "invariant" || s == "forall" || s == "exists" || s == "where" || s == "requires" || s == "ensures" || s == "on_true" || s == "on_false" || s == "resources" || s == "region" || s == "owned" || s == "pack" || s == "open"; }
    fn name(contextual: bool) -> i64 { let t = pos; if tokens[pos].kind != 2 || (!contextual && reserved(spelling(pos))) { fail("expected identifier"); } pos++; return t; }
    fn make(tag: AstTag, token: i64, children: const u32[:]) -> u32 {
        if nodes.len >= 1048576 { fail_at("k1_source_limit", "syntax node ceiling reached", tokens[token].start, tokens[token].end); }
        let s = Span { start: refs.len as u32, count: children.len as u32 }; refs.append(children); let id = nodes.len as u32;
        nodes.push(AstNode { tag: tag, start: tokens[token].start, end: if pos > token { tokens[pos - 1].end } else { tokens[token].end }, text_start: tokens[token].start, text_count: tokens[token].end - tokens[token].start, children: s, .. }); return id;
    }
    fn finish(tag: AstTag, token: i64, mark: i64) -> u32 { let n = make(tag, token, scratch[mark..]); scratch.resize(mark); return n; }
    fn enter() { if depth > 64 { fail_at("k1_source_limit", "syntax nesting exceeds 64", tokens[pos].start, tokens[pos].end); } depth++; }
    fn leave(n: u32) -> u32 { depth--; return n; }
    fn integer() -> u64 { if tokens[pos].kind != 3 { fail("expected U32 integer literal"); } var n: u64 = 0; for c in spelling(pos) { n = n * 10 + (c - '0') as u64; if n > MAX_U32 { fail("integer literal exceeds U32"); } } pos++; return n; }
    recursive fn term() -> u32 {
        enter(); let t = pos; var n: u32 = 0;
        if tokens[pos].kind == 3 { let v = integer(); n = make(AstTag.Integer, t, []); nodes[n].bits = v; }
        else if take("MAX") && take("-") { let x = term(); return leave(make(AstTag.Complement, t, [x])); }
        else { pos = t; let nm = name(true); if (spelling(nm) == "Len" || spelling(nm) == "Cap" || spelling(nm) == "Init") && take("(") { let x = term(); expect(")"); n = make(AstTag.Observation, nm, [x]); } else { n = make(AstTag.Name, nm, []); } }
        while take(".") { let nm = pos; if tokens[pos].kind == 3 { let ignored = integer(); } else { name(true); } let f = make(AstTag.Name, nm, []); n = make(AstTag.Select, t, [n, f]); } return leave(n);
    }
    fn facts() -> u32 {
        let t = pos; expect("["); let mark = scratch.len;
        if !is("]") { loop { let f = name(true); let s = spelling(f); if s != "Eq" && s != "Lt" && s != "Le" && s != "AddFits" && s != "SubFits" && s != "MulFits" && s != "Index" { fail_at("k1_unsupported_fact", "predicate is outside the finite proof algebra", tokens[f].start, tokens[f].end); } expect("("); let a = term(); expect(","); let b = term(); var c: u32 = 0; if s == "Index" { expect(","); c = term(); } expect(")"); scratch.push(make(AstTag.Fact, f, [a, b, c])); if !take(",") { break; } } }
        expect("]"); return finish(AstTag.Contract, t, mark);
    }
    fn binders() -> u32 {
        let t = pos; expect("["); let mark = scratch.len; if is("]") { fail("empty binder list"); }
        loop { let nm = name(false); expect(":"); let k = name(true); let s = spelling(k); if s != "Type" && s != "Region" && s != "Nat" && s != "Domain" { fail("unknown binder kind"); } let kn = make(AstTag.Name, k, []); scratch.push(make(AstTag.Binder, nm, [kn])); if scratch.len - mark > 32 { fail_at("k1_source_limit", "generic binders exceed 32", tokens[t].start, tokens[pos].end); } if !take(",") { break; } } expect("]"); return finish(AstTag.Tuple, t, mark);
    }
    recursive fn constraints() -> u32 {
        let t = pos; expect("["); let mark = scratch.len; if is("]") { fail("empty constraint list"); }
        loop { let nm = name(true); if spelling(nm) != "Plain" && spelling(nm) != "Share" { fail("unknown class constraint"); } expect("("); let ty = parse_type(0); expect(")"); scratch.push(make(AstTag.Constraint, nm, [ty])); if !take(",") { break; } } expect("]"); return finish(AstTag.Tuple, t, mark);
    }
    recursive fn type_atom() -> u32 {
        continuation(); enter(); let t = pos;
        if take("forall") || take("exists") { let exists = spelling(t) == "exists"; let bs = binders(); continuation(); var cs: u32 = 0; if !exists && take("where") { cs = constraints(); continuation(); } expect("=>"); let previous_extra = continuation_extra; continuation_extra = tokens[t].indent + 2; let body = parse_type(0); continuation_extra = previous_extra; return leave(make(if exists { AstTag.Exists } else { AstTag.Forall }, t, [bs, cs, body])); }
        if take("(") { let mark = scratch.len; if !is(")") { loop { scratch.push(parse_type(0)); if !take(",") { break; } } } expect(")"); if scratch.len == mark + 1 { let x = scratch[mark]; scratch.resize(mark); return leave(x); } return leave(finish(AstTag.TypeTuple, t, mark)); }
        if take("{") { let mark = scratch.len; if !is("}") { loop { let nm = name(false); expect(":"); let ty = parse_type(0); scratch.push(make(AstTag.TypeField, nm, [ty])); if !take(",") { break; } } } expect("}"); return leave(finish(AstTag.TypeRecord, t, mark)); }
        if take("#") { let nm = name(false); var payload: u32 = 0; if take("(") { payload = parse_type(0); expect(")"); } return leave(make(AstTag.TypeVariant, nm, [payload])); }
        if tokens[pos].kind == 3 { let value = integer(); let n = make(AstTag.Integer, t, []); nodes[n].bits = value; return leave(n); }
        let nm = name(true); var n = make(AstTag.TypeName, nm, []);
        while take(".") { let f = name(false); let field = make(AstTag.Name, f, []); n = make(AstTag.Select, t, [n, field]); }
        if take("[") { let mark = scratch.len; scratch.push(n); if is("]") { fail("empty type argument list"); } loop { scratch.push(parse_type(0)); if !take(",") { break; } } expect("]"); n = finish(AstTag.TypeApply, t, mark); }
        return leave(n);
    }
    recursive fn parse_type(minimum: u32) -> u32 {
        let t = pos; var n = type_atom();
        loop { if is("|") && minimum <= 2 { pos++; let rhs = parse_type(3); n = make(AstTag.TypeSum, t, [n, rhs]); continue; } if is("->") && minimum <= 1 { pos++; let rhs = parse_type(1); n = make(AstTag.TypeArrow, t, [n, rhs]); continue; } break; }
        if minimum == 0 {
            let mark = scratch.len; scratch.push(n); var last: u32 = 0;
            loop {
                let saved = pos; if tokens[pos].kind == 1 { lines(); if tokens[pos].indent != header_indent + 2 { pos = saved; break; } }
                var clause: u32 = 0; if is("!") { clause = 1; } else if is("requires") { clause = 2; } else if is("ensures") { clause = 3; } else if is("on_true") { clause = 4; } else if is("on_false") { clause = 5; } else if is("resources") { clause = 6; }
                if clause == 0 { pos = saved; break; } if clause <= last { fail("callable suffix order is invalid"); } last = clause; let ct = pos; pos++;
                if clause == 1 { expect("{"); let em = scratch.len; if !is("}") { loop { let en = name(true); let es = spelling(en); var region: u32 = 0; if es == "read" || es == "write" || es == "place" || es == "reset" { let rn = name(true); region = make(AstTag.Name, rn, []); } else if es != "reserve" && es != "release" && es != "host" { fail("unknown effect"); } scratch.push(make(AstTag.Effect, en, [region])); if !take(",") { break; } } } expect("}"); scratch.push(finish(AstTag.Contract, ct, em)); }
                else if clause == 6 { expect("{"); expect("depth"); expect(":"); let dt = pos; let d = integer(); expect(","); expect("frame"); expect(":"); let ft = pos; let f = integer(); expect("}"); let dn = make(AstTag.Integer, dt, []); nodes[dn].bits = d; let fnn = make(AstTag.Integer, ft, []); nodes[fnn].bits = f; scratch.push(make(AstTag.Resource, ct, [dn, fnn])); }
                else { let fs = facts(); nodes[fs].text_start = tokens[ct].start; nodes[fs].text_count = tokens[ct].end - tokens[ct].start; scratch.push(fs); }
            }
            if scratch.len > mark + 1 { n = finish(AstTag.Contract, t, mark); } else { scratch.resize(mark); }
        }
        return n;
    }
    recursive fn pattern() -> u32 {
        enter(); let t = pos;
        if take("(") { let mark = scratch.len; if !is(")") { loop { scratch.push(pattern()); if !take(",") { break; } } } if take(":") { if scratch.len != mark + 1 { fail("annotation requires one pattern"); } let p = scratch[mark]; scratch.resize(mark); let ty = parse_type(0); expect(")"); return leave(make(AstTag.AnnotatedPattern, t, [p, ty])); } expect(")"); return leave(finish(AstTag.Pattern, t, mark)); }
        if take("{") { let mark = scratch.len; if !is("}") { loop { let f = name(false); var value = make(AstTag.Name, f, []); if take(":") { value = pattern(); } scratch.push(make(AstTag.Field, f, [value])); if !take(",") { break; } } } expect("}"); return leave(finish(AstTag.Pattern, t, mark)); }
        let nm = name(false); return leave(make(AstTag.Name, nm, []));
    }
    fn precedence(s: const u8[:]) -> u32 { if s == "||" { return 1; } if s == "&&" { return 2; } if s == "==" || s == "!=" { return 3; } if s == "<" || s == "<=" || s == ">" || s == ">=" { return 4; } if s == "|" { return 5; } if s == "^" { return 6; } if s == "&" { return 7; } if s == "<<" || s == ">>" { return 8; } if s == "+" || s == "-" { return 9; } if s == "*" || s == "/" || s == "%" { return 10; } return 0; }
    recursive fn expression(minimum: u32) -> u32 {
        continuation(); enter(); let t = pos; var n: u32 = 0;
        if take("!") || take("~") || take("-") { let x = expression(11); n = make(AstTag.Unary, t, [x]); } else { n = primary(); }
        var comparison = false;
        loop {
            if take("(") { let mark = scratch.len; scratch.push(n); if !is(")") { loop { scratch.push(expression(1)); if !take(",") { break; } } } expect(")"); n = finish(AstTag.Call, t, mark); continue; }
            if take("@") { expect("["); let mark = scratch.len; scratch.push(n); if is("]") { fail("empty generic argument list"); } loop { scratch.push(parse_type(0)); if !take(",") { break; } } expect("]"); n = finish(AstTag.Apply, t, mark); continue; }
            if take(".") { let f = pos; if tokens[pos].kind == 3 { let ignored = integer(); } else { name(true); } let field = make(AstTag.Name, f, []); n = make(AstTag.Select, t, [n, field]); continue; }
            if take("[") { let ix = expression(1); expect("]"); n = make(AstTag.Index, t, [n, ix]); continue; }
            let op = pos; let p = precedence(spelling(pos)); if p == 0 || p < minimum { break; }
            if p == 3 || p == 4 { if comparison { fail("comparisons cannot chain"); } comparison = true; }
            pos++; let rhs = expression(p + 1); n = make(AstTag.Binary, op, [n, rhs]);
        }
        return leave(n);
    }
    recursive fn suite(tag: AstTag, indent: u32) -> u32 {
        let t = pos; if tokens[pos].kind != 1 { fail("suite requires newline"); } lines(); let expected = indent + 2;
        if tokens[pos].kind == 0 || tokens[pos].indent != expected { fail("suite must begin two spaces below final header line"); }
        let mark = scratch.len;
        loop { if tokens[pos].kind == 0 || tokens[pos].indent < expected { break; } if tokens[pos].indent != expected { fail("unexpected suite indentation"); } let old = header_indent; header_indent = expected; scratch.push(statement()); header_indent = old; if tokens[pos].kind == 1 { lines(); } else if tokens[pos].kind != 0 && tokens[pos].indent >= expected && tokens[pos].line == tokens[pos - 1].line { fail("statements require newlines"); } }
        return finish(tag, t, mark);
    }
    recursive fn primary() -> u32 {
        let t = pos;
        if tokens[pos].kind == 3 { let v = integer(); let n = make(AstTag.Integer, t, []); nodes[n].bits = v; return n; }
        if tokens[pos].kind == 4 { pos++; return make(AstTag.Float, t, []); }
        if take("(") { let mark = scratch.len; if !is(")") { loop { scratch.push(expression(1)); if !take(",") { break; } } } expect(")"); if scratch.len == mark { return finish(AstTag.Unit, t, mark); } if scratch.len == mark + 1 { let x = scratch[mark]; scratch.resize(mark); return x; } return finish(AstTag.Tuple, t, mark); }
        if take("{") { let mark = scratch.len; if !is("}") { loop { let nm = name(false); expect(":"); let x = expression(1); scratch.push(make(AstTag.Field, nm, [x])); if !take(",") { break; } } } expect("}"); return finish(AstTag.Record, t, mark); }
        if take("#") {
            if take("[") { let mark = scratch.len; if !is("]") { loop { scratch.push(expression(1)); if !take(",") { break; } } } expect("]"); return finish(AstTag.Array, t, mark); }
            let nm = name(false); var payload: u32 = 0; if take("(") { payload = expression(1); expect(")"); }
            if spelling(nm) == "True" || spelling(nm) == "False" { if payload != 0 { fail("Bool is nullary"); } let n = make(AstTag.Bool, nm, []); nodes[n].bits = if spelling(nm) == "True" { 1 } else { 0 }; return n; }
            return make(AstTag.Variant, nm, [payload]);
        }
        if take("fn") { var placement: u32 = 0; if take("in") { let nm = name(false); placement = make(AstTag.Name, nm, []); } let p = pattern(); expect("=>"); continuation(); var body: u32 = 0; if take("return") { let rt = pos - 1; let x = expression(1); body = make(AstTag.Return, rt, [x]); } else { expect("do"); let ind = tokens[pos - 1].indent; expect(":"); body = suite(AstTag.FunctionBody, ind); } return make(AstTag.Function, t, [p, body, placement]); }
        if take("do") { expect(":"); let body = suite(AstTag.Suite, tokens[t].indent); return make(AstTag.ValueDo, t, [body]); }
        if take("for") { let nm = name(false); let variable = make(AstTag.Name, nm, []); expect("in"); let lo = expression(1); expect(".."); let hi = expression(1); let mark = scratch.len; scratch.push(variable); scratch.push(lo); scratch.push(hi); if take("carry") { expect("("); if is(")") { fail("empty carry list"); } loop { let cn = name(false); expect("="); let init = expression(1); scratch.push(make(AstTag.Carry, cn, [init])); if !take(",") { break; } } expect(")"); } if tokens[pos].kind == 1 { continuation(); } var inv: u32 = 0; if take("invariant") { inv = facts(); } scratch.push(inv); expect("do"); let ind = tokens[pos - 1].indent; expect(":"); scratch.push(suite(AstTag.Suite, ind)); return finish(AstTag.For, t, mark); }
        if (is("region") || is("owned")) && spelling(pos + 1) == "@" { let own = take("owned"); if !own { expect("region"); } expect("@"); expect("["); let ty = parse_type(0); var et: u32 = 0; if own { expect(","); et = parse_type(0); } expect("]"); expect("("); let bytes = expression(1); expect(")"); if tokens[pos].kind == 1 { continuation(); } expect("as"); let rn = name(false); let r = make(AstTag.Name, rn, []); var owner: u32 = 0; var free: u32 = 0; if own { let nm = name(false); free = make(AstTag.Name, nm, []); } else { expect("("); let on = name(false); owner = make(AstTag.Name, on, []); expect(","); let fnn = name(false); free = make(AstTag.Name, fnn, []); expect(")"); } expect("in"); expect("do"); let ind = tokens[pos - 1].indent; expect(":"); let body = suite(AstTag.Suite, ind); return make(if own { AstTag.OwnedScope } else { AstTag.RegionScope }, t, [ty, et, bytes, r, owner, free, body]); }
        if is("owned") && spelling(pos + 1) == "." && spelling(pos + 2) == "open" { pos += 3; expect("("); let h = expression(1); expect(")"); expect("as"); let rn = name(false); let r = make(AstTag.Name, rn, []); let pn = name(false); let p = make(AstTag.Name, pn, []); expect("in"); expect("do"); let ind = tokens[pos - 1].indent; expect(":"); let body = suite(AstTag.Suite, ind); return make(AstTag.OwnedOpen, t, [h, r, p, body]); }
        if take("pack") { expect("["); let mark = scratch.len; if is("]") { fail("empty witness list"); } loop { scratch.push(parse_type(0)); if !take(",") { break; } } expect("]"); let ws = finish(AstTag.Tuple, t, mark); expect("as"); let ty = parse_type(0); let payload = expression(1); return make(AstTag.Pack, t, [ws, ty, payload]); }
        if take("open") { let package = expression(1); expect("as"); expect("["); let mark = scratch.len; if is("]") { fail("empty opening binder list"); } loop { let bn = name(false); scratch.push(make(AstTag.Name, bn, [])); if !take(",") { break; } } expect("]"); let bs = finish(AstTag.Tuple, t, mark); let nm = name(false); let payload = make(AstTag.Name, nm, []); expect("in"); expect("do"); let ind = tokens[pos - 1].indent; expect(":"); let body = suite(AstTag.Suite, ind); return make(AstTag.Open, t, [package, bs, payload, body]); }
        if tokens[pos].kind == 2 { if reserved(spelling(pos)) && !is("region") && !is("owned") && !is("local") && !is("static") { fail("reserved word cannot be an expression"); } pos++; return make(AstTag.Name, t, []); }
        fail("expected expression"); return 0;
    }
    recursive fn declaration() -> u32 {
        let t = pos; var flags: u32 = 0; if take("pub") { flags |= 1; } if take("static") { flags |= 2; if flags & 1 != 0 { fail("pub static is not a declaration form"); } }
        if take("type") { if flags & 2 != 0 { fail("static type is invalid"); } let nm = name(false); let nn = make(AstTag.Name, nm, []); var bs: u32 = 0; var cs: u32 = 0; if is("[") { bs = binders(); } if take("where") { cs = constraints(); } continuation(); expect("="); let ty = parse_type(0); let n = make(AstTag.Alias, t, [nn, bs, cs, ty]); nodes[n].flags = flags; return n; }
        expect("let"); let p = pattern(); var ty: u32 = 0; if take(":") { ty = parse_type(0); } if flags & 1 != 0 && (ty == 0 || nodes[p].tag != AstTag.Name) { fail("public let requires name and annotation"); } continuation(); expect("="); let x = expression(1); let n = make(AstTag.Let, t, [p, ty, x]); nodes[n].flags = flags; return n;
    }
    recursive fn statement() -> u32 {
        let t = pos; if is("pub") || is("let") || is("static") || is("type") { return declaration(); }
        if take("return") { let x = expression(1); return make(AstTag.Return, t, [x]); }
        if take("break") { var x: u32 = 0; if tokens[pos].kind != 1 && tokens[pos].kind != 0 { x = expression(1); } return make(AstTag.Break, t, [x]); }
        if take("continue") { return make(AstTag.Continue, t, []); }
        if take("next") || take("stop") || take("seal") || take("abort") { let s = spelling(t); let tag = if s == "next" { AstTag.Next } else if s == "stop" { AstTag.Stop } else if s == "seal" { AstTag.Seal } else { AstTag.Abort }; expect("("); let mark = scratch.len; if !is(")") { loop { scratch.push(expression(1)); if !take(",") { break; } } } expect(")"); if (tag == AstTag.Seal || tag == AstTag.Abort) && scratch.len - mark != 2 { fail("seal/abort require two arguments"); } return finish(tag, t, mark); }
        if take("if") { let c = expression(1); let ind = tokens[pos].indent; expect(":"); let yes = suite(AstTag.Suite, ind); var no: u32 = 0; if is("else") && tokens[pos].indent == tokens[t].indent { pos++; expect(":"); no = suite(AstTag.Suite, tokens[t].indent); } return make(AstTag.If, t, [c, yes, no]); }
        if take("case") { let value = expression(1); let ind = tokens[pos].indent; expect(":"); if tokens[pos].kind != 1 { fail("case requires suite"); } lines(); let mark = scratch.len; scratch.push(value); var wildcard = false; if tokens[pos].indent != ind + 2 { fail("invalid case indentation"); }
            while tokens[pos].kind != 0 && tokens[pos].indent == ind + 2 { if wildcard { fail_at("k1_nonexhaustive_case", "wildcard must be last", tokens[pos].start, tokens[pos].end); } let at = pos; var p: u32 = 0;
                if take("#") { let nm = name(false); var payload: u32 = 0; if take("(") { payload = pattern(); expect(")"); } p = make(AstTag.Variant, nm, [payload]); }
                else if take("_") { wildcard = true; p = make(AstTag.Name, at, []); }
                else if tokens[pos].kind == 3 || tokens[pos].kind == 4 { p = primary(); }
                else if take("-") { if tokens[pos].kind != 4 { fail_at("k1_nonexhaustive_case", "negative case pattern requires F32 literal", tokens[at].start, tokens[pos].end); } let value = primary(); p = make(AstTag.Unary, at, [value]); }
                else { fail_at("k1_nonexhaustive_case", "invalid case pattern", tokens[pos].start, tokens[pos].end); }
                expect("=>"); var body: u32 = 0; if take("do") { let ai = tokens[pos - 1].indent; expect(":"); body = suite(AstTag.Suite, ai); } else { body = statement(); } scratch.push(make(AstTag.Arm, at, [p, body])); if tokens[pos].kind == 1 { lines(); } else if tokens[pos].kind != 0 && tokens[pos].line == tokens[pos - 1].line { fail("case arms require newlines"); }
            } return finish(AstTag.Case, t, mark);
        }
        return expression(1);
    }
    lex(); lines(); let mark = scratch.len; var declarations_started = false;
    while tokens[pos].kind != 0 {
        if tokens[pos].indent != 0 { fail("top-level declaration is indented"); } header_indent = 0;
        if take("import") { if declarations_started { fail("imports must precede declarations"); } let t = pos - 1; let path = pos; if tokens[pos].kind != 5 { fail("import requires quoted path"); } pos++; expect("as"); let nm = name(false); let alias = make(AstTag.Name, nm, []); let pn = make(AstTag.Name, path, []); scratch.push(make(AstTag.Import, t, [pn, alias])); }
        else { declarations_started = true; scratch.push(declaration()); }
        if tokens[pos].kind == 1 { lines(); } else if tokens[pos].kind != 0 && tokens[pos].line == tokens[pos - 1].line { fail("declarations require newlines"); }
    }
    let root = finish(AstTag.Module, 0, mark); return ParseOutcome { root: root, .. };
}

let FE_SYNTAX: u32 = 1000;
let FE_UNBOUND: u32 = 1001;
let FE_TYPE: u32 = 1002;
let FE_KIND: u32 = 1003;
let FE_CASE: u32 = 1004;
let FE_EFFECT: u32 = 1005;
let FE_CONTRACT: u32 = 1006;
let FE_RETURN: u32 = 1007;
let FE_TARGET: u32 = 1008;
let FE_BOUNDS: u32 = 1009;
let FE_ARITHMETIC: u32 = 1010;
let FE_DOMAIN: u32 = 1011;
let FE_MOVED: u32 = 1012;
let FE_USAGE: u32 = 1013;
let FE_OWNERSHIP: u32 = 1014;
let FE_LIFETIME: u32 = 1015;
let FE_LOAN: u32 = 1016;
let FE_INITIALIZATION: u32 = 1017;
let FE_CAPTURE: u32 = 1018;
let FE_OWNED_PAYLOAD: u32 = 1019;
let FE_RESULT: u32 = 1020;
let FE_RECURSION: u32 = 1021;
let FE_RESOURCE: u32 = 1022;
let FE_LAYOUT: u32 = 1023;
let FE_ENV_CAPACITY: u32 = 1024;
let FE_INTERFACE: u32 = 1025;
let FE_FACT: u32 = 1026;
let FE_UNSUPPORTED: u32 = 1027;
let FE_SOURCE_LIMIT: u32 = 1028;
let FE_SEMANTIC_LIMIT: u32 = 1029;
let FE_CORE_LIMIT: u32 = 1030;
let FE_PROOF_LIMIT: u32 = 1031;
let FE_STATIC_LIMIT: u32 = 1032;
fn frontend_diagnostic_name(code: u32) -> const u8[:] {
    if code == FE_SYNTAX { return "k1_syntax"; } if code == FE_UNBOUND { return "k1_unbound_name"; }
    if code == FE_TYPE { return "k1_type_mismatch"; } if code == FE_KIND { return "k1_kind_mismatch"; }
    if code == FE_CASE { return "k1_nonexhaustive_case"; } if code == FE_EFFECT { return "k1_effect_mismatch"; }
    if code == FE_CONTRACT { return "k1_contract_not_established"; } if code == FE_RETURN { return "k1_missing_return"; }
    if code == FE_TARGET { return "k1_bad_control_target"; } if code == FE_BOUNDS { return "k1_bounds_not_established"; }
    if code == FE_ARITHMETIC { return "k1_arithmetic_not_established"; } if code == FE_DOMAIN { return "k1_domain_mismatch"; }
    if code == FE_MOVED { return "k1_use_after_move"; } if code == FE_USAGE { return "k1_usage_not_permitted"; }
    if code == FE_OWNERSHIP { return "k1_ownership_not_discharged"; } if code == FE_LIFETIME { return "k1_lifetime_escape"; }
    if code == FE_LOAN { return "k1_loan_conflict"; } if code == FE_INITIALIZATION { return "k1_incomplete_initialization"; }
    if code == FE_CAPTURE { return "k1_invalid_capture"; } if code == FE_OWNED_PAYLOAD { return "k1_invalid_owned_payload"; }
    if code == FE_RESULT { return "k1_unhandled_result"; } if code == FE_RECURSION { return "k1_recursive_call"; }
    if code == FE_RESOURCE { return "k1_resource_bound"; } if code == FE_LAYOUT { return "k1_layout_limit"; }
    if code == FE_ENV_CAPACITY { return "k1_environment_capacity"; } if code == FE_INTERFACE { return "k1_incomplete_interface"; }
    if code == FE_FACT { return "k1_unsupported_fact"; } if code == FE_UNSUPPORTED { return "k1_unsupported_feature"; }
    if code == FE_SOURCE_LIMIT { return "k1_source_limit"; } if code == FE_SEMANTIC_LIMIT { return "k1_semantic_limit"; }
    if code == FE_CORE_LIMIT { return "k1_core_limit"; } if code == FE_PROOF_LIMIT { return "k1_proof_limit"; }
    if code == FE_STATIC_LIMIT { return "k1_static_limit"; } return "k1_invalid_artifact";
}
fn frontend_parse_code(category: const u8[:]) -> u32 {
    if category == "k1_source_limit" { return FE_SOURCE_LIMIT; }
    if category == "k1_unsupported_fact" { return FE_FACT; }
    if category == "k1_nonexhaustive_case" { return FE_CASE; }
    return FE_SYNTAX;
}
fn frontend_imports(source: const u8[:], paths: Span[>..]&, aliases: Span[>..]&, diagnostics: Diagnostic[>..]&) -> bool {
    var nodes: AstNode[>..] = []; var refs: u32[>..] = [];
    let parsed = parse_source(source, nodes, refs);
    if parsed.root == 0 { diagnostics.push(Diagnostic { code: frontend_parse_code(parsed.category), origin: parsed.start, related: parsed.end, .. }); return false; }
    let children = nodes[parsed.root].children;
    for i in children.count {
        let node = nodes[refs[children.start + i]];
        if node.tag != AstTag.Import { break; }
        let path = nodes[refs[node.children.start]]; let alias = nodes[refs[node.children.start + 1]];
        paths.push(Span { start: path.text_start + 1, count: path.text_count - 2 });
        aliases.push(Span { start: alias.text_start, count: alias.text_count });
    }
    return true;
}

import .proofs;
import .numeric;
import .evaluate;
struct FrontBinding { generic_function: u32, name: u32, value: u32, type_id: u32, moved: bool, held_original: u32 }
struct FrontDecl { node: u32, definition: u32, function: u32, state: u32, projection_root: u32, projection_path: Span }
struct FrontPending { block_id: u32, operation: u32, next: u32 }
struct FrontNatValue { binder: u32, value: u32 }
struct FrontTypeBinding { name: u32, binder: u32 }
struct FrontAliasDependency { dependent: u32, next: u32 }
struct FrontAlias { name: u32, type_id: u32, binders: Span, complete: bool }
struct FrontBoolean { value: u32, left: u32, right: u32, conjunction: bool }
struct FrontImport { name: u32, module: u32 }
struct FrontStage { function: u32, value: u32, type_id: u32 }
struct FrontQuery { owner: u32, dependency: u32 }
struct FrontHeld { original: u32, binding: u32 }
struct FrontCaptureFrame { function: u32, parent_function: u32, parent_base: u32, parent_end: u32, facts: Span }
struct FrontCaptureFact { function: u32, premise: u32, evidence: u32 }
struct FrontCapturedName { function: u32, name: u32, value: u32 }
struct FrontOwned { target: u32, construction: u32, owned_type: u32, error_type: u32, body_error: u32, substitutions: Span, scope: u32 }
struct FrontLoop { id: u32, node: u32, index: u32, upper_value: u32, header_params: Span, exit_params: Span, carries: u32, hidden_indices: Span }
struct FrontTarget { block_id: u32, value: u32, type_id: u32, incoming: u32, scope: u32, binding_limit: u32, carry_indices: Span, carry_values: Span }
// Owned by one candidate build, never a retained revision or admission receipt.
// Types/terms/facts are append-only during completion. Reload the finalized
// suffix at each module boundary, including rows appended by retained replay.
// Seen sets, ranks and declaration budgets remain module-local.
struct FrontendLoaded { types: u32, terms: u32, facts: u32 }
struct FrontendScratch { lists: KeyIndex<FrontListKey>&, types: KeyIndex<FrontTypeKey>&, terms: KeyIndex<ProofTermKey>&, facts: KeyIndex<Fact>&, loaded: FrontendLoaded& }
fn with_frontend_scratch<F>() {
    var lists = KeyIndex<FrontListKey> {}; var types = KeyIndex<FrontTypeKey> {}; var terms = KeyIndex<ProofTermKey> {}; var facts = KeyIndex<Fact> {}; var loaded = FrontendLoaded { .. };
    F(FrontendScratch { lists: lists, types: types, terms: terms, facts: facts, loaded: loaded });
}
fn frontend_scratch_clear(scratch: FrontendScratch) {
    scratch.lists.heads = [0; 1024]; scratch.lists.slots.resize(0); scratch.types.heads = [0; 1024]; scratch.types.slots.resize(0);
    scratch.terms.heads = [0; 1024]; scratch.terms.slots.resize(0); scratch.facts.heads = [0; 1024]; scratch.facts.slots.resize(0); scratch.loaded = FrontendLoaded { .. };
}
fn frontend_seed(b: CoreBuilder, scratch: FrontendScratch) {
    for id in scratch.loaded.types..b.types.len { if id != 0 { key_index_insert(scratch.types, front_type_key(core_view(b), b.types[id], scratch.lists), id as u32); } }
    for id in scratch.loaded.terms..b.terms.len { if id != 0 { key_index_insert(scratch.terms, proof_key(b, b.terms[id]), id as u32); } }
    for id in scratch.loaded.facts..b.facts.len { if id != 0 { key_index_insert(scratch.facts, b.facts[id], id as u32); } }
    scratch.loaded.types = b.types.len as u32; scratch.loaded.terms = b.terms.len as u32; scratch.loaded.facts = b.facts.len as u32;
}
fn frontend_no_reuse<R>(definition: u32, span: Span, type_id: u32) -> u32 { 0 }
fn frontend_complete(source: const u8[:], module_name: const u8[:], b: CoreBuilder, work: Work&, diagnostics: Diagnostic[>..]&) -> bool {
    return frontend_complete_with_reuse(source, module_name, b, work, diagnostics, frontend_no_reuse);
}
fn frontend_complete_with_reuse<F>(source: const u8[:], module_name: const u8[:], b: CoreBuilder, work: Work&, diagnostics: Diagnostic[>..]&) -> bool {
    var ok = false;
    with_frontend_scratch() { scratch => ok = frontend_complete_with_reuse_in(source, module_name, b, work, diagnostics, scratch, F); };
    return ok;
}
fn frontend_complete_in(source: const u8[:], module_name: const u8[:], b: CoreBuilder, work: Work&, diagnostics: Diagnostic[>..]&, scratch: FrontendScratch) -> bool {
    return frontend_complete_with_reuse_in(source, module_name, b, work, diagnostics, scratch, frontend_no_reuse);
}
fn frontend_complete_with_reuse_in<F>(source: const u8[:], module_name: const u8[:], b: CoreBuilder, work: Work&, diagnostics: Diagnostic[>..]&, scratch: FrontendScratch) -> bool {
    let ok = frontend_complete_indexed(source, module_name, b, work, diagnostics, scratch, F);
    // Failed attempts cannot lend indexes to another candidate or a retry.
    if !ok { frontend_scratch_clear(scratch); }
    return ok;
}
fn frontend_complete_indexed<F>(source: const u8[:], module_name: const u8[:], b: CoreBuilder, work: Work&, diagnostics: Diagnostic[>..]&, scratch: FrontendScratch) -> bool {
    var nodes: AstNode[>..] = []; var ast_refs: u32[>..] = [];
    let parsed = parse_source(source, nodes, ast_refs);
    var module_id: u32 = 0;
    for m, i in b.modules { if i != 0 && name_bytes(core_view(b), m.name) == module_name { module_id = i as u32; } }
    if module_id == 0 { module_id = b.modules.len as u32; let name = add_name(b, module_name); let bytes = Span { start: b.bytes.len as u32, count: source.len as u32 }; b.bytes.append(source); b.modules.push(Module { name: name, path: name, source: bytes, .. }); }
    if parsed.root == 0 { let origin = b.origins.len as u32; b.origins.push(Origin { module: module_id, start: parsed.start, end: parsed.end }); diagnostics.push(Diagnostic { code: frontend_parse_code(parsed.category), origin: origin, detail: add_name(b, parsed.message), .. }); return false; }
    var owned_schemas: FrontOwnedSchema[>..] = [FrontOwnedSchema { .. }]; var local_regions = KeyIndex<u32> {};
    frontend_seed(b, scratch);
    var proof_seen = KeyIndex<ProofSeenKey> {}; var proof_counts: ProofCounts[>..] = [];
    let proof_index = ProofIndex { terms: scratch.terms, facts: scratch.facts, seen: proof_seen, counts: proof_counts };
    var environment_bounds: u32[>..<] = []; var escape_bounds: u32[>..<] = []; var emit_arguments: u32[>..<] = []; var booleans: FrontBoolean[>..] = [];
    var alias_work: u64[>..] = []; var alias_heads: u32[>..] = []; var alias_remaining: u32[>..] = []; var alias_dependencies: FrontAliasDependency[>..] = [FrontAliasDependency { .. }]; var alias_names = KeyIndex<u32> {}; var alias_seen = KeyIndex<FrontListKey> {}; var alias_bounds: u32[>..<] = []; var alias_queue: u32[>..] = []; var value_names = KeyIndex<u32> {}; var value_queue: u32[>..] = [];
    var local_aliases: FrontAlias[>..<] = []; var alias_base: i64 = 0; var alias_lexical: i64 = 0;
    var natvalues: FrontNatValue[>..<] = []; var open_scopes: u32[>..<] = []; var open_base: i64 = 0;
    var loop_stack: FrontLoop[>..<] = []; var loop_base: i64 = 0;
    var typebindings: FrontTypeBinding[>..<] = []; var type_base: i64 = 0;
    var imports: FrontImport[>..] = []; var bindings: FrontBinding[>..<] = []; var decls: FrontDecl[>..] = []; var pending: FrontPending[>..] = [FrontPending { .. }]; var block_heads: u32[>..] = []; var block_tails: u32[>..] = []; var active: u32[>..<] = []; var temporaries: u32[>..<] = []; var targets: FrontTarget[>..<] = [];
    var static_stats = StaticStats { .. }; var static_scope_start: i64 = 0; var static_scope_end: i64 = 0; var top_definitions: u32[>..<] = []; var static_values: StaticValue[>..<] = []; var queries: FrontQuery[>..<] = []; var current_producer: u32 = 0; var held: FrontHeld[>..<] = []; var held_base: i64 = 0; var explicit_effects: u32[>..<] = []; var capture_frames: FrontCaptureFrame[>..<] = []; var capture_facts: FrontCaptureFact[>..] = []; var capture_names: FrontCapturedName[>..<] = []; var capture_base: i64 = 0; var owned_stack: FrontOwned[>..<] = []; var owned_base: i64 = 0; var schema_hole: u32 = 0; var lexical_base: i64 = 0; var snapshots: FrontBinding[>..<] = []; var lambda_outer_base: i64 = -1; var binding_base: i64 = 0; var active_base: i64 = 0; var target_base: i64 = 0;
    var effects_explicit = false; var current_function: u32 = 0; var current_block: u32 = 0; var current_scope: u32 = 0; var return_type: u32 = 0;
    var type_start = b.types.len; var block_start = b.blocks.len; var op_start = b.ops.len + b.terminators.len;
    var visit_start = work.visits; var proof_limits = proof_budget(b, work, proof_index); var current_decl: u32 = 0; var max_callee_depth: u32 = 0; var max_callee_frame: u32 = 0;
    let initial_active = b.phase.active;
    fn child(n: u32, index: u32) -> u32 { ast_refs[nodes[n].children.start + index] }
    fn origin(n: u32) -> u32 { let id = b.origins.len as u32; b.origins.push(Origin { module: module_id, start: nodes[n].start, end: nodes[n].end }); return id; }
    fn fail(code: u32, n: u32, message: const u8[:]) {
        diagnostics.push(Diagnostic { code: code, origin: origin(n), detail: add_name(b, message), .. });
        while b.phase.active > initial_active { end_completion(b); }
        return false from frontend_complete_indexed;
    }
    fn tick(n: u32) { if !charge(work, 1, visit_start + LIMIT_VISITS) { fail(FE_SEMANTIC_LIMIT, n, "required semantic traversal limit reached"); } }
    fn allocate(n: u32) { if !allocation(work) { fail(FE_SEMANTIC_LIMIT, n, "completion allocation failed"); } }
    recursive fn demand_type(ty: u32) { if ty == 0 { return; } let key = ProofSeenKey { budget: proof_limits.id, kind: 3, id: ty }; if key_index_get(proof_index.seen, key) != 0 { return; } tick(current_decl); if !proof_track(work, proof_limits, proof_index, 3, ty) { fail(FE_CORE_LIMIT, current_decl, "type graph limit reached"); } let t = b.types[ty]; if !proof_demand(b, work, proof_limits, proof_index, t.nat) || !proof_demand(b, work, proof_limits, proof_index, t.capacity) { fail(FE_PROOF_LIMIT, current_decl, "type witness term limit"); } if t.tag == TY_OWNED { let id = owned_schemas.len as u32; owned_schemas.push(FrontOwnedSchema { type_id: ty, next: proof_index.counts[proof_limits.id].owned_head }); proof_index.counts[proof_limits.id].owned_head = id; } for i in t.children.count { demand_type(b.refs[t.children.start + i]); } for i in t.fields.count { tick(current_decl); demand_type(b.fields[b.refs[t.fields.start + i]].type_id); } }
    fn intern_type(t: TypeNode) -> u32 {
        tick(current_decl); for i in t.children.count { tick(current_decl); } for i in t.fields.count { tick(current_decl); } for i in t.binders.count { tick(current_decl); }
        let key = front_type_key(core_view(b), t, scratch.lists); let found = key_index_get(scratch.types, key); if found != 0 { demand_type(found); return found; }
        allocate(current_decl); let id = b.types.len as u32; b.types.push(t); key_index_insert(scratch.types, key, id); demand_type(id); return id;
    }
    current_decl = parsed.root;
    let unit = intern_type(TypeNode { tag: TY_UNIT, .. }); let boolean = intern_type(TypeNode { tag: TY_BOOL, .. }); let unsigned = intern_type(TypeNode { tag: TY_U32, .. }); let floating = intern_type(TypeNode { tag: TY_F32, .. });
    fn new_block() -> u32 { tick(current_decl); if b.blocks.len - block_start >= LIMIT_BLOCKS { fail(FE_CORE_LIMIT, current_decl, "block limit reached"); } let id = b.blocks.len as u32; b.blocks.push(Block { scope: current_scope, function: current_function, .. }); while block_heads.len <= id { block_heads.push(0); block_tails.push(0); } b.functions[current_function].blocks = append_reference(b.functions[current_function].blocks, id); return id; }
    fn operation_limit(n: u32) { if b.ops.len + b.terminators.len - op_start >= LIMIT_OPS { fail(FE_CORE_LIMIT, n, "operation and terminator limit reached"); } }
    fn record_op(block_id: u32, operation: u32) { let id = pending.len as u32; pending.push(FrontPending { block_id: block_id, operation: operation, .. }); let tail = block_tails[block_id]; if tail != 0 { pending[tail].next = id; } else { block_heads[block_id] = id; } block_tails[block_id] = id; }
    fn hold(value: u32) { if value == 0 || share(type_of(value)) { return; } let index = bindings.len as u32; bindings.push(FrontBinding { value: value, type_id: type_of(value), held_original: value, .. }); held.push(FrontHeld { original: value, binding: index }); }
    fn refresh(value: u32) -> u32 { var i = held.len; while i > held_base { i--; let item = held[i]; if item.original == value && item.binding < bindings.len && bindings[item.binding].held_original == item.original && !bindings[item.binding].moved { return bindings[item.binding].value; } } return value; }
    fn release_held(value: u32) { var i = held.len; while i > held_base { i--; let item = held[i]; if item.binding < bindings.len && bindings[item.binding].held_original == item.original && !bindings[item.binding].moved && (item.original == value || bindings[item.binding].value == value) { bindings[item.binding].moved = true; return; } } }
    fn operation_borrows(tag: u32, index: u32) -> bool { return index == 0 && (tag == OP_TAG || tag == OP_VIEW_LEN || tag == OP_VIEW_INDEX || tag == OP_BUILDER_LEN || tag == OP_BUILDER_CAP || tag == OP_DEST_CAP || tag == OP_BUILDER_GET || tag == OP_INDEX_VALUE || tag == OP_OWNED_OPEN); }
    fn emit(op: u32, ty: u32, args: const u32[:], evidence: const u32[:], immediate: u32, n: u32) -> u32 {
        tick(n); if current_block == 0 { return 0; } demand_type(ty); operation_limit(n); allocate(n);
        let argument_mark = emit_arguments.len; for arg in args { emit_arguments.push(refresh(arg)); } let resolved = ref_span(b, emit_arguments[argument_mark..]); emit_arguments.resize(argument_mark); for arg, i in args { if !operation_borrows(op, i as u32) { release_held(arg); } }
        let oid = b.ops.len as u32; let value = b.values.len as u32; let o = origin(n);
        b.values.push(Value { type_id: ty, block_id: current_block, op: oid, version: value, scope: current_scope, origin: o });
        b.ops.push(Operation { tag: op, registry: op, args: resolved, results: ref_span(b, [value]), evidence: ref_span(b, evidence), scope: current_scope, origin: o, imm0: immediate, .. });
        record_op(current_block, oid); return value;
    }
    fn product_type(types: const u32[:]) -> u32 { let mark = temporaries.len; for ty in types { let id = b.fields.len as u32; b.fields.push(Field { type_id: ty, .. }); temporaries.push(id); } let result = intern_type(TypeNode { tag: TY_TUPLE, fields: ref_span(b, temporaries[mark..]), .. }); temporaries.resize(mark); return result; }
    fn option_type(payload: u32) -> u32 { let none = b.fields.len as u32; b.fields.push(Field { name: add_name(b, "None"), type_id: unit, tag: 0, .. }); let some = b.fields.len as u32; b.fields.push(Field { name: add_name(b, "Some"), type_id: payload, tag: 1, .. }); return intern_type(TypeNode { tag: TY_SUM, fields: ref_span(b, [none, some]), .. }); }
    fn two_sum(first_name: const u8[:], first_type: u32, second_name: const u8[:], second_type: u32) -> u32 {
        let a = b.fields.len as u32; b.fields.push(Field { name: add_name(b, first_name), type_id: first_type, tag: 0, .. }); let z = b.fields.len as u32; b.fields.push(Field { name: add_name(b, second_name), type_id: second_type, tag: 1, .. }); return intern_type(TypeNode { tag: TY_SUM, fields: ref_span(b, [a, z]), .. });
    }
    recursive fn valid_owned_payload(ty: u32, hole: u32) -> bool {
        tick(current_decl); let t = b.types[ty]; if !share(ty) || t.tag == TY_OWNED || t.region != 0 && t.region != hole || t.tag == TY_PARAM && !plain(ty) { return false; }
        for i in t.children.count { if !valid_owned_payload(b.refs[t.children.start + i], hole) { return false; } } for i in t.fields.count { if !valid_owned_payload(b.fields[b.refs[t.fields.start + i]].type_id, hole) { return false; } } return true;
    }
    recursive fn equivalent_type(a: u32, z: u32) -> bool {
        if a == z { return true; } tick(current_decl); let x = b.types[a]; let y = b.types[z]; if x.tag == TY_FN && y.tag == TY_FN { return callable_weakening(a, z) && callable_weakening(z, a); }
        if x.tag != y.tag || x.region != y.region || x.nat != y.nat || x.capacity != y.capacity || x.domain != y.domain || x.mode != y.mode || x.binder != y.binder || x.contract != y.contract || x.children.count != y.children.count || x.fields.count != y.fields.count || x.binders.count != y.binders.count { return false; }
        for i in x.binders.count { if b.refs[x.binders.start + i] != b.refs[y.binders.start + i] { return false; } } for i in x.children.count { if !equivalent_type(b.refs[x.children.start + i], b.refs[y.children.start + i]) { return false; } } for i in x.fields.count { let f = b.fields[b.refs[x.fields.start + i]]; let g = b.fields[b.refs[y.fields.start + i]]; if f.name != g.name || f.tag != g.tag || !equivalent_type(f.type_id, g.type_id) { return false; } } return true;
    }
    recursive fn owned_schema(n: u32) -> u32 {
        let previous = schema_hole; schema_hole = b.binders.len as u32; let hole = schema_hole; b.binders.push(Binder { kind: KIND_REGION, origin: origin(n), .. });
        let payload = resolve_type(n); schema_hole = previous;
        if !valid_owned_payload(payload, hole) { fail(FE_OWNED_PAYLOAD, n, "Owned payload must be Share and contain only the owned Region or static loans"); }
        var candidate = proof_index.counts[proof_limits.id].owned_head; while candidate != 0 { let id = owned_schemas[candidate].type_id; candidate = owned_schemas[candidate].next; tick(n); let old = b.types[id]; let sub = b.substitutions.len as u32; b.substitutions.push(Substitution { binder: hole, kind: KIND_REGION, value: b.refs[old.binders.start] }); let renamed = substitute_type(payload, ref_span(b, [sub]), 0); if equivalent_type(renamed, b.refs[old.children.start]) { return id as u32; } }
        return intern_type(TypeNode { tag: TY_OWNED, children: ref_span(b, [payload]), binders: ref_span(b, [hole]), .. });
    }
    fn storage_error(reserve: bool) -> u32 {
        let mark = temporaries.len;
        for i in (if reserve { 3 } else { 2 }) { let name = if i == 0 { "SizeOverflow" } else if reserve && i == 1 { "NoOwnerSlots" } else if reserve { "NoContiguousSpace" } else { "NoSpace" }; let fid = b.fields.len as u32; b.fields.push(Field { name: add_name(b, name), type_id: unit, tag: i as u32, .. }); temporaries.push(fid); }
        let result = intern_type(TypeNode { tag: TY_SUM, fields: ref_span(b, temporaries[mark..]), .. }); temporaries.resize(mark); return result;
    }
    fn result_type(success: u32, error: u32) -> u32 { let ok = b.fields.len as u32; b.fields.push(Field { name: add_name(b, "Ok"), type_id: success, tag: 0, .. }); let err = b.fields.len as u32; b.fields.push(Field { name: add_name(b, "Err"), type_id: error, tag: 1, .. }); return intern_type(TypeNode { tag: TY_RESULT, fields: ref_span(b, [ok, err]), .. }); }
    fn emit_destructure(value: u32, n: u32) -> Span {
        tick(n); operation_limit(n); allocate(n);
        let ty = b.types[type_of(value)]; let mark = temporaries.len; let oid = b.ops.len as u32;
        for i in ty.fields.count { let field = b.fields[b.refs[ty.fields.start + i]]; let id = b.values.len as u32; b.values.push(Value { type_id: field.type_id, block_id: current_block, op: oid, version: id, scope: current_scope, origin: origin(n) }); temporaries.push(id); }
        let results = ref_span(b, temporaries[mark..]); temporaries.resize(mark);
        b.ops.push(Operation { tag: OP_DESTRUCTURE, registry: OP_DESTRUCTURE, args: ref_span(b, [value]), results: results, scope: current_scope, origin: origin(n), .. }); record_op(current_block, oid); return results;
    }
    fn terminate(tag: u32, subject: u32, edges: const u32[:], n: u32) { tick(n); if current_block == 0 { return; } operation_limit(n); allocate(n); let id = b.terminators.len as u32; b.terminators.push(Terminator { tag: tag, subject: subject, edges: ref_span(b, edges), origin: origin(n), .. }); b.blocks[current_block].term = id; current_block = 0; }
    fn edge(from: u32, to: u32, kind: u32, args: const u32[:]) -> u32 { let id = b.edges.len as u32; b.edges.push(Edge { from: from, to: to, args: ref_span(b, args), kind: kind, .. }); return id; }
    fn type_of(value: u32) -> u32 { if value == 0 { return 0; } return b.values[value].type_id; }
    recursive fn refinement_evidence(from: u32, to: u32, n: u32) -> bool {
        tick(n); if from == to { return true; } let a = b.types[from]; let c = b.types[to];
        if a.tag != c.tag || a.region != c.region || a.domain != c.domain || a.capacity != c.capacity || a.mode != c.mode || a.binder != c.binder || a.contract != c.contract || a.children.count != c.children.count || a.fields.count != c.fields.count || a.binders.count != c.binders.count { return false; }
        for i in a.binders.count { if b.refs[a.binders.start + i] != b.refs[c.binders.start + i] { return false; } }
        if a.nat != c.nat { if a.nat == 0 || c.nat == 0 { return false; } let e = proof_query(b, work, proof_limits, proof_index, current_scope, active[active_base..], Fact { tag: FACT_EQ, left: a.nat, right: c.nat, .. }); if e == 0 { return false; } temporaries.push(e); }
        for i in a.children.count { if !refinement_evidence(b.refs[a.children.start + i], b.refs[c.children.start + i], n) { return false; } }
        for i in a.fields.count { let af = b.fields[b.refs[a.fields.start + i]]; let cf = b.fields[b.refs[c.fields.start + i]]; if af.name != cf.name || af.tag != cf.tag || !refinement_evidence(af.type_id, cf.type_id, n) { return false; } } return true;
    }
    recursive fn same_formal_term(left: u32, right: u32, left_contract: u32, right_contract: u32) -> bool {
        if left == right { return true; } if left == 0 || right == 0 { return false; } tick(current_decl); let a = b.terms[left]; let z = b.terms[right];
        if a.tag != z.tag || a.type_id != z.type_id || a.literal != z.literal || a.args.count != z.args.count { return false; }
        if a.tag == EXPR_ARG || a.tag == EXPR_RESULT { return a.binder == left_contract && z.binder == right_contract; }
        if a.binder != z.binder || a.value != z.value || a.version != z.version || a.scope != z.scope { return false; }
        for i in a.args.count { if !same_formal_term(b.refs[a.args.start + i], b.refs[z.args.start + i], left_contract, right_contract) { return false; } } return true;
    }
    fn same_formal_clause(left: Span, right: Span, left_contract: u32, right_contract: u32) -> bool {
        if left.count != right.count { return false; } for i in left.count { let a = b.facts[b.refs[left.start + i]]; let z = b.facts[b.refs[right.start + i]]; if a.tag != z.tag || a.domain != z.domain || !same_formal_term(a.left, z.left, left_contract, right_contract) || !same_formal_term(a.right, z.right, left_contract, right_contract) { return false; } } return true;
    }
    fn callable_weakening(from: u32, to: u32) -> bool {
        let a = b.types[from]; let z = b.types[to]; if a.tag != TY_FN || z.tag != TY_FN || a.mode == MODE_ONCE && z.mode != MODE_ONCE { return false; }
        if a.region != z.region && a.region != 0 { if z.region == 0 || !scope_inside(b.binders[z.region].scope, b.binders[a.region].scope) { return false; } }
        let x = b.contracts[a.contract]; let y = b.contracts[z.contract];
        if x.arg != y.arg || x.result != y.result || x.binders.count != y.binders.count || x.depth != 0 && (x.depth > y.depth || x.frame > y.frame) { return false; }
        if !same_formal_clause(x.requires, y.requires, a.contract, z.contract) || !same_formal_clause(x.ensures, y.ensures, a.contract, z.contract) || !same_formal_clause(x.on_true, y.on_true, a.contract, z.contract) || !same_formal_clause(x.on_false, y.on_false, a.contract, z.contract) { return false; }
        for i in x.effects.count { let e = b.effects[b.refs[x.effects.start + i]]; var found = false; for j in y.effects.count { let f = b.effects[b.refs[y.effects.start + j]]; if e.kind == f.kind && e.region == f.region { found = true; } } if !found { return false; } } return true;
    }
    fn exact(value: u32, expected: u32, n: u32) -> u32 {
        if value == 0 || expected == 0 || type_of(value) == expected { return value; } if callable_weakening(type_of(value), expected) { return emit(OP_FN_WEAKEN, expected, [value], [], 0, n); } let mark = temporaries.len;
        if !refinement_evidence(type_of(value), expected, n) { fail(FE_TYPE, n, "value does not match its complete expected type"); }
        let result = emit(OP_REFINE, expected, [value], temporaries[mark..], 0, n); temporaries.resize(mark); return result;
    }
    recursive fn share(ty: u32) -> bool {
        tick(current_decl); let t = b.types[ty]; if t.tag == TY_UNIT || t.tag == TY_U32 || t.tag == TY_F32 || t.tag == TY_BOOL || t.tag == TY_INDEX || t.tag == TY_VIEW { return true; }
        if t.tag == TY_FN { return t.mode == MODE_MANY; }
        if t.tag == TY_PARAM { return b.binders[t.binder].constraints != 0; }
        if t.tag == TY_EXISTS { return share(b.refs[t.children.start]); }
        if t.tag == TY_TUPLE || t.tag == TY_RECORD || t.tag == TY_SUM { for i in t.fields.count { if !share(b.fields[b.refs[t.fields.start + i]].type_id) { return false; } } return true; }
        return false;
    }
    recursive fn plain(ty: u32) -> bool {
        tick(current_decl); let t = b.types[ty];
        if t.tag == TY_UNIT || t.tag == TY_BOOL || t.tag == TY_U32 || t.tag == TY_F32 || t.tag == TY_INDEX { return true; }
        if t.tag == TY_PARAM { return b.binders[t.binder].constraints & CONSTRAINT_PLAIN != 0; }
        if t.tag == TY_TUPLE || t.tag == TY_RECORD || t.tag == TY_SUM { for i in t.fields.count { if !plain(b.fields[b.refs[t.fields.start + i]].type_id) { return false; } } return true; } return false;
    }
    fn builtin_name(name: const u8[:]) -> bool { return name == "Unit" || name == "Bool" || name == "U32" || name == "F32" || name == "View" || name == "Index" || name == "Dest" || name == "EnvDest" || name == "Builder" || name == "RegionOwner" || name == "Space" || name == "Owned" || name == "Fn" || name == "Result" || name == "Option" || name == "ReserveError" || name == "AllocError" || name == "Many" || name == "Once" || name == "Append" || name == "Resize" || name == "region" || name == "owned" || name == "space" || name == "dest" || name == "env" || name == "builder" || name == "view" || name == "index" || name == "array"; }
    fn local_region(n: u32) -> u32 {
        if current_function == 0 || current_scope == 0 { fail(FE_LIFETIME, n, "local Region is body-only"); }
        let existing = key_index_get(local_regions, current_scope); if existing != 0 { return existing; }
        let id = b.binders.len as u32; b.binders.push(Binder { introduction_kind: INTRO_FUNCTION, kind: KIND_REGION, scope: current_scope, introduction: current_function, name: add_name(b, "local"), origin: origin(n), .. }); key_index_insert(local_regions, current_scope, id); return id;
    }
    fn bind(n: u32, value: u32) { let name = add_name(b, ast_text(source, nodes[n])); if builtin_name(name_bytes(core_view(b), name)) { fail(FE_UNBOUND, n, "builtin names cannot be rebound"); } if name_bytes(core_view(b), name) == "_" { if b.types[type_of(value)].tag == TY_FN && b.types[type_of(value)].mode == MODE_ONCE { emit(OP_DISCARD_ONCE, unit, [value], [], 0, n); return; } if !share(type_of(value)) { fail(if b.types[type_of(value)].tag == TY_RESULT { FE_RESULT } else { FE_USAGE }, n, "affine value cannot be discarded"); } return; } for bi in lexical_base..bindings.len { let old = bindings[bi]; tick(n); if old.name == name { fail(FE_UNBOUND, n, "duplicate immutable binding"); } } bindings.push(FrontBinding { name: name, value: value, type_id: type_of(value), .. }); }
    recursive fn bind_pattern(n: u32, value: u32) {
        tick(n); let node = nodes[n];
        if node.tag == AstTag.Name { bind(n, value); return; }
        if node.tag == AstTag.AnnotatedPattern { let ty = resolve_type(child(n, 1)); let coerced = exact(value, ty, n); bind_pattern(child(n, 0), coerced); return; }
        if node.tag != AstTag.Pattern { fail(FE_TYPE, n, "invalid parameter pattern"); }
        let ty = b.types[type_of(value)];
        if node.children.count == 0 && ty.tag == TY_UNIT { return; }
        if (ty.tag != TY_TUPLE && ty.tag != TY_RECORD) || ty.fields.count != node.children.count { fail(FE_TYPE, n, "pattern must destructure every product field"); }
        let affine = !share(type_of(value)); var destructured = Span { .. }; if affine { destructured = emit_destructure(value, n); }
        for i in node.children.count { let field = b.fields[b.refs[ty.fields.start + i]]; var p = child(n, i); if nodes[p].tag == AstTag.Field { if field.name != add_name(b, ast_text(source, nodes[p])) { fail(FE_TYPE, p, "record pattern field order mismatch"); } p = child(p, 0); } let v = if affine { b.refs[destructured.start + i] } else { emit(OP_PROJECT, field.type_id, [value], [], i as u32, p) }; bind_pattern(p, v); }
    }
    fn type_binder(n: u32, wanted: u32) -> u32 {
        let name = add_name(b, ast_text(source, nodes[n])); var i = typebindings.len;
        while i > type_base { i--; tick(n); if typebindings[i].name == name { let id = typebindings[i].binder; if b.binders[id].kind != wanted { fail(FE_KIND, n, "generic argument has the wrong kind"); } return id; } }
        fail(FE_UNBOUND, n, "generic binder is not in scope"); return 0;
    }
    fn region_argument(n: u32) -> u32 { if ast_text(source, nodes[n]) == "local" { return local_region(n); } if ast_text(source, nodes[n]) == "_" { if schema_hole == 0 { fail(FE_KIND, n, "Region hole is allowed only in Owned payload schema"); } return schema_hole; } if ast_text(source, nodes[n]) == "static" { return 0; } return type_binder(n, KIND_REGION); }
    fn nat_argument(n: u32) -> u32 {
        var term = Term { tag: EXPR_LITERAL, type_id: unsigned, .. };
        if nodes[n].tag == AstTag.Integer { term.literal = nodes[n].bits as u32; } else { term.tag = EXPR_BINDER; term.binder = type_binder(n, KIND_NAT); term.scope = b.binders[term.binder].scope; }
        let id = proof_term(b, work, proof_limits, proof_index, term); if id == 0 { fail(FE_PROOF_LIMIT, n, "Nat witness term limit"); } return id;
    }
    fn make_binders(n: u32, existential: bool) -> Span {
        let mark = temporaries.len;
        for i in nodes[n].children.count {
            let item = child(n, i); let name = add_name(b, ast_text(source, nodes[item])); let kind_name = ast_text(source, nodes[child(item, 0)]);
            let kind = if kind_name == "Type" { KIND_TYPE } else if kind_name == "Region" { KIND_REGION } else if kind_name == "Nat" { KIND_NAT } else { KIND_DOMAIN };
            if existential && kind != KIND_NAT && kind != KIND_DOMAIN { fail(FE_UNSUPPORTED, item, "existentials bind only Nat and Domain"); }
            for old, oi in typebindings { if oi >= type_base && old.name == name { fail(FE_UNBOUND, item, "duplicate generic binder"); } }
            let id = b.binders.len as u32; b.binders.push(Binder { kind: kind, scope: current_scope, introduction: 0, name: name, origin: origin(item), .. });
            typebindings.push(FrontTypeBinding { name: name, binder: id }); temporaries.push(id);
        }
        let result = ref_span(b, temporaries[mark..]); temporaries.resize(mark); return result;
    }
    recursive fn constrain_type(ty: u32, is_plain: bool, n: u32) {
        tick(n); let t = b.types[ty]; if t.tag == TY_PARAM { b.binders[t.binder].constraints |= if is_plain { CONSTRAINT_PLAIN | CONSTRAINT_SHARE } else { CONSTRAINT_SHARE }; return; }
        if t.tag == TY_TUPLE || t.tag == TY_RECORD || t.tag == TY_SUM { for i in t.fields.count { constrain_type(b.fields[b.refs[t.fields.start + i]].type_id, is_plain, n); } return; }
        if t.tag == TY_EXISTS && !is_plain { constrain_type(b.refs[t.children.start], false, n); return; }
        if (is_plain && plain(ty)) || (!is_plain && share(ty)) { return; } fail(FE_USAGE, n, "class constraint contradicts the type constructor");
    }
    recursive fn apply_constraints(n: u32) {
        if n == 0 { return; } for i in nodes[n].children.count { let c = child(n, i); constrain_type(resolve_type(child(c, 0)), ast_text(source, nodes[c]) == "Plain", c); }
    }
    recursive fn complete_callable_slots(ty: u32, n: u32) {
        if ty == 0 { return; } tick(n); let t = b.types[ty]; if t.tag == TY_FORALL { fail(FE_UNSUPPORTED, n, "higher-rank callable parameters and results are unsupported"); } if t.tag == TY_FN { let ct = b.contracts[t.contract]; var effects = false; for id in explicit_effects { if id == t.contract { effects = true; } } if !effects { fail(FE_INTERFACE, n, "function-typed parameter/result requires explicit effects"); } if ct.depth == 0 { fail(FE_RESOURCE, n, "function-typed parameter/result requires finite resources"); } }
        for i in t.children.count { complete_callable_slots(b.refs[t.children.start + i], n); } for i in t.fields.count { complete_callable_slots(b.fields[b.refs[t.fields.start + i]].type_id, n); }
    }
    fn unwrap_callable(ty: u32) -> u32 { var result = ty; for i in 64 { let t = b.types[result]; if t.tag != TY_FORALL && t.tag != TY_ALIAS { return result; } if t.children.count != 1 { return 0; } result = b.refs[t.children.start]; } return 0; }
    fn substituted_identity(value: u32, kind: u32, substitutions: Span) -> u32 {
        for i in substitutions.count { tick(current_decl); let sub = b.substitutions[b.refs[substitutions.start + i]]; if sub.kind == kind && sub.binder == value { return sub.value; } } return value;
    }
    fn substituted_nat(term: u32, substitutions: Span) -> u32 { if term != 0 && b.terms[term].tag == EXPR_BINDER { let binder = b.terms[term].binder; for i in substitutions.count { let sub = b.substitutions[b.refs[substitutions.start + i]]; if sub.kind == KIND_NAT && sub.binder == binder { return sub.value; } } } return term; }
    recursive fn substitute_term(term: u32, substitutions: Span, old_contract: u32, new_contract: u32) -> u32 {
        if term == 0 { return 0; } tick(current_decl); let old = b.terms[term]; if old.tag == EXPR_BINDER { let replaced = substituted_nat(term, substitutions); if replaced != term { return replaced; } }
        var next = old; if (old.tag == EXPR_ARG || old.tag == EXPR_RESULT) && old.binder == old_contract { next.binder = new_contract; } next.type_id = substitute_type(old.type_id, substitutions, 0);
        let mark = temporaries.len; for i in old.args.count { temporaries.push(substitute_term(b.refs[old.args.start + i], substitutions, old_contract, new_contract)); } next.args = ref_span(b, temporaries[mark..]); temporaries.resize(mark);
        let id = proof_term(b, work, proof_limits, proof_index, next); if id == 0 { fail(FE_PROOF_LIMIT, current_decl, "contract substitution term budget"); } return id;
    }
    fn substitute_clause(facts: Span, substitutions: Span, old_contract: u32, new_contract: u32) -> Span {
        let mark = temporaries.len; for i in facts.count { var f = b.facts[b.refs[facts.start + i]]; f.left = substitute_term(f.left, substitutions, old_contract, new_contract); f.right = substitute_term(f.right, substitutions, old_contract, new_contract); f.third = substitute_term(f.third, substitutions, old_contract, new_contract); f.domain = substituted_identity(f.domain, KIND_DOMAIN, substitutions); let id = proof_fact(b, work, proof_limits, proof_index, f); if id == 0 { fail(FE_PROOF_LIMIT, current_decl, "contract substitution fact budget"); } temporaries.push(id); } let result = ref_span(b, temporaries[mark..]); temporaries.resize(mark); return result;
    }
    recursive fn substitute_type(ty: u32, substitutions: Span, depth: u32) -> u32 {
        tick(current_decl); if depth >= 64 { fail(FE_CORE_LIMIT, current_decl, "type substitution nesting exceeds 64"); } let old = b.types[ty];
        if old.tag == TY_PARAM { for i in substitutions.count { let sub = b.substitutions[b.refs[substitutions.start + i]]; if sub.kind == KIND_TYPE && sub.binder == old.binder { return sub.value; } } return ty; }
        var result = old; result.region = substituted_identity(old.region, KIND_REGION, substitutions); result.domain = substituted_identity(old.domain, KIND_DOMAIN, substitutions); result.nat = substituted_nat(old.nat, substitutions); result.capacity = substituted_nat(old.capacity, substitutions);
        let mark = temporaries.len;
        for i in old.children.count { temporaries.push(substitute_type(b.refs[old.children.start + i], substitutions, depth + 1)); }
        result.children = ref_span(b, temporaries[mark..]); temporaries.resize(mark);
        for i in old.fields.count { let field = b.fields[b.refs[old.fields.start + i]]; let ct = substitute_type(field.type_id, substitutions, depth + 1); let id = b.fields.len as u32; b.fields.push(Field { name: field.name, type_id: ct, offset: field.offset, tag: field.tag }); temporaries.push(id); }
        result.fields = ref_span(b, temporaries[mark..]); temporaries.resize(mark);
        if old.tag == TY_FN { let c = b.contracts[old.contract]; var contract = c; contract.arg = substitute_type(c.arg, substitutions, depth + 1); contract.result = substitute_type(c.result, substitutions, depth + 1); contract.binders = Span { .. }; result.contract = b.contracts.len as u32; b.contracts.push(contract); for id in explicit_effects { if id == old.contract { explicit_effects.push(result.contract); break; } }
            b.contracts[result.contract].requires = substitute_clause(c.requires, substitutions, old.contract, result.contract); b.contracts[result.contract].ensures = substitute_clause(c.ensures, substitutions, old.contract, result.contract); b.contracts[result.contract].on_true = substitute_clause(c.on_true, substitutions, old.contract, result.contract); b.contracts[result.contract].on_false = substitute_clause(c.on_false, substitutions, old.contract, result.contract);
            let em = temporaries.len; for i in c.effects.count { let effect = b.effects[b.refs[c.effects.start + i]]; let eid = b.effects.len as u32; b.effects.push(Effect { kind: effect.kind, region: substituted_identity(effect.region, KIND_REGION, substitutions) }); temporaries.push(eid); } b.contracts[result.contract].effects = ref_span(b, temporaries[em..]); temporaries.resize(em);
        }
        return intern_type(result);
    }
    // Count one completed declaration interface application, not its type nodes.
    fn instantiate_interface_type(ty: u32, substitutions: Span) -> u32 { let result = substitute_type(ty, substitutions, 0); work.interface_instantiations++; return result; }
    recursive fn make_substitutions(binders: Span, args: u32, offset: u32) -> Span {
        if nodes[args].children.count - offset != binders.count { fail(FE_KIND, args, "explicit generic argument count mismatch"); } let mark = temporaries.len;
        for i in binders.count { let binder_id = b.refs[binders.start + i]; let binder = b.binders[binder_id]; let arg = child(args, i + offset); var value: u32 = 0;
            if binder.kind == KIND_TYPE { value = resolve_type(arg); if binder.constraints & CONSTRAINT_PLAIN != 0 && !plain(value) || binder.constraints & CONSTRAINT_SHARE != 0 && !share(value) { fail(FE_USAGE, arg, "type does not satisfy declared Share/Plain constraint"); } }
            else if binder.kind == KIND_REGION { value = region_argument(arg); }
            else if binder.kind == KIND_NAT { value = nat_argument(arg); }
            else { value = type_binder(arg, KIND_DOMAIN); }
            let id = b.substitutions.len as u32; b.substitutions.push(Substitution { binder: binder_id, kind: binder.kind, value: value }); temporaries.push(id);
        }
        let result = ref_span(b, temporaries[mark..]); temporaries.resize(mark); return result;
    }
    fn name_query(module: u32, name: u32, kind: u32, selected: u32) {
        if current_producer == 0 { return; } let path = name_bytes(core_view(b), b.modules[module].path); let label = name_bytes(core_view(b), name); let start = b.bytes.len as u32; b.bytes.append(path); b.bytes.push(0); b.bytes.append(label);
        let id = b.dependencies.len as u32; b.dependencies.push(Dependency { query_kind: kind, kind: if selected == 0 { DEP_NEGATIVE } else if b.definitions[selected].kind == DEF_STATIC { DEP_STATIC } else { DEP_INTERFACE }, producer: selected, identity: Span { start: start, count: b.bytes.len as u32 - start }, present: selected != 0, .. }); queries.push(FrontQuery { owner: current_producer, dependency: id });
    }
    fn producer_queries(producer: u32) -> Span { let mark = temporaries.len; for query in queries { if query.owner == producer { temporaries.push(query.dependency); } } let result = ref_span(b, temporaries[mark..]); temporaries.resize(mark); return result; }
    fn imported_definition(n: u32, kind: u32) -> u32 {
        if nodes[n].tag != AstTag.Select || nodes[child(n, 0)].tag != AstTag.Name && nodes[child(n, 0)].tag != AstTag.TypeName { fail(FE_UNBOUND, n, "expected imported module selector"); }
        let alias = add_name(b, ast_text(source, nodes[child(n, 0)])); let name = add_name(b, ast_text(source, nodes[child(n, 1)]));
        for item in imports { tick(n); if item.name == alias { let definitions = b.modules[item.module].declarations; for i in definitions.count { tick(n); let did = b.refs[definitions.start + i]; let d = b.definitions[did]; if d.name == name && d.visibility == VIS_PUBLIC && (d.kind == kind || kind == DEF_FUNCTION && d.kind == DEF_STATIC) { name_query(item.module, name, if kind == DEF_TYPE { 2 } else { 1 }, did); return did; } } name_query(item.module, name, if kind == DEF_TYPE { 2 } else { 1 }, 0); fail(FE_UNBOUND, n, "selected declaration is absent or private"); } }
        fail(FE_UNBOUND, n, "unknown import alias"); return 0;
    }
    recursive fn formal_term(n: u32, contract: u32) -> u32 {
        tick(n); let node = nodes[n]; let text = ast_text(source, node); var t = Term { type_id: unsigned, .. };
        if node.tag == AstTag.Integer { t.tag = EXPR_LITERAL; t.literal = node.bits as u32; }
        else if node.tag == AstTag.Name {
            if text == "arg" || text == "result" { t.tag = if text == "arg" { EXPR_ARG } else { EXPR_RESULT }; t.binder = contract; t.type_id = if text == "arg" { b.contracts[contract].arg } else { b.contracts[contract].result }; }
            else { t.tag = EXPR_BINDER; t.binder = type_binder(n, KIND_NAT); t.scope = b.binders[t.binder].scope; }
        }
        else if node.tag == AstTag.Complement { let x = formal_term(child(n, 0), contract); if b.terms[x].type_id != unsigned { fail(FE_FACT, n, "complement requires U32"); } t.tag = EXPR_MAX_MINUS; t.args = ref_span(b, [x]); }
        else if node.tag == AstTag.Observation { let base = formal_term(child(n, 0), contract); t.tag = if text == "Len" { EXPR_LEN } else if text == "Cap" { EXPR_CAP } else { EXPR_INIT }; t.args = ref_span(b, [base]); }
        else if node.tag == AstTag.Select {
            let base = formal_term(child(n, 0), contract); let ty = b.types[b.terms[base].type_id]; let selector = ast_text(source, nodes[child(n, 1)]);
            if selector == "length" && (ty.tag == TY_VIEW || ty.tag == TY_BUILDER) { t.tag = if ty.tag == TY_VIEW { EXPR_LEN } else { EXPR_INIT }; t.args = ref_span(b, [base]); }
            else if selector == "capacity" && (ty.tag == TY_BUILDER || ty.tag == TY_DEST) { t.tag = EXPR_CAP; t.args = ref_span(b, [base]); }
            else { var ordinal: u32 = 0; var found = false; if ty.tag == TY_TUPLE { let v, ok = parse_int(selector); if ok && v >= 0 && v < ty.fields.count { ordinal = v as u32; found = true; } } else if ty.tag == TY_RECORD { let name = add_name(b, selector); for i in ty.fields.count { if b.fields[b.refs[ty.fields.start + i]].name == name { ordinal = i as u32; found = true; } } } if !found { fail(FE_FACT, n, "unknown formal component"); } t.tag = EXPR_FIELD; t.args = ref_span(b, [base]); t.literal = ordinal; t.type_id = b.fields[b.refs[ty.fields.start + ordinal]].type_id; }
        }
        else { fail(FE_FACT, n, "term is outside the finite proof algebra"); }
        let id = proof_term(b, work, proof_limits, proof_index, t); if id == 0 { fail(FE_PROOF_LIMIT, n, "contract term budget exhausted"); } return id;
    }
    fn formal_facts(n: u32, contract: u32) -> Span {
        let mark = temporaries.len;
        for i in nodes[n].children.count { let item = child(n, i); let text = ast_text(source, nodes[item]); var f = Fact { .. };
            if text == "Index" { f.tag = FACT_INDEX; f.domain = type_binder(child(item, 0), KIND_DOMAIN); f.left = formal_term(child(item, 1), contract); f.right = formal_term(child(item, 2), contract); }
            else { f.tag = if text == "Eq" { FACT_EQ } else if text == "Lt" { FACT_LT } else if text == "Le" { FACT_LE } else if text == "AddFits" { FACT_ADD_FITS } else if text == "SubFits" { FACT_SUB_FITS } else { FACT_MUL_FITS }; f.left = formal_term(child(item, 0), contract); f.right = formal_term(child(item, 1), contract); }
            if b.terms[f.left].type_id != unsigned || b.terms[f.right].type_id != unsigned { fail(FE_FACT, item, "fact operands must be U32"); }
            let id = proof_fact(b, work, proof_limits, proof_index, f); if id == 0 { fail(FE_PROOF_LIMIT, item, "contract fact budget exhausted"); } temporaries.push(id);
        }
        let result = ref_span(b, temporaries[mark..]); temporaries.resize(mark); return result;
    }
    recursive fn resolve_type(n: u32) -> u32 { let result = resolve_type_inner(n); demand_type(result); return result; }
    recursive fn resolve_type_inner(n: u32) -> u32 {
        tick(n); let node = nodes[n]; let text = ast_text(source, node);
        if node.tag == AstTag.Select { let definition = b.definitions[imported_definition(n, DEF_TYPE)]; if definition.binders.count != 0 { fail(FE_KIND, n, "generic alias requires explicit arguments"); } return definition.type_id; }
        if node.tag == AstTag.TypeName {
            if text == "ReserveError" { return storage_error(true); } if text == "AllocError" { return storage_error(false); } if text == "Unit" { return unit; } if text == "Bool" { return boolean; } if text == "U32" { return unsigned; } if text == "F32" { return floating; }
            let name = add_name(b, text);
            var bi = typebindings.len; while bi > type_base { bi--; if typebindings[bi].name == name { let binder = typebindings[bi].binder; if b.binders[binder].kind != KIND_TYPE { fail(FE_KIND, n, "non-Type binder used as a value type"); } return intern_type(TypeNode { tag: TY_PARAM, binder: binder, .. }); } }
            var ai = local_aliases.len; while ai > alias_base { ai--; let alias = local_aliases[ai]; if alias.name == name { if !alias.complete { fail(FE_RECURSION, n, "recursive local type alias"); } if alias.binders.count != 0 { fail(FE_KIND, n, "generic alias requires explicit arguments"); } return alias.type_id; } }
            for def, di in b.definitions { if def.module == module_id && def.kind == DEF_TYPE { tick(n); } if def.name == name && def.module == module_id && def.kind == DEF_TYPE && def.type_id != 0 { if def.binders.count != 0 { fail(FE_KIND, n, "generic alias requires explicit arguments"); } name_query(module_id, name, 2, di as u32); return def.type_id; } }
            for d, i in decls { tick(n); if b.definitions[d.definition].name == name && b.definitions[d.definition].kind == DEF_TYPE { name_query(module_id, name, 2, d.definition); complete_declaration(i as u32); if b.definitions[d.definition].binders.count != 0 { fail(FE_KIND, n, "generic alias requires explicit arguments"); } return b.definitions[d.definition].type_id; } }
            name_query(module_id, name, 2, 0); fail(FE_UNBOUND, n, "unknown type name");
        }
        if node.tag == AstTag.Forall || node.tag == AstTag.Exists {
            let bs = make_binders(child(n, 0), node.tag == AstTag.Exists); apply_constraints(child(n, 1)); let payload = resolve_type(child(n, 2));
            if node.tag == AstTag.Forall { let inner = unwrap_callable(payload); if inner == 0 || b.types[inner].tag != TY_FN { fail(FE_UNSUPPORTED, n, "forall only declares a reusable callable boundary"); } b.contracts[b.types[inner].contract].binders = bs; }
            return intern_type(TypeNode { tag: if node.tag == AstTag.Forall { TY_FORALL } else { TY_EXISTS }, children: ref_span(b, [payload]), binders: bs, .. });
        }
        if node.tag == AstTag.TypeTuple || node.tag == AstTag.TypeRecord {
            if node.children.count == 0 { return unit; } let mark = temporaries.len;
            for i in node.children.count { let item = child(n, i); var ty: u32 = 0; var nm: u32 = 0; if node.tag == AstTag.TypeRecord { nm = add_name(b, ast_text(source, nodes[item])); ty = resolve_type(child(item, 0)); } else { ty = resolve_type(item); } let fid = b.fields.len as u32; b.fields.push(Field { name: nm, type_id: ty, .. }); temporaries.push(fid); }
            let fs = ref_span(b, temporaries[mark..]); temporaries.resize(mark); return intern_type(TypeNode { tag: if node.tag == AstTag.TypeTuple { TY_TUPLE } else { TY_RECORD }, fields: fs, .. });
        }
        if node.tag == AstTag.TypeVariant {
            let payload = child(n, 0); let ty = if payload == 0 { unit } else { resolve_type(payload) };
            let field = b.fields.len as u32; b.fields.push(Field { name: add_name(b, text), type_id: ty, tag: 0, .. });
            return intern_type(TypeNode { tag: TY_SUM, fields: ref_span(b, [field]), .. });
        }
        if node.tag == AstTag.TypeSum {
            let left = resolve_type(child(n, 0)); let right = resolve_type(child(n, 1)); let a = b.types[left]; let c = b.types[right];
            if a.tag != TY_SUM || c.tag != TY_SUM || a.fields.count + c.fields.count > 4 { fail(FE_LAYOUT, n, "closed sum supports at most four constructors"); }
            var ids: u32[4] = [0; 4]; var count: u32 = 0;
            for side in [left, right] { let t = b.types[side]; for i in t.fields.count { let f = b.fields[b.refs[t.fields.start + i]]; for j in count { if b.fields[ids[j]].name == f.name { fail(FE_TYPE, n, "duplicate sum constructor"); } } let fid = b.fields.len as u32; b.fields.push(Field { name: f.name, type_id: f.type_id, tag: count, .. }); ids[count] = fid; count++; } }
            return intern_type(TypeNode { tag: TY_SUM, fields: ref_span(b, ids[..count]), .. });
        }
        if node.tag == AstTag.TypeArrow {
            let arg = resolve_type(child(n, 0)); let result = resolve_type(child(n, 1)); let contract = b.contracts.len as u32; b.contracts.push(Contract { arg: arg, result: result, depth: 0, frame: 0, origin: origin(n), .. });
            return intern_type(TypeNode { tag: TY_FN, children: ref_span(b, [arg, result]), mode: MODE_MANY, contract: contract, .. });
        }
        if node.tag == AstTag.Contract {
            let ty = resolve_type(child(n, 0)); if b.types[ty].tag != TY_FN { fail(FE_TYPE, n, "callable suffix requires callable type"); } let contract = b.types[ty].contract;
            for i in 1..node.children.count { let c = child(n, i); let clause = ast_text(source, nodes[c]);
                if nodes[c].tag == AstTag.Resource { b.contracts[contract].depth = nodes[child(c, 0)].bits as u32; b.contracts[contract].frame = nodes[child(c, 1)].bits as u32; if b.contracts[contract].depth == 0 || b.contracts[contract].depth > 128 { fail(FE_RESOURCE, c, "call depth must be in 1..128"); } }
                else if clause == "!" { explicit_effects.push(contract); let mark = temporaries.len; for j in nodes[c].children.count { let en = child(c, j); let name = ast_text(source, nodes[en]); let region_node = child(en, 0); let region = if region_node == 0 { 0 } else { region_argument(region_node) }; let kind = if name == "read" { EFFECT_READ } else if name == "write" { EFFECT_WRITE } else if name == "place" { EFFECT_PLACE } else if name == "reset" { EFFECT_RESET } else if name == "reserve" { EFFECT_RESERVE } else if name == "release" { EFFECT_RELEASE } else { EFFECT_HOST }; let eid = b.effects.len as u32; b.effects.push(Effect { kind: kind, region: region }); temporaries.push(eid); } b.contracts[contract].effects = ref_span(b, temporaries[mark..]); temporaries.resize(mark); }
                else { let fs = formal_facts(c, contract); if clause == "requires" { b.contracts[contract].requires = fs; } else if clause == "ensures" { b.contracts[contract].ensures = fs; } else if clause == "on_true" { if b.contracts[contract].result != boolean { fail(FE_TYPE, c, "on_true requires Bool result"); } b.contracts[contract].on_true = fs; } else if clause == "on_false" { if b.contracts[contract].result != boolean { fail(FE_TYPE, c, "on_false requires Bool result"); } b.contracts[contract].on_false = fs; } }
            } return ty;
        }
        if node.tag == AstTag.TypeApply {
            let base = ast_text(source, nodes[child(n, 0)]);
            if base == "View" || base == "Dest" || base == "Builder" || base == "Index" || base == "RegionOwner" || base == "Space" || base == "EnvDest" {
                let count = node.children.count; var t = TypeNode { .. };
                if base == "Index" { if count != 3 { fail(FE_KIND, n, "Index requires Domain,Nat"); } t.tag = TY_INDEX; t.domain = type_binder(child(n, 1), KIND_DOMAIN); t.nat = nat_argument(child(n, 2)); }
                else {
                    if count < 2 { fail(FE_KIND, n, "storage type requires Region"); } t.region = region_argument(child(n, 1));
                    if base == "RegionOwner" || base == "Space" { if count != 2 { fail(FE_KIND, n, "owner/frontier requires one Region"); } t.tag = if base == "RegionOwner" { TY_REGION_OWNER } else { TY_SPACE }; }
                    else if base == "EnvDest" { if count != 3 { fail(FE_KIND, n, "EnvDest requires Region,Nat"); } t.tag = TY_ENV_DEST; t.capacity = nat_argument(child(n, 2)); }
                    else { let element = resolve_type(child(n, 2)); t.children = ref_span(b, [element]);
                        if base == "Dest" { if count != 4 { fail(FE_KIND, n, "Dest requires Region,Type,Nat"); } t.tag = TY_DEST; t.capacity = nat_argument(child(n, 3)); }
                        else if base == "View" { if count != 5 { fail(FE_KIND, n, "View requires Region,Type,Nat,Domain"); } t.tag = TY_VIEW; t.nat = nat_argument(child(n, 3)); t.domain = type_binder(child(n, 4), KIND_DOMAIN); }
                        else { if count != 6 { fail(FE_KIND, n, "Builder requires Region,Type,Nat,Nat,Mode"); } t.tag = TY_BUILDER; t.nat = nat_argument(child(n, 3)); t.capacity = nat_argument(child(n, 4)); let mode = ast_text(source, nodes[child(n, 5)]); if mode != "Append" && mode != "Resize" { fail(FE_KIND, n, "unknown builder mode"); } t.mode = if mode == "Append" { MODE_APPEND } else { MODE_RESIZE }; }
                    }
                }
                return intern_type(t);
            }
            if base == "Result" || base == "Option" {
                let is_result = base == "Result"; if node.children.count != (if is_result { 3 } else { 2 }) { fail(FE_TYPE, n, "wrong Result/Option arity"); }
                let success = resolve_type(child(n, 1)); let failure = if is_result { resolve_type(child(n, 2)) } else { unit };
                let first = b.fields.len as u32; b.fields.push(Field { name: add_name(b, if is_result { "Ok" } else { "None" }), type_id: if is_result { success } else { unit }, tag: 0, .. });
                let second = b.fields.len as u32; b.fields.push(Field { name: add_name(b, if is_result { "Err" } else { "Some" }), type_id: if is_result { failure } else { success }, tag: 1, .. });
                return intern_type(TypeNode { tag: if is_result { TY_RESULT } else { TY_SUM }, fields: ref_span(b, [first, second]), .. });
            }
            if base == "Owned" { if node.children.count != 2 { fail(FE_KIND, n, "Owned takes one payload schema"); } return owned_schema(child(n, 1)); }
            if base == "Fn" { if node.children.count != 5 { fail(FE_TYPE, n, "Fn requires four arguments"); } let r = region_argument(child(n, 1)); let mode = ast_text(source, nodes[child(n, 2)]); if mode != "Many" && mode != "Once" { fail(FE_UNSUPPORTED, n, "capturing callable type producer is not completed"); } let arg = resolve_type(child(n, 3)); let result = resolve_type(child(n, 4)); let ct = b.contracts.len as u32; b.contracts.push(Contract { arg: arg, result: result, depth: 0, frame: 0, .. }); return intern_type(TypeNode { tag: TY_FN, children: ref_span(b, [arg, result]), region: r, mode: if mode == "Many" { MODE_MANY } else { MODE_ONCE }, contract: ct, .. }); }
        }
        if node.tag == AstTag.TypeApply {
            let base_node = child(n, 0); var definition: u32 = 0;
            if nodes[base_node].tag != AstTag.Select { let name = add_name(b, ast_text(source, nodes[base_node])); var ai = local_aliases.len; while ai > alias_base { ai--; let alias = local_aliases[ai]; if alias.name == name { if !alias.complete { fail(FE_RECURSION, n, "recursive local type alias"); } if alias.binders.count == 0 { fail(FE_KIND, n, "type alias is not generic"); } let substitutions = make_substitutions(alias.binders, n, 1); return instantiate_interface_type(alias.type_id, substitutions); } } }
            if nodes[base_node].tag == AstTag.Select { definition = imported_definition(base_node, DEF_TYPE); }
            else { let name = add_name(b, ast_text(source, nodes[base_node])); for d, i in decls { if b.definitions[d.definition].name == name && b.definitions[d.definition].kind == DEF_TYPE { name_query(module_id, name, 2, d.definition); complete_declaration(i as u32); definition = d.definition; } } }
            if definition == 0 { name_query(module_id, add_name(b, ast_text(source, nodes[base_node])), 2, 0); fail(FE_UNBOUND, n, "unknown type constructor"); }
            let d = b.definitions[definition]; if d.binders.count == 0 { fail(FE_KIND, n, "type alias is not generic"); }
            let substitutions = make_substitutions(d.binders, n, 1); return instantiate_interface_type(d.type_id, substitutions);
        }
        fail(FE_UNSUPPORTED, n, "type family has no completed semantic producer yet"); return 0;
    }
    fn nat_value(binder: u32, n: u32) -> u32 { for item in natvalues { if item.binder == binder && b.blocks[b.values[item.value].block_id].function == current_function { return item.value; } } return emit(OP_NAT_VALUE, unsigned, [], [], binder, n); }
    fn scope_inside(child_scope: u32, parent_scope: u32) -> bool { var scope = child_scope; for i in 64 { tick(current_decl); if scope == parent_scope { return true; } if scope == 0 { return false; } scope = b.scopes[scope].parent; } return false; }
    fn check_escape_binder(id: u32, target_scope: u32, returning: bool, n: u32) {
        if id == 0 { return; } tick(n); for bound in escape_bounds { tick(n); if bound == id { return; } }
        let binder = b.binders[id];
        if binder.introduction_kind == INTRO_FUNCTION && (returning && binder.introduction == current_function || !scope_inside(target_scope, binder.scope)) { fail(FE_LIFETIME, n, "callable cannot escape its lexical activation"); }
        for i in open_base..open_scopes.len { tick(n); let scope = open_scopes[i]; if binder.scope == scope && !scope_inside(target_scope, scope) { fail(FE_LIFETIME, n, "opened region/domain witness escapes its lexical scope"); } }
    }
    recursive fn check_escape_term(id: u32, target_scope: u32, returning: bool, n: u32) {
        if id == 0 { return; } tick(n); let term = b.terms[id]; if term.tag == EXPR_BINDER { check_escape_binder(term.binder, target_scope, returning, n); }
        for i in term.args.count { check_escape_term(b.refs[term.args.start + i], target_scope, returning, n); }
    }
    recursive fn check_escape_type(ty: u32, target_scope: u32, returning: bool, n: u32) {
        if ty == 0 { return; } tick(n); let t = b.types[ty]; let mark = escape_bounds.len;
        for i in t.binders.count { tick(n); escape_bounds.push(b.refs[t.binders.start + i]); }
        if t.contract != 0 { let contract = b.contracts[t.contract]; for i in contract.binders.count { tick(n); escape_bounds.push(b.refs[contract.binders.start + i]); } }
        check_escape_binder(t.region, target_scope, returning, n); check_escape_binder(t.domain, target_scope, returning, n); check_escape_binder(t.binder, target_scope, returning, n);
        check_escape_term(t.nat, target_scope, returning, n); check_escape_term(t.capacity, target_scope, returning, n);
        for i in t.children.count { check_escape_type(b.refs[t.children.start + i], target_scope, returning, n); }
        for i in t.fields.count { tick(n); check_escape_type(b.fields[b.refs[t.fields.start + i]].type_id, target_scope, returning, n); }
        if t.contract != 0 { let contract = b.contracts[t.contract]; for i in contract.effects.count { tick(n); check_escape_binder(b.effects[b.refs[contract.effects.start + i]].region, target_scope, returning, n); }
            for facts in [contract.requires, contract.ensures, contract.on_true, contract.on_false] { for i in facts.count { tick(n); let fact = b.facts[b.refs[facts.start + i]]; check_escape_binder(fact.domain, target_scope, returning, n); check_escape_term(fact.left, target_scope, returning, n); check_escape_term(fact.right, target_scope, returning, n); check_escape_term(fact.third, target_scope, returning, n); } }
        }
        escape_bounds.resize(mark);
    }
    fn check_escape(value: u32, target_scope: u32, n: u32) { check_escape_type(type_of(value), target_scope, false, n); }
    fn require_effect(kind: u32, region: u32, n: u32) {
        let ct = b.functions[current_function].contract; let effects = b.contracts[ct].effects;
        if region != 0 && (kind == EFFECT_READ || kind == EFFECT_WRITE || kind == EFFECT_PLACE || kind == EFFECT_RESET) { let scope = b.binders[region].scope; if scope != 0 && (b.scopes[scope].kind == SCOPE_REGION || b.scopes[scope].kind == SCOPE_OWNED) && scope_inside(current_scope, scope) { return; } }
        for i in effects.count { let e = b.effects[b.refs[effects.start + i]]; if e.kind == kind && e.region == region { return; } }
        if effects_explicit { fail(FE_EFFECT, n, "operation exceeds advertised effects"); }
        let eid = b.effects.len as u32; b.effects.push(Effect { kind: kind, region: region }); let mark = temporaries.len; for i in effects.count { temporaries.push(b.refs[effects.start + i]); } temporaries.push(eid); b.contracts[ct].effects = ref_span(b, temporaries[mark..]); temporaries.resize(mark);
    }
    fn observation_term(value: u32, tag: u32) -> u32 { let v = b.values[value]; let id = proof_term(b, work, proof_limits, proof_index, Term { tag: tag, type_id: unsigned, value: value, version: v.version, scope: v.scope, .. }); if id == 0 { fail(FE_PROOF_LIMIT, current_decl, "observation term budget exhausted"); } let ty = b.types[v.type_id]; let known = if tag == EXPR_CAP { ty.capacity } else { ty.nat }; if known != 0 && known != id { let e = proof_evidence(b, work, proof_limits, proof_index, Fact { tag: FACT_EQ, left: id, right: known, .. }, RULE_LEN, current_scope, 0, [value], []); if e == 0 { fail(FE_PROOF_LIMIT, current_decl, "observation evidence limit"); } active.push(e); } return id; }
    fn term_of(value: u32) -> u32 {
        for item in natvalues { if item.value == value { return proof_term(b, work, proof_limits, proof_index, Term { tag: EXPR_BINDER, type_id: unsigned, binder: item.binder, scope: b.binders[item.binder].scope, .. }); } }
        let v = b.values[value]; var term = Term { tag: EXPR_VALUE, type_id: unsigned, value: value, version: v.version, scope: v.scope, .. };
        if v.op != 0 && b.ops[v.op].tag == OP_STATIC && v.type_id == unsigned { let object = b.static_objects[b.ops[v.op].imm0]; if object.kind == STATIC_VALUE && object.bytes.count == 4 && object.relocations.count == 0 { var literal: u32 = 0; for i in 4 { literal |= (b.bytes[object.bytes.start + i] as u32) << (8 * i); } return proof_term(b, work, proof_limits, proof_index, Term { tag: EXPR_LITERAL, type_id: unsigned, literal: literal, .. }); } }
        if v.op != 0 && b.ops[v.op].tag == OP_U32 { term = Term { tag: EXPR_LITERAL, type_id: unsigned, literal: b.ops[v.op].imm0, .. }; }
        if v.op != 0 { let op = b.ops[v.op]; if op.tag == OP_NAT_VALUE { return proof_term(b, work, proof_limits, proof_index, Term { tag: EXPR_BINDER, type_id: unsigned, binder: op.imm0, scope: b.binders[op.imm0].scope, .. }); } if op.tag == OP_VIEW_LEN || op.tag == OP_BUILDER_LEN || op.tag == OP_BUILDER_CAP || op.tag == OP_DEST_CAP { return observation_term(b.refs[op.args.start], if op.tag == OP_VIEW_LEN { EXPR_LEN } else if op.tag == OP_BUILDER_LEN { EXPR_INIT } else { EXPR_CAP }); } }
        let result = proof_term(b, work, proof_limits, proof_index, term); if result == 0 { fail(FE_PROOF_LIMIT, current_decl, "proof term budget exhausted"); } return result;
    }
    fn exact_value_term(value: u32) -> u32 { let v = b.values[value]; if v.op != 0 && (b.ops[v.op].tag == OP_U32 || b.ops[v.op].tag == OP_NAT_VALUE) { return term_of(value); } let id = proof_term(b, work, proof_limits, proof_index, Term { tag: EXPR_VALUE, type_id: v.type_id, value: value, version: v.version, scope: v.scope, .. }); if id == 0 { fail(FE_PROOF_LIMIT, current_decl, "value term limit"); } return id; }
    fn projected_value(base: u32, ordinal: u32, n: u32) -> u32 {
        let defining = b.values[base].op; if defining != 0 && (b.ops[defining].tag == OP_TUPLE || b.ops[defining].tag == OP_RECORD) && ordinal < b.ops[defining].args.count { return b.refs[b.ops[defining].args.start + ordinal]; }
        for block_id in [current_block, b.functions[current_function].entry] { var at = block_heads[block_id]; while at != 0 { tick(n); let op = b.ops[pending[at].operation]; if op.tag == OP_PROJECT && op.imm0 == ordinal && b.refs[op.args.start] == base { return b.refs[op.results.start]; } if op.tag == OP_DESTRUCTURE && b.refs[op.args.start] == base && ordinal < op.results.count { return b.refs[op.results.start + ordinal]; } at = pending[at].next; } }
        let ty = b.types[type_of(base)]; if !share(type_of(base)) { fail(FE_UNSUPPORTED, n, "affine formal-field projection needs a recorded whole destructure"); }
        return emit(OP_PROJECT, b.fields[b.refs[ty.fields.start + ordinal]].type_id, [base], [], ordinal, n);
    }
    recursive fn instantiate_term(formal: u32, arg: u32, result: u32, substitutions: Span, n: u32) -> u32 {
        tick(n); let t = b.terms[formal];
        if t.tag == EXPR_ARG { if arg == 0 { fail(FE_FACT, n, "arg root unavailable"); } return exact_value_term(arg); }
        if t.tag == EXPR_RESULT { if result == 0 { fail(FE_FACT, n, "result root unavailable"); } return exact_value_term(result); }
        if t.tag == EXPR_LITERAL { return formal; }
        if t.tag == EXPR_BINDER { return substituted_nat(formal, substitutions); }
        if t.tag == EXPR_FIELD { let base_term = instantiate_term(b.refs[t.args.start], arg, result, substitutions, n); let base = b.terms[base_term]; if base.tag != EXPR_VALUE { fail(FE_FACT, n, "formal field has no exact value root"); } return exact_value_term(projected_value(base.value, t.literal, n)); }
        if t.tag == EXPR_LEN || t.tag == EXPR_CAP || t.tag == EXPR_INIT { let base_term = instantiate_term(b.refs[t.args.start], arg, result, substitutions, n); if b.terms[base_term].tag != EXPR_VALUE { fail(FE_FACT, n, "observation has no exact value root"); } return observation_term(b.terms[base_term].value, t.tag); }
        if t.tag == EXPR_MAX_MINUS { let x = instantiate_term(b.refs[t.args.start], arg, result, substitutions, n); return proof_term(b, work, proof_limits, proof_index, Term { tag: EXPR_MAX_MINUS, type_id: unsigned, args: ref_span(b, [x]), scope: current_scope, .. }); }
        fail(FE_FACT, n, "unsupported formal term substitution"); return 0;
    }
    fn instantiate_fact(formal: u32, arg: u32, result: u32, substitutions: Span, n: u32) -> Fact {
        let f = b.facts[formal]; return Fact { tag: f.tag, left: instantiate_term(f.left, arg, result, substitutions, n), right: instantiate_term(f.right, arg, result, substitutions, n), third: if f.third == 0 { 0 } else { instantiate_term(f.third, arg, result, substitutions, n) }, domain: substituted_identity(f.domain, KIND_DOMAIN, substitutions), version: f.version };
    }
    fn contract_proofs(clause: Span, arg: u32, result: u32, substitutions: Span, n: u32) -> Span {
        let mark = temporaries.len;
        for i in clause.count { let formal = b.refs[clause.start + i]; let f = instantiate_fact(formal, arg, result, substitutions, n); let e = proof_query(b, work, proof_limits, proof_index, current_scope, active[active_base..], f); if e == 0 { fail(if work.exhausted { FE_PROOF_LIMIT } else { FE_CONTRACT }, n, "call or return contract fact not established"); } temporaries.push(e); }
        let result_span = ref_span(b, temporaries[mark..]); temporaries.resize(mark); return result_span;
    }
    fn assume_contract(clause: Span, contract: u32, arg: u32, result: u32, call: u32, edge_id: u32, n: u32) {
        let substitutions = if call == 0 { Span { .. } } else { b.ops[call].substitutions };
        for i in clause.count {
            let formal = b.refs[clause.start + i]; let f = instantiate_fact(formal, arg, result, substitutions, n);
            let e = if call == 0 { proof_evidence(b, work, proof_limits, proof_index, f, RULE_ASSUMPTION, current_scope, edge_id, [arg], []) } else { proof_evidence(b, work, proof_limits, proof_index, f, RULE_CONTRACT, current_scope, edge_id, [arg, result], []) };
            if e == 0 { fail(FE_PROOF_LIMIT, n, "contract evidence budget exhausted"); } b.evidence[e].contract = contract; b.evidence[e].formal_fact = formal; b.evidence[e].call = call; active.push(e);
            if call == 0 && (f.tag == FACT_LT || f.tag == FACT_LE || f.tag == FACT_EQ) {
                let opposite = Fact { tag: if f.tag == FACT_LT { FACT_LE } else { FACT_LT }, left: f.right, right: f.left, .. };
                if proof_query(b, work, proof_limits, proof_index, current_scope, active[active_base..], opposite) != 0 { fail(FE_CONTRACT, n, "inconsistent public requirements"); }
            }
        }
    }
    recursive fn finish_return(value: u32, n: u32) {
        if owned_stack.len > owned_base { fail(FE_TARGET, n, "return cannot bypass an Owned construction terminal"); }
        if return_type == 0 { return_type = type_of(value); b.contracts[b.functions[current_function].contract].result = return_type; }
        for binding, i in bindings { if i >= binding_base && !binding.moved && !share(binding.type_id) { fail(if b.types[binding.type_id].tag == TY_RESULT { FE_RESULT } else { FE_OWNERSHIP }, n, "normal return loses a live affine capability"); } }
        let f = b.functions[current_function]; let c = b.contracts[f.contract]; check_escape_type(type_of(value), b.blocks[f.entry].scope, true, n);
        contract_proofs(c.ensures, f.param, value, Span { .. }, n);
        if c.on_true.count != 0 || c.on_false.count != 0 {
            let v = b.values[value];
            if v.op != 0 && b.ops[v.op].tag == OP_BOOL { contract_proofs(if b.ops[v.op].imm0 != 0 { c.on_true } else { c.on_false }, f.param, value, Span { .. }, n); }
            else { let from = current_block; let yes = new_block(); let no = new_block(); let ey = edge(from, yes, EDGE_TRUE, []); let en = edge(from, no, EDGE_FALSE, []); terminate(TERM_BRANCH, value, [ey, en], n); let mark = active.len; current_block = yes; branch_facts(value, ey, true); finish_return(emit(OP_BOOL, boolean, [], [], 1, n), n); active.resize(mark); current_block = no; branch_facts(value, en, false); finish_return(emit(OP_BOOL, boolean, [], [], 0, n), n); active.resize(mark); return; }
        }
        terminate(TERM_RETURN, value, [], n);
    }
    fn append_reference(span: Span, value: u32) -> Span { let mark = temporaries.len; for i in span.count { temporaries.push(b.refs[span.start + i]); } temporaries.push(value); let result = ref_span(b, temporaries[mark..]); temporaries.resize(mark); return result; }
    recursive fn local_term(n: u32) -> u32 {
        tick(n); let node = nodes[n];
        if node.tag == AstTag.Integer { return proof_term(b, work, proof_limits, proof_index, Term { tag: EXPR_LITERAL, type_id: unsigned, literal: node.bits as u32, .. }); }
        if node.tag == AstTag.Name { let value = observe_expression(n); return if type_of(value) == unsigned { term_of(value) } else { exact_value_term(value) }; }
        if node.tag == AstTag.Complement { let x = local_term(child(n, 0)); return proof_term(b, work, proof_limits, proof_index, Term { tag: EXPR_MAX_MINUS, type_id: unsigned, args: ref_span(b, [x]), scope: current_scope, .. }); }
        if node.tag == AstTag.Observation { let base = local_term(child(n, 0)); if b.terms[base].tag != EXPR_VALUE { fail(FE_FACT, n, "observation requires an exact collection value"); } let name = ast_text(source, node); return observation_term(b.terms[base].value, if name == "Len" { EXPR_LEN } else if name == "Init" { EXPR_INIT } else { EXPR_CAP }); }
        if node.tag == AstTag.Select { let value = observe_expression(n); return term_of(value); }
        fail(FE_FACT, n, "unsupported local fact term"); return 0;
    }
    fn local_fact(n: u32) -> Fact {
        let name = ast_text(source, nodes[n]); var f = Fact { .. };
        if name == "Index" { f.tag = FACT_INDEX; f.domain = type_binder(child(n, 0), KIND_DOMAIN); f.left = local_term(child(n, 1)); f.right = local_term(child(n, 2)); }
        else { f.tag = if name == "Eq" { FACT_EQ } else if name == "Lt" { FACT_LT } else if name == "Le" { FACT_LE } else if name == "AddFits" { FACT_ADD_FITS } else if name == "SubFits" { FACT_SUB_FITS } else { FACT_MUL_FITS }; f.left = local_term(child(n, 0)); f.right = local_term(child(n, 1)); }
        if b.terms[f.left].type_id != unsigned || b.terms[f.right].type_id != unsigned { fail(FE_FACT, n, "local facts require U32 operands"); } return f;
    }
    recursive fn rename_term(id: u32, params: Span, args: Span) -> u32 {
        let term = b.terms[id]; tick(current_decl);
        if term.tag == EXPR_VALUE || term.tag == EXPR_LEN || term.tag == EXPR_INIT || term.tag == EXPR_CAP {
            for i in params.count { if b.refs[params.start + i] == term.value { let arg = b.refs[args.start + i]; return if term.tag == EXPR_VALUE { term_of(arg) } else { observation_term(arg, term.tag) }; } }
            return id;
        }
        if term.args.count == 0 { return id; } let mark = temporaries.len;
        for i in term.args.count { temporaries.push(rename_term(b.refs[term.args.start + i], params, args)); }
        var changed = term; changed.args = ref_span(b, temporaries[mark..]); temporaries.resize(mark); return proof_term(b, work, proof_limits, proof_index, changed);
    }
    fn rename_fact(f: Fact, params: Span, args: Span) -> Fact { return Fact { tag: f.tag, left: rename_term(f.left, params, args), right: rename_term(f.right, params, args), third: if f.third == 0 { 0 } else { rename_term(f.third, params, args) }, domain: f.domain, version: f.version }; }
    fn loop_edge_proofs(loop_id: u32, params: Span, args: Span, n: u32) -> Span {
        let invariants = b.loops[loop_id].invariant; let mark = temporaries.len;
        for i in invariants.count { let assumed = b.evidence[b.refs[invariants.start + i]]; let wanted = rename_fact(b.facts[assumed.fact], params, args); let e = proof_query(b, work, proof_limits, proof_index, current_scope, active[active_base..], wanted); if e == 0 { fail(if work.exhausted { FE_PROOF_LIMIT } else { FE_CONTRACT }, n, "loop invariant is not established for this transfer"); } temporaries.push(e); }
        let result = ref_span(b, temporaries[mark..]); temporaries.resize(mark); return result;
    }
    fn loop_parameter(initial: u32, block_id: u32) -> u32 {
        let id = b.values.len as u32; var ty = type_of(initial); b.values.push(Value { type_id: ty, block_id: block_id, version: id, scope: b.blocks[block_id].scope, .. });
        if b.types[ty].tag == TY_BUILDER { let witness = proof_term(b, work, proof_limits, proof_index, Term { tag: EXPR_INIT, type_id: unsigned, value: id, version: id, scope: b.blocks[block_id].scope, .. }); var next = b.types[ty]; next.nat = witness; ty = intern_type(next); b.values[id].type_id = ty; } return id;
    }
    fn carry_compatible(before: u32, after: u32, n: u32) {
        if before == after { return; } let a = b.types[before]; let c = b.types[after];
        if a.tag != TY_BUILDER || c.tag != TY_BUILDER || a.region != c.region || a.capacity != c.capacity || a.mode != c.mode || a.children.count != 1 || c.children.count != 1 || b.refs[a.children.start] != b.refs[c.children.start] { fail(FE_TYPE, n, "loop carry changed constructor, region, element, capacity or mode"); }
    }
    fn loop_transfer(n: u32, advancing: bool, has_arguments: bool) {
        if loop_stack.len == loop_base { fail(FE_TARGET, n, "loop transfer has no lexical loop"); } let context = loop_stack[loop_stack.len - 1]; let info = b.loops[context.id];
        if has_arguments != (context.carries != 0) { fail(FE_TARGET, n, "next/stop are required only for carry loops"); }
        if has_arguments && nodes[n].children.count != context.carries { fail(FE_TYPE, n, "loop transfer carry arity mismatch"); }
        let mark = temporaries.len; temporaries.push(context.index);
        for i in context.carries { let ty = type_of(b.refs[context.header_params.start + i + 1]); let next = expression(child(n, i), 0); temporaries.push(next); }
        if current_block == 0 { temporaries.resize(mark); return; }
        for i in context.hidden_indices.count { let binding = bindings[b.refs[context.hidden_indices.start + i]]; if binding.moved { fail(FE_OWNERSHIP, n, "loop consumed outer capability without an explicit carry"); } temporaries.push(binding.value); }
        for i in mark + 1..temporaries.len { check_escape(temporaries[i], b.blocks[if advancing { info.header } else { info.exit }].scope, n); }
        for i in context.carries { carry_compatible(type_of(b.refs[context.header_params.start + i + 1]), type_of(temporaries[mark + i + 1]), n); }
        if advancing { let one = emit(OP_U32, unsigned, [], [], 1, n); temporaries[mark] = scalar_op(n, OP_U32_ADD, context.index, one, unsigned); }
        let args = ref_span(b, temporaries[mark..]); temporaries.resize(mark); let evidence = loop_edge_proofs(context.id, context.header_params, args, n);
        let target = if advancing { info.header } else { info.exit }; let kind = if advancing { EDGE_LOOP_NEXT } else { EDGE_LOOP_STOP }; let eid = edge(current_block, target, kind, b.refs[args.start..args.start + args.count]); b.edges[eid].loop_id = context.id; b.edges[eid].evidence = evidence;
        if advancing { b.loops[context.id].backedges = append_reference(b.loops[context.id].backedges, eid); } else { b.loops[context.id].exits = append_reference(b.loops[context.id].exits, eid); }
        terminate(TERM_JUMP, 0, [eid], n);
    }
    fn require_fact(fact: Fact, n: u32) -> u32 { let evidence = proof_query(b, work, proof_limits, proof_index, current_scope, active[active_base..], fact); if evidence == 0 { fail(if work.exhausted { FE_PROOF_LIMIT } else { FE_ARITHMETIC }, n, "required arithmetic fact was not established"); } return evidence; }
    fn collection_read(collection: u32, index: u32, n: u32) -> u32 {
        let t = b.types[type_of(collection)]; if t.tag != TY_VIEW && t.tag != TY_BUILDER { fail(FE_TYPE, n, "indexing requires an initialized collection"); }
        let it = b.types[type_of(index)]; var evidence: u32 = 0;
        if it.tag == TY_INDEX { if t.tag != TY_VIEW || it.domain != t.domain || it.nat != t.nat { fail(FE_DOMAIN, n, "index does not belong to this exact view domain and extent"); } }
        else { exact(index, unsigned, n); let bound = observation_term(collection, if t.tag == TY_VIEW { EXPR_LEN } else { EXPR_INIT }); evidence = proof_query(b, work, proof_limits, proof_index, current_scope, active[active_base..], Fact { tag: FACT_LT, left: term_of(index), right: bound, .. }); if evidence == 0 { fail(if work.exhausted { FE_PROOF_LIMIT } else { FE_BOUNDS }, n, "index is not established below initialized extent"); } }
        require_effect(EFFECT_READ, t.region, n); let element = b.refs[t.children.start]; let op = if t.tag == TY_VIEW { OP_VIEW_INDEX } else { OP_BUILDER_GET };
        return if evidence == 0 { emit(op, element, [collection, index], [], 0, n) } else { emit(op, element, [collection, index], [evidence], 0, n) };
    }
    fn require_bounds(fact: Fact, n: u32) -> u32 { let evidence = proof_query(b, work, proof_limits, proof_index, current_scope, active[active_base..], fact); if evidence == 0 { fail(if work.exhausted { FE_PROOF_LIMIT } else { FE_BOUNDS }, n, "required collection bounds were not established"); } return evidence; }
    fn scalar_op(n: u32, op: u32, lhs: u32, rhs: u32, result_type: u32) -> u32 {
        var evidence: u32 = 0;
        if op >= OP_U32_ADD && op <= OP_U32_REM { let x = term_of(lhs); let y = term_of(rhs); var fact = Fact { left: x, right: y, .. }; if op == OP_U32_ADD { fact.tag = FACT_ADD_FITS; } else if op == OP_U32_SUB { fact.tag = FACT_SUB_FITS; } else if op == OP_U32_MUL { fact.tag = FACT_MUL_FITS; } else { fact.tag = FACT_LT; fact.left = proof_term(b, work, proof_limits, proof_index, Term { tag: EXPR_LITERAL, type_id: unsigned, literal: 0, .. }); } evidence = require_fact(fact, n); }
        if op == OP_U32_SHL || op == OP_U32_SHR { let limit = proof_term(b, work, proof_limits, proof_index, Term { tag: EXPR_LITERAL, type_id: unsigned, literal: 32, .. }); evidence = require_fact(Fact { tag: FACT_LT, left: term_of(rhs), right: limit, .. }, n); }
        let value = if evidence != 0 { emit(op, result_type, [lhs, rhs], [evidence], 0, n) } else { emit(op, result_type, [lhs, rhs], [], 0, n) };
        if op == OP_U32_ADD || op == OP_U32_SUB { let x = term_of(lhs); let y = term_of(rhs); let symbolic = proof_term(b, work, proof_limits, proof_index, Term { tag: if op == OP_U32_ADD { EXPR_ADD } else { EXPR_SUB }, type_id: unsigned, args: ref_span(b, [x, y]), scope: current_scope, .. }); let px = proof_evidence(b, work, proof_limits, proof_index, Fact { tag: FACT_EQ, left: x, right: x, .. }, RULE_REFLEXIVE, current_scope, 0, [], []); let py = proof_evidence(b, work, proof_limits, proof_index, Fact { tag: FACT_EQ, left: y, right: y, .. }, RULE_REFLEXIVE, current_scope, 0, [], []); let equality = proof_evidence(b, work, proof_limits, proof_index, Fact { tag: FACT_EQ, left: symbolic, right: term_of(value), .. }, RULE_CHECKED_SUCCESS, current_scope, 0, [value], [px, py]); if equality == 0 { fail(FE_PROOF_LIMIT, n, "checked arithmetic provenance budget"); } active.push(equality); }
        return value;
    }
    recursive fn stage_static(n: u32, expected: u32, object: u32, projection: Span = Span { .. }) -> FrontStage {
        let sstatic_start = static_scope_start; let sstatic_end = static_scope_end; static_scope_start = binding_base; static_scope_end = bindings.len; let sf = current_function; let sb = current_block; let ss = current_scope; let sr = return_type; let se = effects_explicit; let sl = lambda_outer_base; let sbas = binding_base; let abas = active_base; let tbas = target_base; let obas = owned_base; let lbas = loop_base; let pbas = open_base; let hbas = held_base; let lex = lexical_base; let sd = max_callee_depth; let sm = max_callee_frame;
        let bm = bindings.len; let am = active.len; let tm = targets.len; let om = owned_stack.len; let lm = loop_stack.len; let pm = open_scopes.len; let hm = held.len;
        binding_base = bm; active_base = am; target_base = tm; owned_base = om; loop_base = lm; open_base = pm; held_base = hm; lexical_base = bm; lambda_outer_base = -1; effects_explicit = true; max_callee_depth = 0; max_callee_frame = 0;
        let ct = b.contracts.len as u32; b.contracts.push(Contract { arg: unit, result: expected, .. }); current_scope = b.scopes.len as u32; b.scopes.push(Scope { kind: SCOPE_FUNCTION, origin: origin(n), .. }); current_function = b.functions.len as u32; let fid = current_function;
        complete_callable_slots(b.contracts[ct].arg, n); complete_callable_slots(b.contracts[ct].result, n);
        let ty: u32 = 0; b.functions.push(Function { evaluator_only: true, name: add_name(b, "<static>"), module: module_id, type_id: ty, contract: ct, producer: current_producer, origin: origin(n), .. }); current_block = new_block(); b.functions[fid].entry = current_block; return_type = expected;
        let parameter = b.values.len as u32; b.values.push(Value { type_id: unit, block_id: current_block, version: parameter, scope: current_scope, .. }); b.functions[fid].param = parameter; b.blocks[current_block].params = ref_span(b, [parameter]);
        var value = if object != 0 { emit(OP_STATIC, b.static_objects[object].type_id, [], [], object, n) } else { expression(n, expected) };
        for i in projection.count { let ordinal = b.refs[projection.start + i]; let ty = b.types[type_of(value)]; if (ty.tag != TY_TUPLE && ty.tag != TY_RECORD) || ordinal >= ty.fields.count { fail(FE_TYPE, n, "static destructuring does not match product shape"); } value = emit(OP_PROJECT, b.fields[b.refs[ty.fields.start + ordinal]].type_id, [value], [], ordinal, n); }
        if current_block != 0 { finish_return(value, n); } if return_type == 0 { fail(FE_INTERFACE, n, "static initializer has no determinate result"); }
        if !share(return_type) { fail(FE_USAGE, n, "static data must be transitively Share"); } let completed = TypeNode { tag: TY_FN, children: ref_span(b, [unit, return_type]), mode: MODE_MANY, contract: ct, .. }; b.functions[fid].type_id = intern_type(completed); finalize_blocks(fid, n); let result = FrontStage { function: fid, value: value, type_id: return_type };
        static_scope_start = sstatic_start; static_scope_end = sstatic_end; current_function = sf; current_block = sb; current_scope = ss; return_type = sr; effects_explicit = se; lambda_outer_base = sl; binding_base = sbas; active_base = abas; target_base = tbas; owned_base = obas; loop_base = lbas; open_base = pbas; held_base = hbas; lexical_base = lex; max_callee_depth = sd; max_callee_frame = sm;
        bindings.resize(bm); active.resize(am); targets.resize(tm); owned_stack.resize(om); loop_stack.resize(lm); open_scopes.resize(pm); held.resize(hm); return result;
    }
    recursive fn static_dependencies(fid: u32, seen: Span) {
        for i in seen.count { if b.refs[seen.start + i] == fid { return; } } let mark = temporaries.len; for i in seen.count { temporaries.push(b.refs[seen.start + i]); } temporaries.push(fid); let path = ref_span(b, temporaries[mark..]); temporaries.resize(mark);
        let function = b.functions[fid]; if function.producer != 0 && b.definitions[function.producer].kind == DEF_FUNCTION { let d = b.definitions[function.producer]; name_query(d.module, d.name, 1, function.producer); b.dependencies[b.dependencies.len - 1].kind = DEP_BODY; }
        for i in function.blocks.count { let ops = b.blocks[b.refs[function.blocks.start + i]].ops; for j in ops.count { tick(current_decl); let op = b.ops[b.refs[ops.start + j]]; if op.tag == OP_CALL || op.tag == OP_CLOSURE || op.tag == OP_FN_PLACE { static_dependencies(op.imm0, path); } else if op.tag == OP_STATIC { let object = b.static_objects[op.imm0]; if object.producer != 0 { let d = b.definitions[object.producer]; name_query(d.module, d.name, 1, object.producer); b.dependencies[b.dependencies.len - 1].kind = DEP_STATIC; } for k in object.relocations.count { let r = b.static_relocations[b.refs[object.relocations.start + k]]; if r.kind == STATIC_FUNCTION { static_dependencies(r.target, path); } else if r.kind == STATIC_CLOSURE { static_dependencies(b.ops[r.target].imm0, path); } } } } }
    }
    fn evaluate_static(fid: u32, stats: StaticStats&, n: u32) -> StaticValue {
        // Stats are cumulative within a declaration, including nested statics.
        static_dependencies(fid, Span { .. }); let before = stats.visits; let steps_before = stats.steps; let bytes_before = stats.produced_bytes;
        let value, ok = static_evaluate_publish_initializer(b, fid, StaticValue { .. }, current_producer, stats, diagnostics);
        work.static_steps += stats.steps - steps_before; work.static_bytes += stats.produced_bytes - bytes_before;
        if !charge(work, (stats.visits - before) as u64, visit_start + LIMIT_VISITS) { fail(FE_SEMANTIC_LIMIT, n, "static evaluation exceeded declaration traversal limit"); }
        if !ok { fail(FE_STATIC_LIMIT, n, "required static initializer failed"); } return value;
    }
    fn publish_static(kind: u32, type_id: u32, element_type: u32, count: u32, domain: u32, values: const StaticValue[:], producer: u32, stats: StaticStats&) -> u32, bool { let before = stats.visits; let steps_before = stats.steps; let bytes_before = stats.produced_bytes; let object, ok = static_publish(b, kind, type_id, element_type, count, domain, values, producer, stats, diagnostics); work.static_steps += stats.steps - steps_before; work.static_bytes += stats.produced_bytes - bytes_before; if !charge(work, (stats.visits - before) as u64, visit_start + LIMIT_VISITS) { fail(FE_SEMANTIC_LIMIT, current_decl, "static publication exceeded declaration traversal limit"); } return object, ok; }
    recursive fn runtime_dictionary(ty: u32) -> bool {
        tick(current_decl); let t = b.types[ty]; if t.tag == TY_PARAM { return true; }
        for i in t.children.count { if runtime_dictionary(b.refs[t.children.start + i]) { return true; } }
        for i in t.fields.count { if runtime_dictionary(b.fields[b.refs[t.fields.start + i]].type_id) { return true; } } return false;
    }
    recursive fn validate_global_pattern(n: u32, ty: u32) {
        let node = nodes[n]; if node.tag == AstTag.Name { return; } if node.tag == AstTag.AnnotatedPattern { if !equivalent_type(ty, resolve_type(child(n, 1))) { fail(FE_TYPE, n, "static pattern annotation mismatch"); } validate_global_pattern(child(n, 0), ty); return; }
        let t = b.types[ty]; if node.children.count == 0 && ty == unit { return; } if node.tag != AstTag.Pattern || (t.tag != TY_TUPLE && t.tag != TY_RECORD) || node.children.count != t.fields.count { fail(FE_TYPE, n, "static pattern must destructure every product field"); }
        for i in node.children.count { let field = b.fields[b.refs[t.fields.start + i]]; var pattern = child(n, i); if nodes[pattern].tag == AstTag.Field { if field.name != add_name(b, ast_text(source, nodes[pattern])) { fail(FE_TYPE, n, "static record pattern field mismatch"); } pattern = child(pattern, 0); } validate_global_pattern(pattern, field.type_id); }
    }
    recursive fn register_top_pattern(n: u32, declaration: u32, root_index: u32, path: Span) {
        let node = nodes[n]; if node.tag == AstTag.AnnotatedPattern { register_top_pattern(child(n, 0), declaration, root_index, path); return; }
        if node.tag == AstTag.Name { let name = add_name(b, ast_text(source, node)); if name_bytes(core_view(b), name) == "_" { return; } if builtin_name(name_bytes(core_view(b), name)) { fail(FE_UNBOUND, n, "builtin names cannot be rebound"); } for prior in decls { if b.definitions[prior.definition].name == name { fail(FE_UNBOUND, n, "duplicate top-level binding"); } } let id = b.definitions.len as u32; b.definitions.push(Definition { kind: DEF_STATIC, name: name, module: module_id, origin: origin(declaration), .. }); top_definitions.push(id); decls.push(FrontDecl { node: declaration, definition: id, projection_root: root_index + 1, projection_path: path, .. }); return; }
        if node.tag != AstTag.Pattern { fail(FE_TYPE, n, "invalid static pattern"); } for i in node.children.count { var pattern = child(n, i); if nodes[pattern].tag == AstTag.Field { pattern = child(pattern, 0); } let mark = temporaries.len; for j in path.count { temporaries.push(b.refs[path.start + j]); } temporaries.push(i as u32); let next = ref_span(b, temporaries[mark..]); temporaries.resize(mark); register_top_pattern(pattern, declaration, root_index, next); }
    }
    recursive fn complete_static(n: u32, annotation: u32, initializer: u32, definition: u32) -> u32 {
        let expected = if annotation == 0 { 0 } else { resolve_type(annotation) }; let mark = static_values.len; var result_type = expected; var element_type: u32 = 0; var count: u32 = 1; var domain: u32 = 0; var kind = STATIC_VALUE;
        if nodes[initializer].tag == AstTag.Array {
            kind = STATIC_ARRAY; count = nodes[initializer].children.count; if expected != 0 { let et = b.types[expected]; if et.tag != TY_VIEW || et.region != 0 { fail(FE_TYPE, n, "static array annotation must be static View"); } element_type = b.refs[et.children.start]; }
            for i in count { let stage = stage_static(child(initializer, i), element_type, 0); if element_type == 0 { element_type = stage.type_id; } if stage.type_id != element_type || !plain(element_type) { fail(FE_USAGE, n, "static array requires one Plain element type"); } let value = evaluate_static(stage.function, static_stats, n); static_values.push(value); }
            if element_type == 0 { fail(FE_INTERFACE, n, "empty static array requires element annotation"); } domain = b.binders.len as u32; b.binders.push(Binder { kind: KIND_DOMAIN, name: add_name(b, "<static-domain>"), origin: origin(n), .. }); let length = proof_term(b, work, proof_limits, proof_index, Term { tag: EXPR_LITERAL, type_id: unsigned, literal: count, .. }); result_type = intern_type(TypeNode { tag: TY_VIEW, children: ref_span(b, [element_type]), nat: length, domain: domain, .. });
        } else { let stage = stage_static(initializer, expected, 0); result_type = stage.type_id; let value = evaluate_static(stage.function, static_stats, n); static_values.push(value); }
        let object, ok = publish_static(kind, result_type, element_type, count, domain, static_values[mark..], definition, static_stats); static_values.resize(mark); if !ok { fail(FE_STATIC_LIMIT, n, "static result exceeds publication limits"); }
        if definition != 0 { let publication = stage_static(n, result_type, object); b.definitions[definition].type_id = result_type; b.definitions[definition].value = publication.value; return publication.value; }
        return emit(OP_STATIC, result_type, [], [], object, n);
    }
    fn static_named(name: u32, n: u32) -> u32 {
        if current_function != 0 && name_bytes(core_view(b), b.functions[current_function].name) == "<static>" { var at = static_scope_end; while at > static_scope_start { at--; let local = bindings[at]; if local.name == name { let op = b.values[local.value].op; if op == 0 || b.ops[op].tag != OP_STATIC { fail(FE_STATIC_LIMIT, n, "required static initializer depends on runtime value"); } return emit(OP_STATIC, local.type_id, [], [], b.ops[op].imm0, n); } } }
        for d, index in decls { if b.definitions[d.definition].name == name && b.definitions[d.definition].kind == DEF_STATIC { name_query(module_id, name, 1, d.definition); complete_declaration(index as u32); let value = b.definitions[d.definition].value; return emit(OP_STATIC, type_of(value), [], [], b.ops[b.values[value].op].imm0, n); } } return 0;
    }
    fn local_generic(name: u32, n: u32, required: bool) -> u32 {
        var at = bindings.len; while at > binding_base { at--; tick(n); let binding = bindings[at]; if binding.name == name { if binding.generic_function == 4294967295 { fail(FE_RECURSION, n, "recursive local generic declaration"); } if required && binding.generic_function == 0 { fail(FE_KIND, n, "monomorphic local value cannot be instantiated"); } return binding.generic_function; } }
        var frame = capture_frames.len; while frame > capture_base { frame--; let parent = capture_frames[frame]; at = parent.parent_end; while at > parent.parent_base { at--; tick(n); let binding = bindings[at]; if binding.name == name { if binding.generic_function == 4294967295 { fail(FE_RECURSION, n, "recursive local generic declaration"); } if required && binding.generic_function == 0 { fail(FE_KIND, n, "monomorphic local value cannot be instantiated"); } return binding.generic_function; } } }
        return 0;
    }
    fn lookup_function(name: u32, n: u32) -> u32 {
        for d, i in decls { tick(n); if b.definitions[d.definition].name == name && b.definitions[d.definition].kind == DEF_FUNCTION { name_query(module_id, name, 1, d.definition); complete_declaration(i as u32); return decls[i].function; } }
        name_query(module_id, name, 1, 0); fail(FE_UNBOUND, n, "unknown callable name"); return 0;
    }
    fn finalize_blocks(fid: u32, n: u32) {
        let mark = temporaries.len; let owned = b.functions[fid].blocks;
        for j in owned.count { tick(n); let id = b.refs[owned.start + j]; let bb = b.blocks[id]; if bb.term == 0 { continue; } let om = temporaries.len; var at = block_heads[id]; while at != 0 { tick(n); temporaries.push(pending[at].operation); at = pending[at].next; } b.blocks[id].ops = ref_span(b, temporaries[om..]); temporaries.resize(om); temporaries.push(id); }
        b.functions[fid].blocks = ref_span(b, temporaries[mark..]); temporaries.resize(mark);
    }
    recursive fn captured_term(id: u32, fid: u32) -> u32 {
        if id == 0 { return 0; } tick(current_decl); var t = b.terms[id];
        if t.value != 0 { var found: u32 = 0; let caps = b.functions[fid].captures; for i in caps.count { let cap = b.captures[b.refs[caps.start + i]]; if cap.value == t.value { found = cap.local_value; break; } } if found == 0 { return 0; } t.value = found; t.version = b.values[found].version; t.scope = b.values[found].scope; }
        let mark = temporaries.len; for i in t.args.count { let arg = captured_term(b.refs[t.args.start + i], fid); if arg == 0 { temporaries.resize(mark); return 0; } temporaries.push(arg); } t.args = ref_span(b, temporaries[mark..]); temporaries.resize(mark);
        if t.value == 0 && t.args.count != 0 { t.scope = b.blocks[b.functions[fid].entry].scope; }
        let result = proof_term(b, work, proof_limits, proof_index, t); if result == 0 { fail(FE_PROOF_LIMIT, current_decl, "capture term budget exhausted"); } return result;
    }
    fn capture_fact(fid: u32, premise: u32) {
        for prior in capture_facts { if prior.function == fid && prior.premise == premise { return; } }
        var fact = b.facts[b.evidence[premise].fact]; let left = captured_term(fact.left, fid); let right = captured_term(fact.right, fid); let third = captured_term(fact.third, fid);
        if left == 0 || right == 0 || (fact.third != 0 && third == 0) { return; } fact.left = left; fact.right = right; fact.third = third; let scope = b.blocks[b.functions[fid].entry].scope;
        let evidence = proof_evidence(b, work, proof_limits, proof_index, fact, RULE_CAPTURE, scope, 0, [], [premise]); if evidence == 0 { fail(FE_PROOF_LIMIT, current_decl, "capture evidence budget exhausted"); } b.evidence[evidence].contract = b.functions[fid].contract;
        capture_facts.push(FrontCaptureFact { function: fid, premise: premise, evidence: evidence }); if fid == current_function { active.push(evidence); }
    }
    fn refresh_capture_facts(fid: u32) {
        for frame in capture_frames { if frame.function != fid { continue; } for i in frame.facts.count { capture_fact(fid, b.refs[frame.facts.start + i]); } let count = capture_facts.len; for i in count { let fact = capture_facts[i]; if fact.function == frame.parent_function { capture_fact(fid, fact.evidence); } } break; }
    }
    recursive fn capture_from(index: i64, name: u32, n: u32) -> u32 {
        if index < capture_base { return 0; } let frame = capture_frames[index];
        for item in capture_names { if item.function == frame.function && item.name == name { return item.value; } }
        var source_value: u32 = 0; var at = frame.parent_end;
        while at > frame.parent_base { at--; let binding = bindings[at]; if binding.name == name { if binding.generic_function != 0 { fail(FE_INTERFACE, n, "generic declaration requires explicit instantiation"); } if binding.moved { fail(FE_MOVED, n, "capturing a consumed value"); } source_value = binding.value; break; } }
        if source_value == 0 { source_value = capture_from(index - 1, name, n); } if source_value == 0 { return 0; }
        return capture_source(index, source_value, name, n);
    }
    fn capture_source(index: i64, source_value: u32, name: u32, n: u32) -> u32 {
        let frame = capture_frames[index]; let old = b.functions[frame.function].captures; for i in old.count { tick(n); let cap = b.captures[b.refs[old.start + i]]; if cap.value == source_value { return cap.local_value; } }
        let ty = type_of(source_value); if !share(ty) { fail(FE_CAPTURE, n, "closure captures must be transitively Share"); }
        let fid = frame.function; let entry = b.functions[fid].entry; let scope = b.blocks[entry].scope; let value = b.values.len as u32;
        b.values.push(Value { type_id: ty, block_id: entry, version: value, scope: scope, origin: origin(n), .. });
        let capture = b.captures.len as u32; b.captures.push(Capture { function: fid, value: source_value, local_value: value, field: b.functions[fid].captures.count, scope: scope });
        b.functions[fid].captures = append_reference(b.functions[fid].captures, capture); b.blocks[entry].params = append_reference(b.blocks[entry].params, value);
        capture_names.push(FrontCapturedName { function: fid, name: name, value: value }); let known = if ty == unsigned { term_of(source_value) } else { 0 }; if known != 0 && b.terms[known].tag == EXPR_LITERAL { let local = proof_term(b, work, proof_limits, proof_index, Term { tag: EXPR_VALUE, type_id: ty, value: value, version: value, scope: scope, .. }); let premise = proof_evidence(b, work, proof_limits, proof_index, Fact { tag: FACT_EQ, left: known, right: known, .. }, RULE_REFLEXIVE, b.values[source_value].scope, 0, [], []); let evidence = proof_evidence(b, work, proof_limits, proof_index, Fact { tag: FACT_EQ, left: local, right: known, .. }, RULE_CAPTURE, scope, 0, [], [premise]); b.evidence[evidence].contract = b.functions[fid].contract; capture_facts.push(FrontCaptureFact { function: fid, premise: premise, evidence: evidence }); if fid == current_function { active.push(evidence); } } refresh_capture_facts(fid); return value;
    }
    recursive fn forward_capture(index: i64, source_value: u32, n: u32) -> u32 {
        if index < capture_base { fail(FE_CAPTURE, n, "generic capture is outside the current lexical activation"); } let frame = capture_frames[index]; var source = source_value; if b.blocks[b.values[source].block_id].function != frame.parent_function { source = forward_capture(index - 1, source, n); } return capture_source(index, source, 0, n);
    }
    fn captured_value(name: u32, n: u32) -> u32 {
        if lambda_outer_base < 0 || capture_frames.len == capture_base { return 0; } let value = capture_from(capture_frames.len - 1, name, n);
        if value != 0 { bindings.push(FrontBinding { name: name, value: value, type_id: type_of(value), .. }); } return value;
    }
    fn environment_binder(fid: u32, binder: u32) {
        if binder == 0 { return; } tick(current_decl); let own = b.contracts[b.functions[fid].contract].binders; for i in own.count { tick(current_decl); if b.refs[own.start + i] == binder { return; } } for bound in environment_bounds { tick(current_decl); if bound == binder { return; } } let kind = b.binders[binder].kind; if kind != KIND_TYPE && kind != KIND_NAT { return; }
        let bindings = b.functions[fid].environment_bindings; for i in bindings.count { if b.environment_bindings[b.refs[bindings.start + i]].binder == binder { return; } }
        var source_value: u32 = 0; if kind == KIND_NAT { for item in natvalues { if item.binder == binder { source_value = item.value; } } }
        let id = b.environment_bindings.len as u32; b.environment_bindings.push(EnvironmentBinding { function: fid, kind: kind, binder: binder, offset: bindings.count * 4, source_value: source_value }); b.functions[fid].environment_bindings = append_reference(bindings, id);
    }
    recursive fn environment_term(fid: u32, id: u32) { if id == 0 { return; } tick(current_decl); let term = b.terms[id]; if term.tag == EXPR_BINDER { environment_binder(fid, term.binder); } for i in term.args.count { environment_term(fid, b.refs[term.args.start + i]); } }
    recursive fn environment_type(fid: u32, ty: u32) {
        if ty == 0 { return; } tick(current_decl); let t = b.types[ty]; let mark = environment_bounds.len; for i in t.binders.count { tick(current_decl); environment_bounds.push(b.refs[t.binders.start + i]); }
        if t.tag == TY_PARAM { environment_binder(fid, t.binder); }
        environment_term(fid, t.nat); environment_term(fid, t.capacity);
        for i in t.children.count { environment_type(fid, b.refs[t.children.start + i]); } for i in t.fields.count { environment_type(fid, b.fields[b.refs[t.fields.start + i]].type_id); }
        environment_bounds.resize(mark);
    }
    recursive fn closure(n: u32, expected: u32, generic_declaration: bool) -> u32 {
        var callable = expected; var ct: u32 = 0; var placement: u32 = 0;
        if generic_declaration && child(n, 2) != 0 { fail(FE_INTERFACE, n, "place an instantiated generic callable, not its declaration"); }
        if child(n, 2) != 0 { placement = expression(child(n, 2), 0); if b.types[type_of(placement)].tag != TY_ENV_DEST { fail(FE_TYPE, n, "explicit closure placement requires EnvDest"); } }
        if callable != 0 { callable = unwrap_callable(callable); if b.types[callable].tag != TY_FN { fail(FE_TYPE, n, "lambda expected type must be callable"); } ct = b.types[callable].contract; }
        else { let pattern = child(n, 0); if nodes[pattern].tag != AstTag.AnnotatedPattern { fail(FE_INTERFACE, n, "lambda requires expected callable type or annotated parameter"); } let arg = resolve_type(child(pattern, 1)); ct = b.contracts.len as u32; b.contracts.push(Contract { arg: arg, .. }); }
        let saved_held_base = held_base; held_base = held.len; let saved_lexical_base = lexical_base; lexical_base = bindings.len; let saved_owned_base = owned_base; owned_base = owned_stack.len; let saved_function = current_function; let saved_block = current_block; let saved_scope = current_scope; let saved_return = return_type; let saved_effects = effects_explicit; let saved_lambda = lambda_outer_base; let saved_binding_base = binding_base; let saved_active_base = active_base; let saved_target_base = target_base; let saved_loop_base = loop_base; let saved_open_base = open_base; let saved_depth = max_callee_depth; let saved_frame = max_callee_frame;
        let bm = bindings.len; let am = active.len; let tm = targets.len; let lm = loop_stack.len; let om = open_scopes.len; let nm = natvalues.len;
        lambda_outer_base = binding_base; binding_base = bm; active_base = am; target_base = tm; loop_base = lm; open_base = om; max_callee_depth = 0; max_callee_frame = 0;
        current_scope = b.scopes.len as u32; b.scopes.push(Scope { parent: saved_scope, kind: SCOPE_FUNCTION, origin: origin(n), .. });
        current_function = b.functions.len as u32; let fid = current_function;
        complete_callable_slots(b.contracts[ct].arg, n); complete_callable_slots(b.contracts[ct].result, n);
        b.functions.push(Function { name: add_name(b, "<lambda>"), module: module_id, type_id: callable, contract: ct, origin: origin(n), .. });
        capture_frames.push(FrontCaptureFrame { function: fid, parent_function: saved_function, parent_base: saved_binding_base as u32, parent_end: bm as u32, facts: ref_span(b, active[saved_active_base..am]) });
        current_block = new_block(); b.functions[fid].entry = current_block; return_type = b.contracts[ct].result; effects_explicit = expected != 0;
        let parameter = b.values.len as u32; b.values.push(Value { type_id: b.contracts[ct].arg, block_id: current_block, version: parameter, scope: current_scope, origin: origin(n), .. }); b.functions[fid].param = parameter; b.blocks[current_block].params = ref_span(b, [parameter]);
        bind_pattern(child(n, 0), parameter); assume_contract(b.contracts[ct].requires, ct, parameter, 0, 0, 0, n); check_suite(child(n, 1));
        if current_block != 0 { fail(FE_RETURN, n, "lambda has a reachable path without return"); }
        if b.contracts[ct].depth != 0 && (b.contracts[ct].depth < max_callee_depth + 1 || b.contracts[ct].frame < max_callee_frame) { fail(FE_RESOURCE, n, "lambda resource bound does not cover callees"); }
        finalize_blocks(fid, n); environment_type(fid, b.contracts[ct].arg); environment_type(fid, return_type);
        let function_blocks = b.functions[fid].blocks; for bi in function_blocks.count { tick(n); let basic = b.blocks[b.refs[function_blocks.start + bi]]; for pi in basic.params.count { environment_type(fid, type_of(b.refs[basic.params.start + pi])); } for oi in basic.ops.count { tick(n); let op = b.ops[b.refs[basic.ops.start + oi]]; for ri in op.results.count { environment_type(fid, type_of(b.refs[op.results.start + ri])); } if op.tag == OP_NAT_VALUE { environment_binder(fid, op.imm0); } } }
        let captures = b.functions[fid].captures; let needs_environment = captures.count != 0 || b.functions[fid].environment_bindings.count != 0;
        var region: u32 = 0;
        if placement != 0 { region = b.types[type_of(placement)].region; }
        else if needs_environment && !b.functions[saved_function].evaluator_only { let prior = current_scope; let prior_function = current_function; current_scope = saved_scope; current_function = saved_function; region = local_region(n); current_scope = prior; current_function = prior_function; }
        if callable != 0 { if b.types[callable].region != region { if !needs_environment && placement == 0 { region = b.types[callable].region; } else { fail(FE_LIFETIME, n, "captured callable does not satisfy advertised lifetime"); } } }
        else { callable = intern_type(TypeNode { tag: TY_FN, children: ref_span(b, [b.contracts[ct].arg, return_type]), region: region, mode: MODE_MANY, contract: ct, .. }); }
        b.functions[fid].type_id = if generic_declaration { expected } else { callable };
        held.resize(held_base); held_base = saved_held_base; lexical_base = saved_lexical_base; owned_stack.resize(owned_base); owned_base = saved_owned_base; current_function = saved_function; current_block = saved_block; current_scope = saved_scope; return_type = saved_return; effects_explicit = saved_effects; lambda_outer_base = saved_lambda; binding_base = saved_binding_base; active_base = saved_active_base; target_base = saved_target_base; loop_base = saved_loop_base; open_base = saved_open_base; max_callee_depth = saved_depth; max_callee_frame = saved_frame;
        capture_frames.resize(capture_frames.len - 1); bindings.resize(bm); active.resize(am); targets.resize(tm); loop_stack.resize(lm); open_scopes.resize(om); natvalues.resize(nm);
        let mark = temporaries.len; if placement != 0 { temporaries.push(placement); require_effect(EFFECT_PLACE, region, n); } for i in captures.count { temporaries.push(b.captures[b.refs[captures.start + i]].value); }
        var result: u32 = 0; var constructor: u32 = 0; if generic_declaration { tick(n); operation_limit(n); allocate(n); constructor = b.ops.len as u32; b.ops.push(Operation { tag: OP_GENERIC_BIND, registry: OP_GENERIC_BIND, args: ref_span(b, temporaries[mark..]), scope: current_scope, origin: origin(n), imm0: fid, .. }); record_op(current_block, constructor); } else { result = emit(if placement != 0 { OP_FN_PLACE } else { OP_CLOSURE }, callable, temporaries[mark..], [], fid, n); constructor = b.values[result].op; } temporaries.resize(mark);
        for i in captures.count { temporaries.push(b.captures[b.refs[captures.start + i]].value); } for i in captures.count { temporaries.push(b.captures[b.refs[captures.start + i]].local_value); } let mapped = ref_span(b, temporaries[mark..]); temporaries.resize(mark);
        for item in capture_facts { if item.function == fid { b.evidence[item.evidence].call = constructor; b.evidence[item.evidence].operands = mapped; } } return if generic_declaration { fid } else { result };
    }
    recursive fn observe_expression(n: u32) -> u32 {
        if nodes[n].tag == AstTag.Name { let name = add_name(b, ast_text(source, nodes[n])); var i = bindings.len; while i > binding_base { i--; let binding = bindings[i]; if binding.name == name { if binding.moved { fail(FE_MOVED, n, "observation uses consumed value"); } return binding.value; } } }
        return expression(n, 0);
    }
    recursive fn expression(n: u32, expected: u32) -> u32 {
        tick(n); let node = nodes[n]; var value: u32 = 0;
        if node.tag == AstTag.Integer { value = emit(OP_U32, unsigned, [], [], node.bits as u32, n); }
        else if node.tag == AstTag.Bool { value = emit(OP_BOOL, boolean, [], [], node.bits as u32, n); }
        else if node.tag == AstTag.Unit { value = emit(OP_UNIT, unit, [], [], 0, n); }
        else if node.tag == AstTag.Float { let bits, ok = parse_decimal_f32(ast_text(source, node)); if !ok { fail(FE_SYNTAX, n, "invalid floating literal"); } value = emit(OP_F32, floating, [], [], bits, n); }
        else if node.tag == AstTag.Name {
            let name = add_name(b, ast_text(source, node)); if local_generic(name, n, false) != 0 { fail(FE_INTERFACE, n, "generic declaration requires explicit instantiation"); } var found = false;
            var lookup = bindings.len; while lookup > binding_base { lookup--; tick(n); let binding = bindings[lookup]; if binding.name == name { if binding.moved { fail(if b.types[binding.type_id].tag == TY_PARAM { FE_USAGE } else { FE_MOVED }, n, "value was already moved"); } value = binding.value; if !share(binding.type_id) { bindings[lookup].moved = true; } found = true; break; } }
            if !found { value = captured_value(name, n); found = value != 0; }
            if !found { var ti = typebindings.len; while ti > type_base { ti--; let item = typebindings[ti]; if item.name == name && b.binders[item.binder].kind == KIND_NAT { value = nat_value(item.binder, n); found = true; break; } } }
            if !found { value = static_named(name, n); found = value != 0; }
            if !found { let fid = lookup_function(name, n); let fnn = b.functions[fid]; if b.contracts[fnn.contract].binders.count != 0 { fail(FE_INTERFACE, n, "generic function value requires explicit instantiation"); } value = emit(OP_CLOSURE, unwrap_callable(fnn.type_id), [], [], fid, n); }
        }
        else if node.tag == AstTag.Apply {
            let callee = child(n, 0); var fid: u32 = 0; if nodes[callee].tag == AstTag.Select { fid = b.definitions[imported_definition(callee, DEF_FUNCTION)].function; } else if nodes[callee].tag == AstTag.Name { let name = add_name(b, ast_text(source, nodes[callee])); fid = local_generic(name, n, true); if fid == 0 { fid = lookup_function(name, n); } }
            if fid == 0 { fail(FE_INTERFACE, n, "generic function value needs declared callable"); } let fnn = b.functions[fid]; let ct = b.contracts[fnn.contract]; if ct.binders.count == 0 { fail(FE_KIND, n, "nongeneric function cannot be instantiated"); }
            let substitutions = make_substitutions(ct.binders, n, 1); var ty = instantiate_interface_type(unwrap_callable(fnn.type_id), substitutions); let resulting_contract = b.types[ty].contract;
            let capture_mark = temporaries.len; for i in substitutions.count { let sub = b.substitutions[b.refs[substitutions.start + i]]; if sub.kind == KIND_TYPE && runtime_dictionary(sub.value) || sub.kind == KIND_NAT && b.terms[sub.value].tag != EXPR_LITERAL { let id = b.adapter_captures.len as u32; b.adapter_captures.push(AdapterCapture { kind: sub.kind, source: sub.value, offset: (temporaries.len - capture_mark) as u32 * 4 }); temporaries.push(id); } }
            let adapter_captures = ref_span(b, temporaries[capture_mark..]); temporaries.resize(capture_mark); if adapter_captures.count != 0 || fnn.captures.count != 0 || fnn.environment_bindings.count != 0 { var local = b.types[ty]; local.region = if b.functions[current_function].evaluator_only { 0 } else { local_region(n) }; ty = intern_type(local); }
            var extra: u32 = 0; if b.types[ct.arg].tag == TY_PARAM && (b.types[b.contracts[resulting_contract].arg].tag == TY_PARAM || b.types[b.contracts[resulting_contract].arg].tag == TY_U32 || b.types[b.contracts[resulting_contract].arg].tag == TY_F32 || b.types[b.contracts[resulting_contract].arg].tag == TY_BOOL || b.types[b.contracts[resulting_contract].arg].tag == TY_INDEX) { extra += 4; } if b.types[ct.result].tag == TY_PARAM && (b.types[b.contracts[resulting_contract].result].tag == TY_PARAM || b.types[b.contracts[resulting_contract].result].tag == TY_U32 || b.types[b.contracts[resulting_contract].result].tag == TY_F32 || b.types[b.contracts[resulting_contract].result].tag == TY_BOOL || b.types[b.contracts[resulting_contract].result].tag == TY_INDEX) { extra += 4; }
            if ct.depth != 0 { if ct.depth == 128 || ct.frame > 16777216 - extra { fail(FE_RESOURCE, n, "generic callback adapter exceeds resource limit"); } b.contracts[resulting_contract].depth = ct.depth + 1; b.contracts[resulting_contract].frame = ct.frame + extra; }
            let arguments_mark = temporaries.len; for i in fnn.captures.count { let cap = b.captures[b.refs[fnn.captures.start + i]]; var captured = cap.value; if b.blocks[b.values[captured].block_id].function != current_function { captured = forward_capture(capture_frames.len - 1, captured, n); } temporaries.push(captured); } for i in fnn.environment_bindings.count { let binding = b.environment_bindings[b.refs[fnn.environment_bindings.start + i]]; environment_binder(current_function, binding.binder); } value = emit(OP_CLOSURE, ty, temporaries[arguments_mark..], [], fid, n); temporaries.resize(arguments_mark); b.ops[b.values[value].op].substitutions = substitutions; if adapter_captures.count != 0 { b.callable_adapters.push(CallableAdapter { op: b.values[value].op, target_function: fid, callback_contract: resulting_contract, captures: adapter_captures, target_environment_offset: adapter_captures.count * 4, .. }); }
        }
        else if node.tag == AstTag.Function { value = closure(n, expected, false); }
        else if node.tag == AstTag.Tuple || node.tag == AstTag.Record {
            let mark = temporaries.len; var expected_fields = Span { .. }; if expected != 0 { expected_fields = b.types[expected].fields; if expected_fields.count != node.children.count { fail(FE_TYPE, n, "product field count mismatch"); } }
            for i in node.children.count { let item = child(n, i); let expr = if node.tag == AstTag.Record { child(item, 0) } else { item }; let et = if expected != 0 { b.fields[b.refs[expected_fields.start + i]].type_id } else { 0 }; let component = expression(expr, et); hold(component); temporaries.push(component); if current_block == 0 { temporaries.resize(mark); return 0; } }
            let args = ref_span(b, temporaries[mark..]); temporaries.resize(mark);
            for i in node.children.count { let fid = b.fields.len as u32; let item = child(n, i); let nm = if node.tag == AstTag.Record { add_name(b, ast_text(source, nodes[item])) } else { 0 }; b.fields.push(Field { name: nm, type_id: type_of(b.refs[args.start + i]), .. }); temporaries.push(fid); }
            let ty = intern_type(TypeNode { tag: if node.tag == AstTag.Tuple { TY_TUPLE } else { TY_RECORD }, fields: ref_span(b, temporaries[mark..]), .. }); temporaries.resize(mark);
            value = emit(if node.tag == AstTag.Tuple { OP_TUPLE } else { OP_RECORD }, ty, b.refs[args.start..args.start + args.count], [], 0, n);
        }
        else if node.tag == AstTag.Variant {
            let name = add_name(b, ast_text(source, node)); var ty = expected; var ordinal: u32 = 0;
            if ty == 0 { if ast_text(source, node) == "Ok" || ast_text(source, node) == "Err" { fail(FE_TYPE, n, "Result constructor requires expected Result type"); } let payload = child(n, 0); let val = if payload == 0 { emit(OP_UNIT, unit, [], [], 0, n) } else { expression(payload, 0) }; let f = b.fields.len as u32; b.fields.push(Field { name: name, type_id: type_of(val), tag: 0, .. }); ty = intern_type(TypeNode { tag: TY_SUM, fields: ref_span(b, [f]), .. }); value = emit(OP_SUM, ty, [val], [], 0, n); }
            else { let t = b.types[ty]; if t.tag != TY_SUM && t.tag != TY_RESULT { fail(FE_TYPE, n, "constructor expected a closed sum"); } var found = false; for i in t.fields.count { if b.fields[b.refs[t.fields.start + i]].name == name { ordinal = i as u32; found = true; } } if !found { fail(FE_TYPE, n, "constructor absent from expected type"); } let payload = child(n, 0); let pt = b.fields[b.refs[t.fields.start + ordinal]].type_id; let val = if payload == 0 { emit(OP_UNIT, unit, [], [], 0, n) } else { expression(payload, pt) }; exact(val, pt, n); value = emit(OP_SUM, ty, [val], [], ordinal, n); }
        }
        else if node.tag == AstTag.Binary {
            let operator = ast_text(source, node); if operator == "&&" || operator == "||" {
                let lhs = expression(child(n, 0), boolean); if current_block == 0 { return 0; } let from = current_block; let yes = new_block(); let no = new_block(); let snapshot = save_bindings(); let ey = flow_edge(from, yes, EDGE_TRUE, [], n); restore_bindings(snapshot); let en = flow_edge(from, no, EDGE_FALSE, [], n); restore_bindings(snapshot); terminate(TERM_BRANCH, lhs, [ey, en], n);
                var joined = FrontTarget { type_id: boolean, scope: current_scope, binding_limit: bindings.len as u32, .. }; let facts_mark = active.len;
                current_block = if operator == "&&" { no } else { yes }; flow_bindings(current_block, 0); let fixed = emit(OP_BOOL, boolean, [], [], if operator == "&&" { 0 } else { 1 }, n); exit_value(joined, fixed, n);
                restore_bindings(snapshot); current_block = if operator == "&&" { yes } else { no }; flow_bindings(current_block, 0); branch_facts(lhs, if operator == "&&" { ey } else { en }, operator == "&&"); var rhs: u32 = 0; let left_truth, left_known = literal_boolean(lhs, 0); if left_known && left_truth != (operator == "&&") { impossible(n, []); } else if !prune_facts(n) { rhs = expression(child(n, 1), boolean); if current_block != 0 { exit_value(joined, rhs, n); } }
                active.resize(facts_mark); restore_bindings(snapshot); snapshots.resize(snapshot.start); current_block = joined.block_id; enter_join(joined); b.blocks[from].merge = joined.block_id; booleans.push(FrontBoolean { value: joined.value, left: lhs, right: rhs, conjunction: operator == "&&" }); return exact(joined.value, expected, n);
            }
            let lhs = expression(child(n, 0), 0); let rhs = expression(child(n, 1), type_of(lhs)); if current_block == 0 { return 0; }
            let ty = type_of(lhs); var op: u32 = 0; var result_type = ty;
            if ty == unsigned { if operator == "+" { op = OP_U32_ADD; } else if operator == "-" { op = OP_U32_SUB; } else if operator == "*" { op = OP_U32_MUL; } else if operator == "/" { op = OP_U32_DIV; } else if operator == "%" { op = OP_U32_REM; } else if operator == "&" { op = OP_U32_AND; } else if operator == "|" { op = OP_U32_OR; } else if operator == "^" { op = OP_U32_XOR; } else if operator == "<<" { op = OP_U32_SHL; } else if operator == ">>" { op = OP_U32_SHR; } else if operator == "==" { op = OP_U32_EQ; } else if operator == "!=" { op = OP_U32_NE; } else if operator == "<" { op = OP_U32_LT; } else if operator == "<=" { op = OP_U32_LE; } else if operator == ">" { op = OP_U32_GT; } else if operator == ">=" { op = OP_U32_GE; } if op >= OP_U32_EQ && op <= OP_U32_GE { result_type = boolean; } }
            else if ty == floating { if operator == "+" { op = OP_F32_ADD; } else if operator == "-" { op = OP_F32_SUB; } else if operator == "*" { op = OP_F32_MUL; } else if operator == "/" { op = OP_F32_DIV; } else if operator == "==" { op = OP_F32_EQ; } else if operator == "!=" { op = OP_F32_NE; } else if operator == "<" { op = OP_F32_LT; } else if operator == "<=" { op = OP_F32_LE; } else if operator == ">" { op = OP_F32_GT; } else if operator == ">=" { op = OP_F32_GE; } if op >= OP_F32_EQ && op <= OP_F32_GE { result_type = boolean; } }
            if ty == boolean && (operator == "==" || operator == "!=") { let both = emit(OP_BOOL_AND, boolean, [lhs, rhs], [], 0, n); let nl = emit(OP_BOOL_NOT, boolean, [lhs], [], 0, n); let nr = emit(OP_BOOL_NOT, boolean, [rhs], [], 0, n); let neither = emit(OP_BOOL_AND, boolean, [nl, nr], [], 0, n); let equal = emit(OP_BOOL_OR, boolean, [both, neither], [], 0, n); return exact(if operator == "==" { equal } else { emit(OP_BOOL_NOT, boolean, [equal], [], 0, n) }, expected, n); }
            if op == 0 { fail(FE_TYPE, n, "operator is not defined for this scalar type"); } value = scalar_op(n, op, lhs, rhs, result_type);
        }
        else if node.tag == AstTag.Unary { let arg = expression(child(n, 0), 0); let s = ast_text(source, node); var op: u32 = 0; if s == "!" && type_of(arg) == boolean { op = OP_BOOL_NOT; } if s == "~" && type_of(arg) == unsigned { op = OP_U32_NOT; } if s == "-" && type_of(arg) == floating { op = OP_F32_NEG; } if op == 0 { fail(FE_TYPE, n, "unary operation has incompatible operand"); } value = emit(op, type_of(arg), [arg], [], 0, n); }
        else if node.tag == AstTag.Select {
            if nodes[child(n, 0)].tag == AstTag.Name { let alias = add_name(b, ast_text(source, nodes[child(n, 0)])); var shadow = false; for binding, i in bindings { if i >= binding_base && binding.name == alias { shadow = true; } } if !shadow { for item in imports { if item.name == alias { let did = imported_definition(n, DEF_FUNCTION); let d = b.definitions[did]; if d.kind == DEF_STATIC { let v = d.value; value = emit(OP_STATIC, d.type_id, [], [], b.ops[b.values[v].op].imm0, n); } else { value = emit(OP_CLOSURE, unwrap_callable(d.type_id), [], [], d.function, n); } return exact(value, expected, n); } } } }
            let base = observe_expression(child(n, 0)); let ty = b.types[type_of(base)]; let selector = ast_text(source, nodes[child(n, 1)]);
            if ty.tag == TY_INDEX && selector == "value" { value = emit(OP_INDEX_VALUE, unsigned, [base], [], 0, n); let evidence = proof_evidence(b, work, proof_limits, proof_index, Fact { tag: FACT_LT, left: term_of(value), right: ty.nat, .. }, RULE_INDEX_BOUND, current_scope, 0, [base, value], []); if evidence == 0 { fail(FE_PROOF_LIMIT, n, "Index range proof limit"); } active.push(evidence); return exact(value, expected, n); }
            if (ty.tag == TY_VIEW || ty.tag == TY_BUILDER) && selector == "length" { value = emit(if ty.tag == TY_VIEW { OP_VIEW_LEN } else { OP_BUILDER_LEN }, unsigned, [base], [], 0, n); exact(value, expected, n); return value; }
            if (ty.tag == TY_BUILDER || ty.tag == TY_DEST) && selector == "capacity" { value = emit(if ty.tag == TY_BUILDER { OP_BUILDER_CAP } else { OP_DEST_CAP }, unsigned, [base], [], 0, n); exact(value, expected, n); return value; } var index: u32 = 0; var found = false; if ty.tag == TY_TUPLE { let parsed, ok = parse_int(selector); if ok && parsed >= 0 && parsed < ty.fields.count { index = parsed as u32; found = true; } } else if ty.tag == TY_RECORD { let nm = add_name(b, selector); for i in ty.fields.count { tick(n); if b.fields[b.refs[ty.fields.start + i]].name == nm { index = i as u32; found = true; } } } if !found { fail(FE_TYPE, n, "unknown product field"); } if !share(type_of(base)) { fail(FE_USAGE, n, "affine products require complete destructuring"); } value = emit(OP_PROJECT, b.fields[b.refs[ty.fields.start + index]].type_id, [base], [], index, n); }
        else if node.tag == AstTag.OwnedOpen {
            let original = observe_expression(child(n, 0)); let ot = b.types[type_of(original)]; if ot.tag != TY_OWNED { fail(FE_TYPE, n, "owned.open requires Owned handle"); }
            let previous_scope = current_scope; let binding_mark = bindings.len; let type_mark = typebindings.len; let facts_mark = active.len;
            current_scope = b.scopes.len as u32; let scope = current_scope; b.scopes.push(Scope { parent: previous_scope, kind: SCOPE_LOAN, origin: origin(n), .. });
            let body = new_block(); let entrance = flow_edge(current_block, body, EDGE_NORMAL, [], n); terminate(TERM_JUMP, 0, [entrance], n); current_block = body; let owner = observe_expression(child(n, 0));
            let region_name = add_name(b, ast_text(source, nodes[child(n, 1)])); let region = b.binders.len as u32; b.binders.push(Binder { introduction_kind: INTRO_OPERATION, kind: KIND_REGION, scope: scope, introduction: b.ops.len as u32, name: region_name, origin: origin(n), .. }); typebindings.push(FrontTypeBinding { name: region_name, binder: region });
            let sub = b.substitutions.len as u32; b.substitutions.push(Substitution { binder: b.refs[ot.binders.start], kind: KIND_REGION, value: region }); let substitutions = ref_span(b, [sub]); let payload_type = substitute_type(b.refs[ot.children.start], substitutions, 0);
            let payload = emit(OP_OWNED_OPEN, payload_type, [owner], [], 0, n); b.ops[b.values[payload].op].substitutions = substitutions; bind(child(n, 2), payload);
            let target_mark = targets.len; targets.push(FrontTarget { type_id: expected, scope: previous_scope, binding_limit: binding_mark as u32, .. }); open_scopes.push(scope); check_suite(child(n, 3)); if current_block != 0 { fail(FE_RETURN, n, "owned.open requires explicit break value"); }
            let target = targets[target_mark]; targets.resize(target_mark); open_scopes.resize(open_scopes.len - 1); typebindings.resize(type_mark); bindings.resize(binding_mark); active.resize(facts_mark); current_scope = previous_scope;
            if target.incoming == 0 { return 0; } current_block = target.block_id; enter_join(target); value = target.value;
        }
        else if node.tag == AstTag.OwnedScope {
            let owned_type = owned_schema(child(n, 0)); let body_error = resolve_type(child(n, 1)); if !plain(body_error) { fail(FE_OWNED_PAYLOAD, n, "Owned body error must be Plain"); }
            let bytes = expression(child(n, 2), unsigned); require_effect(EFFECT_RESERVE, 0, n);
            let previous_scope = current_scope; let binding_mark = bindings.len; let type_mark = typebindings.len; let facts_mark = active.len;
            current_scope = b.scopes.len as u32; let scope = current_scope; b.scopes.push(Scope { parent: previous_scope, kind: SCOPE_OWNED, origin: origin(n), .. });
            let entry = new_block(); let entrance = flow_edge(current_block, entry, EDGE_NORMAL, [], n); terminate(TERM_JUMP, 0, [entrance], n); current_block = entry;
            let region = b.binders.len as u32; let region_name = add_name(b, ast_text(source, nodes[child(n, 3)])); b.binders.push(Binder { introduction_kind: INTRO_OPERATION, kind: KIND_REGION, scope: scope, introduction: b.ops.len as u32, name: region_name, origin: origin(n), .. }); typebindings.push(FrontTypeBinding { name: region_name, binder: region });
            let owner_type = intern_type(TypeNode { tag: TY_OWNED_CONSTRUCTION, region: region, .. }); let space_type = intern_type(TypeNode { tag: TY_SPACE, region: region, .. }); let pair_type = product_type([owner_type, space_type]); let reserve_error = storage_error(true); let error_type = two_sum("Reserve", reserve_error, "Body", body_error); let output_type = result_type(owned_type, error_type);
            let reserved = emit(OP_OWNED_BEGIN, result_type(pair_type, reserve_error), [bytes], [], 0, n); let from = current_block; let snapshot = save_bindings(); let yes = new_block(); let no = new_block();
            let ey = flow_edge(from, yes, EDGE_CASE, [reserved], n); restore_bindings(snapshot); let en = flow_edge(from, no, EDGE_CASE, [reserved], n); restore_bindings(snapshot); b.edges[ey].case_tag = 0; b.edges[en].case_tag = 1; terminate(TERM_SWITCH, reserved, [ey, en], n);
            let target_mark = targets.len; targets.push(FrontTarget { type_id: output_type, scope: previous_scope, binding_limit: binding_mark as u32, .. });
            current_block = no; let no_params = b.blocks[no].params; var ai: u32 = 1; for binding, i in bindings { if i >= binding_base && !binding.moved && !share(binding.type_id) { bindings[i].value = b.refs[no_params.start + ai]; ai++; } }
            let error = emit(OP_PAYLOAD, reserve_error, [b.refs[no_params.start]], [], 1, n); let wrapped = emit(OP_SUM, error_type, [error], [], 0, n); let failed = emit(OP_SUM, output_type, [wrapped], [], 1, n); exit_value(targets[target_mark], failed, n);
            restore_bindings(snapshot); current_block = yes; let yes_params = b.blocks[yes].params; ai = 1; for binding, i in bindings { if i >= binding_base && !binding.moved && !share(binding.type_id) { bindings[i].value = b.refs[yes_params.start + ai]; ai++; } }
            let pair = emit(OP_PAYLOAD, pair_type, [b.refs[yes_params.start]], [], 0, n); let parts = emit_destructure(pair, n);
            let construction = bindings.len as u32; bindings.push(FrontBinding { value: b.refs[parts.start], type_id: owner_type, .. }); bind(child(n, 5), b.refs[parts.start + 1]);
            let sub = b.substitutions.len as u32; b.substitutions.push(Substitution { binder: b.refs[b.types[owned_type].binders.start], kind: KIND_REGION, value: region }); let substitutions = ref_span(b, [sub]);
            owned_stack.push(FrontOwned { target: target_mark as u32, construction: construction, owned_type: owned_type, error_type: error_type, body_error: body_error, substitutions: substitutions, scope: scope }); open_scopes.push(scope); check_suite(child(n, 6)); if current_block != 0 { fail(FE_TARGET, n, "Owned body requires seal or abort on every path"); }
            owned_stack.resize(owned_stack.len - 1); open_scopes.resize(open_scopes.len - 1); let target = targets[target_mark]; targets.resize(target_mark); bindings.resize(binding_mark); typebindings.resize(type_mark); active.resize(facts_mark); current_scope = previous_scope; restore_bindings(snapshot); snapshots.resize(snapshot.start); current_block = target.block_id; enter_join(target); value = target.value; b.blocks[from].merge = target.block_id;
        }
        else if node.tag == AstTag.RegionScope {
            let payload_type = resolve_type(child(n, 0)); let bytes = expression(child(n, 2), unsigned); require_effect(EFFECT_RESERVE, 0, n);
            let previous_scope = current_scope; let binding_mark = bindings.len; let type_mark = typebindings.len; let facts_mark = active.len;
            current_scope = b.scopes.len as u32; let scope = current_scope; b.scopes.push(Scope { parent: previous_scope, kind: SCOPE_REGION, origin: origin(n), .. });
            let entry = new_block(); let entrance = flow_edge(current_block, entry, EDGE_NORMAL, [], n); terminate(TERM_JUMP, 0, [entrance], n); current_block = entry;
            let region = b.binders.len as u32; let region_name = add_name(b, ast_text(source, nodes[child(n, 3)])); b.binders.push(Binder { introduction_kind: INTRO_OPERATION, kind: KIND_REGION, scope: scope, introduction: b.ops.len as u32, name: region_name, origin: origin(n), .. }); typebindings.push(FrontTypeBinding { name: region_name, binder: region });
            let owner_type = intern_type(TypeNode { tag: TY_REGION_OWNER, region: region, .. }); let space_type = intern_type(TypeNode { tag: TY_SPACE, region: region, .. }); let pair_type = product_type([owner_type, space_type]); let error_type = storage_error(true); let reserved_type = result_type(pair_type, error_type); let output_type = result_type(payload_type, error_type);
            let reserved = emit(OP_RESERVE, reserved_type, [bytes], [], 0, n); let from = current_block; let snapshot = save_bindings(); let yes = new_block(); let no = new_block();
            let ey = flow_edge(from, yes, EDGE_CASE, [reserved], n); restore_bindings(snapshot); let en = flow_edge(from, no, EDGE_CASE, [reserved], n); restore_bindings(snapshot); b.edges[ey].case_tag = 0; b.edges[en].case_tag = 1; terminate(TERM_SWITCH, reserved, [ey, en], n);
            var joined = FrontTarget { type_id: output_type, scope: previous_scope, binding_limit: binding_mark as u32, .. };
            current_block = no; let no_params = b.blocks[no].params; var ai: u32 = 1; for binding, i in bindings { if i >= binding_base && !binding.moved && !share(binding.type_id) { bindings[i].value = b.refs[no_params.start + ai]; ai++; } }
            let error = emit(OP_PAYLOAD, error_type, [b.refs[no_params.start]], [], 1, n); let failed = emit(OP_SUM, output_type, [error], [], 1, n); exit_value(joined, failed, n);
            restore_bindings(snapshot); current_block = yes; let yes_params = b.blocks[yes].params; ai = 1; for binding, i in bindings { if i >= binding_base && !binding.moved && !share(binding.type_id) { bindings[i].value = b.refs[yes_params.start + ai]; ai++; } }
            let pair = emit(OP_PAYLOAD, pair_type, [b.refs[yes_params.start]], [], 0, n); let parts = emit_destructure(pair, n); bind(child(n, 4), b.refs[parts.start]); bind(child(n, 5), b.refs[parts.start + 1]);
            let target_mark = targets.len; targets.push(FrontTarget { type_id: payload_type, scope: previous_scope, binding_limit: binding_mark as u32, .. }); open_scopes.push(scope); check_suite(child(n, 6)); if current_block != 0 { fail(FE_RETURN, n, "region scope requires explicit break after closing storage"); }
            let target = targets[target_mark]; targets.resize(target_mark); open_scopes.resize(open_scopes.len - 1); bindings.resize(binding_mark); typebindings.resize(type_mark); active.resize(facts_mark); current_scope = previous_scope;
            if target.incoming != 0 { current_block = target.block_id; enter_join(target); let succeeded = emit(OP_SUM, output_type, [target.value], [], 0, n); exit_value(joined, succeeded, n); }
            restore_bindings(snapshot); snapshots.resize(snapshot.start); current_block = joined.block_id; enter_join(joined); value = joined.value; b.blocks[from].merge = joined.block_id;
        }
        else if node.tag == AstTag.Open {
            let package = expression(child(n, 0), 0); let pt = b.types[type_of(package)]; if pt.tag != TY_EXISTS { fail(FE_TYPE, n, "open requires an existential package"); }
            let names_node = child(n, 1); if nodes[names_node].children.count != pt.binders.count { fail(FE_KIND, n, "opening binder count mismatch"); }
            let previous_scope = current_scope; let scope = b.scopes.len as u32; b.scopes.push(Scope { parent: previous_scope, kind: SCOPE_PACKAGE, origin: origin(n), .. }); current_scope = scope;
            let body = new_block(); let from = current_block; var package_value = package; var enter_edge: u32 = 0;
            if share(type_of(package)) { enter_edge = flow_edge(from, body, EDGE_NORMAL, [], n); } else { enter_edge = flow_edge(from, body, EDGE_NORMAL, [package], n); package_value = b.refs[b.blocks[body].params.start]; }
            terminate(TERM_JUMP, 0, [enter_edge], n); current_block = body;
            let type_mark = typebindings.len; let nat_mark = natvalues.len; let binding_mark = bindings.len; let facts_mark = active.len; let oid = b.ops.len as u32; let sub_mark = temporaries.len;
            for i in pt.binders.count { let old_id = b.refs[pt.binders.start + i]; let old = b.binders[old_id]; let name_node = child(names_node, i); let name = add_name(b, ast_text(source, nodes[name_node])); let fresh = b.binders.len as u32; b.binders.push(Binder { introduction_kind: INTRO_OPERATION, kind: old.kind, scope: scope, introduction: oid, name: name, origin: origin(name_node), .. }); typebindings.push(FrontTypeBinding { name: name, binder: fresh }); var witness = fresh; if old.kind == KIND_NAT { witness = proof_term(b, work, proof_limits, proof_index, Term { tag: EXPR_BINDER, type_id: unsigned, binder: fresh, scope: scope, .. }); } let sid = b.substitutions.len as u32; b.substitutions.push(Substitution { binder: old_id, kind: old.kind, value: witness }); temporaries.push(sid); }
            let substitutions = ref_span(b, temporaries[sub_mark..]); temporaries.resize(sub_mark); let payload_type = substitute_type(b.refs[pt.children.start], substitutions, 0);
            let payload = b.values.len as u32; b.values.push(Value { type_id: payload_type, block_id: body, op: oid, version: payload, scope: scope, origin: origin(n) }); temporaries.push(payload);
            for i in pt.binders.count { let old = b.binders[b.refs[pt.binders.start + i]]; if old.kind == KIND_NAT { let term = b.substitutions[b.refs[substitutions.start + i]].value; let fresh = b.terms[term].binder; let id = b.values.len as u32; b.values.push(Value { type_id: unsigned, block_id: body, op: oid, version: id, scope: scope, .. }); temporaries.push(id); natvalues.push(FrontNatValue { binder: fresh, value: id }); } }
            let results = ref_span(b, temporaries[sub_mark..]); temporaries.resize(sub_mark); tick(n); operation_limit(n); allocate(n); b.ops.push(Operation { tag: OP_OPEN, registry: OP_OPEN, args: ref_span(b, [package_value]), results: results, substitutions: substitutions, scope: scope, origin: origin(n), .. }); record_op(body, oid); bind(child(n, 2), payload);
            let target_mark = targets.len; targets.push(FrontTarget { type_id: expected, scope: previous_scope, binding_limit: binding_mark as u32, .. }); open_scopes.push(scope); check_suite(child(n, 3)); if current_block != 0 { fail(FE_RETURN, n, "package opening requires explicit break value"); }
            let target = targets[target_mark]; targets.resize(target_mark); open_scopes.resize(open_scopes.len - 1); typebindings.resize(type_mark); natvalues.resize(nat_mark); bindings.resize(binding_mark); active.resize(facts_mark); current_scope = previous_scope;
            if target.incoming == 0 { return 0; } current_block = target.block_id; enter_join(target); value = target.value;
        }
        else if node.tag == AstTag.Pack {
            let package = resolve_type(child(n, 1)); let pt = b.types[package]; if pt.tag != TY_EXISTS { fail(FE_TYPE, n, "pack requires existential package schema"); }
            let witnesses = child(n, 0); let substitutions = make_substitutions(pt.binders, witnesses, 0); let payload_type = substitute_type(b.refs[pt.children.start], substitutions, 0); let mark = temporaries.len;
            for i in pt.binders.count { let binder = b.binders[b.refs[pt.binders.start + i]]; if binder.kind == KIND_NAT { let witness_node = child(witnesses, i); if nodes[witness_node].tag == AstTag.Integer { temporaries.push(emit(OP_U32, unsigned, [], [], nodes[witness_node].bits as u32, n)); } else { let nat = type_binder(witness_node, KIND_NAT); temporaries.push(nat_value(nat, n)); } } }
            temporaries.push(expression(child(n, 2), payload_type)); value = emit(OP_PACK, package, temporaries[mark..], [], 0, n); temporaries.resize(mark); b.ops[b.values[value].op].substitutions = substitutions;
        }
        else if node.tag == AstTag.Index { let collection = observe_expression(child(n, 0)); let index = expression(child(n, 1), 0); value = collection_read(collection, index, n); }
        else if node.tag == AstTag.Call {
            var callee = child(n, 0); var application: u32 = 0; if nodes[callee].tag == AstTag.Apply { application = callee; callee = child(callee, 0); } var fid: u32 = 0; var intrinsic: u32 = 0;
            if nodes[callee].tag == AstTag.Select && nodes[child(callee, 0)].tag == AstTag.Name && ast_text(source, nodes[child(callee, 0)]) == "array" {
                if ast_text(source, nodes[child(callee, 1)]) != "in" || node.children.count != 3 || application != 0 || nodes[child(n, 2)].tag != AstTag.Array { fail(FE_TYPE, n, "array.in requires destination and contextual array literal"); }
                let dest = expression(child(n, 1), 0); let dt = b.types[type_of(dest)]; if dt.tag != TY_DEST { fail(FE_TYPE, n, "array.in requires destination"); } let array = child(n, 2); let element = b.refs[dt.children.start]; if !plain(element) { fail(FE_USAGE, n, "array element must be Plain"); }
                let zero = proof_term(b, work, proof_limits, proof_index, Term { tag: EXPR_LITERAL, type_id: unsigned, .. }); let bt = intern_type(TypeNode { tag: TY_BUILDER, children: dt.children, region: dt.region, nat: zero, capacity: dt.capacity, mode: MODE_APPEND, .. }); var builder = emit(OP_BUILDER_BEGIN, bt, [dest], [], MODE_APPEND, n); require_effect(EFFECT_WRITE, dt.region, n);
                for i in nodes[array].children.count { hold(builder); let item = expression(child(array, i), element); let before = b.types[type_of(builder)]; let evidence = require_bounds(Fact { tag: FACT_LT, left: before.nat, right: before.capacity, .. }, n); let one = proof_term(b, work, proof_limits, proof_index, Term { tag: EXPR_LITERAL, type_id: unsigned, literal: 1, .. }); let next = proof_term(b, work, proof_limits, proof_index, Term { tag: EXPR_ADD, type_id: unsigned, args: ref_span(b, [before.nat, one]), scope: current_scope, .. }); var after = before; after.nat = next; builder = emit(OP_BUILDER_APPEND, intern_type(after), [builder, item], [evidence], 0, n); }
                let before = b.types[type_of(builder)]; let domain = b.binders.len as u32; b.binders.push(Binder { introduction_kind: INTRO_OPERATION, kind: KIND_DOMAIN, scope: current_scope, introduction: b.ops.len as u32, origin: origin(n), .. }); let vt = intern_type(TypeNode { tag: TY_VIEW, children: before.children, region: before.region, nat: before.nat, domain: domain, .. }); let package = intern_type(TypeNode { tag: TY_EXISTS, children: ref_span(b, [vt]), binders: ref_span(b, [domain]), .. }); value = emit(OP_BUILDER_FREEZE, package, [builder], [], 0, n);
            } else if nodes[callee].tag == AstTag.Select && nodes[child(callee, 0)].tag == AstTag.Name && ast_text(source, nodes[child(callee, 0)]) == "owned" {
                if ast_text(source, nodes[child(callee, 1)]) != "close" || node.children.count != 2 || application != 0 { fail(FE_UNSUPPORTED, n, "Owned primitive is not source-callable"); } let owner = expression(child(n, 1), 0); if b.types[type_of(owner)].tag != TY_OWNED { fail(FE_TYPE, n, "owned.close requires Owned handle"); } require_effect(EFFECT_RELEASE, 0, n); value = emit(OP_OWNED_CLOSE, unit, [owner], [], 0, n);
            } else if nodes[callee].tag == AstTag.Select && nodes[child(callee, 0)].tag == AstTag.Name && (ast_text(source, nodes[child(callee, 0)]) == "region" || ast_text(source, nodes[child(callee, 0)]) == "env") {
                let namespace_name = ast_text(source, nodes[child(callee, 0)]); let member = ast_text(source, nodes[child(callee, 1)]);
                if member == "try_alloc" {
                    if node.children.count != 3 { fail(FE_TYPE, n, "allocation requires Space and capacity"); } let space = expression(child(n, 1), 0); let st = b.types[type_of(space)]; if st.tag != TY_SPACE { fail(FE_TYPE, n, "allocation requires exclusive Space"); } hold(space); let capacity = expression(child(n, 2), unsigned); var element: u32 = 0;
                    if namespace_name == "region" { if application == 0 || nodes[application].children.count != 2 { fail(FE_KIND, n, "region.try_alloc requires one explicit Plain element type"); } element = resolve_type(child(application, 1)); if !plain(element) { fail(FE_USAGE, n, "array element must be Plain"); } } else if application != 0 { fail(FE_KIND, n, "env.try_alloc has no explicit arguments"); }
                    let dt = intern_type(TypeNode { tag: if namespace_name == "env" { TY_ENV_DEST } else { TY_DEST }, children: if element != 0 { ref_span(b, [element]) } else { Span { .. } }, region: st.region, capacity: term_of(capacity), .. }); let success = product_type([type_of(space), dt]); let error = product_type([type_of(space), storage_error(false)]); require_effect(EFFECT_PLACE, st.region, n); value = emit(if namespace_name == "env" { OP_ENV_TRY_ALLOC } else { OP_TRY_ALLOC }, result_type(success, error), [space, capacity], [], element, n);
                } else if member == "close" && namespace_name == "region" { if node.children.count != 2 || application != 0 { fail(FE_TYPE, n, "region.close requires one owner"); } let owner = expression(child(n, 1), 0); if b.types[type_of(owner)].tag != TY_REGION_OWNER { fail(FE_TYPE, n, "region.close requires RegionOwner"); } require_effect(EFFECT_RELEASE, 0, n); value = emit(OP_REGION_CLOSE, unit, [owner], [], 0, n); }
                else if member == "reset" && namespace_name == "region" { if node.children.count != 2 || application != 0 { fail(FE_TYPE, n, "region.reset requires one owner"); } let owner = expression(child(n, 1), 0); let ot = b.types[type_of(owner)]; if ot.tag != TY_REGION_OWNER { fail(FE_TYPE, n, "region.reset requires RegionOwner"); } require_effect(EFFECT_RESET, ot.region, n); let region = b.binders.len as u32; b.binders.push(Binder { introduction_kind: INTRO_OPERATION, kind: KIND_REGION, scope: b.binders[ot.region].scope, introduction: b.ops.len as u32, name: b.binders[ot.region].name, origin: origin(n), .. }); let owner_type = intern_type(TypeNode { tag: TY_REGION_OWNER, region: region, .. }); let space_type = intern_type(TypeNode { tag: TY_SPACE, region: region, .. }); let sub = b.substitutions.len as u32; b.substitutions.push(Substitution { binder: ot.region, kind: KIND_REGION, value: region }); value = emit(OP_REGION_RESET, product_type([owner_type, space_type]), [owner], [], region, n); b.ops[b.values[value].op].substitutions = ref_span(b, [sub]); for item, i in typebindings { if item.binder == ot.region { typebindings[i].binder = region; } } }
                else { fail(FE_UNSUPPORTED, n, "region intrinsic is not source-callable"); }
            } else if nodes[callee].tag == AstTag.Select && nodes[child(callee, 0)].tag == AstTag.Name && ast_text(source, nodes[child(callee, 0)]) == "U32" {
                let name = ast_text(source, nodes[child(callee, 1)]); var fallible = false; var predicate = false;
                if name == "wrapping_add" { intrinsic = OP_U32_ADD_WRAP; } else if name == "wrapping_sub" { intrinsic = OP_U32_SUB_WRAP; } else if name == "wrapping_mul" { intrinsic = OP_U32_MUL_WRAP; }
                else if name == "fits_add" { intrinsic = OP_ADD_FITS; predicate = true; } else if name == "fits_sub" { intrinsic = OP_SUB_FITS; predicate = true; } else if name == "fits_mul" { intrinsic = OP_MUL_FITS; predicate = true; }
                else if name == "try_add" { intrinsic = OP_CHECKED_ADD; fallible = true; } else if name == "try_sub" { intrinsic = OP_CHECKED_SUB; fallible = true; } else if name == "try_mul" { intrinsic = OP_CHECKED_MUL; fallible = true; } else if name == "try_div" { intrinsic = OP_CHECKED_DIV; fallible = true; } else if name == "try_shift_left" { intrinsic = OP_CHECKED_SHL; fallible = true; } else if name == "try_shift_right" { intrinsic = OP_CHECKED_SHR; fallible = true; }
                else if name == "from_f32" { intrinsic = OP_F32_TO_U32; fallible = true; } else { fail(FE_UNBOUND, n, "unknown U32 intrinsic"); }
                if intrinsic == OP_F32_TO_U32 { if node.children.count != 2 { fail(FE_TYPE, n, "conversion requires one F32"); } value = emit(intrinsic, result_type(unsigned, unit), [expression(child(n, 1), floating)], [], 0, n); }
                else { if node.children.count != 3 { fail(FE_TYPE, n, "intrinsic requires two tuple components"); } let x = expression(child(n, 1), unsigned); let y = expression(child(n, 2), unsigned); value = emit(intrinsic, if fallible { result_type(unsigned, unit) } else if predicate { boolean } else { unsigned }, [x, y], [], 0, n); }
            } else if nodes[callee].tag == AstTag.Select && nodes[child(callee, 0)].tag == AstTag.Name && ast_text(source, nodes[child(callee, 0)]) == "F32" {
                let name = ast_text(source, nodes[child(callee, 1)]); var arity: u32 = 1;
                if name == "sqrt" { intrinsic = OP_F32_SQRT; } else if name == "abs" { intrinsic = OP_F32_ABS; } else if name == "min" { intrinsic = OP_F32_MIN; arity = 2; } else if name == "max" { intrinsic = OP_F32_MAX; arity = 2; } else if name == "ceil" { intrinsic = OP_F32_CEIL; } else if name == "floor" { intrinsic = OP_F32_FLOOR; } else if name == "trunc" { intrinsic = OP_F32_TRUNC; } else if name == "nearest" { intrinsic = OP_F32_NEAREST; } else if name == "from_u32" { intrinsic = OP_U32_TO_F32; } else { fail(FE_UNBOUND, n, "unknown F32 intrinsic"); }
                if node.children.count != arity + 1 { fail(FE_TYPE, n, "wrong F32 intrinsic arity"); } let x = expression(child(n, 1), if intrinsic == OP_U32_TO_F32 { unsigned } else { floating }); if arity == 1 { value = emit(intrinsic, floating, [x], [], 0, n); } else { let y = expression(child(n, 2), floating); value = emit(intrinsic, floating, [x, y], [], 0, n); }
            } else if nodes[callee].tag == AstTag.Select && nodes[child(callee, 0)].tag == AstTag.Name && ast_text(source, nodes[child(callee, 0)]) == "index" && ast_text(source, nodes[child(callee, 1)]) == "try_make" {
                if node.children.count != 3 { fail(FE_TYPE, n, "index.try_make requires view and U32"); } let view = expression(child(n, 1), 0); let position = expression(child(n, 2), unsigned); let vt = b.types[type_of(view)]; if vt.tag != TY_VIEW { fail(FE_TYPE, n, "index.try_make requires immutable View"); } require_effect(EFFECT_READ, vt.region, n); let it = intern_type(TypeNode { tag: TY_INDEX, nat: vt.nat, domain: vt.domain, .. }); value = emit(OP_TRY_INDEX, option_type(it), [view, position], [], 0, n);
            } else if nodes[callee].tag == AstTag.Select && nodes[child(callee, 0)].tag == AstTag.Name && ast_text(source, nodes[child(callee, 0)]) == "builder" && ast_text(source, nodes[child(callee, 1)]) != "discard" {
                let member = ast_text(source, nodes[child(callee, 1)]); if node.children.count < 2 { fail(FE_TYPE, n, "builder primitive needs capability"); } let input = if member == "read" || member == "length" || member == "capacity" { observe_expression(child(n, 1)) } else { expression(child(n, 1), 0) }; let before = b.types[type_of(input)];
                if member == "begin_append" || member == "begin_resize" { if before.tag != TY_DEST || node.children.count != 2 { fail(FE_TYPE, n, "builder begin requires one destination"); } let zero = proof_term(b, work, proof_limits, proof_index, Term { tag: EXPR_LITERAL, type_id: unsigned, .. }); let mode = if member == "begin_append" { MODE_APPEND } else { MODE_RESIZE }; let ty = intern_type(TypeNode { tag: TY_BUILDER, children: before.children, region: before.region, nat: zero, capacity: before.capacity, mode: mode, .. }); value = emit(OP_BUILDER_BEGIN, ty, [input], [], mode, n); }
                else if before.tag != TY_BUILDER { fail(FE_TYPE, n, "builder operation requires exact builder state"); }
                else if member == "append" || member == "try_append" { hold(input);
                    if node.children.count != 3 { fail(FE_TYPE, n, "append requires builder and element"); } let element = expression(child(n, 2), b.refs[before.children.start]); require_effect(EFFECT_WRITE, before.region, n);
                    let one = proof_term(b, work, proof_limits, proof_index, Term { tag: EXPR_LITERAL, type_id: unsigned, literal: 1, .. }); let next = proof_term(b, work, proof_limits, proof_index, Term { tag: EXPR_ADD, type_id: unsigned, args: ref_span(b, [before.nat, one]), scope: current_scope, .. }); var after = before; after.nat = next; let after_type = intern_type(after);
                    if member == "try_append" { let failed = product_type([type_of(input), type_of(element)]); value = emit(OP_BUILDER_TRY_APPEND, result_type(after_type, failed), [input, element], [], 0, n); }
                    else { observation_term(input, EXPR_INIT); observation_term(input, EXPR_CAP); let evidence = proof_query(b, work, proof_limits, proof_index, current_scope, active[active_base..], Fact { tag: FACT_LT, left: before.nat, right: before.capacity, .. }); if evidence == 0 { fail(if work.exhausted { FE_PROOF_LIMIT } else { FE_BOUNDS }, n, "append length is not below capacity"); } value = emit(OP_BUILDER_APPEND, after_type, [input, element], [evidence], 0, n); }
                }
                else if member == "set" { hold(input); if node.children.count != 4 { fail(FE_TYPE, n, "set requires builder,index,value"); } let index = expression(child(n, 2), unsigned); let element = expression(child(n, 3), b.refs[before.children.start]); let evidence = require_bounds(Fact { tag: FACT_LT, left: term_of(index), right: observation_term(input, EXPR_INIT), .. }, n); require_effect(EFFECT_WRITE, before.region, n); value = emit(OP_BUILDER_SET, type_of(input), [input, index, element], [evidence], 0, n); }
                else if member == "truncate" { hold(input); if node.children.count != 3 || before.mode != MODE_RESIZE { fail(FE_TYPE, n, "truncate requires Resize builder and length"); } let length = expression(child(n, 2), unsigned); let evidence = require_bounds(Fact { tag: FACT_LE, left: term_of(length), right: before.nat, .. }, n); var after = before; after.nat = term_of(length); require_effect(EFFECT_WRITE, before.region, n); value = emit(OP_BUILDER_TRUNCATE, intern_type(after), [input, length], [evidence], 0, n); }
                else if member == "read" { if node.children.count != 3 { fail(FE_TYPE, n, "builder.read requires index"); } let index = expression(child(n, 2), unsigned); value = collection_read(input, index, n); }
                else if member == "length" || member == "capacity" { if node.children.count != 2 { fail(FE_TYPE, n, "observation requires one builder"); } value = emit(if member == "length" { OP_BUILDER_LEN } else { OP_BUILDER_CAP }, unsigned, [input], [], 0, n); }
                else if member == "freeze" { if node.children.count != 2 { fail(FE_TYPE, n, "freeze requires one builder"); } let domain = b.binders.len as u32; b.binders.push(Binder { introduction_kind: INTRO_OPERATION, kind: KIND_DOMAIN, scope: current_scope, introduction: b.ops.len as u32, origin: origin(n), .. }); let vt = intern_type(TypeNode { tag: TY_VIEW, children: before.children, region: before.region, nat: before.nat, domain: domain, .. }); let package = intern_type(TypeNode { tag: TY_EXISTS, children: ref_span(b, [vt]), binders: ref_span(b, [domain]), .. }); value = emit(OP_BUILDER_FREEZE, package, [input], [], 0, n); }
                else { fail(FE_UNSUPPORTED, n, "builder primitive producer is not completed"); }
            } else if nodes[callee].tag == AstTag.Select && nodes[child(callee, 0)].tag == AstTag.Name && ast_text(source, nodes[child(callee, 0)]) == "dest" && ast_text(source, nodes[child(callee, 1)]) == "split" {
                if node.children.count != 3 { fail(FE_TYPE, n, "dest.split requires destination and prefix capacity"); } let dest = expression(child(n, 1), 0); let dt = b.types[type_of(dest)]; if dt.tag != TY_DEST { fail(FE_TYPE, n, "dest.split requires destination"); } hold(dest); let count = expression(child(n, 2), unsigned); let length = term_of(count); let evidence = require_bounds(Fact { tag: FACT_LE, left: length, right: dt.capacity, .. }, n); let suffix = proof_term(b, work, proof_limits, proof_index, Term { tag: EXPR_SUB, type_id: unsigned, args: ref_span(b, [dt.capacity, length]), scope: current_scope, .. }); var a = dt; var z = dt; a.capacity = length; z.capacity = suffix; value = emit(OP_DEST_SPLIT, product_type([intern_type(a), intern_type(z)]), [dest, count], [evidence], 0, n);
            } else if nodes[callee].tag == AstTag.Select && nodes[child(callee, 0)].tag == AstTag.Name && ast_text(source, nodes[child(callee, 0)]) == "view" {
                let member = ast_text(source, nodes[child(callee, 1)]); if node.children.count < 2 { fail(FE_TYPE, n, "view primitive requires View"); } let view = expression(child(n, 1), 0); let vt = b.types[type_of(view)]; if vt.tag != TY_VIEW { fail(FE_TYPE, n, "view primitive requires immutable View"); }
                if member == "length" { if node.children.count != 2 { fail(FE_TYPE, n, "view.length takes one View"); } value = emit(OP_VIEW_LEN, unsigned, [view], [], 0, n); }
                else if member == "slice" { if node.children.count != 4 { fail(FE_TYPE, n, "view.slice requires start,count"); } let start = expression(child(n, 2), unsigned); let count = expression(child(n, 3), unsigned); let a = require_bounds(Fact { tag: FACT_LE, left: term_of(start), right: vt.nat, .. }, n); let remaining = proof_term(b, work, proof_limits, proof_index, Term { tag: EXPR_SUB, type_id: unsigned, args: ref_span(b, [vt.nat, term_of(start)]), scope: current_scope, .. }); let z = require_bounds(Fact { tag: FACT_LE, left: term_of(count), right: remaining, .. }, n); let domain = b.binders.len as u32; b.binders.push(Binder { introduction_kind: INTRO_OPERATION, kind: KIND_DOMAIN, scope: current_scope, introduction: b.ops.len as u32, origin: origin(n), .. }); var sliced = vt; sliced.nat = term_of(count); sliced.domain = domain; let package = intern_type(TypeNode { tag: TY_EXISTS, children: ref_span(b, [intern_type(sliced)]), binders: ref_span(b, [domain]), .. }); value = emit(OP_VIEW_SLICE, package, [view, start, count], [a, z], 0, n); }
                else if member == "read" { if node.children.count != 3 { fail(FE_TYPE, n, "view.read requires index"); } let index = expression(child(n, 2), 0); value = collection_read(view, index, n); }
                else if member == "try_read" {
                    if node.children.count != 3 { fail(FE_TYPE, n, "view.try_read requires raw U32 index"); } let index = expression(child(n, 2), unsigned); require_effect(EFFECT_READ, vt.region, n); let length = emit(OP_VIEW_LEN, unsigned, [view], [], 0, n); let condition = emit(OP_U32_LT, boolean, [index, length], [], 0, n); let result_type = option_type(b.refs[vt.children.start]);
                    let from = current_block; let yes = new_block(); let no = new_block(); let snapshot = save_bindings(); let ey = flow_edge(from, yes, EDGE_TRUE, [], n); restore_bindings(snapshot); let en = flow_edge(from, no, EDGE_FALSE, [], n); restore_bindings(snapshot); terminate(TERM_BRANCH, condition, [ey, en], n); let facts_mark = active.len; var target = FrontTarget { type_id: result_type, scope: current_scope, binding_limit: bindings.len as u32, .. };
                    current_block = yes; flow_bindings(yes, 0); branch_facts(condition, ey, true); let evidence = require_fact(Fact { tag: FACT_LT, left: term_of(index), right: term_of(length), .. }, n); let element = emit(OP_VIEW_INDEX, b.refs[vt.children.start], [view, index], [evidence], 0, n); let some = emit(OP_SUM, result_type, [element], [], 1, n); exit_value(target, some, n);
                    active.resize(facts_mark); restore_bindings(snapshot); current_block = no; flow_bindings(no, 0); let empty = emit(OP_UNIT, unit, [], [], 0, n); let none = emit(OP_SUM, result_type, [empty], [], 0, n); exit_value(target, none, n); restore_bindings(snapshot); snapshots.resize(snapshot.start); current_block = target.block_id; enter_join(target); b.blocks[from].merge = target.block_id; value = target.value;
                } else { fail(FE_UNBOUND, n, "unknown View intrinsic"); }
            } else if nodes[callee].tag == AstTag.Select && nodes[child(callee, 0)].tag == AstTag.Name && (ast_text(source, nodes[child(callee, 0)]) == "dest" || ast_text(source, nodes[child(callee, 0)]) == "builder" || ast_text(source, nodes[child(callee, 0)]) == "space") {
                let namespace_name = ast_text(source, nodes[child(callee, 0)]); let member = ast_text(source, nodes[child(callee, 1)]);
                if node.children.count != 2 || (member != "discard" && !(namespace_name == "space" && member == "end")) { fail(FE_UNSUPPORTED, n, "storage primitive producer is not completed"); }
                let arg = expression(child(n, 1), 0); let tag = b.types[type_of(arg)].tag; let wanted = if namespace_name == "dest" { TY_DEST } else if namespace_name == "builder" { TY_BUILDER } else { TY_SPACE };
                if tag != wanted { fail(FE_TYPE, n, "terminal operation requires its exact capability"); }
                value = emit(if wanted == TY_DEST { OP_DEST_DISCARD } else if wanted == TY_BUILDER { OP_BUILDER_DISCARD } else { OP_SPACE_END }, unit, [arg], [], 0, n);
            } else {
                var indirect: u32 = 0; var contract_id: u32 = 0;
                if application != 0 && nodes[callee].tag == AstTag.Name && local_generic(add_name(b, ast_text(source, nodes[callee])), n, false) != 0 { indirect = expression(application, 0); application = 0; }
                else if nodes[callee].tag == AstTag.Name { let name = add_name(b, ast_text(source, nodes[callee])); var local = false; for binding, i in bindings { if i >= binding_base && binding.name == name { local = true; } } if !local && lambda_outer_base >= 0 { local = captured_value(name, callee) != 0; } if local { indirect = expression(callee, 0); } else { indirect = static_named(name, callee); if indirect == 0 { fid = lookup_function(name, n); } } }
                else if nodes[callee].tag == AstTag.Select { var imported = false; if nodes[child(callee, 0)].tag == AstTag.Name { let alias = add_name(b, ast_text(source, nodes[child(callee, 0)])); for item in imports { if item.name == alias { imported = true; } } } if imported { let definition = imported_definition(callee, DEF_FUNCTION); if b.definitions[definition].kind == DEF_STATIC { indirect = expression(callee, 0); } else { fid = b.definitions[definition].function; } } else { indirect = expression(callee, 0); } }
                else { indirect = expression(callee, 0); }
                if indirect != 0 { if b.types[type_of(indirect)].tag != TY_FN { fail(FE_TYPE, n, "indirect call requires callable value"); } contract_id = b.types[type_of(indirect)].contract; } else { contract_id = b.functions[fid].contract; }
                if indirect != 0 { hold(indirect); } let contract = b.contracts[contract_id]; var substitutions = Span { .. }; var arg_type = contract.arg; var result_type = contract.result;
                if contract.binders.count != 0 { if application == 0 { fail(FE_INTERFACE, n, "generic call requires explicit type arguments"); } substitutions = make_substitutions(contract.binders, application, 1); arg_type = substitute_type(contract.arg, substitutions, 0); result_type = substitute_type(contract.result, substitutions, 0); work.interface_instantiations++; }
                else if application != 0 { fail(FE_KIND, n, "nongeneric callable does not take type arguments"); }
                var arg: u32 = 0;
                if node.children.count == 1 { arg = emit(OP_UNIT, unit, [], [], 0, n); }
                else if node.children.count == 2 { arg = expression(child(n, 1), arg_type); }
                else { let mark = temporaries.len; let ty = b.types[arg_type]; if ty.tag != TY_TUPLE || ty.fields.count != node.children.count - 1 { fail(FE_TYPE, n, "call supplies one incompatible tuple"); } for i in 1..node.children.count { let component = expression(child(n, i), b.fields[b.refs[ty.fields.start + i - 1]].type_id); hold(component); temporaries.push(component); } arg = emit(OP_TUPLE, arg_type, temporaries[mark..], [], 0, n); temporaries.resize(mark); }
                exact(arg, arg_type, n); if current_block == 0 { return 0; }
                let required = contract_proofs(contract.requires, arg, 0, substitutions, n); if indirect != 0 { value = emit(OP_CALL_INDIRECT, result_type, [indirect, arg], b.refs[required.start..required.start + required.count], 0, n); } else { value = emit(OP_CALL, result_type, [arg], b.refs[required.start..required.start + required.count], fid, n); } b.ops[b.values[value].op].substitutions = substitutions; let call_id = b.calls.len as u32; b.calls.push(Call { op: b.values[value].op, caller: current_function, callee: fid, contract: contract_id, substitutions: substitutions, .. }); b.functions[current_function].calls = append_reference(b.functions[current_function].calls, call_id); assume_contract(contract.ensures, contract_id, arg, value, b.values[value].op, 0, n); for i in contract.effects.count { let effect = b.effects[b.refs[contract.effects.start + i]]; require_effect(effect.kind, substituted_identity(effect.region, KIND_REGION, substitutions), n); }
                if contract.depth > max_callee_depth { max_callee_depth = contract.depth; } if contract.frame > max_callee_frame { max_callee_frame = contract.frame; }
            }
        }
        else if node.tag == AstTag.For {
            let lower = expression(child(n, 1), unsigned); let upper = expression(child(n, 2), unsigned); let bound = require_fact(Fact { tag: FACT_LE, left: term_of(lower), right: term_of(upper), .. }, n);
            let carries = node.children.count - 5; let carry_mark = temporaries.len; temporaries.push(lower);
            for i in carries { let initial = expression(child(child(n, i + 3), 0), 0); hold(initial); temporaries.push(initial); }
            for i in carry_mark..temporaries.len { let original = temporaries[i]; temporaries[i] = refresh(original); release_held(original); } let explicit_initial = ref_span(b, temporaries[carry_mark..]); temporaries.resize(carry_mark); for binding, i in bindings { if i >= binding_base && !binding.moved && !share(binding.type_id) { temporaries.push(i as u32); } } let hidden_indices = ref_span(b, temporaries[carry_mark..]); temporaries.resize(carry_mark);
            for i in explicit_initial.count { temporaries.push(b.refs[explicit_initial.start + i]); } for i in hidden_indices.count { temporaries.push(bindings[b.refs[hidden_indices.start + i]].value); }
            let total_carries = carries + hidden_indices.count; let initial = ref_span(b, temporaries[carry_mark..]); temporaries.resize(carry_mark); let from = current_block; let loop_scope = current_scope; let header = new_block(); let body = new_block(); let exit_block = new_block(); let iteration_scope = b.scopes.len as u32; b.scopes.push(Scope { parent: loop_scope, kind: SCOPE_BLOCK, origin: origin(n), .. }); b.blocks[body].scope = iteration_scope;
            let parameter_mark = temporaries.len;
            for i in initial.count { temporaries.push(loop_parameter(b.refs[initial.start + i], header)); }
            let params = ref_span(b, temporaries[parameter_mark..]); temporaries.resize(parameter_mark); b.blocks[header].params = params;
            for i in initial.count { temporaries.push(loop_parameter(b.refs[initial.start + i], exit_block)); }
            let exit_params = ref_span(b, temporaries[parameter_mark..]); temporaries.resize(parameter_mark); b.blocks[exit_block].params = exit_params; b.blocks[header].merge = exit_block;
            let index = b.refs[params.start]; let loop_id = b.loops.len as u32;
            b.loops.push(Loop { header: header, body: body, exit: exit_block, index: index, lower: term_of(lower), upper: term_of(upper), carries: ref_span(b, b.refs[params.start + 1..params.start + params.count]), .. });
            let binding_mark = bindings.len; let facts_mark = active.len; let saved_lexical = lexical_base; lexical_base = binding_mark; bind(child(n, 0), index);
            for i in hidden_indices.count { let bi = b.refs[hidden_indices.start + i]; bindings[bi].value = b.refs[params.start + 1 + carries + i]; }
            for i in carries { let carry = child(n, i + 3); bind(carry, b.refs[params.start + i + 1]); }
            current_block = header; let invariant_node = child(n, node.children.count - 2);
            if invariant_node != 0 { for i in nodes[invariant_node].children.count { let fact = local_fact(child(invariant_node, i)); let ev = proof_evidence(b, work, proof_limits, proof_index, fact, RULE_LOOP_INVARIANT, current_scope, 0, b.refs[params.start..params.start + params.count], []); if ev == 0 { fail(FE_PROOF_LIMIT, n, "loop invariant evidence budget"); } b.loops[loop_id].invariant = append_reference(b.loops[loop_id].invariant, ev); } }
            current_block = from; let entry_proofs = loop_edge_proofs(loop_id, params, initial, n); let entry = edge(from, header, EDGE_LOOP_ENTRY, b.refs[initial.start..initial.start + initial.count]); b.edges[entry].loop_id = loop_id; b.edges[entry].evidence = append_reference(entry_proofs, bound); terminate(TERM_JUMP, 0, [entry], n);
            current_block = header; let invariants = b.loops[loop_id].invariant; for i in invariants.count { active.push(b.refs[invariants.start + i]); }
            let lower_fact = proof_evidence(b, work, proof_limits, proof_index, Fact { tag: FACT_LE, left: term_of(lower), right: term_of(index), .. }, RULE_LOOP_RANGE, current_scope, 0, [index], []);
            let upper_fact = proof_evidence(b, work, proof_limits, proof_index, Fact { tag: FACT_LE, left: term_of(index), right: term_of(upper), .. }, RULE_LOOP_RANGE, current_scope, 0, [index], []); active.push(lower_fact); active.push(upper_fact);
            let body_mark = temporaries.len; for i in total_carries { temporaries.push(loop_parameter(b.refs[params.start + i + 1], body)); } let body_params = ref_span(b, temporaries[body_mark..]); temporaries.resize(body_mark); b.blocks[body].params = body_params;
            let condition = emit(OP_U32_LT, boolean, [index, upper], [], 0, n); let yes = edge(header, body, EDGE_TRUE, b.refs[params.start + 1..params.start + params.count]); let no = edge(header, exit_block, EDGE_FALSE, b.refs[params.start..params.start + params.count]); b.edges[yes].loop_id = loop_id; b.edges[no].loop_id = loop_id; b.loops[loop_id].exits = ref_span(b, [no]); terminate(TERM_BRANCH, condition, [yes, no], n);
            let header_facts = active.len; current_block = body; current_scope = iteration_scope; open_scopes.push(iteration_scope); branch_facts(condition, yes, true);
            let body_sub_mark = temporaries.len; temporaries.push(index); for i in total_carries { temporaries.push(b.refs[body_params.start + i]); if i < carries { bindings[binding_mark + 1 + i].value = b.refs[body_params.start + i]; bindings[binding_mark + 1 + i].type_id = type_of(b.refs[body_params.start + i]); } else { let bi = b.refs[hidden_indices.start + i - carries]; bindings[bi].value = b.refs[body_params.start + i]; bindings[bi].type_id = type_of(b.refs[body_params.start + i]); } }
            let body_substitution = ref_span(b, temporaries[body_sub_mark..]); temporaries.resize(body_sub_mark);
            if body_params.count != 0 { for i in invariants.count { let premise = b.refs[invariants.start + i]; let fact = rename_fact(b.facts[b.evidence[premise].fact], params, body_substitution); let joined = proof_evidence(b, work, proof_limits, proof_index, fact, RULE_JOIN, current_scope, 0, b.refs[body_params.start..body_params.start + body_params.count], [premise]); active.push(joined); } }

            loop_stack.push(FrontLoop { id: loop_id, node: n, index: index, upper_value: upper, header_params: params, exit_params: exit_params, carries: carries, hidden_indices: hidden_indices });
            check_suite(child(n, node.children.count - 1)); if current_block != 0 { fail(FE_RETURN, n, "loop body requires explicit next, stop, continue or break"); } loop_stack.resize(loop_stack.len - 1);
            open_scopes.resize(open_scopes.len - 1); current_scope = loop_scope; lexical_base = saved_lexical; active.resize(header_facts); current_block = header; branch_facts(condition, no, false);
            let natural = proof_evidence(b, work, proof_limits, proof_index, Fact { tag: FACT_EQ, left: term_of(index), right: term_of(upper), .. }, RULE_LOOP_RANGE, current_scope, no, [index], []); b.edges[no].evidence = append_reference(b.edges[no].evidence, natural);
            for i in invariants.count { b.edges[no].evidence = append_reference(b.edges[no].evidence, b.refs[invariants.start + i]); }
            bindings.resize(binding_mark); for i in hidden_indices.count { let bi = b.refs[hidden_indices.start + i]; bindings[bi].value = b.refs[exit_params.start + carries + 1 + i]; bindings[bi].type_id = type_of(bindings[bi].value); bindings[bi].moved = false; } active.resize(facts_mark); current_block = exit_block;
            let exits = b.loops[loop_id].exits;
            for i in invariants.count { let original = b.facts[b.evidence[b.refs[invariants.start + i]].fact]; let joined_fact = rename_fact(original, params, exit_params); let mark = temporaries.len;
                for j in exits.count { let eid = b.refs[exits.start + j]; let wanted = rename_fact(joined_fact, exit_params, b.edges[eid].args); var found: u32 = 0; let proofs = b.edges[eid].evidence; for k in proofs.count { let ev = b.refs[proofs.start + k]; if proof_fact_equal(b.facts[b.evidence[ev].fact], wanted) { found = ev; } } if found == 0 { fail(FE_CONTRACT, n, "exit invariant evidence missing"); } temporaries.push(found); }
                let joined = proof_evidence(b, work, proof_limits, proof_index, joined_fact, RULE_JOIN, current_scope, 0, b.refs[exit_params.start..exit_params.start + exit_params.count], temporaries[mark..]); temporaries.resize(mark); active.push(joined);
            }
            if exits.count == 1 { let fact = Fact { tag: FACT_EQ, left: term_of(b.refs[exit_params.start]), right: term_of(upper), .. }; active.push(proof_evidence(b, work, proof_limits, proof_index, fact, RULE_JOIN, current_scope, 0, [b.refs[exit_params.start]], [natural])); }
            if carries == 0 { value = emit(OP_UNIT, unit, [], [], 0, n); }
            else if carries == 1 { value = b.refs[exit_params.start + 1]; }
            else { let mark = temporaries.len; for i in carries { let id = b.fields.len as u32; b.fields.push(Field { type_id: type_of(b.refs[exit_params.start + i + 1]), .. }); temporaries.push(id); } let ty = intern_type(TypeNode { tag: TY_TUPLE, fields: ref_span(b, temporaries[mark..]), .. }); temporaries.resize(mark); value = emit(OP_TUPLE, ty, b.refs[exit_params.start + 1..exit_params.start + 1 + carries], [], 0, n); }
        }
        else if node.tag == AstTag.ValueDo {
            let previous_scope = current_scope; current_scope = b.scopes.len as u32; let scope = current_scope; b.scopes.push(Scope { parent: previous_scope, kind: SCOPE_BLOCK, origin: origin(n), .. }); let body = new_block(); let entrance = flow_edge(current_block, body, EDGE_NORMAL, [], n); terminate(TERM_JUMP, 0, [entrance], n); current_block = body;
            let target_index = targets.len; targets.push(FrontTarget { type_id: expected, scope: previous_scope, binding_limit: bindings.len as u32, .. }); open_scopes.push(scope); check_suite(child(n, 0));
            if current_block != 0 { fail(FE_RETURN, n, "value block requires break value on every normal path"); }
            let target = targets[target_index]; targets.resize(target_index); open_scopes.resize(open_scopes.len - 1); current_scope = previous_scope; if target.incoming == 0 { return 0; } current_block = target.block_id; enter_join(target); value = target.value;
        }
        else { fail(FE_UNSUPPORTED, n, "expression family has no completed semantic producer yet"); }
        return exact(value, expected, n);
    }
    fn branch_facts(condition: u32, edge_id: u32, truth: bool) { boolean_facts(condition, edge_id, truth, condition, truth); }
    recursive fn boolean_facts(condition: u32, edge_id: u32, truth: bool, outer: u32, outer_truth: bool) {
        var selected = condition; var v = b.values[selected]; var normalized_truth = truth; let actual_truth = truth; var op = Operation { .. };
        for unwrap in 64 { if v.op == 0 { break; } op = b.ops[v.op]; if op.tag != OP_BOOL_NOT || op.args.count != 1 { break; } normalized_truth = !normalized_truth; selected = b.refs[op.args.start]; v = b.values[selected]; }
        for logical in booleans { if logical.value == selected { if logical.conjunction && normalized_truth || !logical.conjunction && !normalized_truth { boolean_facts(logical.left, edge_id, normalized_truth, outer, outer_truth); boolean_facts(logical.right, edge_id, normalized_truth, outer, outer_truth); } return; } }
        if v.op == 0 { return; } op = b.ops[v.op];
        if op.tag == OP_CALL || op.tag == OP_CALL_INDIRECT { let contract = if op.tag == OP_CALL { b.functions[op.imm0].contract } else { b.types[type_of(b.refs[op.args.start])].contract }; let ct = b.contracts[contract]; assume_contract(if normalized_truth { ct.on_true } else { ct.on_false }, contract, b.refs[op.args.start + (if op.tag == OP_CALL { 0 } else { 1 })], b.refs[op.results.start], v.op, edge_id, current_decl); return; }
        if op.args.count != 2 { return; }
        let x = b.refs[op.args.start]; let y = b.refs[op.args.start + 1]; if type_of(x) != unsigned || type_of(y) != unsigned { return; }
        var fact = Fact { left: term_of(x), right: term_of(y), .. };
        if op.tag == OP_U32_LT { fact.tag = if normalized_truth { FACT_LT } else { FACT_LE }; if !normalized_truth { let t = fact.left; fact.left = fact.right; fact.right = t; } }
        else if op.tag == OP_U32_LE { fact.tag = if normalized_truth { FACT_LE } else { FACT_LT }; if !normalized_truth { let t = fact.left; fact.left = fact.right; fact.right = t; } }
        else if op.tag == OP_U32_GT { fact.tag = if normalized_truth { FACT_LT } else { FACT_LE }; if normalized_truth { let t = fact.left; fact.left = fact.right; fact.right = t; } }
        else if op.tag == OP_U32_GE { fact.tag = if normalized_truth { FACT_LE } else { FACT_LT }; if normalized_truth { let t = fact.left; fact.left = fact.right; fact.right = t; } }
        else if (op.tag == OP_U32_EQ && normalized_truth) || (op.tag == OP_U32_NE && !normalized_truth) { fact.tag = FACT_EQ; }
        else if (op.tag == OP_U32_NE && normalized_truth) || (op.tag == OP_U32_EQ && !normalized_truth) {
            let left = b.terms[fact.left]; let right = b.terms[fact.right];
            if left.tag == EXPR_LITERAL && left.literal == 0 { fact.tag = FACT_LT; }
            else if right.tag == EXPR_LITERAL && right.literal == 0 { fact.tag = FACT_LT; let t = fact.left; fact.left = fact.right; fact.right = t; }
            else if right.tag == EXPR_LITERAL && right.literal == 4294967295 { fact.tag = FACT_LT; }
            else if left.tag == EXPR_LITERAL && left.literal == 4294967295 { fact.tag = FACT_LT; let t = fact.left; fact.left = fact.right; fact.right = t; }
        }
        else if !normalized_truth && op.tag == OP_SUB_FITS { fact.tag = FACT_LT; }
        else if !normalized_truth && op.tag == OP_ADD_FITS { fact.tag = FACT_LT; fact.left = proof_term(b, work, proof_limits, proof_index, Term { tag: EXPR_MAX_MINUS, type_id: unsigned, args: ref_span(b, [fact.left]), scope: current_scope, .. }); }
        else if normalized_truth && op.tag == OP_ADD_FITS { fact.tag = FACT_ADD_FITS; }
        else if normalized_truth && op.tag == OP_SUB_FITS { fact.tag = FACT_SUB_FITS; }
        else if normalized_truth && op.tag == OP_MUL_FITS { fact.tag = FACT_MUL_FITS; }
        if fact.tag != 0 { let rule = if outer != condition { RULE_BOOL_PATH } else if actual_truth { RULE_COMPARE_TRUE } else { RULE_COMPARE_FALSE }; let mark = temporaries.len; temporaries.push(outer); if rule == RULE_BOOL_PATH { temporaries.push(condition); } let e = proof_evidence(b, work, proof_limits, proof_index, fact, rule, current_scope, edge_id, temporaries[mark..], []); temporaries.resize(mark); if e == 0 { fail(FE_PROOF_LIMIT, current_decl, "edge proof budget exhausted"); } active.push(e); b.edges[edge_id].evidence = append_reference(b.edges[edge_id].evidence, e); }
    }
    fn exit_value(target: FrontTarget&, value: u32, n: u32) {
        if target.value == 0 { let previous_scope = current_scope; current_scope = target.scope; target.block_id = new_block(); current_scope = previous_scope; let id = b.values.len as u32; let ty = type_of(value); b.values.push(Value { type_id: ty, block_id: target.block_id, version: id, scope: target.scope, .. }); target.value = id; target.type_id = ty; b.blocks[target.block_id].params = ref_span(b, [id]); }
        check_escape(value, target.scope, n);
        for i in target.binding_limit..bindings.len { let binding = bindings[i]; if !binding.moved && !share(binding.type_id) { fail(FE_OWNERSHIP, n, "scope transfer loses a local affine capability"); } }
        let result = exact(value, target.type_id, n); let e = join_values(target, [result], n); terminate(TERM_JUMP, 0, [e], n);
    }
    fn save_bindings() -> Span { let span = Span { start: snapshots.len as u32, count: bindings.len as u32 }; for item in bindings { snapshots.push(item); } return span; }
    fn restore_bindings(span: Span) { bindings.resize(span.count); for i in span.count { bindings[i] = snapshots[span.start + i]; } }
    fn flow_bindings(block_id: u32, prefix: u32) {
        let params = b.blocks[block_id].params; var index = prefix; for binding, i in bindings { if i >= binding_base && !binding.moved && !share(binding.type_id) { bindings[i].value = b.refs[params.start + index]; index++; } }
    }
    fn checked_case_facts(subject: u32, payload: u32, variant: u32, eid: u32, n: u32) {
        if variant != 0 || b.values[subject].op == 0 { return; } let op = b.ops[b.values[subject].op]; if op.args.count != 2 || (op.tag != OP_CHECKED_ADD && op.tag != OP_CHECKED_SUB && op.tag != OP_CHECKED_MUL && op.tag != OP_CHECKED_DIV && op.tag != OP_CHECKED_SHL && op.tag != OP_CHECKED_SHR) { return; } let lhs = b.refs[op.args.start]; let rhs = b.refs[op.args.start + 1]; var fact = Fact { left: term_of(lhs), right: term_of(rhs), .. };
        if op.tag == OP_CHECKED_ADD { fact.tag = FACT_ADD_FITS; } else if op.tag == OP_CHECKED_SUB { fact.tag = FACT_SUB_FITS; } else if op.tag == OP_CHECKED_MUL { fact.tag = FACT_MUL_FITS; }
        else if op.tag == OP_CHECKED_DIV { fact.tag = FACT_LT; fact.left = proof_term(b, work, proof_limits, proof_index, Term { tag: EXPR_LITERAL, type_id: unsigned, .. }); }
        else if op.tag == OP_CHECKED_SHL || op.tag == OP_CHECKED_SHR { fact.tag = FACT_LT; fact.left = term_of(rhs); fact.right = proof_term(b, work, proof_limits, proof_index, Term { tag: EXPR_LITERAL, type_id: unsigned, literal: 32, .. }); } else { return; }
        let evidence = proof_evidence(b, work, proof_limits, proof_index, fact, RULE_CHECKED_SUCCESS, current_scope, eid, [subject, payload], []); if evidence == 0 { fail(FE_PROOF_LIMIT, n, "checked-result success fact limit"); } active.push(evidence); b.edges[eid].evidence = append_reference(b.edges[eid].evidence, evidence);
    }
    fn scalar_pattern(pattern: u32, ty: u32) -> u32 {
        let node = nodes[pattern]; if ty == boolean { let name = ast_text(source, node); if node.tag != AstTag.Variant || (name != "True" && name != "False") || child(pattern, 0) != 0 { fail(FE_CASE, pattern, "Bool case requires nullary Bool constructors"); } return if name == "True" { 1 } else { 0 }; }
        if ty == unsigned && node.tag == AstTag.Integer { return node.bits as u32; }
        if ty == floating && node.tag == AstTag.Float { let bits, ok = parse_decimal_f32(ast_text(source, node)); if ok { return bits; } }
        if ty == floating && node.tag == AstTag.Unary && ast_text(source, node) == "-" && nodes[child(pattern, 0)].tag == AstTag.Float { let bits, ok = parse_decimal_f32(ast_text(source, nodes[child(pattern, 0)])); if ok { return bits ^ 2147483648; } }
        fail(FE_CASE, pattern, "case literal must have subject scalar type"); return 0;
    }
    recursive fn scalar_case(n: u32, subject: u32) {
        let ty = type_of(subject); let count = nodes[n].children.count; let root_block = current_block; let binding_mark = bindings.len; let facts_mark = active.len; var seen_bool: u32 = 0; var wildcard_seen = false;
        var joined = FrontTarget { scope: current_scope, binding_limit: binding_mark as u32, .. };
        for index in 1..count {
            let arm = child(n, index); let pat = child(arm, 0); let wildcard = nodes[pat].tag == AstTag.Name && ast_text(source, nodes[pat]) == "_";
            if wildcard { if index + 1 != count { fail(FE_CASE, pat, "wildcard must be last"); } wildcard_seen = true; check_suite(child(arm, 1)); if current_block != 0 { if joined.block_id == 0 { joined.block_id = new_block(); } let e = join_values(joined, [], n); terminate(TERM_JUMP, 0, [e], n); } break; }
            let bits = scalar_pattern(pat, ty); for prior in 1..index { let prior_pat = child(child(n, prior), 0); let prior_bits = scalar_pattern(prior_pat, ty); if prior_bits == bits || ty == floating && (prior_bits & 2147483647) == 0 && (bits & 2147483647) == 0 { fail(FE_CASE, pat, "overlapping scalar patterns"); } }
            if ty == boolean { seen_bool |= 1 << bits; if seen_bool == 3 { if index + 1 != count { fail(FE_CASE, pat, "arm after exhaustive Bool alternatives"); } check_suite(child(arm, 1)); if current_block != 0 { if joined.block_id == 0 { joined.block_id = new_block(); } let e = join_values(joined, [], n); terminate(TERM_JUMP, 0, [e], n); } break; } }
            let literal = emit(if ty == floating { OP_F32 } else if ty == boolean { OP_BOOL } else { OP_U32 }, ty, [], [], bits, pat);
            let condition = if ty == boolean { if bits == 1 { subject } else { emit(OP_BOOL_NOT, boolean, [subject], [], 0, pat) } } else { emit(if ty == floating { OP_F32_EQ } else { OP_U32_EQ }, boolean, [subject, literal], [], 0, pat) };
            let from = current_block; let yes = new_block(); let no = new_block(); let snapshot = save_bindings(); let ey = flow_edge(from, yes, EDGE_TRUE, [], n); restore_bindings(snapshot); let en = flow_edge(from, no, EDGE_FALSE, [], n); restore_bindings(snapshot); terminate(TERM_BRANCH, condition, [ey, en], n);
            current_block = yes; flow_bindings(yes, 0); branch_facts(condition, ey, true); check_suite(child(arm, 1)); if current_block != 0 { if joined.block_id == 0 { joined.block_id = new_block(); } let e = join_values(joined, [], n); terminate(TERM_JUMP, 0, [e], n); }
            bindings.resize(binding_mark); active.resize(facts_mark); restore_bindings(snapshot); snapshots.resize(snapshot.start); current_block = no; flow_bindings(no, 0); branch_facts(condition, en, false); b.blocks[from].merge = joined.block_id;
            if ty == boolean && seen_bool == 3 { if index + 1 != count { fail(FE_CASE, pat, "arm after exhaustive Bool alternatives"); } terminate(TERM_UNREACHABLE, 0, [], n); }
        }
        if !wildcard_seen && !(ty == boolean && seen_bool == 3) { fail(FE_CASE, n, "U32/F32 cases require final wildcard"); }
        active.resize(facts_mark); current_block = joined.block_id; if joined.incoming != 0 { enter_join(joined); } b.blocks[root_block].merge = joined.block_id;
    }
    fn flow_edge(from: u32, to: u32, kind: u32, prefix: const u32[:], n: u32) -> u32 {
        let mark = temporaries.len; for value in prefix { temporaries.push(value); } let original = temporaries.len;
        for binding, i in bindings { if i >= binding_base && !binding.moved && !share(binding.type_id) { temporaries.push(binding.value); } }
        let args = ref_span(b, temporaries[mark..]); temporaries.resize(mark);
        for value in prefix { let id = b.values.len as u32; b.values.push(Value { type_id: type_of(value), block_id: to, version: id, scope: b.blocks[to].scope, origin: origin(n), .. }); temporaries.push(id); }
        for binding, i in bindings { if i >= binding_base && !binding.moved && !share(binding.type_id) { let id = b.values.len as u32; b.values.push(Value { type_id: binding.type_id, block_id: to, version: id, scope: b.blocks[to].scope, origin: origin(n), .. }); bindings[i].value = id; temporaries.push(id); } }
        b.blocks[to].params = ref_span(b, temporaries[mark..]); temporaries.resize(mark); return edge(from, to, kind, b.refs[args.start..args.start + args.count]);
    }
    fn join_values(target: FrontTarget&, prefix: const u32[:], n: u32) -> u32 {
        let mark = temporaries.len;
        if target.incoming == 0 {
            for i in binding_base..target.binding_limit { let binding = bindings[i]; if !binding.moved && !share(binding.type_id) { temporaries.push(i as u32); } }
            target.carry_indices = ref_span(b, temporaries[mark..]); temporaries.resize(mark);
            for i in target.carry_indices.count { let binding = bindings[b.refs[target.carry_indices.start + i]]; let id = b.values.len as u32; b.values.push(Value { type_id: binding.type_id, block_id: target.block_id, version: id, scope: target.scope, origin: origin(n), .. }); temporaries.push(id); }
            target.carry_values = ref_span(b, temporaries[mark..]); temporaries.resize(mark);
            let old = b.blocks[target.block_id].params; for i in old.count { temporaries.push(b.refs[old.start + i]); } for i in target.carry_values.count { temporaries.push(b.refs[target.carry_values.start + i]); } b.blocks[target.block_id].params = ref_span(b, temporaries[mark..]); temporaries.resize(mark);
        }
        for i in binding_base..target.binding_limit { let binding = bindings[i]; if share(binding.type_id) { continue; } var carried = false; for j in target.carry_indices.count { if b.refs[target.carry_indices.start + j] == i { carried = true; } } if carried == binding.moved { fail(FE_OWNERSHIP, n, "control-flow paths must agree on affine ownership"); } }
        for value in prefix { temporaries.push(value); }
        for i in target.carry_indices.count { let binding = bindings[b.refs[target.carry_indices.start + i]]; let ty = type_of(b.refs[target.carry_values.start + i]); temporaries.push(exact(binding.value, ty, n)); }
        let eid = edge(current_block, target.block_id, EDGE_NORMAL, temporaries[mark..]); temporaries.resize(mark); target.incoming++; return eid;
    }
    fn enter_join(target: FrontTarget) {
        for i in binding_base..target.binding_limit { if !share(bindings[i].type_id) { bindings[i].moved = true; } }
        for i in target.carry_indices.count { let at = b.refs[target.carry_indices.start + i]; bindings[at].value = b.refs[target.carry_values.start + i]; bindings[at].type_id = type_of(bindings[at].value); bindings[at].moved = false; }
    }
    fn impossible(n: u32, evidence: const u32[:]) { let block_id = current_block; terminate(TERM_UNREACHABLE, 0, [], n); b.terminators[b.blocks[block_id].term].evidence = ref_span(b, evidence); }
    recursive fn literal_boolean(value: u32, depth: u32) -> bool, bool {
        if value == 0 || depth > 64 { return false, false; } tick(current_decl); for logical in booleans { if logical.value == value { let left, known = literal_boolean(logical.left, depth + 1); if known && (logical.conjunction && !left || !logical.conjunction && left) { return left, true; } let right, rknown = literal_boolean(logical.right, depth + 1); if known && rknown { return if logical.conjunction { left && right } else { left || right }, true; } return false, false; } }
        let defining = b.values[value].op; if defining == 0 { return false, false; } let op = b.ops[defining]; if op.tag == OP_BOOL { return op.imm0 != 0, true; } if op.tag == OP_BOOL_NOT { let truth, known = literal_boolean(b.refs[op.args.start], depth + 1); return !truth, known; }
        if op.tag >= OP_U32_EQ && op.tag <= OP_U32_GE { let left, lk = proof_literal_value(b, work, proof_limits, proof_index, term_of(b.refs[op.args.start]), 0); let right, rk = proof_literal_value(b, work, proof_limits, proof_index, term_of(b.refs[op.args.start + 1]), 0); if lk && rk { return if op.tag == OP_U32_EQ { left == right } else if op.tag == OP_U32_NE { left != right } else if op.tag == OP_U32_LT { left < right } else if op.tag == OP_U32_LE { left <= right } else if op.tag == OP_U32_GT { left > right } else { left >= right }, true; } }
        return false, false;
    }
    fn prune_facts(n: u32) -> bool {
        if current_block == 0 { return true; }
        for i in active_base..active.len { tick(n); let evidence = active[i]; let f = b.facts[b.evidence[evidence].fact]; if f.tag == FACT_LT && f.left == f.right { impossible(n, [evidence]); return true; }
            let x, xk = proof_literal_value(b, work, proof_limits, proof_index, f.left, 0); let y, yk = proof_literal_value(b, work, proof_limits, proof_index, f.right, 0);
            if xk && yk && f.tag >= FACT_EQ && f.tag <= FACT_MUL_FITS && !proof_literal_truth(b, work, proof_limits, proof_index, f) { impossible(n, [evidence]); return true; }
            if f.tag == FACT_LT && (yk && y == 0 || xk && x == MAX_U32) { let bound = proof_evidence(b, work, proof_limits, proof_index, Fact { tag: FACT_LE, left: f.right, right: f.left, .. }, RULE_U32_BOUNDS, current_scope, 0, [], []); if bound == 0 { fail(FE_PROOF_LIMIT, n, "reachability bound limit"); } impossible(n, [evidence, bound]); return true; }
            for j in active_base..i { tick(n); let other = active[j]; let g = b.facts[b.evidence[other].fact]; var contradictory = false;
                if f.tag == FACT_LT { contradictory = (g.tag == FACT_LE || g.tag == FACT_LT || g.tag == FACT_EQ) && f.left == g.right && f.right == g.left || g.tag == FACT_EQ && f.left == g.left && f.right == g.right; }
                if g.tag == FACT_LT { contradictory = contradictory || (f.tag == FACT_LE || f.tag == FACT_EQ) && g.left == f.right && g.right == f.left || f.tag == FACT_EQ && f.left == g.left && f.right == g.right; }
                if contradictory { impossible(n, [evidence, other]); return true; }
            }
        }
        let cycle = proof_cycle(b, work, proof_limits, proof_index, current_scope, active[active_base..]);
        if cycle != 0 { impossible(n, [cycle]); return true; }
        if work.exhausted { fail(FE_PROOF_LIMIT, n, "finite reachability proof limit"); } return false;
    }
    recursive fn check_suite(n: u32) {
        if prune_facts(n) { return; } let node = nodes[n]; if node.tag != AstTag.Suite && node.tag != AstTag.FunctionBody { check_statement(n); if current_block != 0 { prune_facts(n); } return; }
        let alias_mark = local_aliases.len; let saved_alias_lexical = alias_lexical; alias_lexical = alias_mark;
        let binding_mark = bindings.len; let facts_mark = active.len; let saved_lexical = lexical_base; lexical_base = binding_mark;
        for i in node.children.count { if current_block == 0 { fail(FE_SYNTAX, child(n, i), "unreachable code after unconditional transfer"); } check_statement(child(n, i)); }
        if current_block != 0 { prune_facts(n); } if current_block != 0 { for binding, i in bindings { if i >= binding_mark && !binding.moved && !share(binding.type_id) { fail(if b.types[binding.type_id].tag == TY_RESULT { FE_RESULT } else { FE_USAGE }, n, "affine binding leaves scope without transfer or terminal operation"); } } }
        local_aliases.resize(alias_mark); alias_lexical = saved_alias_lexical; lexical_base = saved_lexical; bindings.resize(binding_mark); if active.len > facts_mark { active.resize(facts_mark); }
    }
    recursive fn check_statement(n: u32) {
        tick(n); let node = nodes[n];
        if node.tag == AstTag.Return { let value = expression(child(n, 0), return_type); if current_block != 0 { finish_return(value, n); } return; }
        if node.tag == AstTag.Break {
            let expr = child(n, 0); if expr == 0 { loop_transfer(n, false, false); return; } if targets.len == target_base { fail(FE_TARGET, n, "break has no matching value block target"); }
            let target_index = targets.len - 1; let value = expression(expr, targets[target_index].type_id); if current_block == 0 { return; }
            exit_value(targets[target_index], value, n); return;
        }
        if node.tag == AstTag.Continue { loop_transfer(n, true, false); return; }
        if node.tag == AstTag.Next || node.tag == AstTag.Stop { loop_transfer(n, node.tag == AstTag.Next, true); return; }
        if node.tag == AstTag.Seal || node.tag == AstTag.Abort {
            if owned_stack.len == owned_base { fail(FE_TARGET, n, "seal/abort has no owning construction target"); } let owned = owned_stack[owned_stack.len - 1];
            let space = expression(child(n, 0), 0); let space_type = b.types[type_of(space)]; let owner = bindings[owned.construction].value; if space_type.tag != TY_SPACE || space_type.region != b.types[type_of(owner)].region { fail(FE_TYPE, n, "terminal frontier must belong to this Owned construction"); }
            hold(space); let payload_type = if node.tag == AstTag.Seal { substitute_type(b.refs[b.types[owned.owned_type].children.start], owned.substitutions, 0) } else { owned.body_error }; let payload = expression(child(n, 1), payload_type);
            emit(OP_SPACE_END, unit, [space], [], 0, n); bindings[owned.construction].moved = true; let output_type = targets[owned.target].type_id; var result: u32 = 0;
            if node.tag == AstTag.Seal { let handle = emit(OP_OWNED_SEAL, owned.owned_type, [owner, payload], [], 0, n); b.ops[b.values[handle].op].substitutions = owned.substitutions; result = emit(OP_SUM, output_type, [handle], [], 0, n); }
            else { require_effect(EFFECT_RELEASE, 0, n); emit(OP_OWNED_ABORT, unit, [owner], [], 0, n); let wrapped = emit(OP_SUM, owned.error_type, [payload], [], 1, n); result = emit(OP_SUM, output_type, [wrapped], [], 1, n); }
            exit_value(targets[owned.target], result, n); return;
        }
        if node.tag == AstTag.Alias { if node.flags != 0 { fail(FE_INTERFACE, n, "local aliases cannot be public or static"); } let name = add_name(b, ast_text(source, nodes[child(n, 0)])); if builtin_name(name_bytes(core_view(b), name)) { fail(FE_UNBOUND, n, "builtin names cannot be rebound"); } for i in alias_lexical..local_aliases.len { if local_aliases[i].name == name { fail(FE_UNBOUND, n, "duplicate local type alias"); } } let index = local_aliases.len; local_aliases.push(FrontAlias { name: name, .. }); let mark = typebindings.len; var binders = Span { .. }; if child(n, 1) != 0 { binders = make_binders(child(n, 1), false); apply_constraints(child(n, 2)); } let ty = resolve_type(child(n, 3)); typebindings.resize(mark); local_aliases[index] = FrontAlias { name: name, type_id: ty, binders: binders, complete: true }; return; }
        if node.tag == AstTag.Let { let annotation = child(n, 1); if node.flags & 2 != 0 { let value = complete_static(n, annotation, child(n, 2), 0); bind_pattern(child(n, 0), value); return; } let type_mark = typebindings.len; let ty = if annotation != 0 { resolve_type(annotation) } else { 0 };
            if ty != 0 && b.types[ty].tag == TY_FORALL { let pattern = child(n, 0); let initializer = child(n, 2); if nodes[pattern].tag != AstTag.Name || nodes[initializer].tag != AstTag.Function { fail(FE_INTERFACE, n, "a local forall declaration requires one name and a function body"); } let name = add_name(b, ast_text(source, nodes[pattern])); if builtin_name(name_bytes(core_view(b), name)) || name_bytes(core_view(b), name) == "_" { fail(FE_UNBOUND, pattern, "generic declaration requires an ordinary name"); } for i in lexical_base..bindings.len { tick(n); if bindings[i].name == name { fail(FE_UNBOUND, n, "duplicate immutable binding"); } } let index = bindings.len; bindings.push(FrontBinding { generic_function: 4294967295, name: name, type_id: unit, .. }); let fid = closure(initializer, ty, true); bindings[index].generic_function = fid; }
            else { let value = expression(child(n, 2), ty); if current_block != 0 { bind_pattern(child(n, 0), value); } } typebindings.resize(type_mark); return; }
        if node.tag == AstTag.Case {
            let subject = expression(child(n, 0), 0); let subject_type = type_of(subject); let ty = b.types[subject_type];
            if ty.tag == TY_BOOL || ty.tag == TY_U32 || ty.tag == TY_F32 { scalar_case(n, subject); return; } if ty.tag != TY_SUM && ty.tag != TY_RESULT { fail(FE_TYPE, n, "case requires closed sum or scalar"); }
            let from = current_block; let binding_mark = bindings.len; let facts_mark = active.len; var edges: u32[4] = [0; 4]; var edge_count: u32 = 0; var covered: u32 = 0; var joined = FrontTarget { scope: current_scope, binding_limit: bindings.len as u32, .. }; let snapshot = save_bindings();
            for arm_index in 1..node.children.count {
                let arm = child(n, arm_index); let pat = child(arm, 0); let wildcard = nodes[pat].tag == AstTag.Name && ast_text(source, nodes[pat]) == "_";
                if !wildcard && nodes[pat].tag != AstTag.Variant { fail(FE_CASE, pat, "sum case requires constructor patterns"); }
                let pattern_name = add_name(b, ast_text(source, nodes[pat])); var matched = false;
                for variant in ty.fields.count {
                    tick(arm); let field = b.fields[b.refs[ty.fields.start + variant]]; let bit: u32 = 1 << variant;
                    if (wildcard && covered & bit == 0) || (!wildcard && pattern_name == field.name) {
                        matched = true; if covered & bit != 0 { fail(FE_CASE, pat, "overlapping constructor arms"); } covered |= bit;
                        restore_bindings(snapshot); let target = new_block(); var payload_subject = subject; var eid: u32 = 0;
                        if !share(subject_type) { eid = flow_edge(from, target, EDGE_CASE, [subject], n); payload_subject = b.refs[b.blocks[target].params.start]; }
                        else { eid = flow_edge(from, target, EDGE_CASE, [], n); }
                        b.edges[eid].case_tag = variant as u32; edges[edge_count] = eid; edge_count++; current_block = target;
                        let payload = emit(OP_PAYLOAD, field.type_id, [payload_subject], [], variant as u32, pat); checked_case_facts(subject, payload, variant as u32, eid, pat);
                        if wildcard { if !share(field.type_id) || ty.tag == TY_RESULT { fail(FE_RESULT, pat, "wildcard cannot discard a Result obligation"); } }
                        else { let p = child(pat, 0); if p == 0 { if field.type_id != unit { fail(FE_TYPE, pat, "constructor payload pattern is required"); } } else { bind_pattern(p, payload); } }
                        check_suite(child(arm, 1));
                        if current_block != 0 { if joined.block_id == 0 { joined.block_id = new_block(); } let e = join_values(joined, [], arm); terminate(TERM_JUMP, 0, [e], arm); }
                        bindings.resize(binding_mark); active.resize(facts_mark);
                    }
                }
                if !matched { fail(FE_CASE, pat, "constructor arm does not match remaining variants"); }
            }
            if covered != (1 << ty.fields.count) - 1 { fail(FE_CASE, n, "case does not handle every constructor"); }
            b.blocks[from].merge = joined.block_id; current_block = from; terminate(TERM_SWITCH, subject, edges[..edge_count], n); restore_bindings(snapshot); snapshots.resize(snapshot.start); current_block = joined.block_id; if joined.incoming != 0 { enter_join(joined); } return;
        }
        if node.tag == AstTag.If {
            let condition = expression(child(n, 0), boolean); if current_block == 0 { return; } let known_truth, is_known = literal_boolean(condition, 0); if is_known { let selected = child(n, if known_truth { 1 } else { 2 }); if selected != 0 { check_suite(selected); } return; }
            let snapshot = save_bindings(); let from = current_block; let yes = new_block(); let no = new_block();
            let ey = flow_edge(from, yes, EDGE_TRUE, [], n); restore_bindings(snapshot); let en = flow_edge(from, no, EDGE_FALSE, [], n); restore_bindings(snapshot); terminate(TERM_BRANCH, condition, [ey, en], n);
            var joined = FrontTarget { scope: current_scope, binding_limit: bindings.len as u32, .. }; let mark = active.len;
            current_block = yes; let yes_args = b.blocks[yes].params; var ai: u32 = 0; for binding, i in bindings { if i >= binding_base && !binding.moved && !share(binding.type_id) { bindings[i].value = b.refs[yes_args.start + ai]; ai++; } }
            branch_facts(condition, ey, true); check_suite(child(n, 1)); let yes_end = current_block;
            if yes_end != 0 { joined.block_id = new_block(); let e = join_values(joined, [], n); terminate(TERM_JUMP, 0, [e], n); }
            active.resize(mark); restore_bindings(snapshot); current_block = no; let no_args = b.blocks[no].params; ai = 0; for binding, i in bindings { if i >= binding_base && !binding.moved && !share(binding.type_id) { bindings[i].value = b.refs[no_args.start + ai]; ai++; } }
            branch_facts(condition, en, false); let else_node = child(n, 2); if else_node != 0 { check_suite(else_node); } let no_end = current_block;
            if no_end != 0 { if joined.block_id == 0 { joined.block_id = new_block(); } let e = join_values(joined, [], n); terminate(TERM_JUMP, 0, [e], n); }
            active.resize(mark); restore_bindings(snapshot); snapshots.resize(snapshot.start); current_block = joined.block_id; b.blocks[from].merge = joined.block_id;
            if joined.incoming != 0 { enter_join(joined); if yes_end == 0 { branch_facts(condition, en, false); } else if no_end == 0 { branch_facts(condition, ey, true); } }
            return;
        }
        let value = expression(n, 0); if current_block != 0 && type_of(value) != unit { fail(if b.types[type_of(value)].tag == TY_RESULT { FE_RESULT } else { FE_RETURN }, n, "value expression does not provide implicit completion"); }
    }
    fn resolve_retained(name: u32, kind: u32) -> u32 {
        for d, index in decls { tick(current_decl); let definition = b.definitions[d.definition]; if definition.name == name && definition.kind == kind { complete_declaration(index as u32); return d.definition; } } return 0;
    }
    recursive fn complete_declaration(index: u32) {
        let d = decls[index]; if d.state == 2 { return; } if d.state == 1 { fail(FE_RECURSION, d.node, "recursive declaration dependency"); }
        let saved_alias_base = alias_base; let saved_alias_lexical = alias_lexical; alias_base = local_aliases.len; alias_lexical = alias_base;
        let saved_static_stats = static_stats; static_stats = StaticStats { .. }; decls[index].state = 1; let saved_producer = current_producer; current_producer = d.definition;
        let saved_capture_base = capture_base; capture_base = capture_frames.len; let saved_lambda_outer = lambda_outer_base; lambda_outer_base = -1; let nat_value_mark = natvalues.len; let saved_open_base = open_base; open_base = open_scopes.len; let saved_loop_base = loop_base; loop_base = loop_stack.len; let saved_effects_explicit = effects_explicit; effects_explicit = false; let saved_held_base = held_base; held_base = held.len; let saved_lexical_base = lexical_base; lexical_base = bindings.len; let saved_owned_base = owned_base; owned_base = owned_stack.len; let saved_function = current_function; let saved_block = current_block; let saved_scope = current_scope; let saved_return = return_type; let saved_decl = current_decl; let saved_type_start = type_start; let saved_block_start = block_start; let saved_op_start = op_start; let saved_visit_start = visit_start; let saved_proof = proof_limits; let saved_depth = max_callee_depth; let saved_frame = max_callee_frame;
        let type_mark = typebindings.len; let saved_type_base = type_base; type_base = type_mark;
        let bindings_mark = bindings.len; let active_mark = active.len; let target_mark = targets.len; let saved_binding_base = binding_base; let saved_active_base = active_base; let saved_target_base = target_base; binding_base = bindings_mark; active_base = active_mark; target_base = target_mark;
        current_function = 0; current_scope = 0; current_block = 0; current_decl = d.node; type_start = b.types.len; block_start = b.blocks.len; op_start = b.ops.len + b.terminators.len; visit_start = work.visits; proof_limits = proof_budget(b, work, proof_index); max_callee_depth = 0; max_callee_frame = 0;
        if index < alias_work.len && !charge(work, alias_work[index], visit_start + LIMIT_VISITS) { fail(FE_SEMANTIC_LIMIT, d.node, "alias dependency traversal limit reached"); }
        var did_complete = false; let node = nodes[d.node];
        if d.projection_root != 0 {
            complete_declaration(d.projection_root - 1); if !begin_completion(b) { fail(FE_INTERFACE, d.node, "static projection after sealing"); } did_complete = true; let root = decls[d.projection_root - 1]; let source_value = b.definitions[root.definition].value; let object = b.ops[b.values[source_value].op].imm0; let stage = stage_static(d.node, 0, object, d.projection_path); var stats = StaticStats { .. }; let value = evaluate_static(stage.function, stats, d.node); let published, published_ok = publish_static(STATIC_VALUE, stage.type_id, 0, 1, 0, [value], d.definition, stats); if !published_ok { fail(FE_STATIC_LIMIT, d.node, "static destructuring publication failed"); } let result = stage_static(d.node, stage.type_id, published); b.definitions[d.definition].type_id = stage.type_id; b.definitions[d.definition].value = result.value;
        }
        else if node.tag == AstTag.Alias { if !begin_completion(b) { fail(FE_INTERFACE, d.node, "completion attempted after sealing"); } did_complete = true; var bs = Span { .. }; if child(d.node, 1) != 0 { bs = make_binders(child(d.node, 1), false); apply_constraints(child(d.node, 2)); } let ty = resolve_type(child(d.node, 3)); b.definitions[d.definition].type_id = ty; b.definitions[d.definition].binders = bs; }
        else if b.definitions[d.definition].kind == DEF_STATIC { if !begin_completion(b) { fail(FE_INTERFACE, d.node, "static completion after sealing"); } did_complete = true; complete_static(d.node, child(d.node, 1), child(d.node, 2), d.definition); validate_global_pattern(child(d.node, 0), b.definitions[d.definition].type_id); }
        else {
            let annotation = child(d.node, 1); let initializer = child(d.node, 2);
            var ty: u32 = 0; var inferred_contract: u32 = 0;
            if annotation == 0 { if nodes[initializer].tag != AstTag.Function || nodes[child(initializer, 0)].tag != AstTag.AnnotatedPattern { fail(FE_INTERFACE, d.node, "declaration requires an expected type or annotated parameter"); } let arg = resolve_type(child(child(initializer, 0), 1)); inferred_contract = b.contracts.len as u32; b.contracts.push(Contract { arg: arg, .. }); ty = 0; }
            else { ty = resolve_type(annotation); } let callable_type = if ty == 0 { 0 } else { unwrap_callable(ty) }; if (annotation != 0 && (callable_type == 0 || b.types[callable_type].tag != TY_FN)) || nodes[initializer].tag != AstTag.Function { fail(FE_UNSUPPORTED, d.node, "static data completion producer is not completed"); }
            if node.flags & 2 != 0 { fail(FE_UNSUPPORTED, d.node, "required static function evaluation is not completed"); }
            if child(initializer, 2) != 0 { fail(FE_UNSUPPORTED, initializer, "placed closure producer is not completed"); }
            let ct = if annotation == 0 { inferred_contract } else { b.types[callable_type].contract }; complete_callable_slots(b.contracts[ct].arg, d.node); complete_callable_slots(b.contracts[ct].result, d.node);
            var outer_annotation = annotation; if nodes[outer_annotation].tag == AstTag.Forall { outer_annotation = child(outer_annotation, 2); }
            if nodes[outer_annotation].tag == AstTag.Contract { for i in 1..nodes[outer_annotation].children.count { if ast_text(source, nodes[child(outer_annotation, i)]) == "!" { effects_explicit = true; } } }
            if node.flags & 1 != 0 {
                var contract_annotation = annotation; if nodes[contract_annotation].tag == AstTag.Forall { contract_annotation = child(contract_annotation, 2); }
                if nodes[contract_annotation].tag != AstTag.Contract { fail(FE_INTERFACE, d.node, "public callable requires explicit effects and resources"); }
                var effects = false; var resources = false;
                for i in 1..nodes[contract_annotation].children.count { let c = child(contract_annotation, i); if ast_text(source, nodes[c]) == "!" { effects = true; } if nodes[c].tag == AstTag.Resource { resources = true; } }
                if !effects || !resources { fail(FE_INTERFACE, d.node, "public callable requires explicit effects and resources"); }
            }
            let cached = F(d.definition, Span { start: node.start, count: node.end - node.start }, ty, resolve_retained);
            if cached == 4294967295 { while b.phase.active > initial_active { end_completion(b); } return false from frontend_complete_indexed; }
            if cached != 0 { if !id_ok(cached, b.functions.len) { fail(FE_INTERFACE, d.node, "reuse callback returned invalid function"); } decls[index].function = cached; b.definitions[d.definition].function = cached; }
            else {
                if !begin_completion(b) { fail(FE_INTERFACE, d.node, "completion attempted after sealing"); } did_complete = true;
                current_function = b.functions.len as u32; decls[index].function = current_function; current_scope = b.scopes.len as u32; b.scopes.push(Scope { kind: SCOPE_FUNCTION, origin: origin(d.node), .. });
                b.functions.push(Function { visibility: b.definitions[d.definition].visibility, name: b.definitions[d.definition].name, module: module_id, type_id: ty, contract: ct, producer: d.definition, origin: origin(d.node), .. });
                current_block = new_block(); b.functions[current_function].entry = current_block; return_type = b.contracts[ct].result;
                let param = b.values.len as u32; b.values.push(Value { type_id: b.contracts[ct].arg, block_id: current_block, version: param, scope: current_scope, origin: origin(child(initializer, 0)), .. }); b.functions[current_function].param = param; b.blocks[current_block].params = ref_span(b, [param]);
                bind_pattern(child(initializer, 0), param); assume_contract(b.contracts[ct].requires, ct, param, 0, 0, 0, d.node); check_suite(child(initializer, 1));
                if current_block != 0 { fail(FE_RETURN, initializer, "function has a reachable path without explicit return"); }
                let own_frame: u32 = 0;
                if b.contracts[ct].depth != 0 && (b.contracts[ct].depth < max_callee_depth + 1 || b.contracts[ct].frame < own_frame + max_callee_frame) { fail(FE_RESOURCE, d.node, "caller resources do not cover callees"); }
                finalize_blocks(current_function, d.node);
                if annotation == 0 { let completed = TypeNode { tag: TY_FN, children: ref_span(b, [b.contracts[ct].arg, b.contracts[ct].result]), mode: MODE_MANY, contract: ct, .. }; ty = intern_type(completed); b.functions[current_function].type_id = ty; }
                b.definitions[d.definition].type_id = ty; b.definitions[d.definition].function = current_function;
                b.interfaces.push(Interface { function: current_function, type_id: ty, contract: ct, producer: d.definition, .. });
            }
        }
        if did_complete { b.receipts.push(Receipt { producer: d.definition, dependencies: producer_queries(d.definition), completed_visits: work.visits - visit_start, .. }); end_completion(b); } decls[index].state = 2;
        let own_visits = work.visits - visit_start; let own_proof_visits = work.proof_visits - proof_limits.visits_start; let own_types = b.types.len - type_start; let own_blocks = b.blocks.len - block_start; let own_ops = b.ops.len + b.terminators.len - op_start; let own_terms = b.terms.len as u32 - proof_limits.terms_start; let own_edges = (b.facts.len + b.evidence.len) as u32 - proof_limits.edges_start;
        local_aliases.resize(alias_base); alias_base = saved_alias_base; alias_lexical = saved_alias_lexical; static_stats = saved_static_stats; current_producer = saved_producer; typebindings.resize(type_mark); type_base = saved_type_base; bindings.resize(bindings_mark); active.resize(active_mark); targets.resize(target_mark); binding_base = saved_binding_base; active_base = saved_active_base; target_base = saved_target_base;
        capture_base = saved_capture_base; lambda_outer_base = saved_lambda_outer; natvalues.resize(nat_value_mark); open_scopes.resize(open_base); open_base = saved_open_base; loop_stack.resize(loop_base); loop_base = saved_loop_base; effects_explicit = saved_effects_explicit; held.resize(held_base); held_base = saved_held_base; lexical_base = saved_lexical_base; owned_stack.resize(owned_base); owned_base = saved_owned_base; current_function = saved_function; current_block = saved_block; current_scope = saved_scope; return_type = saved_return; current_decl = saved_decl; type_start = saved_type_start + own_types; block_start = saved_block_start + own_blocks; op_start = saved_op_start + own_ops; visit_start = saved_visit_start + own_visits; proof_limits = saved_proof; proof_limits.terms_start += own_terms; proof_limits.edges_start += own_edges; proof_limits.visits_start += own_proof_visits; proof_limits.semantic_start += own_visits; max_callee_depth = saved_depth; max_callee_frame = saved_frame;
    }
    fn alias_charge(owner: u32) { alias_work[owner]++; if alias_work[owner] > LIMIT_VISITS { fail(FE_SEMANTIC_LIMIT, decls[owner].node, "alias dependency traversal limit reached"); } }
    fn alias_bind_names(n: u32, owner: u32) { if n == 0 { return; } for i in nodes[n].children.count { alias_charge(owner); alias_bounds.push(add_name(b, ast_text(source, nodes[child(n, i)]))); } }
    recursive fn alias_dependencies_of(n: u32, owner: u32) {
        if n == 0 { return; } alias_charge(owner); let node = nodes[n]; if node.tag == AstTag.Select { return; }
        if node.tag == AstTag.TypeName { let name = add_name(b, ast_text(source, node)); for bound in alias_bounds { alias_charge(owner); if bound == name { return; } } let found = key_index_get(alias_names, name); if found != 0 { let dependency = found - 1; let key = FrontListKey { prefix: owner, word: dependency }; if key_index_get(alias_seen, key) == 0 { key_index_insert(alias_seen, key, 1); let edge = alias_dependencies.len as u32; alias_dependencies.push(FrontAliasDependency { dependent: owner, next: alias_heads[dependency] }); alias_heads[dependency] = edge; alias_remaining[owner]++; } } return; }
        if node.tag == AstTag.Forall || node.tag == AstTag.Exists { let mark = alias_bounds.len; alias_bind_names(child(n, 0), owner); alias_dependencies_of(child(n, 1), owner); alias_dependencies_of(child(n, 2), owner); alias_bounds.resize(mark); return; }
        for i in node.children.count { alias_dependencies_of(child(n, i), owner); }
    }
    fn complete_aliases() {
        var total: u32 = 0; for d, index in decls { alias_work.push(0); alias_heads.push(0); alias_remaining.push(0); if nodes[d.node].tag == AstTag.Alias { key_index_insert(alias_names, b.definitions[d.definition].name, index as u32 + 1); total++; } }
        for d, index in decls { if nodes[d.node].tag != AstTag.Alias { continue; } let mark = alias_bounds.len; alias_bind_names(child(d.node, 1), index as u32); alias_dependencies_of(child(d.node, 2), index as u32); alias_dependencies_of(child(d.node, 3), index as u32); alias_bounds.resize(mark); }
        for d, index in decls { if nodes[d.node].tag == AstTag.Alias && alias_remaining[index] == 0 { alias_queue.push(index as u32); } }
        var head: i64 = 0; var completed: u32 = 0; while head < alias_queue.len { let index = alias_queue[head]; head++; complete_declaration(index); completed++; var edge = alias_heads[index]; while edge != 0 { let item = alias_dependencies[edge]; alias_remaining[item.dependent]--; if alias_remaining[item.dependent] == 0 { alias_queue.push(item.dependent); } edge = item.next; } }
        if completed != total { for d, index in decls { if nodes[d.node].tag == AstTag.Alias && alias_remaining[index] != 0 { fail(FE_RECURSION, d.node, "recursive transparent alias dependency"); } } }
    }
    fn value_dependency(owner: u32, dependency: u32) { let key = FrontListKey { prefix: owner, word: dependency }; if key_index_get(alias_seen, key) == 0 { key_index_insert(alias_seen, key, 1); let edge = alias_dependencies.len as u32; alias_dependencies.push(FrontAliasDependency { dependent: owner, next: alias_heads[dependency] }); alias_heads[dependency] = edge; alias_remaining[owner]++; } }
    fn value_name(n: u32, owner: u32) { if n == 0 { return; } alias_charge(owner); let name = add_name(b, ast_text(source, nodes[n])); for bound in alias_bounds { alias_charge(owner); if bound == name { return; } } for item in imports { alias_charge(owner); if item.name == name { return; } } let found = key_index_get(value_names, name); if found != 0 { value_dependency(owner, found - 1); } }
    recursive fn value_pattern(n: u32, owner: u32) { if n == 0 { return; } alias_charge(owner); let node = nodes[n]; if node.tag == AstTag.Name { alias_bounds.push(add_name(b, ast_text(source, node))); return; } if node.tag == AstTag.AnnotatedPattern || node.tag == AstTag.Field || node.tag == AstTag.Variant { value_pattern(child(n, 0), owner); return; } if node.tag == AstTag.Pattern || node.tag == AstTag.Tuple { for i in node.children.count { value_pattern(child(n, i), owner); } } }
    fn value_forall(n: u32, owner: u32) { if n != 0 && nodes[n].tag == AstTag.Forall { alias_bind_names(child(n, 0), owner); } }
    recursive fn value_dependencies_of(n: u32, owner: u32) {
        if n == 0 { return; } alias_charge(owner); let node = nodes[n];
        if node.tag == AstTag.Name { value_name(n, owner); return; }
        if node.tag == AstTag.Alias || node.tag == AstTag.TypeName || node.tag == AstTag.TypeApply || node.tag == AstTag.TypeArrow || node.tag == AstTag.Forall || node.tag == AstTag.Exists || node.tag == AstTag.Contract || node.tag == AstTag.Fact || node.tag == AstTag.Resource || node.tag == AstTag.Constraint { return; }
        if node.tag == AstTag.Let { let mark = alias_bounds.len; let generic = child(n, 1) != 0 && nodes[child(n, 1)].tag == AstTag.Forall; if generic { value_pattern(child(n, 0), owner); } value_forall(child(n, 1), owner); value_dependencies_of(child(n, 2), owner); alias_bounds.resize(mark); value_pattern(child(n, 0), owner); return; }
        if node.tag == AstTag.Suite || node.tag == AstTag.FunctionBody { let mark = alias_bounds.len; for i in node.children.count { value_dependencies_of(child(n, i), owner); } alias_bounds.resize(mark); return; }
        if node.tag == AstTag.Function { let mark = alias_bounds.len; value_pattern(child(n, 0), owner); value_dependencies_of(child(n, 2), owner); value_dependencies_of(child(n, 1), owner); alias_bounds.resize(mark); return; }
        if node.tag == AstTag.Select || node.tag == AstTag.Apply { value_dependencies_of(child(n, 0), owner); return; }
        if node.tag == AstTag.Arm { let mark = alias_bounds.len; value_pattern(child(n, 0), owner); value_dependencies_of(child(n, 1), owner); alias_bounds.resize(mark); return; }
        if node.tag == AstTag.Open { value_dependencies_of(child(n, 0), owner); let mark = alias_bounds.len; for i in nodes[child(n, 1)].children.count { value_pattern(child(child(n, 1), i), owner); } value_pattern(child(n, 2), owner); value_dependencies_of(child(n, 3), owner); alias_bounds.resize(mark); return; }
        if node.tag == AstTag.OwnedOpen { value_dependencies_of(child(n, 0), owner); let mark = alias_bounds.len; value_pattern(child(n, 1), owner); value_pattern(child(n, 2), owner); value_dependencies_of(child(n, 3), owner); alias_bounds.resize(mark); return; }
        if node.tag == AstTag.RegionScope || node.tag == AstTag.OwnedScope { value_dependencies_of(child(n, 2), owner); let mark = alias_bounds.len; value_pattern(child(n, 3), owner); value_pattern(child(n, 4), owner); value_pattern(child(n, 5), owner); value_dependencies_of(child(n, 6), owner); alias_bounds.resize(mark); return; }
        if node.tag == AstTag.Pack { value_dependencies_of(child(n, 2), owner); return; }
        if node.tag == AstTag.For { value_dependencies_of(child(n, 1), owner); value_dependencies_of(child(n, 2), owner); for i in 3..node.children.count - 2 { value_dependencies_of(child(child(n, i), 0), owner); } let mark = alias_bounds.len; value_pattern(child(n, 0), owner); for i in 3..node.children.count - 2 { alias_charge(owner); alias_bounds.push(add_name(b, ast_text(source, nodes[child(n, i)]))); } value_dependencies_of(child(n, node.children.count - 1), owner); alias_bounds.resize(mark); return; }
        for i in node.children.count { value_dependencies_of(child(n, i), owner); }
    }
    fn complete_values() {
        var total: u32 = 0; for d, index in decls { alias_heads[index] = 0; alias_remaining[index] = 0; if nodes[d.node].tag != AstTag.Alias { key_index_insert(value_names, b.definitions[d.definition].name, index as u32 + 1); total++; } }
        for d, index in decls { if nodes[d.node].tag == AstTag.Alias { continue; } let mark = alias_bounds.len; value_forall(child(d.node, 1), index as u32); value_dependencies_of(child(d.node, 2), index as u32); alias_bounds.resize(mark); if d.projection_root != 0 { value_dependency(index as u32, d.projection_root - 1); } }
        for d, index in decls { if nodes[d.node].tag != AstTag.Alias && alias_remaining[index] == 0 { value_queue.push(index as u32); } }
        var head: i64 = 0; var completed: u32 = 0; while head < value_queue.len { let index = value_queue[head]; head++; complete_declaration(index); completed++; var edge = alias_heads[index]; while edge != 0 { let item = alias_dependencies[edge]; alias_remaining[item.dependent]--; if alias_remaining[item.dependent] == 0 { value_queue.push(item.dependent); } edge = item.next; } }
        if completed != total { for d, index in decls { if nodes[d.node].tag != AstTag.Alias && alias_remaining[index] != 0 { fail(FE_RECURSION, d.node, "recursive named declaration dependency"); } } }
    }
    let root = nodes[parsed.root];
    for i in root.children.count {
        let n = child(parsed.root, i); current_decl = n;
        if nodes[n].tag == AstTag.Import { let dependencies = b.modules[module_id].imports; if imports.len >= dependencies.count { fail(FE_UNBOUND, n, "import dependency was not loaded"); } let alias = add_name(b, ast_text(source, nodes[child(n, 1)])); for old in imports { if old.name == alias { fail(FE_UNBOUND, n, "duplicate import alias"); } } imports.push(FrontImport { name: alias, module: b.refs[dependencies.start + imports.len] }); continue; }
        let name_node = child(n, 0);
        if nodes[name_node].tag != AstTag.Name || ast_text(source, nodes[name_node]) == "_" { let root_index = decls.len as u32; let id = b.definitions.len as u32; b.definitions.push(Definition { kind: DEF_STATIC, name: add_name(b, str("<pattern:", nodes[n].start, ">")), module: module_id, origin: origin(n), .. }); top_definitions.push(id); decls.push(FrontDecl { node: n, definition: id, .. }); register_top_pattern(name_node, n, root_index, Span { .. }); continue; }
        let name = add_name(b, ast_text(source, nodes[name_node]));
        if builtin_name(name_bytes(core_view(b), name)) { fail(FE_UNBOUND, name_node, "builtin names cannot be rebound"); }
        for prior in decls { if b.definitions[prior.definition].name == name { fail(FE_UNBOUND, name_node, "duplicate declaration name"); } }
        let id = b.definitions.len as u32; b.definitions.push(Definition { kind: if nodes[n].tag == AstTag.Alias { DEF_TYPE } else if nodes[n].flags & 2 != 0 || nodes[child(n, 2)].tag != AstTag.Function { DEF_STATIC } else { DEF_FUNCTION }, name: name, module: module_id, visibility: if nodes[n].flags & 1 != 0 { VIS_PUBLIC } else { VIS_PRIVATE }, origin: origin(n), .. }); top_definitions.push(id); decls.push(FrontDecl { node: n, definition: id, .. });
    }
    b.modules[module_id].declarations = ref_span(b, top_definitions[..]);
    complete_aliases();
    complete_values();
    return true;
}
