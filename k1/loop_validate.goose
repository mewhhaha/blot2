// Independent closed-language recognizer and Core verifier. It walks an
// explicit token sequence, including all type/effect/resource and indentation
// tokens, without invoking the producer parser. It independently reconstructs
// each fixed operation and evidence record from a trusted expected context.
// Sharing the lexer and accepting caller-owned IDs are explicit limitations.
namespace loop_validate;
import lexer;
import loop_core;
fn same_span(s: loop_core::Span, t: lexer::Token) -> bool { return s.start == t.start && s.end == t.end; }
fn verify(core: loop_core::Core&, source: u8[:], expected: loop_core::Context) -> bool {
    if source.len > 4096 || core.source[..] != source || !loop_core::context_valid(expected) || !loop_core::same_context(core.context,expected) { return false; }
    var lex = lexer::init(source); var t = lexer::next(source,lex);
    while t.kind == 6 { t = lexer::next(source,lex); }
    var source_count = 0;
    for value in [
        "pub","let","copy_into",":","forall","[","r",":","Region",",","s",":","Region",",",
        "n",":","Nat",",","c",":","Nat",",","d",":","Domain","]","=>","Fn","[","static",",","Many",",","(",
        "View","[","r",",","U32",",","n",",","d","]",",","Builder","[","s",",","U32",",","0",",","c",",","Append","]",")",",",
        "Builder","[","s",",","U32",",","n",",","c",",","Append","]","]","!","{","read","r",",","write","s","}",
        "requires","[","Le","(","n",",","c",")","]","resources","{","depth",":","1",",","frame",":","256","}","=","fn","(","source",",","initial",")","=>","do",":",
        "\n","\t","let","built","=","for","i","in","0","..","n","carry","(","b","=","initial",")","\n","\t",
        "invariant","[","Eq","(","Init","(","b",")",",","i",")","]","do",":","\n","\t",
        "next","(","builder",".","append","(","b",",","source","[","i","]",")",")","@optional_newline","\r","\r",
        "return","built","@optional_newline","\r"
    ] {
        if value == "@optional_newline" { if t.kind == 6 { t = lexer::next(source,lex); } continue; }
        if value == "\n" { if t.kind != 6 { return false; } }
        else if value == "\t" { if t.kind != 7 { return false; } }
        else if value == "\r" { if t.kind != 8 { return false; } }
        else {
            let first = value[0];
            let kind = if first >= '0' && first <= '9' { 2 } else if (first >= 'a' && first <= 'z') || (first >= 'A' && first <= 'Z') || first == '_' { 1 } else { 5 };
            if t.kind != kind || t.start < 0 || t.end <= t.start || t.end > source.len || source[t.start..t.end] != value { return false; }
            if value == "requires" && !same_span(core.sites.requires_site,t) { return false; }
            if value == "for" && !same_span(core.sites.for_site,t) { return false; }
            if value == "invariant" && !same_span(core.sites.invariant_site,t) { return false; }
            if value == "next" && !same_span(core.sites.next_site,t) { return false; }
            if value == "append" && !same_span(core.sites.append_site,t) { return false; }
            if value == "source" { source_count += 1; if source_count == 2 && !same_span(core.sites.read_site,t) { return false; } }
            if value == "return" && !same_span(core.sites.return_site,t) { return false; }
        }
        t = lexer::next(source,lex);
    }
    while t.kind == 6 { t = lexer::next(source,lex); }
    if t.kind != 0 || source_count != 2 { return false; }
    let s = core.sites; let c = expected;
    let proof: loop_core::Evidence[6] = [
        loop_core::Evidence { rule: 1, owner: c.owner, left: c.length, right: c.capacity, site: s.requires_site.start },
        loop_core::Evidence { rule: 2, owner: c.owner, left: c.builder, right: c.index, version: c.builder_version, site: s.invariant_site.start },
        loop_core::Evidence { rule: 3, owner: c.owner, left: c.index, right: c.length, version: c.input_version, site: s.for_site.start },
        loop_core::Evidence { rule: 4, owner: c.owner, left: c.builder, right: c.capacity, version: c.builder_version, dep1: 1, dep2: 2, dep3: 3, site: s.append_site.start },
        loop_core::Evidence { rule: 5, owner: c.owner, left: c.next_builder, right: c.index, version: c.next_version, dep1: 2, dep2: 4, site: s.next_site.start },
        loop_core::Evidence { rule: 6, owner: c.owner, left: c.result, right: c.length, version: c.result_version, dep1: 2, dep2: 5, site: s.return_site.start }
    ];
    let ops: loop_core::Op[4] = [
        loop_core::Op { kind: 1, owner: c.owner, input: c.input, version: c.input_version, index: c.index, domain: c.input_domain, proof1: 3, site: s.read_site.start },
        loop_core::Op { kind: 2, owner: c.owner, input: c.builder, version: c.builder_version, output: c.next_builder, output_version: c.next_version, proof1: 4, proof2: 2, site: s.append_site.start },
        loop_core::Op { kind: 3, owner: c.owner, input: c.next_builder, version: c.next_version, output: c.builder, output_version: c.builder_version, proof1: 5, site: s.next_site.start },
        loop_core::Op { kind: 4, owner: c.owner, input: c.builder, version: c.builder_version, output: c.result, output_version: c.result_version, proof1: 6, site: s.return_site.start }
    ];
    for i in 6 { if !loop_core::same_evidence(core.evidence[i],proof[i]) { return false; } }
    for i in 4 { if !loop_core::same_op(core.ops[i],ops[i]) { return false; } }
    return true;
}
