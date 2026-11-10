// Content-equal copied keys share admissions and chains; deletion preserves wrapped clusters.
import bootstrap_globals;
import std;
import backend.storage_calls;
import backend.backend_plan;
import check.core;
import reuse.code_artifacts;
import support.pooled_map;
import driver.compile_workspace;
type Key=blot_backend_storage_calls::Key;
reusable[] var slots:dictionary_slot<Key,i64>[>..]=[];
reusable[] var scalar_slots:dictionary_slot<u32,u32>[>..]=[];
var input:u32[3]=[11,22,33];
var query_input:u32[3]=[11,22,33];
fn key(binding:u32)->Key {return Key{unit:1,binding:binding,context:3,evidence:input[..],..};}
fn query(binding:u32)->Key {return Key{unit:1,binding:binding,context:3,evidence:query_input[..],..};}
fn cacheLaw(){
 var cache=blot_backend_storage_calls::Cache{..};
 assert(cache.admit(key(2),3)==blot_error::Error.none);
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none && frame.release()==blot_error::Error.none);
 assert(cache.admitted(query(2)).present && cache.admitted(query(2)).value==3);
 assert(cache.admit(query(2),7)==blot_error::Error.none);
 assert(cache.plans.items.len==1 && cache.plan_positions.count==1 && cache.admitted(key(2)).value==7);
 let first,error=cache.insert(key(2),42,false);assert(error==blot_error::Error.none && first==0);
 let second,error=cache.insert(query(2),43,false);assert(error==blot_error::Error.none && second==1);
 assert(cache.entry_positions.count==1 && cache.entries.items.len==2 && cache.find(query(2)).value==0);
 {var candidates=cache.candidates(query(2));assert(candidates.next().value==0);assert(candidates.next().value==1);assert(!candidates.next().present);}
 cache.rollbackEntries(1);assert(cache.entry_positions.count==1 && cache.entries.items.len==1 && cache.find(query(2)).value==0);
 cache.rollbackEntries(0);assert(cache.entry_positions.count==0 && !cache.find(query(2)).present);
 cache.deinit();
}
fn completionLaw(){
 var cache=blot_backend_storage_calls::Cache{..};let first,error=cache.insert(key(9),77,false);assert(error==blot_error::Error.none && first==0);
 assert(cache.complete(first,false)==blot_error::Error.none && cache.entries.items.len==2 && !cache.entries.items[first].building && !cache.entries.items[first].context_sensitive);
 var other=query(9);other.context=41;let shared=cache.find(other);assert(shared.present && shared.value==1 && cache.entries.items[shared.value].key.context_free && cache.entries.items[shared.value].function==77);
 {var candidates=cache.candidates(query(9));assert(candidates.next().value==0 && candidates.next().value==1 && !candidates.next().present);}
 cache.rollbackEntries(0);assert(cache.entry_positions.count==0);cache.deinit();
}
fn collisionLaw(){
 var ids:u32[3]=[0,0,0];var count:i64=0;
 for candidate in 1..1000 {if (key(candidate as u32).hash()&7)==7 {ids[count]=candidate as u32;count++;if count==3 {break;}}}
 assert(count==3);
 let first=blot_backend_storage_calls::own(key(ids[0]));let second=blot_backend_storage_calls::own(key(ids[1]));let third=blot_backend_storage_calls::own(key(ids[2]));
 var map=blot_support_pooled_map::Map<Key,i64>{..};
 assert(blot_support_pooled_map::insert(map,first,11,slots));assert(blot_support_pooled_map::insert(map,second,22,slots));assert(blot_support_pooled_map::insert(map,third,33,slots));
 assert(map.slots.len==8 && map.count==3);
 assert(blot_support_pooled_map::remove(map,query(ids[0]),slots));
 {let value .= blot_support_pooled_map::get(map,query(ids[1]));assert(value && value==22);}
 {let value .= blot_support_pooled_map::get(map,query(ids[2]));assert(value && value==33);}
 assert(!blot_support_pooled_map::contains(map,query(ids[0])) && map.count==2);
 assert(!blot_support_pooled_map::insert(map,query(ids[1]),44,slots));
 {let value .= blot_support_pooled_map::get(map,query(ids[1]));assert(value && value==44);}
 assert(blot_support_pooled_map::remove(map,query(ids[1]),slots));assert(blot_support_pooled_map::remove(map,query(ids[2]),slots));assert(!blot_support_pooled_map::remove(map,query(ids[2]),slots));assert(map.count==0);
 blot_support_pooled_map::deinit(map,slots);blot_backend_storage_calls::release(first);blot_backend_storage_calls::release(second);blot_backend_storage_calls::release(third);
}
fn scalarLaw(){var map=blot_support_pooled_map::Map<u32,u32>{..};blot_support_pooled_map::insert(map,1 as u32,10 as u32,scalar_slots);blot_support_pooled_map::insert(map,2 as u32,20 as u32,scalar_slots);assert(blot_support_pooled_map::remove(map,2 as u32,scalar_slots));assert(!blot_support_pooled_map::contains(map,2 as u32));assert(blot_support_pooled_map::remove(map,1 as u32,scalar_slots));assert(map.count==0);blot_support_pooled_map::deinit(map,scalar_slots);}

fn backendPlanHashLaw(){
 var cache=blot_backend_backend_plan::KeyCache{..};
 let first=blot_reuse_code_artifacts::Key{target:blot_check_core::BindingRef{1,2},count:2,parameters:[1,2,1,1,1,1,1,1,1,1,1,1,1,1,1,1],effects:[3,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0],..};
 var equal=first;
 assert(blot_backend_backend_plan::insert(cache,first,11));
 {let found .= blot_backend_backend_plan::get(cache,equal);assert(found && found==11);}
 assert(!blot_backend_backend_plan::insert(cache,equal,17));
 {let found .= blot_backend_backend_plan::get(cache,first);assert(found && found==17);}
 var distinct=first;distinct.target.binding=3;
 assert(!blot_backend_backend_plan::get(cache,distinct));
 assert(blot_backend_backend_plan::insert(cache,distinct,23));
 {let found .= blot_backend_backend_plan::get(cache,distinct);assert(found && found==23);}
 assert(cache.count==2);
 blot_support_pooled_map::deinit(cache,blot_backend_backend_plan::slots_KeyCache);
}

fn main(){cacheLaw();backendPlanHashLaw();completionLaw();collisionLaw();scalarLaw();print("cache equality, owner removal, collision wrap and scalar fallback passed");}
