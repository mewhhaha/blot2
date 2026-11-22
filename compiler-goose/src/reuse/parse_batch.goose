// Parse independent modules before the authoritative depth-first loader
// publishes unit IDs, symbols and diagnostics in source order.
namespace blot_reuse_project;
import .project;
import reuse.parse_packet;
import dictionary;
import support.pooled_map;

struct ParseInput { path:const u8[:], source:const u8[:] }
reusable[] var parse_inputs:ParseInput[>..]=[];
reusable[] var parse_paths:dictionary_slot<const u8[:],u32>[>..]=[];
reusable[] var parse_raw_keys:const u8[:][>..]=[];
struct ParseBatch {
    paths:blot_support_pooled_map::Map<const u8[:],u32> =blot_support_pooled_map::Map<const u8[:],u32>{},
    raw_paths:blot_support_pooled_map::Map<const u8[:],u32> =blot_support_pooled_map::Map<const u8[:],u32>{},
    raw_keys:blot_support_pooled_buffer::Buffer<const u8[:]> =blot_support_pooled_buffer::Buffer<const u8[:]>{},
    inputs:blot_support_pooled_buffer::Buffer<ParseInput> =blot_support_pooled_buffer::Buffer<ParseInput>{},
    total:i64=0,
    shared:u64=0,
}
fn deinit(batch:ParseBatch&) {
    if batch.shared!=0 {blot_native::persist_close(batch.shared);}
    batch.paths.deinit(parse_paths);
    batch.raw_paths.deinit(parse_paths);
    for key in batch.raw_keys.items {releaseSource(key);}
    blot_support_pooled_buffer::deinit(batch.raw_keys,parse_raw_keys);
    for item in batch.inputs.items {releaseSource(item.path);releaseSource(item.source);}
    blot_support_pooled_buffer::deinit(batch.inputs,parse_inputs);
    batch.shared=0;
}
fn canonicalSource(bytes:const u8[:])->const u8[:] {
    if bytes.len==0 {return default<const u8[:]>();}
    let result=owned_source.realloc_slice(bytes,bytes.len);
    assert(blot_support::same_slice_identity(result,bytes));
    return result;
}
fn probed(batch:const ParseBatch&,path:const u8[:])->blot_support::Option<ParseInput> {
    if batch.shared==0 {return blot_support::none<ParseInput>();}
    let raw_idx .= batch.raw_paths.get(path);
    if raw_idx {
        let item=batch.inputs.items[raw_idx];
        return blot_support::some(ParseInput{canonicalSource(item.path),canonicalSource(item.source)});
    }
    let idx .= batch.paths.get(path);
    if idx {
        let item=batch.inputs.items[idx];
        return blot_support::some(ParseInput{canonicalSource(item.path),canonicalSource(item.source)});
    }
    return blot_support::none<ParseInput>();
}
fn adopt(batch:ParseBatch&,path:const u8[:],source:const u8[:],symbols:blot_parse_symbols::Pool&,tree:blot_parse_ast::Tree&,recorded:blot_parse_parser::ScratchIdBuffer&)->bool {
    if batch.shared==0 {return false;}
    let index .= batch.paths.get(path);
    if !index {return false;}
    let expected=batch.inputs.items[index].source;
    if !blot_support::same_slice_identity(expected,source) && expected!=source {return false;}
    let id=index+1;
    let size=blot_native::persist_size(batch.shared,id,2);
    if size<=1 {return false;}
    var bytes:u8[>..<]=[];bytes.resize(size,0);
    if !blot_native::persist_read(batch.shared,id,2,bytes[0],size as u64) {return false;}
    return blot_reuse_parse_packet::decode(bytes[..],symbols,tree,recorded);
}
fn addParseInput<P>(loader:Loader<P>&,path:const u8[:]) {
    let batch .= loader.parse_batch;
    if batch.inputs.items.len>=min(4096,loader.options.max_files) {return;}
    if batch.raw_paths.contains(path) || batch.paths.contains(path) {return;}
    let limit=min(loader.options.max_source_bytes,loader.options.max_total_source_bytes-batch.total-loader.project.source_bytes);
    if limit<=0 {return;}
    var name:u8[>..<]=[];
    var source:u8[>..<]=[];
    if !loader.inputs.probeSource(path,limit,name,source) {return;}
    let existing .= batch.paths.get(name[..]);
    if existing {
        if path!=name[..] {
            let existing_idx:u32=existing;
            let owned_raw=copySource(path);
            if batch.raw_keys.push(owned_raw,parse_raw_keys)==blot_error::Error.none {
                batch.raw_paths.insert(owned_raw,existing_idx,parse_paths);
            } else {releaseSource(owned_raw);}
        }
        return;
    }
    let sym,present=loader.project.symbols.lookup(name[..]);
    if present && loader.files.get(sym)!=null {return;}
    let input=ParseInput{copySource(name[..]),copySource(source[..])};
    let error=batch.inputs.push(input,parse_inputs);
    if error!=blot_error::Error.none {releaseSource(input.path);releaseSource(input.source);return;}
    let idx=(batch.inputs.items.len-1) as u32;
    batch.paths.insert(input.path,idx,parse_paths);
    if path!=input.path {
        let owned_raw=copySource(path);
        if batch.raw_keys.push(owned_raw,parse_raw_keys)==blot_error::Error.none {
            batch.raw_paths.insert(owned_raw,idx,parse_paths);
        } else {releaseSource(owned_raw);}
    }
    batch.total+=source.len;
}
// Discover literal imports cheaply. Unsupported spellings are left to the
// normal loader. Only a successful parse of the exact source can be adopted.
fn discoverParseInputs<P>(loader:Loader<P>&,input:ParseInput) {
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
        var path:u8[>..<]=[];
        if resolveImportPath(input.path,line[quote+1..end],loader.options,path)==blot_error::Error.none {addParseInput(loader,path[..]);}
    }
}
fn runParseLane<P>(loader:Loader<P>&)->bool {
    let batch .= loader.parse_batch;
    let marker:u8=0;
    var tokens:blot_parse_token::Token[>..<]=[];
    var comments:blot_parse_token::Token[>..<]=[];
    var diagnostics:blot_parse_lexer::Diagnostic[>..<]=[];
    var local,pool_err=blot_parse_symbols::initPooled();
    if pool_err!=blot_error::Error.none {return false;}
    var bytes:u8[>..<]=[];
    loop {
        let job=blot_native::persist_claim(batch.shared);
        if job==0 {local.deinit();return true;}
        if job<0 {local.deinit();return false;}
        let ok=blot_reuse_parse_packet::encodeWithScratch(batch.inputs.items[job-1].source,loader.project.symbols,tokens,comments,diagnostics,local,bytes);
        if !ok || bytes.len==0 {bytes.clear();bytes.push(0);}
        let id=job as u32;
        if !blot_native::persist_publish(batch.shared,id,1,marker,1) || !blot_native::persist_publish(batch.shared,id,2,bytes[0],bytes.len as u64) {local.deinit();return false;}
    }
}
fn prepareParseBatch<P>(loader:Loader<P>&,entry:const u8[:],workers:u8) {
    var width=min(16,workers);
    if width==0 {width=min(8,blot_native::available_workers());}
    if width<=1 || blot_native::platform_is_linux()==0 {return;}
    let batch .= loader.parse_batch;
    if loader.project.entry==0 {
        addParseInput(loader,entry);
    } else {
        let root=loader.project.entry;
        for edge in loader.project.unitImports(root) {
            var path:u8[>..<]=[];
            if resolveImportPath(loader.project.filename(root),loader.project.symbols.get(edge.path),loader.options,path)==blot_error::Error.none {
                addParseInput(loader,path[..]);
            }
        }
    }
    var i:i64=0;
    while i<batch.inputs.items.len {let item=batch.inputs.items[i];discoverParseInputs(loader,item);i++;}
    if batch.inputs.items.len<16 || batch.total<65536 {return;}

    let shared=blot_native::persist_open(batch.inputs.items.len as u32);
    if shared==0 {return;}
    batch.shared=shared;
    for item,index in batch.inputs.items {
        if !blot_native::persist_node(shared,(index+1) as u32,item.source.len as u32) {blot_native::persist_close(shared);batch.shared=0;return;}
    }
    var pids:i64[16]=[0;16];
    for lane in 1..(width as i64) {
        let pid=blot_native::fork_process();
        if pid==0 {
            if !runParseLane(loader) {blot_native::persist_fail(shared);blot_native::job_exit(1);}
            blot_native::job_exit(0);
        }
        if pid>0 {pids[lane]=pid;}
    }
    var ok=runParseLane(loader);
    if !ok {blot_native::persist_fail(shared);}
    for pid in pids {if pid>0 && !blot_native::wait_success(pid as u32) {ok=false;}}
    if !ok {blot_native::persist_close(shared);batch.shared=0;}
}
