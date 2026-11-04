namespace blot_eval_scheme_membership;
import std;
import dictionary;
import check.types;
import work_counters;
import support.native;
type List=blot_check_types::List;
struct Key { owner: u64,span: List }
fn hash(key: Key) -> u64 { return ::hash_combine(::hash(key.owner),::hash((key.span.start as u64)<<32|key.span.len)); }
struct View { values: const u32[:],sorted: bool=false }
fn contains(self: View,value: u32) -> bool {
 if !self.sorted { for item in self.values { if item==value { return true; } } return false; }
 var low=0; var high=self.values.len; while low<high { let mid=low+(high-low)/2; if self.values[mid]<value { low=mid+1; } else { high=mid; } } return low<self.values.len&&self.values[low]==value;
}
struct Cache { owner_id: u64=blot_native::fresh_owner_id(),entries: dictionary<Key,List>&,words: u32[>..]&,items: i64=0 }
fn init(entries: dictionary<Key,List>&,words: u32[>..]&) -> Cache { return Cache {entries:entries,words:words}; }
fn prepare(self: Cache&,stats: blot_work_counters::SchemeMembership&,owner: u64,span: List,values: const u32[:]) -> View {
 stats.prepares++; if values.len<=16 { stats.small++; return View {values,false}; }
 if values.len>16384||owner==0 { stats.saturated++; return View {values,false}; }
 let key=Key {owner,span}; let known=self.entries.get(key);
 if known { stats.hits++; return View {self.words[known.start..known.start+known.len],true}; }
 if self.entries.count>=64||values.len>16384-self.items { stats.saturated++; return View {values,false}; }
 var sorted: u32[>..]=[]; sorted.append(values); ::sort(sorted); let saved=List {self.words.len as u32,sorted.len as u32}; self.words.append(sorted); self.entries.insert(key,saved); self.items+=sorted.len; stats.publications++; stats.indexed_items+=sorted.len; return View {self.words[saved.start..saved.start+saved.len],true};
}
