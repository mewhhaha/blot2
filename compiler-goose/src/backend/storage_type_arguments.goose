// Invocation-local journal and lookup table; captures own published metadata ranges.
namespace blot_backend_storage_type_arguments;
import dictionary;
import support.option;
import support.error;
import support.native;
import .runtime_ir;
type Range=blot_backend_runtime_ir::Range;
struct TypeArgument {unit:u32,parameter:u32,argument:u32,argument_unit:u32,environment:blot_support::Option<Range>}
type Error=blot_error::Error;
let absent:i64=9223372036854775807;
struct Stats {lookups:u64=0,synchronized:u64=0,captures:u64=0,capture_hits:u64=0}
struct Positions {any:blot_support::Option<i64>,nonidentity:blot_support::Option<i64>}
struct Key {stack:u64,binding:u64}
fn hash(value:Key)->u64 {return (value.stack*0x9e3779b185ebca87) ^ value.binding;}
struct Entry {
 argument:TypeArgument,positions:Positions,snapshot:blot_support::Option<Range>,
 previous:i64=absent,next:i64=absent,active_previous:i64=absent,active_next:i64=absent,ordinal:i64=0
}
struct Journal {free:i64=absent,entries:Entry[>..]}
struct Heads {entries:dictionary<Key,Positions>}
struct Owner {journal:Journal&,heads:Heads&,published:TypeArgument[>..<]&,next_id:u64=1}
struct Stack {
 owner:Owner?=null,id:u64=0,len:i64=0,first:i64=absent,last:i64=absent,
 active_count:i64=0,first_active:i64=absent,last_active:i64=absent,touched:bool=false,
 snapshot:blot_support::Option<Range>,stats:Stats
}
fn init(owner:Owner&)->Stack {let id=owner.next_id;assert(id!=0);owner.next_id++;return Stack{owner:owner,id:id,..};}
fn emptyFrom(source:const Stack&)->Stack {let owner .= source.owner;if owner {return init(owner);}return Stack{..};}
// Temporary type queries share one journal owner and exchange only scalar cursors.
struct Cursor {id:u64=0,len:i64=0,first:i64=absent,last:i64=absent,active_count:i64=0,first_active:i64=absent,last_active:i64=absent,touched:bool=false,snapshot:blot_support::Option<Range>,stats:Stats}
fn cursor(stack:const Stack&)->Cursor {return Cursor{id:stack.id,len:stack.len,first:stack.first,last:stack.last,active_count:stack.active_count,first_active:stack.first_active,last_active:stack.last_active,touched:stack.touched,snapshot:stack.snapshot,stats:stack.stats};}
fn setCursor(stack:Stack&,value:Cursor) {stack.id=value.id;stack.len=value.len;stack.first=value.first;stack.last=value.last;stack.active_count=value.active_count;stack.first_active=value.first_active;stack.last_active=value.last_active;stack.touched=value.touched;stack.snapshot=value.snapshot;stack.stats=value.stats;}
fn isolate(stack:Stack&)->Cursor {let saved=cursor(stack);let owner .=stack.owner;var id:u64=0;if owner {id=owner.next_id;assert(id!=0);owner.next_id++;}setCursor(stack,Cursor{id:id,..});return saved;}
fn restore(stack:Stack&,saved:Cursor) {deinit(stack);setCursor(stack,saved);}

