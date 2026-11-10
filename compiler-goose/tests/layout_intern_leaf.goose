// Quantifier binder synthesis and handle lowering normalize into one intern leaf.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import backend.layout;
import check.task_types;
import support.error;
type Store=blot_backend_layout::Store;
type Error=blot_error::Error;
struct Probe {calls:u32=0}
fn probe(context:Probe&,store:Store&)->Error {
 assert(store.nodes.len==7);
 let universal,error=store.intern(blot_backend_layout::Tag.universal,blot_backend_layout::word,2,[]);assert(error==blot_error::Error.none && universal==9);
 let binders=store.children(universal);assert(binders.len==2 && binders[0]==7 && binders[1]==8);
 for binder,index in binders {let n=store.node(binder);assert(n.tag==blot_backend_layout::Tag.opened && n.a==index && n.b==0 && n.c==0);}
 let again,error=store.intern(blot_backend_layout::Tag.universal,blot_backend_layout::word,2,[7 as u32,8 as u32]);assert(error==blot_error::Error.none && again==universal && store.nodes.len==10);
 let existential,error=store.intern(blot_backend_layout::Tag.existential,blot_backend_layout::word,2,[]);assert(error==blot_error::Error.none && existential==10);
 let repeated,error=store.intern(blot_backend_layout::Tag.existential,blot_backend_layout::word,2,[7 as u32,8 as u32]);assert(error==blot_error::Error.none && repeated==existential && store.nodes.len==11);
 let handle,error=store.intern(blot_backend_layout::Tag.nominal,blot_check_task_types::handle.unit,blot_check_task_types::handle.decl,[]);assert(error==blot_error::Error.none && handle==11);
 let product,error=store.intern(blot_backend_layout::Tag.product,0,0,[blot_check_types::u32_type,blot_check_types::u32_type]);assert(error==blot_error::Error.none && product==handle && store.nodes.len==12);
 let physical=store.node(handle);assert(physical.tag==blot_backend_layout::Tag.product && physical.b==2);
 let children=store.children(handle);assert(children.len==2 && children[0]==blot_check_types::u32_type && children[1]==blot_check_types::u32_type);
 let function,error=store.intern(blot_backend_layout::Tag.function,blot_backend_layout::word,blot_backend_layout::word,[]);assert(error==blot_error::Error.none && function==12);
 let dictionaries,error=store.internUniversalWithDictionaries(blot_backend_layout::word,[7 as u32,8 as u32],[function,0 as u32]);assert(error==blot_error::Error.none && dictionaries==13 && dictionaries!=universal);
 let reordered,error=store.internUniversalWithDictionaries(blot_backend_layout::word,[7 as u32,8 as u32],[0 as u32,function]);assert(error==blot_error::Error.none && reordered==14 && reordered!=dictionaries);
 let reused,error=store.internUniversalWithDictionaries(blot_backend_layout::word,[7 as u32,8 as u32],[function,0 as u32]);assert(error==blot_error::Error.none && reused==dictionaries && store.nodes.len==15);
 let slots=store.dictionarySlots(dictionaries);let reverse=store.dictionarySlots(reordered);
 assert(slots.len==2 && slots[0]==function && slots[1]==0 && reverse.len==2 && reverse[0]==0 && reverse[1]==function);
 assert(store.hasDictionaryABI(dictionaries) && !store.hasDictionaryABI(universal));
 let before=store.nodes.len;
 let invalid,error=store.intern(blot_backend_layout::Tag.opened,128,0,[]);assert(error==blot_error::Error.type_mismatch && store.nodes.len==before);
 let invalid,error=store.intern(blot_backend_layout::Tag.universal,blot_backend_layout::word,0,[]);assert(error==blot_error::Error.type_mismatch && store.nodes.len==before);
 let invalid,error=store.intern(blot_backend_layout::Tag.universal,blot_backend_layout::word,129,[]);assert(error==blot_error::Error.type_mismatch && store.nodes.len==before);
 let invalid,error=store.intern(blot_backend_layout::Tag.existential,blot_backend_layout::word,2,[7 as u32]);assert(error==blot_error::Error.type_mismatch && store.nodes.len==before);
 let invalid,error=store.internUniversalWithDictionaries(blot_backend_layout::word,[7 as u32,8 as u32],[blot_backend_layout::word]);assert(error==blot_error::Error.type_mismatch && store.nodes.len==before);
 context.calls++;return blot_error::Error.none;
}
fn main(){var context=Probe{..};assert(blot_backend_layout::withStore(context,probe)==blot_error::Error.none && context.calls==1);print("layout intern leaf passed: binders, canonical IDs, handle normalization, dictionaries and rejected inputs");}
