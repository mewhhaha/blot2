// Physical slots follow names independently of source evaluation order.
namespace blot_check_record_order;
import std;
import dictionary;
import support.error;
struct Names { map: dictionary<u32, const u8[:]>& }
fn init(map: dictionary<u32, const u8[:]>&) -> Names { return Names { map , ..}; }
fn deinit(self: Names&) { self.map.clear(); }
fn add(self: Names&, module: const blot_check_core::Module&) -> blot_error::Error {
    for field in module.field_names {
        let text = module.name(field.spelling);
        block {
            let previous = self.map.get(field.symbol);
            if previous {
                if previous != text { return blot_error::Error.type_mismatch; }
                continue;
            }
        }
        self.map.insert(field.symbol, text);
    }
    return blot_error::Error.none;
}
fn less(self: const Names&, left: u32, right: u32) -> bool {
    let a = self.map.get(left); let b = self.map.get(right);
    if a { if b { return compare(a, b) < 0; } return false; }
    if b { return true; }
    return left < right;
}
fn destinations(source, record: blot_check_types::Node, names: const Names&) -> u32[>..], blot_error::Error {
    assert(record.tag == blot_check_types::Tag.record);
    if record.b < 2 { return [], blot_error::Error.none; }
    var ordered = true;
    for index in 1..record.b {
        if !less(names, source.recordField(record, index - 1).name, source.recordField(record, index).name) { ordered = false; break; }
    }
    if ordered { return [], blot_error::Error.none; }
    var sorted: u32[>..] = [];
    for i in record.b { sorted.push(i as u32); }
    for i in 1..sorted.len {
        let original = sorted[i]; var j = i;
        while j > 0 && less(names, source.recordField(record, original).name, source.recordField(record, sorted[j - 1]).name) {
            sorted[j] = sorted[j - 1]; j -= 1;
        }
        sorted[j] = original;
    }
    var result: u32[>..] = [];
    for i in record.b { result.push(0); }
    for original, index in sorted { result[original] = index as u32; }
    return result, blot_error::Error.none;
}
