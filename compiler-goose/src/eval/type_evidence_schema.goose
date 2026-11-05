// Evidence tag and node identities shared by semantic and machine requirements.
namespace blot_eval_type_evidence;
enum Tag { absent,unit,boolean,unsigned32,floating32,never,function,product,record,nominal,array,list,cursor,type_constructor,resolver,provider,state_provider,erased_proof,bound,usage,scoped,forall,existential,projection }
fn tagCode(tag: Tag) -> u8 {
 match tag {
  absent=>0,unit=>1,boolean=>2,unsigned32=>3,floating32=>4,never=>5,function=>6,product=>7,record=>8,nominal=>9,array=>10,list=>11,cursor=>12,type_constructor=>13,resolver=>14,provider=>15,state_provider=>16,erased_proof=>17,bound=>20,usage=>21,scoped=>23,forall=>24,existential=>25,projection=>26,
 }
}
struct Node { tag: Tag,a: u32=0,b: u32=0,c: u32=0 }
