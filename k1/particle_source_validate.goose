// Independent closed particle-source recognizer and semantic-record checker.
// It re-lexes trusted expected bytes, reconstructs all field/operation sites,
// proof dependencies and op links without invoking the producer. The lexer is
// shared, and caller-supplied Context is trusted symbolic fixture data; this
// is not general type/effect/loan checking, domain authentication or an M13
// certificate. Accepting this subset does not make raw Wasm handles authority.
namespace particle_source_validate;
import lexer;
import particle_source_core;
fn verify(core:particle_source_core::Core&, source:u8[:], expected:particle_source_core::Context)->bool {
    if source.len>65536 || core.source[..]!=source || !particle_source_core::context_valid(expected) ||
       !particle_source_core::same_context(core.context,expected) {return false;}
    var lex=lexer::init(source); var token=lexer::next(source,lex); while token.kind==6 {token=lexer::next(source,lex);}
    var sites=particle_source_core::Sites {}; var reads:i64=0; var fields:i64=0; var pending:i64=0; var adds:i64=0; var muls:i64=0;
    for word in [
        "pub","let","project",":","forall","[","r",":","Region",",","s",":","Region",",","n",":","Nat",",","c",":","Nat",",","d",":","Domain","]","=>",
        "Fn","[","static",",","Many",",","(","View","[","r",",","{","x",":","F32",",","y",":","F32",",","vx",":","F32",",","vy",":","F32","}",",","n",",","d","]",",",
        "F32",",","Builder","[","s",",","{","x",":","F32",",","y",":","F32","}",",","0",",","c",",","Append","]",")",",",
        "exists","[","e",":","Domain","]","=>","View","[","s",",","{","x",":","F32",",","y",":","F32","}",",","n",",","e","]","]",
        "!","{","read","r",",","write","s","}","requires","[","Le","(","n",",","c",")","]","resources","{","depth",":","2",",","frame",":","256","}","=","fn","(","source",",","dt",",","initial",")","=>","do",":",
        "\n","\t","let","built","=","for","i","in","0","..","n","carry","(","b","=","initial",")","\n","\t",
        "invariant","[","Eq","(","Init","(","b",")",",","i",")","]","do",":","\n","\t",
        "next","(","builder",".","append","(","b",",","{","x",":","source","[","i","]",".","x","+","source","[","i","]",".","vx","*","dt",",",
        "y",":","source","[","i","]",".","y","+","source","[","i","]",".","vy","*","dt","}",")",")","@optional_newline","\r","\r",
        "return","builder",".","freeze","(","built",")","@optional_newline","\r"
    ] {
        if word=="@optional_newline" {if token.kind==6 {token=lexer::next(source,lex);} continue;}
        if word=="\n" {if token.kind!=6 {return false;}}
        else if word=="\t" {if token.kind!=7 {return false;}}
        else if word=="\r" {if token.kind!=8 {return false;}}
        else {
            let ch=word[0]; let kind=if ch>='0' && ch<='9' {2} else if (ch>='a' && ch<='z')||(ch>='A' && ch<='Z')||ch=='_' {1} else {5};
            if token.kind!=kind || token.start<0 || token.end<=token.start || token.end>source.len || source[token.start..token.end]!=word {return false;}
            let span=particle_source_core::Span {start:token.start,end:token.end};
            if pending>0 {
                pending-=1;
                if pending==0 {if fields>=4 {return false;} sites.field[fields]=span; fields+=1;}
            }
            if word=="requires" {sites.requires_site=span;}
            else if word=="for" {sites.for_site=span;}
            else if word=="invariant" {sites.invariant_site=span;}
            else if word=="next" {sites.next_site=span;}
            else if word=="append" {sites.append_site=span;}
            else if word=="freeze" {sites.freeze_site=span;}
            else if word=="return" {sites.return_site=span;}
            else if word=="source" {
                reads+=1; if reads>=2 {if reads>5 || pending!=0 {return false;} sites.read[reads-2]=span; pending=5;}
            } else if word=="+" {if adds>=2 {return false;} sites.add[adds]=span; adds+=1;}
            else if word=="*" {if muls>=2 {return false;} sites.mul[muls]=span; muls+=1;}
        }
        token=lexer::next(source,lex);
    }
    while token.kind==6 {token=lexer::next(source,lex);}
    if token.kind!=0 || reads!=5 || fields!=4 || pending!=0 || adds!=2 || muls!=2 || !particle_source_core::same_sites(core.sites,sites) {return false;}
    let c=expected; let s=sites;
    let evidence:particle_source_core::Evidence[6]=[
        particle_source_core::Evidence {rule:1,owner:c.owner,left:c.length,right:c.capacity,site:s.requires_site.start},
        particle_source_core::Evidence {rule:2,owner:c.owner,left:c.builder,right:c.index,version:c.builder_version,site:s.invariant_site.start},
        particle_source_core::Evidence {rule:3,owner:c.owner,left:c.index,right:c.length,version:c.input_version,site:s.for_site.start},
        particle_source_core::Evidence {rule:4,owner:c.owner,left:c.builder,right:c.capacity,version:c.builder_version,dep1:1,dep2:2,dep3:3,site:s.append_site.start},
        particle_source_core::Evidence {rule:5,owner:c.owner,left:c.next_builder,right:c.index,version:c.next_version,dep1:2,dep2:4,site:s.next_site.start},
        particle_source_core::Evidence {rule:6,owner:c.owner,left:c.result,right:c.length,version:c.result_version,dep1:2,dep2:5,site:s.return_site.start}
    ];
    let ops:particle_source_core::Op[13]=[
        particle_source_core::Op {kind:1,owner:c.owner,symbol:c.input,version:c.input_version,index:c.index,domain:c.input_domain,field:0,proof:3,site:s.read[0].start,field_site:s.field[0].start},
        particle_source_core::Op {kind:1,owner:c.owner,symbol:c.input,version:c.input_version,index:c.index,domain:c.input_domain,field:2,proof:3,site:s.read[1].start,field_site:s.field[1].start},
        particle_source_core::Op {kind:2,owner:c.owner,a:2,symbol:c.dt,version:c.dt_version,site:s.mul[0].start},
        particle_source_core::Op {kind:3,owner:c.owner,a:1,b:3,site:s.add[0].start},
        particle_source_core::Op {kind:1,owner:c.owner,symbol:c.input,version:c.input_version,index:c.index,domain:c.input_domain,field:1,proof:3,site:s.read[2].start,field_site:s.field[2].start},
        particle_source_core::Op {kind:1,owner:c.owner,symbol:c.input,version:c.input_version,index:c.index,domain:c.input_domain,field:3,proof:3,site:s.read[3].start,field_site:s.field[3].start},
        particle_source_core::Op {kind:2,owner:c.owner,a:6,symbol:c.dt,version:c.dt_version,site:s.mul[1].start},
        particle_source_core::Op {kind:3,owner:c.owner,a:5,b:7,site:s.add[1].start},
        particle_source_core::Op {kind:4,owner:c.owner,a:4,b:8,site:s.append_site.start},
        particle_source_core::Op {kind:5,owner:c.owner,a:9,symbol:c.builder,version:c.builder_version,output:c.next_builder,output_version:c.next_version,proof:4,site:s.append_site.start},
        particle_source_core::Op {kind:6,owner:c.owner,symbol:c.next_builder,version:c.next_version,output:c.builder,output_version:c.builder_version,proof:5,site:s.next_site.start},
        particle_source_core::Op {kind:7,owner:c.owner,symbol:c.builder,version:c.builder_version,output:c.result,output_version:c.result_version,domain:c.result_domain,proof:6,site:s.freeze_site.start},
        particle_source_core::Op {kind:8,owner:c.owner,symbol:c.result,version:c.result_version,domain:c.result_domain,site:s.return_site.start}
    ];
    for i in 6 {if !particle_source_core::same_evidence(core.evidence[i],evidence[i]) {return false;}}
    for i in 13 {if !particle_source_core::same_op(core.ops[i],ops[i]) {return false;}}
    return true;
}
