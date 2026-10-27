import std;
import .model;
import .frontend;

fn same_syntax(a_source: const u8[:], a: const AstNode[:], ar: const u32[:],
               b_source: const u8[:], b: const AstNode[:], br: const u32[:]) -> bool {
    if a.len != b.len || ar.len != br.len { return false; }
    for id in ar.len { if ar[id] != br[id] { return false; } }
    for node, i in a {
        if i == 0 { continue; }
        let other = b[i];
        if node.tag != other.tag || node.bits != other.bits || node.flags != other.flags ||
            node.children.start != other.children.start || node.children.count != other.children.count ||
            ast_text(a_source, node) != ast_text(b_source, other) { return false; }
    }
    return true;
}
// Conservative canonical whitespace. Lexical targets and literal/comment text
// stay intact; every result is reparsed and compared before publication.
fn format_source(source: const u8[:], out: u8[>..]&, diagnostics: Diagnostic[>..]&) -> bool {
    var nodes: AstNode[>..] = []; var refs: u32[>..] = [];
    let before = parse_source(source, nodes, refs);
    if before.root == 0 { diagnostics.push(Diagnostic { code: 1000, origin: before.start, related: before.end, .. }); return false; }
    var candidate: u8[>..] = []; var at: i64 = 0; var previous_blank = false;
    while at < source.len {
        let start = at; while at < source.len && source[at] != '\n' { at++; }
        var end = at; if at < source.len { at++; }
        while end > start && (source[end - 1] == ' ' || source[end - 1] == '\r') { end--; }
        var cursor = start;
        while cursor < end && source[cursor] == ' ' { cursor++; }
        if cursor == end {
            if candidate.len != 0 && !previous_blank { candidate.push('\n'); }
            previous_blank = true; continue;
        }
        previous_blank = false; candidate.append(source[start..cursor]);
        var quoted = false; var space = false;
        while cursor < end {
            let ch = source[cursor];
            if !quoted && ch == '/' && cursor + 1 < end && source[cursor + 1] == '/' {
                if space { candidate.push(' '); } candidate.append(source[cursor..end]); break;
            }
            if !quoted && ch == ' ' { space = true; cursor++; continue; }
            if space { candidate.push(' '); space = false; }
            candidate.push(ch); if ch == '"' { quoted = !quoted; } cursor++;
        }
        candidate.push('\n');
    }
    var after_nodes: AstNode[>..] = []; var after_refs: u32[>..] = [];
    let after = parse_source(candidate, after_nodes, after_refs);
    if after.root == 0 || !same_syntax(source, nodes, refs, candidate, after_nodes, after_refs) {
        diagnostics.push(Diagnostic { code: 4014, .. }); return false;
    }
    out.append(candidate); return true;
}
let COMPLETIONS = "AddFits\nAllocError\nAppend\nBool\nBuilder\nCap\nDest\nDomain\nEnvDest\nEq\nF32\nF32.abs\nF32.ceil\nF32.floor\nF32.from_u32\nF32.max\nF32.min\nF32.nearest\nF32.sqrt\nF32.trunc\nFn\nIndex\nInit\nLe\nLen\nLt\nMany\nMulFits\nNat\nOnce\nOption\nOwned\nPlain\nRegion\nRegionOwner\nReserveError\nResize\nResult\nShare\nSpace\nSubFits\nType\nU32\nU32.fits_add\nU32.fits_mul\nU32.fits_sub\nU32.from_f32\nU32.try_add\nU32.try_div\nU32.try_mul\nU32.try_shift_left\nU32.try_shift_right\nU32.try_sub\nU32.wrapping_add\nU32.wrapping_mul\nU32.wrapping_sub\nUnit\nView\nabort\narray.in\nas\nbreak\nbuilder.append\nbuilder.begin_append\nbuilder.begin_resize\nbuilder.capacity\nbuilder.discard\nbuilder.freeze\nbuilder.length\nbuilder.read\nbuilder.set\nbuilder.truncate\nbuilder.try_append\ncarry\ncase\ncontinue\ndest.discard\ndest.split\ndo\nelse\nensures\nenv.try_alloc\nexists\nfn\nfor\nforall\nif\nimport\nin\nindex.try_make\ninvariant\nlet\nlocal\nnext\non_false\non_true\nopen\nowned\nowned.close\nowned.open\npack\npub\nregion\nregion.close\nregion.reset\nregion.try_alloc\nrequires\nresources\nreturn\nseal\nspace.end\nstatic\nstop\ntype\nview.length\nview.read\nview.slice\nview.try_read\nwhere\n";
fn complete_prefix(prefix: const u8[:], out: u8[>..]&) {
    var start: i64 = 0;
    for ch, i in COMPLETIONS {
        if ch == '\n' {
            let word = COMPLETIONS[start..i];
            if starts_with(word, prefix) { out.append(word); out.push('\n'); }
            start = i + 1;
        }
    }
}
struct MigrationFinding { code: u32, start: u32, end: u32 }
// Token-aware review: comments and quoted paths are skipped. This reports work
// requiring a policy decision; it never inserts guards or changes failure paths.
fn migration_findings(source: const u8[:], findings: MigrationFinding[>..]&) {
    var at: i64 = 0; var previous: const u8[:] = source[..0];
    while at < source.len {
        let start = at; let ch = source[at];
        if ch == '/' && at + 1 < source.len && source[at + 1] == '/' { while at < source.len && source[at] != '\n' { at++; } continue; }
        if ch == '"' {
            at++; while at < source.len && source[at] != '"' { if source[at] == '\\' && at + 1 < source.len { at++; } at++; }
            if at < source.len { at++; }
            if previous != "import" && previous != "from" { findings.push(MigrationFinding { 5, start as u32, at as u32 }); }
            previous = source[..0]; continue;
        }
        if ascii_letter(ch) {
            at++; while at < source.len && (ascii_letter(source[at]) || ascii_digit(source[at])) { at++; }
            let word = source[start..at]; var code: u32 = 0;
            if word == "const" || word == "use" { code = 1; }
            if word == "while" || word == "loop" { code = 2; }
            if word == "fn" { code = 3; }
            if word == "Array" { code = 4; }
            if code != 0 { findings.push(MigrationFinding { code, start as u32, at as u32 }); }
            previous = word; continue;
        }
        if ch == '#' && at + 1 < source.len && source[at + 1] == '[' { findings.push(MigrationFinding { 4, start as u32, (at + 2) as u32 }); }
        if ch == '+' || ch == '*' || ch == '/' || ch == '%' ||
            (ch == '-' && (at + 1 == source.len || source[at + 1] != '>')) { findings.push(MigrationFinding { 6, start as u32, (at + 1) as u32 }); }
        if ch == ':' && at + 1 < source.len && source[at + 1] == '=' { findings.push(MigrationFinding { 7, start as u32, (at + 2) as u32 }); }
        if ch == '[' && previous.len != 0 && ascii_letter(previous[0]) && previous[0] >= 'a' && previous[0] <= 'z' {
            findings.push(MigrationFinding { 8, start as u32, (at + 1) as u32 });
        }
        if ch != ' ' && ch != '\n' && ch != '\r' && ch != '\t' { previous = source[..0]; }
        at++;
    }
}
fn migration_message(code: u32) -> const u8[:] {
    if code == 1 { return "Review legacy binding: K1 uses immutable let with explicit effects and moves."; }
    if code == 2 { return "Unbounded iteration is unavailable; express a finite for loop and its invariants."; }
    if code == 3 { return "Check explicit return paths, complete callable resources, and Share-only captures."; }
    if code == 4 { return "Array construction needs an explicit destination or required-static initializer."; }
    if code == 5 { return "Runtime strings are outside K1; quoted paths are supported for imports."; }
    if code == 6 { return "Establish checked arithmetic preconditions or choose an explicit fallible/wrapping operation."; }
    if code == 7 { return "Type-changing rebinding is unavailable; use explicit immutable values and loop carries."; }
    if code == 8 { return "Establish the exact view bound or use a matching-domain Index."; }
    return "Review this construct against the K1 specification.";
}
