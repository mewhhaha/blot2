// A deliberately conservative whitespace formatter. It normalizes CRLF
// and removes trailing code whitespace, retaining comment bytes and indentation.
// Supported callers first parse a grammar without quoted strings; this helper
// alone is not a general K1 formatter or syntax authority.
namespace format_k1_normalize;
fn run(source:u8[:]) -> u8[] {
    var out:u8[>..]=[];var pos:i64=0;
    while pos<source.len {
        let start=pos;while pos<source.len && source[pos]!='\n' {pos+=1;}
        let newline=pos<source.len;var end=pos;
        if newline && end>start && source[end-1]=='\r' {end-=1;}
        var comment=false;var blank=true;var i=start;
        while i+1<end {if source[i]=='/' && source[i+1]=='/' {comment=true;break;}i+=1;}
        for j in start..end {if source[j]!=' ' && source[j]!='\t' {blank=false;break;}}
        if !comment && !blank {while end>start && (source[end-1]==' ' || source[end-1]=='\t') {end-=1;}}
        out.append(source[start..end]);
        if newline {out.push('\n');pos+=1;}
    }
    return out;
}
