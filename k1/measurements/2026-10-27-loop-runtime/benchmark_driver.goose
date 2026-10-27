// Scratch benchmark adapter for already-frozen private typed-canonical APIs.
// It reads trusted benchmark inputs only; not a public compiler interface.
import std;
import os;
import typed_canonical_frontend;
import typed_canonical_wasm;
fn main() {
 let argv=args();if argv.len!=2 {write_stderr("expected benchmark source path\n");exit(2);}
 var source:u8[>..]=[];if !read_file(argv[1],source) || source.len>65536 {write_stderr("benchmark input read/size failure\n");exit(3);}
 var parsed=typed_canonical_frontend::parse(source);if parsed.status!=0 {write_stderr("private canonical source rejected\n");exit(4);}
 let bytes=typed_canonical_wasm::emit(source,parsed.program);if bytes.len==0 {write_stderr("private canonical target validation failed\n");exit(5);}
 let hex="0123456789abcdef";var out:u8[>..]=[];for b in bytes {out.push(hex[b/16]);out.push(hex[b%16]);}out.push('\n');write_stdout(out);
}
