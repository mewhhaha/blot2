import runtime.memory;
import support.json;
import support.io;
import support.error;
// Actual reusable storage: scalar reuse, span reuse, moving growth and shrink.
export "observer_probe" fn probe()->i64 {
    reusable var cells:i64[>..]=[];
    let first=cells.alloc_index(7);
    let second=cells.alloc_index(8);
    cells.free(first);
    let reused=cells.alloc_index(9);
    assert(reused==first && cells[second]==8);
    reusable[] var spans:i64[>..]=[];
    let a=spans.alloc_slice(4);
    let b=spans.alloc_slice(2);
    spans.free_slice(a);
    let c=spans.alloc_slice(3);
    c[0]=123;
    let grown=spans.realloc_slice(c,5);
    assert(grown[0]==123 && grown.len==5);
    let shrunk=spans.realloc_slice(grown,1);
    assert(shrunk[0]==123 && shrunk.len==1);
    spans.free_slice(shrunk);
    spans.free_slice(b);
    return cells[reused]+cells[second]+1;
}
export "observer_invalid" fn invalid(length:i64) {
    reusable[] var spans:i64[>..]=[];
    spans.alloc_slice(length);
}

export "observer_report" fn report() {
    var bytes:u8[>..]=[];
    var writer=blot_json::Writer{out:bytes,options:blot_json::Options{..},..};
    let error=blot_runtime_memory::jsonStringify(blot_runtime_memory::Counts{..},writer);
    assert(error==blot_error::Error.none);
    bytes.push('\n');
    assert(blot_io::write_all(blot_io::Writer{1},bytes[..])==blot_error::Error.none);
}
