// Private bounded preamble parser. This finds imports and validates lexing,
// not declarations, types, effects, resource proofs, or a complete K1 module.
namespace project_imports;
import lexer;
import validate;
struct Import {path_start:i64=0,path_end:i64=0,alias_start:i64=0,alias_end:i64=0}
struct Result {status:i64=0, imports:Import[]=[]}
fn matches(s:u8[:],t:lexer::Token,k:i64,word:u8[:]) -> bool {
    return t.kind==k && t.start>=0 && t.end>t.start && t.end<=s.len && s[t.start..t.end]==word;
}
fn parse(s:u8[:]) -> Result {
    var state=lexer::init(s);var t=lexer::next(s,state);var found:Import[>..]=[];
    while t.kind==6 {t=lexer::next(s,state);}
    while matches(s,t,1,"import") {
        if found.len>=256 {return Result {status:2};}
        t=lexer::next(s,state);
        if t.kind!=4 || t.start<0 || t.end-t.start<3 || t.end>s.len {return Result {status:1};}
        let start=t.start+1;let end=t.end-1;
        // Source-escaped paths are deliberately outside this loader subset.
        for b in s[start..end] {if b=='\\' {return Result {status:1};}}
        t=lexer::next(s,state);if !matches(s,t,1,"as") {return Result {status:1};}
        t=lexer::next(s,state);
        if t.kind!=1 || t.start<0 || t.end<=t.start || t.end>s.len || !validate::name_valid(s[t.start..t.end]) {return Result {status:1};}
        let alias_start=t.start;let alias_end=t.end;
        for prior in found {if s[prior.alias_start..prior.alias_end]==s[alias_start..alias_end] {return Result {status:3};}}
        found.push(Import {path_start:start,path_end:end,alias_start:alias_start,alias_end:alias_end});
        t=lexer::next(s,state);
        if t.kind==6 {t=lexer::next(s,state);}else if t.kind!=0 {return Result {status:1};}
        while t.kind==6 {t=lexer::next(s,state);}
    }
    // Imports are forbidden after any declaration/body token. Complete
    // declaration parsing is the responsibility of a later compiler stage.
    while t.kind!=0 {
        if t.kind==9 || matches(s,t,1,"import") {return Result {status:1};}
        t=lexer::next(s,state);
    }
    return Result {imports:found};
}
