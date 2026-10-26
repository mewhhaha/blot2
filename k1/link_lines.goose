// Private physical-line splitter for the narrow link fixture. Import records
// are independently recognized first. Each non-import declaration must occupy
// one physical top-level line; general K1 module grammar is not implemented.
namespace link_lines;
import project_imports;
import project_imports_check;
struct Span {start:i64=0,end:i64=0}
struct Result {status:i64=0,lines:Span[]=[]}
fn split(source:u8[:]) -> Result {
    let imports=project_imports::parse(source);
    if imports.status!=0 || !project_imports_check::verify(source,imports.imports) {return Result {status:1};}
    var spans:Span[>..]=[];var pos:i64=0;var import_index:i64=0;
    while pos<source.len {
        let start=pos;while pos<source.len && source[pos]!='\n' {pos+=1;}
        if pos<source.len {pos+=1;}
        let end=pos;
        if import_index<imports.imports.len && imports.imports[import_index].path_start>=start &&
           imports.imports[import_index].path_start<end {import_index+=1;continue;}
        var first=start;while first<end && (source[first]==' ' || source[first]=='\t') {first+=1;}
        if first==end || source[first]=='\n' || source[first]=='\r' ||
           (first+1<end && source[first]=='/' && source[first+1]=='/') {continue;}
        if first!=start || spans.len>=256 {return Result {status:1};}
        spans.push(Span {start:start,end:end});
    }
    if import_index!=imports.imports.len {return Result {status:1};}
    return Result {lines:spans};
}
