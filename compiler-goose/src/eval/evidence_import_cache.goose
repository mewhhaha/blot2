namespace blot_eval_evidence_import_cache;
import dictionary;
import support.native;
struct Cache {
 owner_id: u64=blot_native::fresh_owner_id(), answers: dictionary<u64,u32>&,
 source: u64=0,target: u64=0,generation: u16=0,physical: u64=0,max_depth: i64=0
}
fn init(answers: dictionary<u64,u32>&) -> Cache { return Cache {answers:answers}; }
fn clearRetainingCapacity(self: Cache&) { self.answers.clear(); self.source=0; self.target=0; self.generation=0; self.physical=0; self.max_depth=0; }
fn activate(self: Cache&,source: u64,target: u64,generation: u16,physical: u64,max_depth: i64) -> bool {
 if source!=0&&target!=0&&self.source==source&&self.target==target&&self.generation==generation&&self.physical==physical&&self.max_depth==max_depth { return false; }
 self.answers.clear(); self.source=source; self.target=target; self.generation=generation; self.physical=physical; self.max_depth=max_depth; return true;
}
fn key(self: Cache&,value: u32,depth: i64) -> u64,bool {
 if self.source==0||self.target==0||self.generation==0xffff||self.physical==0xffffffffffffffff||depth<0||depth>0xffffffff { return 0,false; }
 return ((value as u64)<<32)|(depth as u64),true;
}
