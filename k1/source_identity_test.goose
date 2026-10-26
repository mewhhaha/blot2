import std;
import source_identity;

fn expect(base: u8[:], input: u8[:], output: u8[:]) {
    let result = source_identity::normalize_import(base,input);
    assert(result.status == 0 && result.path[..] == output);
}
fn owned_scope() -> source_identity::Result {
    var package: u8[>..] = []; package.append("pkg");
    var module: u8[>..] = []; module.append("src/main.blot");
    var declaration: u8[>..] = []; declaration.append("id");
    var source: u8[>..] = []; source.append("let id: U32 -> U32 = fn x => return x\n");
    let result = source_identity::make(package,module,declaration,source);
    package[0] = 'X'; module[0] = 'X'; declaration[0] = 'X'; source[0] = 'X';
    return result;
}
fn main() {
    expect("src/main.blot","./module.blot","src/module.blot");
    expect("src/main.blot","lib/thing.blot","src/lib/thing.blot");
    expect("src/sub/main.blot","../thing.blot","src/thing.blot");
    expect("src/main.blot","../thing.blot","thing.blot");
    expect("main.blot","./child.blot","child.blot");
    expect("deep/inner/main.blot","./dir/../file.blot","deep/inner/file.blot");
    expect("src/main.blot","./\xce\xbb.blot","src/\xce\xbb.blot");
    assert(source_identity::normalize_import("main.blot","../outside.blot").status == 2);
    assert(source_identity::normalize_import("src/main.blot","../../outside.blot").status == 2);
    for relative in ["", "/etc/passwd", "C:/escape", "c:escape", "a\\b", "a//b", "a/", ".", "..", "a/.", "a/.."] {
        assert(source_identity::normalize_import("src/main.blot",relative).status != 0);
    }
    for base in ["", "/main.blot", "../main.blot", "a//main.blot", "a/../main.blot", "C:/main.blot"] {
        assert(source_identity::normalize_import(base,"./x.blot").status != 0);
    }
    let bad_utf8: u8[2] = [0xff, 0x61];
    assert(source_identity::normalize_import("main.blot",bad_utf8).status != 0);
    let nul: u8[3] = ['a', 0, 'b'];
    assert(source_identity::normalize_import("main.blot",nul).status != 0);
    let src = "let id: U32 -> U32 = fn x => return x\n";
    var owned = owned_scope();
    assert(owned.status == 0 && source_identity::verify(owned.source,"pkg","src/main.blot","id",src));
    assert(owned.source.fingerprint_domain == 1);
    var record = source_identity::make("pkg", "src/main.blot", "id", src);
    assert(record.status == 0 && source_identity::verify(record.source,"pkg","src/main.blot","id",src));
    assert(!source_identity::verify(record.source,"other","src/main.blot","id",src));
    assert(!source_identity::verify(record.source,"pkg","src/other.blot","id",src));
    assert(!source_identity::verify(record.source,"pkg","src/main.blot","other",src));
    assert(!source_identity::verify(record.source,"pkg","src/main.blot","id","different"));
    let fake: u8[32] = [0; 32];
    assert(!source_identity::same_bytes("first", fake, "other", fake));
    assert(source_identity::same_bytes("first", fake, "first", fake));
    owned.source.fingerprint_domain = 2;
    assert(!source_identity::verify(owned.source,"pkg","src/main.blot","id",src));
    record.source.fingerprint[0] ^= 1;
    assert(!source_identity::verify(record.source,"pkg","src/main.blot","id",src));
    assert(source_identity::make("pkg", "src/main.blot", "id", bad_utf8).status != 0);
    // This module has no file-open API; a successful logical name gives no
    // authority to follow a symlink or read a host path.
    print("source identity and logical paths: passed");
}
