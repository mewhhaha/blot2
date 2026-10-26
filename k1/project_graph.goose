// Private bounded project source graph and filesystem observations. This is
// not declaration/type checking, a K1 compilation, filesystem snapshot,
// artifact authority, or a complete dependency query engine.
namespace project_graph;
import lexer;
import public_interface;
import source_resolver;
import source_identity;
import project_imports;
import project_imports_check;

extern fn k1_project_probe(root:i64,path:const u8[:]) -> i64;
struct Module {path_start:i64=0,path_end:i64=0,source_start:i64=0,source_end:i64=0}
struct Edge {from:i64=0,to:i64=0,alias_start:i64=0,alias_end:i64=0}
// The caller must identify the source module whose relative lookup is being
// observed. This fixture's explicit probes are not automatically discovered
// compiler queries and cannot establish a complete dependency set.
// Kind 1 is a source-file lookup; other query kinds are not yet supported.
struct Probe {kind:u32=1,base:u8[]=[],path:u8[]=[]}
struct Observation {kind:u32=0,base_start:i64=0,base_end:i64=0,request_start:i64=0,request_end:i64=0,
                    path_start:i64=0,path_end:i64=0,found:bool=false,source_start:i64=0,source_end:i64=0}
struct Graph {package:u8[]=[],paths:u8[]=[],sources:u8[]=[],modules:Module[]=[],edges:Edge[]=[],observations:Observation[]=[]}
// 0 graph, 1 malformed source/import, 2 fixture bound, 3 missing required module,
// 4 filesystem/security/unsupported error, 5 cycle. Failed graphs are empty.
struct Result {status:i64=0,graph:Graph=Graph {},missing:u8[]=[]}
fn find(paths:u8[:],modules:Module[:],name:u8[:]) -> i64 {
    for m,i in modules {
        if m.path_start<0 || m.path_end<m.path_start || m.path_end>paths.len {return -1;}
        if paths[m.path_start..m.path_end]==name {return i;}
    }
    return -1;
}
fn acyclic(modules:Module[:],edges:Edge[:]) -> bool {
    if modules.len<1 || modules.len>64 || edges.len>256 {return false;}
    var incoming:i64[64]=[0;64];var queue:i64[64]=[0;64];
    for e in edges {if e.from<0 || e.from>=modules.len || e.to<0 || e.to>=modules.len {return false;}incoming[e.to]+=1;}
    var tail:i64=0;for i in modules.len {if incoming[i]==0 {queue[tail]=i;tail+=1;}}
    var head:i64=0;
    while head<tail {
        let n=queue[head];head+=1;
        for e in edges {if e.from==n {incoming[e.to]-=1;if incoming[e.to]==0 {queue[tail]=e.to;tail+=1;}}}
    }
    return tail==modules.len;
}
// The root is exclusively owned by the caller, remains open throughout the
// entire graph request, and is never copied or closed by this function.
fn build(root:source_resolver::Root&, entry:u8[:], probes:Probe[:]) -> Result {
    if root.handle<0 || !public_interface::package_valid(root.package) ||
       !public_interface::module_valid(entry) {return Result {status:1};}
    if entry.len>4096 || probes.len>64 {return Result {status:2};}
    var paths:u8[>..]=[];var sources:u8[>..]=[];
    var modules:Module[>..]=[];var edges:Edge[>..]=[];var observations:Observation[>..]=[];
    paths.append(entry);modules.push(Module {path_start:0,path_end:entry.len});
    var at:i64=0;
    while at<modules.len {
        let meta=modules[at];var path:u8[>..]=[];path.append(paths[meta.path_start..meta.path_end]);
        var source:u8[>..]=[];
        let status=source_resolver::k1_source_read_under(root.handle,path,source);
        if status!=0 {
            if status==1 && k1_project_probe(root.handle,path)==0 {return Result {status:3,missing:path};}
            if status==2 {return Result {status:2};}
            return Result {status:4};
        }
        if source.len>16777216-sources.len {return Result {status:2};}
        if lexer::invalid_utf8(source)>=0 {return Result {status:1};}
        let parsed=project_imports::parse(source);
        if parsed.status!=0 {return Result {status:if parsed.status==2 {2} else {1}};}
        if !project_imports_check::verify(source,parsed.imports) {return Result {status:1};}
        let offset=sources.len;sources.append(source);modules[at].source_start=offset;modules[at].source_end=sources.len;
        for imp in parsed.imports {
            if edges.len>=256 {return Result {status:2};}
            let resolved=source_identity::normalize_import(path,source[imp.path_start..imp.path_end]);
            if resolved.status!=0 {return Result {status:if resolved.status==3 {2} else {1}};}
            if resolved.path.len>4096 {return Result {status:2};}
            var target=find(paths,modules,resolved.path);
            if target<0 {
                if modules.len>=64 || resolved.path.len>524288-paths.len {return Result {status:2};}
                target=modules.len;let start=paths.len;paths.append(resolved.path);
                modules.push(Module {path_start:start,path_end:paths.len});
            }
            edges.push(Edge {from:at,to:target,alias_start:offset+imp.alias_start,alias_end:offset+imp.alias_end});
        }
        at+=1;
    }
    if !acyclic(modules,edges) {return Result {status:5};}
    for probe in probes {
        if probe.kind!=1 {return Result {status:1};}
        if probe.base.len>4096 || probe.path.len>4096 {return Result {status:2};}
        if find(paths,modules,probe.base)<0 {return Result {status:1};}
        let resolved=source_identity::normalize_import(probe.base,probe.path);
        if resolved.status!=0 {return Result {status:if resolved.status==3 {2} else {1}};}
        if resolved.path.len>4096 || probe.base.len>524288-paths.len {return Result {status:2};}
        let base_start=paths.len;paths.append(probe.base);let base_end=paths.len;
        if probe.path.len>524288-paths.len {return Result {status:2};}
        let request_start=paths.len;paths.append(probe.path);let request_end=paths.len;
        if resolved.path.len>524288-paths.len {return Result {status:2};}
        let start=paths.len;paths.append(resolved.path);
        var observed:u8[>..]=[];let status=source_resolver::k1_source_read_under(root.handle,resolved.path,observed);
        if status==0 {
            if observed.len>16777216-sources.len {return Result {status:2};}
            if lexer::invalid_utf8(observed)>=0 {return Result {status:1};}
            let content_start=sources.len;sources.append(observed);
            observations.push(Observation {kind:probe.kind,base_start:base_start,base_end:base_end,
                request_start:request_start,request_end:request_end,path_start:start,path_end:paths.len,
                found:true,source_start:content_start,source_end:sources.len});
        } else {
            // A read error must not be mistaken for absence. Only an independent
            // descriptor-relative ENOENT is recorded as a negative lookup.
            if status==2 {return Result {status:2};}
            if status!=1 || k1_project_probe(root.handle,resolved.path)!=0 {return Result {status:4};}
            observations.push(Observation {kind:probe.kind,base_start:base_start,base_end:base_end,
                request_start:request_start,request_end:request_end,path_start:start,path_end:paths.len});
        }
    }
    return Result {graph:Graph {package:copy(root.package),paths:paths,sources:sources,modules:modules,edges:edges,observations:observations}};
}
// Exact graph comparison, including all source bytes and ordered positive/
// negative observation bytes. No hash equality is used as authority.
fn same(a:Graph&,b:Graph&) -> bool {
    return a.package[..]==b.package[..] && a.paths[..]==b.paths[..] && a.sources[..]==b.sources[..] &&
        a.modules[..]==b.modules[..] && a.edges[..]==b.edges[..] && a.observations[..]==b.observations[..];
}