fn key(stack:const Stack&,unit:u32,parameter:u32)->Key {return Key{stack.id,(unit as u64<<32)|parameter};}
fn increase(value:u64&) {if value!=18446744073709551615 {value++;}}
fn at(stack:const Stack&,index:i64)->TypeArgument {let owner .= stack.owner;assert(owner);return owner.journal.entries[index].argument;}
fn heads(stack:const Stack&,unit:u32,parameter:u32)->Positions {let owner .= stack.owner;assert(owner);let selected .= ::get(owner.heads.entries,key(stack,unit,parameter));if selected {return selected;}return Positions{..};}
fn allocate(owner:Owner&)->i64 {let journal:Journal& = owner.journal;var index=journal.free;if index==absent {index=journal.entries.len;journal.entries.push(default<Entry>());}else {journal.free=journal.entries[index].next;}return index;}
fn free(owner:Owner&,index:i64) {owner.journal.entries[index].next=owner.journal.free;owner.journal.free=index;}
fn unlink(stack:Stack&,index:i64) {let owner .=stack.owner;assert(owner);let entry=owner.journal.entries[index];if entry.active_previous==absent {stack.first_active=entry.active_next;}else {owner.journal.entries[entry.active_previous].active_next=entry.active_next;}if entry.active_next==absent {stack.last_active=entry.active_previous;}else {owner.journal.entries[entry.active_next].active_previous=entry.active_previous;}}
fn link(stack:Stack&,index:i64) {let owner .=stack.owner;assert(owner);let entry=owner.journal.entries[index];if entry.active_previous==absent {stack.first_active=index;}else {owner.journal.entries[entry.active_previous].active_next=index;}if entry.active_next==absent {stack.last_active=index;}else {owner.journal.entries[entry.active_next].active_previous=index;}}
fn reserve(stack:Stack&,count:i64)->Error {assert(count>=0);if count>0x5555555555555540-stack.len || count>4294967295 {return blot_error::Error.out_of_memory;}let owner .=stack.owner;assert(owner);if count>0x5555555555555540-owner.heads.entries.count {return blot_error::Error.out_of_memory;}::reserve(owner.heads.entries,owner.heads.entries.count+count);return blot_error::Error.none;}
fn appendAssumeCapacity(stack:Stack&,argument:TypeArgument) {
 let owner .=stack.owner;assert(owner);var positions=heads(stack,argument.unit,argument.parameter);
 if positions.any.present {unlink(stack,positions.any.value);}else {stack.active_count++;}
 let index=allocate(owner);owner.journal.entries[index]=Entry{argument:argument,positions:positions,snapshot:stack.snapshot,previous:stack.last,active_previous:stack.last_active,ordinal:stack.len,..};
 if stack.last==absent {stack.first=index;}else {owner.journal.entries[stack.last].next=index;}stack.last=index;stack.len++;link(stack,index);
 positions.any=blot_support::some(index);if argument.argument_unit!=argument.unit || argument.argument!=argument.parameter {positions.nonidentity=blot_support::some(index);}
 ::insert(owner.heads.entries,key(stack,argument.unit,argument.parameter),positions);stack.snapshot=blot_support::none<Range>();stack.touched=true;increase(stack.stats.synchronized);
}
fn append(stack:Stack&,argument:TypeArgument)->Error {let error=reserve(stack,1);if error!=blot_error::Error.none {return error;}appendAssumeCapacity(stack,argument);return blot_error::Error.none;}
fn shrinkRetainingCapacity(stack:Stack&,length:i64) {
 assert(length>=0 && length<=stack.len);let owner .=stack.owner;assert(owner);
 while stack.len>length {let index=stack.last;let entry=owner.journal.entries[index];unlink(stack,index);if entry.positions.any.present {link(stack,entry.positions.any.value);}else {stack.active_count--;}
  if entry.positions.any.present || entry.positions.nonidentity.present {::insert(owner.heads.entries,key(stack,entry.argument.unit,entry.argument.parameter),entry.positions);}else {::remove(owner.heads.entries,key(stack,entry.argument.unit,entry.argument.parameter));}
  stack.snapshot=entry.snapshot;stack.last=entry.previous;stack.len--;if stack.last==absent {stack.first=absent;}else {owner.journal.entries[stack.last].next=absent;}free(owner,index);
 }
}
fn clearRetainingCapacity(stack:Stack&) {if !stack.touched {return;}shrinkRetainingCapacity(stack,0);stack.snapshot=blot_support::none<Range>();stack.touched=false;}
fn deinit(stack:Stack&) {let owner .=stack.owner;if !owner {return;}shrinkRetainingCapacity(stack,0);stack.snapshot=blot_support::none<Range>();stack.touched=false;stack.stats=Stats{..};}
fn latestAny(stack:Stack&,unit:u32,parameter:u32)->blot_support::Option<i64> {increase(stack.stats.lookups);return heads(stack,unit,parameter).any;}
fn latestNonidentity(stack:Stack&,unit:u32,parameter:u32)->blot_support::Option<i64> {increase(stack.stats.lookups);return heads(stack,unit,parameter).nonidentity;}
fn capture(stack:Stack&)->Range,Error {
 if stack.snapshot.present {increase(stack.stats.capture_hits);return stack.snapshot.value,blot_error::Error.none;}
 let owner .=stack.owner;assert(owner);let published:TypeArgument[>..<]& =owner.published;let result=Range{start:published.len,len:stack.active_count};
 // Preserve the process-wide owner/nonce stream at each capture miss.
 let identity=blot_native::fresh_owner_id();stack.snapshot=blot_support::some(result);increase(stack.stats.captures);
 var index=stack.first_active;while index!=absent {let entry=owner.journal.entries[index];published.push(entry.argument);index=entry.active_next;}
 assert(published.len-result.start==result.len);return result,blot_error::Error.none;
}
fn sift(indexes:i64[:],start:i64,end:i64,owner:Owner&) {var root=start;while root*2+1<end {var child=root*2+1;if child+1<end && owner.journal.entries[indexes[child]].ordinal<owner.journal.entries[indexes[child+1]].ordinal {child++;}if owner.journal.entries[indexes[root]].ordinal>=owner.journal.entries[indexes[child]].ordinal {return;}let held=indexes[root];indexes[root]=indexes[child];indexes[child]=held;root=child;}}
fn sort(indexes:i64[:],owner:Owner&) {var start=indexes.len/2;while start!=0 {start--;sift(indexes,start,indexes.len,owner);}var end=indexes.len;while end>1 {end--;let held=indexes[0];indexes[0]=indexes[end];indexes[end]=held;sift(indexes,0,end,owner);}}
fn inheritActive(stack:Stack&,source:const Stack&)->i64,Error {
 assert(stack.len==0);let source_owner .=source.owner;assert(source_owner);
 if source.len==0 || source.active_count>source.len/8 {let error=reserve(stack,source.len);if error!=blot_error::Error.none {return source.len,error;}var index=source.first;while index!=absent {let entry=source_owner.journal.entries[index];appendAssumeCapacity(stack,entry.argument);index=entry.next;}return source.len,blot_error::Error.none;}
 var indexes:i64[>..<]=[];var cursor=source.first_active;while cursor!=absent {let entry=source_owner.journal.entries[cursor];indexes.push(cursor);let positions=heads(source,entry.argument.unit,entry.argument.parameter);if positions.nonidentity.present && positions.nonidentity.value!=cursor {indexes.push(positions.nonidentity.value);}cursor=entry.active_next;}
 sort(indexes,source_owner);let error=reserve(stack,indexes.len);if error==blot_error::Error.none {for index in indexes {appendAssumeCapacity(stack,source_owner.journal.entries[index].argument);}}return indexes.len,error;
}
