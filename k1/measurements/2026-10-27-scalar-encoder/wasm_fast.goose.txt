// Private direct section encoder for the metered scalar fixture. This does
// not authenticate target bytes; the independent target verifier still runs.
namespace wasm_fast;
import wasm;

fn uleb_length(number:i64) -> i64 {
    var n=number;var count:i64=1;
    while n>=128 {count+=1;n=n/128;}
    return count;
}
fn emit_body(name:u8[:],body:u8[:]) -> u8[] {
    if !wasm::fixture_geometry_valid() || !wasm::identifier(name) {return [];}
    // A signed i64 length requires at most nine ULEB bytes. This guards each
    // section's framing arithmetic independently of available memory.
    let max:i64=9223372036854775807;
    if name.len>max-12 || body.len>max-10 {return [];}
    var output:u8[>..]=[0,0x61,0x73,0x6d,1,0,0,0];
    output.append([1,7,1,0x60,2,0x7f,0x7f,1,0x7f]);
    output.append([3,2,1,0]);
    // The independently checked scalar fixture fixes its two memory limits.
    output.append([5,6,1,1,0x93,2,0x93,2]);
    output.push(7);wasm::unsigned_leb(output,1+uleb_length(name.len)+name.len+2);
    output.push(1);wasm::unsigned_leb(output,name.len);output.append(name);output.push(0);output.push(0);
    output.push(10);wasm::unsigned_leb(output,1+uleb_length(body.len)+body.len);
    output.push(1);wasm::unsigned_leb(output,body.len);output.append(body);
    let metadata_name="blot.k1.fixture.memory";
    let metadata="{\"version\":1,\"page_bytes\":65536,\"pages\":275,\"granule_bytes\":4096,\"static_bytes\":0,\"dictionary_bytes\":0,\"control\":[0,16],\"owners\":[16,8192],\"owner_slots\":256,\"owner_stride\":32,\"bitmap\":[8208,512],\"frame\":[8720,1048576],\"ingress\":[1057296,65536],\"egress\":[1122832,65536],\"alignment_padding\":[1188368,3568],\"pool\":[1191936,16777216],\"page_padding\":[17969152,53248],\"memory_bytes\":18022400}";
    output.push(0);wasm::unsigned_leb(output,uleb_length(metadata_name.len)+metadata_name.len+metadata.len);
    wasm::unsigned_leb(output,metadata_name.len);output.append(metadata_name);output.append(metadata);
    return output;
}
