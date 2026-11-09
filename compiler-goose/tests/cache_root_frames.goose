// Cache-owned path views survive reads into the independent high-water frame buffer.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import reuse.restart_cache;
import reuse.zig_project_frames;
import reuse.zig_project_server;
import support.io;
import support.native;
import support.error;
fn readFrames(reader:blot_io::Reader,cache_root:blot_support::Option<const u8[:]>) {
    for index in 0..2 {
        let frame,present,error=blot_reuse_zig_project_frames::readRequestFrame(reader,blot_reuse_zig_project_server::request_bytes);
        assert(error==blot_error::Error.none && present);
        assert(cache_root.present && cache_root.value=="/tmp/blot-cache-root-law");
        if index==0 {assert(frame.metadata().len==4097 && frame.metadata()[0]==97 && frame.metadata()[4096]==97 && blot_reuse_zig_project_server::request_bytes.len==4097);}
        else {assert(frame.metadata()=="d" && blot_reuse_zig_project_server::request_bytes.len==4097);}
    }
}
fn main() {
    let path="cache_root_frames_law.frames\0";
    let output=blot_native::open_write(path[0],false);assert(output>=0);
    let header:u8[8]=[1,16,0,0,0,0,0,0];let payload:u8[4097]=[97;4097];let second:u8[9]=[1,0,0,0,0,0,0,0,'d'];
    assert(blot_io::write_all(blot_io::Writer{output},header[..])==blot_error::Error.none);
    assert(blot_io::write_all(blot_io::Writer{output},payload[..])==blot_error::Error.none);
    assert(blot_io::write_all(blot_io::Writer{output},second[..])==blot_error::Error.none);assert(blot_native::close(output)==0);
    let input=blot_native::open_read(path[0]);assert(input>=0);
    var cache=blot_support::none<u8[:]>();let root=blot_reuse_restart_cache::absolute("/tmp/blot-cache-root-law");cache=root;
    var cache_root=blot_support::none<const u8[:]>();if cache.present {cache_root=blot_support::some<const u8[:]>(cache.value[..]);}
    readFrames(blot_io::Reader{input},cache_root);
    assert(blot_native::close(input)==0 && blot_native::remove_file(path[0])==0);
    if cache.present {blot_reuse_restart_cache::releaseRoot(cache.value);}
    print("cache root frames passed: separate owners, repeated high-water frame reads");
}
