// Revision sources own their bytes. Missing entries read the filesystem;
// a present entry without contents hides the file for this revision.
namespace blot_reuse_source_overlays;
import std;
import dictionary;
import support.error;
import support.native;
import support.option;

type Error = blot_error::Error;
struct Source { path: const u8[:], contents: blot_support::Option<const u8[:]> }
import support.pooled_map;
import support.native;
struct Files {count:i64=0,slots:dictionary_slot<const u8[:],blot_support::Option<const u8[:]>>[:]=[]}
reusable[] var file_slots:dictionary_slot<const u8[:],blot_support::Option<const u8[:]>>[>..]=[];
reusable[] var owned_bytes:u8[>..]=[];
fn get(self:const Files&,name:const u8[:])->blot_support::Option<const u8[:]>? {return blot_support_pooled_map::get(self,name);}
fn contains(self:const Files&,name:const u8[:])->bool {return blot_support_pooled_map::contains(self,name);}
struct Set {slot:u32=0,generation:u64=0,files:Files&=inactive_files}
struct SetState {live:bool=false,generation:u64=0,files:Files=Files{}}
var inactive_files:Files=Files{};
reusable var sets:SetState[>..]=[];
fn valid(self:const Set&)->bool {return self.slot!=0 && self.slot-1<sets.len && sets[self.slot-1].live && sets[self.slot-1].generation==self.generation;}
fn copyBytes(bytes:const u8[:])->const u8[:] {let result=owned_bytes.alloc_slice(bytes.len);for byte,index in bytes {result[index]=byte;}return result;}
fn releaseBytes(bytes:const u8[:]) {if bytes.len!=0 {let first:const u8&=bytes[0];let at=owned_bytes.index_of(first);owned_bytes.free_slice(owned_bytes[at..at+bytes.len]);}}
fn utf8_valid(text: const u8[:]) -> bool {
    var at: i64 = 0;
    while at < text.len {
        let first = text[at]; at++;
        if first < 128 { continue; }
        var extra: i64 = 0;
        var value: u32 = 0;
        var minimum: u32 = 0;
        if first >= 194 && first <= 223 { extra = 1; value = first as u32 & 31; minimum = 128; }
        else if first >= 224 && first <= 239 { extra = 2; value = first as u32 & 15; minimum = 2048; }
        else if first >= 240 && first <= 244 { extra = 3; value = first as u32 & 7; minimum = 65536; }
        else { return false; }
        if extra > text.len - at { return false; }
        for index in extra {
            let byte = text[at + index]; if byte & 192 != 128 { return false; }
            value = value << 6 | byte as u32 & 63;
        }
        at += extra;
        if value < minimum || value > 1114111 || value >= 55296 && value <= 57343 { return false; }
    }
    return true;
}
fn normalize(raw: const u8[:], out: u8[>..<]&) {
    out.clear(); out.push('/');
    var components: i64[>..<] = [];
    var at: i64 = 0;
    while at < raw.len {
        while at < raw.len && raw[at] == '/' { at++; }
        let start = at;
        while at < raw.len && raw[at] != '/' { at++; }
        let count = at - start;
        if count == 0 || count == 1 && raw[start] == '.' { continue; }
        if count == 2 && raw[start] == '.' && raw[start + 1] == '.' {
            if components.len != 0 { let previous = components.pop(); out.resize(previous, 0); }
            continue;
        }
        let previous = out.len;
        if out.len > 1 { out.push('/'); }
        components.push(previous); out.append(raw[start..at]);
    }
}
fn canonicalPath(raw: const u8[:], out: u8[>..<]&) -> Error {
    if raw.len == 0 || raw[0] != '/' || !utf8_valid(raw) { return Error.invalid_source_path; }
    for byte in raw { if byte == 0 { return Error.invalid_source_path; } }
    var normalized: u8[>..<] = []; normalize(raw, normalized);
    var end = normalized.len;
    var prefix: u8[>..<] = [];
    var resolved: u8[>..<] = []; resolved.resize(4096, 0);
    loop {
        prefix.clear(); prefix.append(normalized[..end]); prefix.push(0);
        let count = blot_native::real_path(prefix[0], resolved[0], resolved.len as u64);
        if count >= 0 {
            if count >= resolved.len { resolved.resize(count + 1, 0); continue; }
            var joined: u8[>..<] = []; joined.append(resolved[..count]);
            var suffix = end;
            while suffix < normalized.len && normalized[suffix] == '/' { suffix++; }
            if suffix < normalized.len {
                if joined.len == 0 || joined[joined.len - 1] != '/' { joined.push('/'); }
                joined.append(normalized[suffix..]);
            }
            normalize(joined, out); return Error.none;
        }
        if count != -2 { return Error.io; }
        if end <= 1 { return Error.io; }
        var parent = end;
        while parent > 1 && normalized[parent - 1] != '/' { parent--; }
        if parent > 1 { parent--; }
        if parent == end { return Error.io; }
        end = parent;
    }
}
fn init<O>(sources:const Source[:],options:O)->Set,Error {
 if sets.len>=0xffffffff {return Set{},Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let at=sets.alloc_index(SetState{live:true,generation:generation});var result=Set{(at+1) as u32,generation,sets[at].files};var published=false;
 if sources.len>options.max_files {let __cleanup_result_1_0: Set = Set{}; let __cleanup_result_1_1: Error = Error.source_limit; {if !published {result.deinit();}} return __cleanup_result_1_0, __cleanup_result_1_1;}var total:i64=0;
 for source in sources {
  if source.contents.present {let count=source.contents.value.len;let remaining=max(options.max_total_source_bytes-total,0);if count>options.max_source_bytes || count>remaining {let __cleanup_result_2_0: Set = Set{}; let __cleanup_result_2_1: Error = Error.source_limit; {if !published {result.deinit();}} return __cleanup_result_2_0, __cleanup_result_2_1;}total+=count;}
  var name:u8[>..<];let error=canonicalPath(source.path,name);if error!=Error.none {let __cleanup_result_3_0: Set = Set{}; let __cleanup_result_3_1: Error = error; {if !published {result.deinit();}} return __cleanup_result_3_0, __cleanup_result_3_1;}if result.files.contains(name[:]) {let __cleanup_result_4_0: Set = Set{}; let __cleanup_result_4_1: Error = Error.duplicate_source_path; {if !published {result.deinit();}} return __cleanup_result_4_0, __cleanup_result_4_1;}
  let key=copyBytes(name[:]);var contents=blot_support::none<const u8[:]>();if source.contents.present {contents=blot_support::some(copyBytes(source.contents.value));}blot_support_pooled_map::insert(result.files,key,contents,file_slots);
 }published=true;let __cleanup_result_5_0: Set = result; let __cleanup_result_5_1: Error = Error.none; {if !published {result.deinit();}} return __cleanup_result_5_0, __cleanup_result_5_1;
 {if !published {result.deinit();}} }
fn deinit(self:Set&) {if self.slot==0 {return;}assert(self.valid());let at=self.slot-1;for slot in self.files.slots {if slot.tag==0 {continue;}releaseBytes(slot.key);if slot.val.present {releaseBytes(slot.val.value);}}blot_support_pooled_map::deinit(self.files,file_slots);sets[at]=SetState{};sets.free(at);self=Set{};}
