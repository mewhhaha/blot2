// Parse independent modules before the authoritative depth-first loader
// publishes unit IDs, symbols and diagnostics in source order.
namespace squid_reuse_project;
import .project;
import reuse.parse_packet;
import dictionary;
import support.pooled_map;

struct ParseInput { path:const u8[:], source:const u8[:], taken:bool=false }
reusable[] var parse_inputs:ParseInput[>..]=[];
reusable[] var parse_paths:dictionary_slot<const u8[:],u32>[>..]=[];
reusable[] var parse_raw_keys:const u8[:][>..]=[];
struct ParseBatch {
    paths:squid_support_pooled_map::Map<const u8[:],u32> =squid_support_pooled_map::Map<const u8[:],u32>{},
    raw_paths:squid_support_pooled_map::Map<const u8[:],u32> =squid_support_pooled_map::Map<const u8[:],u32>{},
    raw_keys:squid_support_pooled_buffer::Buffer<const u8[:]> =squid_support_pooled_buffer::Buffer<const u8[:]>{},
    inputs:squid_support_pooled_buffer::Buffer<ParseInput> =squid_support_pooled_buffer::Buffer<ParseInput>{},
    scratch:u8[:]=default<u8[:]>(),
    total:i64=0,
    shared:u64=0,
}
fn deinit(batch:ParseBatch&) {
    if batch.shared!=0 {squid_native::persist_close(batch.shared);}
    if batch.scratch.len!=0 {owned_source.free_slice(batch.scratch);batch.scratch=default<u8[:]>();}
    batch.paths.deinit(parse_paths);
    batch.raw_paths.deinit(parse_paths);
    for key in batch.raw_keys.items {releaseSource(key);}
    squid_support_pooled_buffer::deinit(batch.raw_keys,parse_raw_keys);
    for item in batch.inputs.items {releaseSource(item.path);if !item.taken {releaseSource(item.source);}}
    squid_support_pooled_buffer::deinit(batch.inputs,parse_inputs);
    batch.shared=0;
}
fn canonicalSource(bytes:const u8[:])->const u8[:] {
    if bytes.len==0 {return default<const u8[:]>();}
    let result=owned_source.realloc_slice(bytes,bytes.len);
    assert(squid_support::same_slice_identity(result,bytes));
    return result;
}
fn probed(batch:const ParseBatch&,path:const u8[:])->squid_support::Option<ParseInput> {
    if batch.shared==0 {return squid_support::none<ParseInput>();}
    let raw_idx .= batch.raw_paths.get(path);
    if raw_idx {
        let item=batch.inputs.items[raw_idx];
        var src=default<const u8[:]>();
        if !item.taken {src=canonicalSource(item.source);}
        return squid_support::some(ParseInput{canonicalSource(item.path),src,item.taken});
    }
    let idx .= batch.paths.get(path);
    if idx {
        let item=batch.inputs.items[idx];
        var src=default<const u8[:]>();
        if !item.taken {src=canonicalSource(item.source);}
        return squid_support::some(ParseInput{canonicalSource(item.path),src,item.taken});
    }
    return squid_support::none<ParseInput>();
}
fn takeSource(batch:ParseBatch&,path:const u8[:],source:const u8[:])->const u8[:],bool {
    if batch.shared==0 {return default<const u8[:]>(),false;}
    let index .= batch.paths.get(path);
    if !index {return default<const u8[:]>(),false;}
    let item .= batch.inputs.items[index];
    if item.taken || !squid_support::same_slice_identity(item.source,source) {return default<const u8[:]>(),false;}
    item.taken=true;
    return canonicalSource(item.source),true;
}
fn adopt(batch:ParseBatch&,path:const u8[:],source:const u8[:],symbols:squid_parse_symbols::Pool&,tree:squid_parse_ast::Tree&,recorded:squid_parse_parser::ScratchIdBuffer&)->bool {
    if batch.shared==0 {return false;}
    let index .= batch.paths.get(path);
    if !index {return false;}
    let expected=batch.inputs.items[index].source;
    if !squid_support::same_slice_identity(expected,source) && expected!=source {return false;}
    let id=index+1;
    let size=squid_native::persist_size(batch.shared,id,2);
    if size<=1 {return false;}
    return squid_reuse_parse_packet::decodeFromPersist(batch.shared,id,2,size,symbols,tree,recorded);
}
fn addParseInput<P>(loader:Loader<P>&,path:const u8[:],dir_map:dictionary<const u8[:],const u8[:]>&,dir_owned:const u8[:][>..<]&,name:u8[>..<]&) {
    let batch .= loader.parse_batch;
    if batch.inputs.items.len>=min(16384,loader.options.max_files) {return;}
    if batch.raw_paths.contains(path) || batch.paths.contains(path) {return;}
    let limit=min(loader.options.max_source_bytes,loader.options.max_total_source_bytes-batch.total-loader.project.source_bytes);
    if limit<=0 {return;}
    name.clear();
    let owned_src,probed_ok=loader.inputs.probeSourceOwned(path,limit,dir_map,dir_owned,name);
    if !probed_ok {return;}
    let existing .= batch.paths.get(name[..]);
    if existing {
        releaseSource(owned_src);
        if path!=name[..] {
            let existing_idx:u32=existing;
            let owned_raw=copySource(path);
            if batch.raw_keys.push(owned_raw,parse_raw_keys)==squid_error::Error.none {
                batch.raw_paths.insert(owned_raw,existing_idx,parse_paths);
            } else {releaseSource(owned_raw);}
        }
        return;
    }
    let sym,present=loader.project.symbols.lookup(name[..]);
    if present && loader.files.get(sym)!=null {releaseSource(owned_src);return;}
    let input=ParseInput{copySource(name[..]),owned_src,false};
    let error=batch.inputs.push(input,parse_inputs);
    if error!=squid_error::Error.none {releaseSource(input.path);releaseSource(input.source);return;}
    let idx=(batch.inputs.items.len-1) as u32;
    batch.paths.insert(input.path,idx,parse_paths);
    if path!=input.path {
        let owned_raw=copySource(path);
        if batch.raw_keys.push(owned_raw,parse_raw_keys)==squid_error::Error.none {
            batch.raw_paths.insert(owned_raw,idx,parse_paths);
        } else {releaseSource(owned_raw);}
    }
    batch.total+=owned_src.len;
}
// Discover literal imports cheaply. Unsupported spellings are left to the
// normal loader. Only a successful parse of the exact source can be adopted.
fn discoverParseInputs<P>(loader:Loader<P>&,input:ParseInput,dir_map:dictionary<const u8[:],const u8[:]>&,dir_owned:const u8[:][>..<]&,name:u8[>..<]&,path:u8[>..<]&) {
    let src=input.source;
    var at:i64=0;
    while at<src.len {
        let start=at;
        while at<src.len && src[at]!='\n' {at++;}
        let line=src[start..at];
        at++;
        var content:i64=0;
        while content<line.len && (line[content]==' ' || line[content]=='\t' || line[content]=='\r') {content++;}
        if content==line.len || starts(line[content..],"//") {continue;}
        if !starts(line,"import ") && !starts(line,"export ") {break;}
        var quote:i64=0;
        while quote<line.len && line[quote]!='"' {quote++;}
        if quote==line.len || quote<5 || line[quote-5..quote]!="from " {break;}
        var end=quote+1;
        while end<line.len && line[end]!='"' {end++;}
        if end==line.len {break;}
        path.clear();
        if resolveImportPath(input.path,line[quote+1..end],loader.options,path)==squid_error::Error.none {addParseInput(loader,path[..],dir_map,dir_owned,name);}
    }
}
fn runParseLane<P>(loader:Loader<P>&)->bool {
    let batch .= loader.parse_batch;
    var tokens:squid_parse_token::Token[>..<]=[];
    var comments:squid_parse_token::Token[>..<]=[];
    var diagnostics:squid_parse_lexer::Diagnostic[>..<]=[];
    var local,pool_err=squid_parse_symbols::initPooled();
    if pool_err!=squid_error::Error.none {return false;}
    var tree,tree_err=squid_parse_ast::initPooled();
    if tree_err!=squid_error::Error.none {local.deinit();return false;}
    var bytes:u8[>..<]=[];
    loop {
        let job=squid_native::persist_claim(batch.shared);
        if job==0 {tree.deinit();local.deinit();return true;}
        if job<0 {tree.deinit();local.deinit();return false;}
        let ok=squid_reuse_parse_packet::encodeWithScratch(batch.inputs.items[job-1].source,loader.project.symbols,tokens,comments,diagnostics,local,tree,bytes);
        if !ok || bytes.len==0 {bytes.clear();bytes.push(0);}
        let id=job as u32;
        if !squid_native::persist_publish(batch.shared,id,2,bytes[0],bytes.len as u64) {tree.deinit();local.deinit();return false;}
    }
}
fn prepareParseBatch<P>(loader:Loader<P>&,entry:const u8[:],workers:u8) {
    if workers==1 || squid_native::platform_is_linux()==0 {return;}
    let batch .= loader.parse_batch;
    var dir_owned:const u8[:][>..<]=[];
    {
        var dir_map:dictionary<const u8[:],const u8[:]> = dictionary<const u8[:],const u8[:]>{};
        var name_buf:u8[>..<]=[];
        var path_buf:u8[>..<]=[];
        if loader.project.entry==0 {
            addParseInput(loader,entry,dir_map,dir_owned,name_buf);
        } else {
            let root=loader.project.entry;
            for edge in loader.project.unitImports(root) {
                path_buf.clear();
                if resolveImportPath(loader.project.filename(root),loader.project.symbols.get(edge.path),loader.options,path_buf)==squid_error::Error.none {
                    addParseInput(loader,path_buf[..],dir_map,dir_owned,name_buf);
                }
            }
        }
        var i:i64=0;
        while i<batch.inputs.items.len {let item=batch.inputs.items[i];discoverParseInputs(loader,item,dir_map,dir_owned,name_buf,path_buf);i++;}
    }
    for s in dir_owned {releaseSource(s);}
    dir_owned.clear();
    if batch.inputs.items.len<16 || batch.total<65536 {return;}
    var width=min(16,workers);
    if width==0 {
        var cap:u8=4;
        if batch.total>=524288 {cap=8;}
        if batch.total>=2097152 {cap=16;}
        width=min(cap,squid_native::available_workers());
    }
    if width<=1 {return;}

    let shared=squid_native::persist_open(batch.inputs.items.len as u32);
    if shared==0 {return;}
    batch.shared=shared;
    for item,index in batch.inputs.items {
        if !squid_native::persist_node(shared,(index+1) as u32,item.source.len as u32) {squid_native::persist_close(shared);batch.shared=0;return;}
    }
    var pids:i64[16]=[0;16];
    for lane in 1..(width as i64) {
        let pid=squid_native::fork_process();
        if pid==0 {
            if !runParseLane(loader) {squid_native::persist_fail(shared);squid_native::job_exit(1);}
            squid_native::job_exit(0);
        }
        if pid>0 {pids[lane]=pid;}
    }
    var ok=runParseLane(loader);
    if !ok {squid_native::persist_fail(shared);}
    for pid in pids {if pid>0 && !squid_native::wait_success(pid as u32) {ok=false;}}
    if !ok {squid_native::persist_close(shared);batch.shared=0;}
}
