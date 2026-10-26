// Independent source-bound recognizer for private import records.
namespace project_imports_check;
import lexer;
import validate;
import project_imports;
fn verify(s:u8[:],records:project_imports::Import[:]) -> bool {
    if s.len>16777216 || records.len>256 {return false;}
    var state=lexer::init(s);var t=lexer::next(s,state);var index:i64=0;
    while t.kind==6 {t=lexer::next(s,state);}
    while t.kind==1 && t.start>=0 && t.end<=s.len && s[t.start..t.end]=="import" {
        if index>=records.len {return false;}
        let r=records[index];index+=1;t=lexer::next(s,state);
        if t.kind!=4 || t.start<0 || t.end-t.start<3 || t.end>s.len || r.path_start!=t.start+1 || r.path_end!=t.end-1 {return false;}
        for b in s[r.path_start..r.path_end] {if b=='\\' {return false;}}
        t=lexer::next(s,state);
        if t.kind!=1 || t.start<0 || t.end>s.len || s[t.start..t.end]!="as" {return false;}
        t=lexer::next(s,state);
        if t.kind!=1 || t.start<0 || t.end<=t.start || t.end>s.len || r.alias_start!=t.start || r.alias_end!=t.end ||
           !validate::name_valid(s[t.start..t.end]) {return false;}
        for i in 0..index-1 {
            let earlier=records[i];
            if earlier.alias_start<0 || earlier.alias_end<=earlier.alias_start || earlier.alias_end>s.len ||
               s[earlier.alias_start..earlier.alias_end]==s[r.alias_start..r.alias_end] {return false;}
        }
        t=lexer::next(s,state);if t.kind==6 {t=lexer::next(s,state);}else if t.kind!=0 {return false;}
        while t.kind==6 {t=lexer::next(s,state);}
    }
    if index!=records.len {return false;}
    while t.kind!=0 {
        if t.kind==9 || (t.kind==1 && t.start>=0 && t.end<=s.len && s[t.start..t.end]=="import") {return false;}
        t=lexer::next(s,state);
    }
    return true;
}
