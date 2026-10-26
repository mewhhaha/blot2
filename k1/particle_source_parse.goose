// Private producer for exactly one spelled F32 particle projection declaration.
// The finite token grammar below accepts whitespace/comments but no alternative
// identifiers, expressions, statements, contracts or layouts. It is a bounded
// demonstration, not general source/type/loan/resource admission. Real region
// and View/Builder authority must already be supplied by a trusted caller.
namespace particle_source_parse;
import lexer;
import particle_source_core;
fn parse(source:u8[:], context:particle_source_core::Context)->particle_source_core::Core,i64 {
    if source.len>65536 {return particle_source_core::Core {},2;}
    if !particle_source_core::context_valid(context) {return particle_source_core::Core {},1;}
    var lex=lexer::init(source); var t=lexer::next(source,lex);
    while t.kind==6 {t=lexer::next(source,lex);}
    var s=particle_source_core::Sites {}; var source_count:i64=0; var field_pending=false; var adds:i64=0; var muls:i64=0;
    for text in [
        "pub","let","project",":","forall","[","r",":","Region",",","s",":","Region",",","n",":","Nat",",","c",":","Nat",",","d",":","Domain","]","=>",
        "Fn","[","static",",","Many",",","(","View","[","r",",","{","x",":","F32",",","y",":","F32",",","vx",":","F32",",","vy",":","F32","}",",","n",",","d","]",",",
        "F32",",","Builder","[","s",",","{","x",":","F32",",","y",":","F32","}",",","0",",","c",",","Append","]",")",",",
        "exists","[","e",":","Domain","]","=>","View","[","s",",","{","x",":","F32",",","y",":","F32","}",",","n",",","e","]","]",
        "!","{","read","r",",","write","s","}","requires","[","Le","(","n",",","c",")","]",
        "resources","{","depth",":","2",",","frame",":","256","}","=","fn","(","source",",","dt",",","initial",")","=>","do",":",
        "\n","\t","let","built","=","for","i","in","0","..","n","carry","(","b","=","initial",")","\n","\t",
        "invariant","[","Eq","(","Init","(","b",")",",","i",")","]","do",":","\n","\t",
        "next","(","builder",".","append","(","b",",","{","x",":","source","[","i","]",".","x","+","source","[","i","]",".","vx","*","dt",",",
        "y",":","source","[","i","]",".","y","+","source","[","i","]",".","vy","*","dt","}",")",")","@optional_newline","\r","\r",
        "return","builder",".","freeze","(","built",")","@optional_newline","\r"
    ] {
        if text=="@optional_newline" { if t.kind==6 {t=lexer::next(source,lex);} continue; }
        if text=="\n" {if t.kind!=6 {return particle_source_core::Core {},1;}}
        else if text=="\t" {if t.kind!=7 {return particle_source_core::Core {},1;}}
        else if text=="\r" {if t.kind!=8 {return particle_source_core::Core {},1;}}
        else {
            let first=text[0];
            let kind=if first>='0' && first<='9' {2} else if (first>='a' && first<='z') || (first>='A' && first<='Z') || first=='_' {1} else {5};
            if t.kind!=kind || t.start<0 || t.end<=t.start || t.end>source.len || source[t.start..t.end]!=text {return particle_source_core::Core {},1;}
            let span=particle_source_core::Span {start:t.start,end:t.end};
            if text=="requires" {s.requires_site=span;}
            else if text=="for" {s.for_site=span;}
            else if text=="invariant" {s.invariant_site=span;}
            else if text=="next" {s.next_site=span;}
            else if text=="append" {s.append_site=span;}
            else if text=="freeze" {s.freeze_site=span;}
            else if text=="return" {s.return_site=span;}
            else if text=="source" {
                source_count+=1;
                if source_count>=2 { if source_count>5 || field_pending {return particle_source_core::Core {},1;} s.read[source_count-2]=span; field_pending=true; }
            } else if field_pending && (text=="x" || text=="y" || text=="vx" || text=="vy") {
                s.field[source_count-2]=span; field_pending=false;
            } else if text=="+" { if adds>=2 {return particle_source_core::Core {},1;} s.add[adds]=span; adds+=1; }
            else if text=="*" { if muls>=2 {return particle_source_core::Core {},1;} s.mul[muls]=span; muls+=1; }
        }
        t=lexer::next(source,lex);
    }
    while t.kind==6 {t=lexer::next(source,lex);}
    if t.kind!=0 || source_count!=5 || field_pending || adds!=2 || muls!=2 {return particle_source_core::Core {},1;}
    return particle_source_core::Core {source:source,context:context,sites:s,evidence:particle_source_core::proofs(context,s),ops:particle_source_core::operations(context,s)},0;
}
