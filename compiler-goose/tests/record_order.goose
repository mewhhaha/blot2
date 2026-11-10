// Name caches retain coordinates; byte ordering observes the live Core owners.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import check.record_order;
import reuse.dependency_payload;
import driver.compile_workspace;
fn main() {
 var owner,error=blot_reuse_dependency_payload::init();assert(error==blot_error::Error.none);
 let units,error=blot_reuse_dependency_payload::alloc<blot_check_core::Module>(owner,3);assert(error==blot_error::Error.none);
 let first,error=owner.copy("zaå");assert(error==blot_error::Error.none);
 let second,error=owner.copy("ab");assert(error==blot_error::Error.none);
 let conflict,error=owner.copy("x");assert(error==blot_error::Error.none);
 let fields,error=owner.copy([blot_check_core::FieldName{symbol:1,spelling:blot_check_core::Name{0,1}},blot_check_core::FieldName{symbol:2,spelling:blot_check_core::Name{1,1}},blot_check_core::FieldName{symbol:3,spelling:blot_check_core::Name{2,2}},blot_check_core::FieldName{symbol:4,spelling:blot_check_core::Name{1,1}}]);assert(error==blot_error::Error.none);
 let others,error=owner.copy([blot_check_core::FieldName{symbol:2,spelling:blot_check_core::Name{0,1}},blot_check_core::FieldName{symbol:5,spelling:blot_check_core::Name{1,1}}]);assert(error==blot_error::Error.none);
 let conflicts,error=owner.copy([blot_check_core::FieldName{symbol:1,spelling:blot_check_core::Name{0,1}}]);assert(error==blot_error::Error.none);
 units[0]=blot_check_core::Module{field_names:fields,unit:1,names:first,..};units[1]=blot_check_core::Module{field_names:others,unit:2,names:second,..};units[2]=blot_check_core::Module{field_names:conflicts,unit:3,names:conflict,..};
 var table:dictionary<u32,blot_check_record_order::RecordName> = dictionary<u32,blot_check_record_order::RecordName>{};var names=blot_check_record_order::init(table);
 assert(names.add(units,units[0])==blot_error::Error.none);assert(names.add(units,units[1])==blot_error::Error.none);assert(names.add(units,units[1])==blot_error::Error.none);
 assert(table.count==5&&names.get(units,2).value=="a"&&names.get(units,5).value=="b"&&!names.get(units,99).present);
 assert(names.less(units,2,5)&&names.less(units,5,1)&&names.less(units,1,3)&&!names.less(units,2,4));
 assert(names.less(units,99,1)&&!names.less(units,1,99)&&names.less(units,99,100)&&!names.less(units,100,99));
 assert(names.add(units,units[2])==blot_error::Error.type_mismatch&&table.count==5&&names.get(units,1).value=="z");
 let words,error=owner.copy([1 as u32,0,5,0,2,0,2,0,5,0,1,0]);assert(error==blot_error::Error.none);
 let types=blot_check_core::Types{extra:words,..};
 let reordered,error=blot_check_record_order::destinations(types,blot_check_types::Node{tag:blot_check_types::Tag.record,a:0,b:3,..},names,units);assert(error==blot_error::Error.none&&reordered==[2 as u32,1,0]);
 let ordered,error=blot_check_record_order::destinations(types,blot_check_types::Node{tag:blot_check_types::Tag.record,a:6,b:3,..},names,units);assert(error==blot_error::Error.none&&ordered.len==0);
 owner.deinit();
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none);assert(frame.release()==blot_error::Error.none);
 // Coordinate inspection remains valid; resolving bytes requires the retired units.
 let saved=table.get(1);assert(saved&&saved.unit==1&&saved.spelling.start==0&&saved.spelling.len==1);names.deinit();assert(table.count==0);
 print("record name coordinates passed");
}
