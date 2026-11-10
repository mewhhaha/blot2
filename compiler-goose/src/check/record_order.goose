// Physical slots follow names independently of source evaluation order.
namespace blot_check_record_order;
import check.core;
import check.types;
import support.error;

import std;
import dictionary;
struct RecordName {unit:u32,spelling:blot_check_core::Name}
struct Names { map: dictionary<u32, RecordName>& }
fn init(map: dictionary<u32, RecordName>&) -> Names { return Names { map , ..}; }
fn deinit(self_: Names&) { self_.map.clear(); }
fn get(self_:const Names&,units:const blot_check_core::Module[:],symbol:u32)->blot_support::Option<const u8[:]> {
    let found=::get(self_.map,symbol);if !found {return blot_support::none<const u8[:]>();}
    let unit=found.unit;let spelling=found.spelling;
    assert(unit!=0&&unit<=units.len);let module:const blot_check_core::Module& =units[unit-1];assert(module.unit==unit);
    return blot_support::Option<const u8[:]> {true,module.name(spelling)};
}
fn add(self_:Names&,units:const blot_check_core::Module[:],module:const blot_check_core::Module&)->blot_error::Error {
    assert(module.unit!=0&&module.unit<=units.len&&units[module.unit-1].unit==module.unit);
    let count=module.field_names.len;
    for index in 0..count {
        let field=module.field_names[index];let text=module.name(field.spelling);
        block {let previous=self_.get(units,field.symbol);if previous.present {if previous.value!=text {return blot_error::Error.type_mismatch;}continue;}}
        self_.map.insert(field.symbol,RecordName{unit:module.unit,spelling:field.spelling});
    }
    return blot_error::Error.none;
}
fn less(self_:const Names&,units:const blot_check_core::Module[:],left:u32,right:u32)->bool {
    let a=self_.get(units,left);let b=self_.get(units,right);
    if a.present {if b.present {return compare(a.value,b.value)<0;}return false;}
    if b.present {return true;}return left<right;
}
fn destinations(source, record: blot_check_types::Node, names: const Names&, units: const blot_check_core::Module[:]) -> u32[>..], blot_error::Error {
    assert(record.tag == blot_check_types::Tag.record);
    if record.b < 2 { return [], blot_error::Error.none; }
    var ordered = true;
    for index in 1..record.b {
        if !less(names, units, source.recordField(record, index - 1).name, source.recordField(record, index).name) { ordered = false; break; }
    }
    if ordered { return [], blot_error::Error.none; }
    var sorted: u32[>..] = [];
    for i in record.b { sorted.push(i as u32); }
    for i in 1..sorted.len {
        let original = sorted[i]; var j = i;
        while j > 0 && less(names, units, source.recordField(record, original).name, source.recordField(record, sorted[j - 1]).name) {
            sorted[j] = sorted[j - 1]; j -= 1;
        }
        sorted[j] = original;
    }
    var result: u32[>..] = [];
    for i in record.b { result.push(0); }
    for original, index in sorted { result[original] = index as u32; }
    return result, blot_error::Error.none;
}
