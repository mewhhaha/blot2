// Backend-private owner evidence; physical words carry no lifetime authority.
namespace blot_backend_storage_plan;
import support.error;
import support.option;
type LayoutId = u32;
type ValueId = u32;
type OwnerId = u32;
type RegionId = u32;
type FunctionId = u32;
type ExitId = u32;
struct Identity { owner: u32,epoch_low: u32,epoch_high: u32 }
let descriptor_words: u32 = 3;
let borrow_words: u32 = 5;
let view_words: u32 = 6;
struct Budgets { temporaryBytes: u32 = 1048576,growerBytes: u32 = 1048576,persistentBytes: u32 = 1048576,transportBytes: u32 = 2097152,ownerCapacity: u32 = 4096 }
struct Config { temporary_bytes: u32 = 1048576,grower_bytes: u32 = 1048576,persistent_bytes: u32 = 1048576,persistent_lanes: const u32[:] = [],transport_bytes: u32 = 2097152,owner_capacity: u32 = 4096 }
fn valid(self: Budgets) -> bool { for value in [self.temporaryBytes,self.growerBytes,self.persistentBytes,self.transportBytes] { if value == 0 || value % 16 != 0 { return false; } } return self.ownerCapacity != 0; }
fn config(self: Budgets) -> Config { Config {temporary_bytes: self.temporaryBytes,grower_bytes: self.growerBytes,persistent_bytes: self.persistentBytes,transport_bytes: self.transportBytes,owner_capacity: self.ownerCapacity,..} }
import .optimizer_buffers;
import support.pooled_buffer;
type Error = blot_error::Error;
struct Request {region: u32,minimum: u32 = 16,requested: blot_support::Option<u32> = blot_support::none<u32>()}
struct Requests {storage: Request[:] = [],items: Request[:] = []}
struct CapacityRequests {items: Requests = Requests {..}}
reusable[] var request_runs: Request[>..] = [];
fn resize(self: Requests&,length: i64) {blot_support_pooled_buffer::resize(self,length);}
fn deinit(self: CapacityRequests&) {blot_support_pooled_buffer::deinit(self.items,request_runs);}
fn add(self: CapacityRequests&,region: u32) -> i64,Error {let id = self.items.items.len;let error = blot_support_pooled_buffer::push(self.items,Request {region,..},request_runs);return id,error;}
fn bytes(count: u32,stride: u32) -> u32,Error {let payload = count as u64 * stride as u64;let total = payload + 16;if total > 4294967295 || total + 15 > 4294967295 {return 0,Error.overflow;}return ((total + 15) & ~15 as u64) as u32,Error.none;}
fn initial(self: CapacityRequests&,id: i64,count: u32,stride: u32) -> Error {let capacity,error = bytes(count,stride);if error != Error.none {return error;}self.items.items[id].minimum = max(self.items.items[id].minimum,capacity);return Error.none;}
fn reserve(self: CapacityRequests&,id: i64,count: u32,stride: u32) -> Error {let capacity,error = bytes(count,stride);if error != Error.none {return error;}var previous: u32 = 0;if self.items.items[id].requested.present {previous = self.items.items[id].requested.value;}self.items.items[id].requested = blot_support::some(max(previous,capacity));return Error.none;}
fn apply(self: const CapacityRequests&,capacities: u32[:]) -> Error {
    var defaults = blot_backend_optimizer_buffers::Words {..};var seen = blot_backend_optimizer_buffers::Flags {..};let copied = defaults.append(capacities);if copied != Error.none {return copied;}let initialized = seen.resize(capacities.len,false);if initialized != Error.none {defaults.deinit();return initialized;}
    for request in self.items.items {assert(request.region < capacities.len);if !seen.items[request.region] {capacities[request.region] = 0;seen.items[request.region] = true;}var capacity = defaults.items[request.region];if request.requested.present {capacity = max(request.minimum,request.requested.value);}capacities[request.region] = max(capacities[request.region],capacity);}
    seen.deinit();defaults.deinit();return Error.none;
}
enum LayoutKind {scalar,aggregate,pool,sequence,borrow,view,callable}
struct Layout {kind: LayoutKind,words: u32,floating: bool = false,fields: const LayoutId[:] = []}
enum RegionRole {persistent,destination,temporary,transport}
struct Region {role: RegionRole,capacity: u32}
enum ExitKind {normal,return_,break_,continue_,trap}
struct Exit {kind: ExitKind,value: blot_support::Option<ValueId> = blot_support::none<ValueId>(),cleanup: const OwnerId[:] = [],transferred: const OwnerId[:] = []}
struct Summary {borrowed_parameters: const u32[:] = [],destination_count: u32 = 0,scratch_regions: u32 = 0,writes: bool = false}
fn unionRootMetadata<T>(arena: i64[>..]&,owner_count: i64,target: T&,value: T) -> Error {
    if !target.root.present && !value.root.present && target.other_roots.len == 0 && value.other_roots.len == 0 {target.depth = max(target.depth,value.depth);return Error.none;}
    var roots = blot_backend_optimizer_buffers::Sizes {..};
    fn collect() -> Error {
        if target.root.present && target.root.value < owner_count {let error = roots.push(target.root.value);if error != Error.none {return error;}}
        if value.root.present && value.root.value < owner_count {let error = roots.push(value.root.value);if error != Error.none {return error;}}
        for owner in target.other_roots {if owner < owner_count {let error = roots.push(owner);if error != Error.none {return error;}}}
        for owner in value.other_roots {if owner < owner_count {let error = roots.push(owner);if error != Error.none {return error;}}}
        for index in 1..roots.len {let owner = roots.items[index];var cursor = index;while cursor > 0 && roots.items[cursor - 1] > owner {roots.items[cursor] = roots.items[cursor - 1];cursor--;}roots.items[cursor] = owner;}
        var count: i64 = 0;for owner in roots.items {if count != 0 && roots.items[count - 1] == owner {continue;}roots.items[count] = owner;count++;}
        if count != 0 {target.root = blot_support::some(roots.items[0]);let start = arena.len;arena.append(roots.items[1..count]);target.other_roots = arena[start..arena.len];}target.depth = max(target.depth,value.depth);return Error.none;
    }
    let error = collect();roots.deinit();return error;
}
recursive fn hasRoot<T>(value: T,owner: i64) -> bool {if value.root.present && value.root.value == owner {return true;}for candidate in value.other_roots {if candidate == owner {return true;}}for field in value.fields {if hasRoot(field,owner) {return true;}}return false;}
recursive fn nextRoot<T>(value: T,start: i64,owner_count: i64) -> blot_support::Option<i64> {
    if start >= owner_count {return blot_support::none<i64>();}var next = blot_support::none<i64>();
    if value.root.present {let owner = value.root.value;if owner >= start && owner < owner_count {if owner == start {return blot_support::some(owner);}next = blot_support::some(owner);}}
    for owner in value.other_roots {if owner < start || owner >= owner_count {continue;}if owner == start {return blot_support::some(owner);}if next.present && owner >= next.value {continue;}next = blot_support::some(owner);}
    for field in value.fields {let owner = nextRoot(field,start,owner_count);if !owner.present {continue;}if owner.value == start {return owner;}if next.present && owner.value >= next.value {continue;}next = owner;}return next;
}
recursive fn borrows<T>(value: T,owner: T) -> bool {match value.tag {ref,view,link=>{if value.root.present && hasRoot(owner,value.root.value) {return true;}for root in value.other_roots {if hasRoot(owner,root) {return true;}}},_=>{},}for field in value.fields {if borrows(field,owner) {return true;}}return false;}
struct Lifetime {depth: i64,live: bool = true,frozen: bool = false,persistent: bool = false}
fn promote(self: Lifetime&,boundary: i64) {assert(boundary != 0);if self.depth >= boundary {self.depth = boundary - 1;}}
fn outlives(self: Lifetime,boundary: i64) -> bool {return self.live && self.depth < boundary;}
struct Layouts {storage: Layout[:] = [],items: Layout[:] = []}
struct Regions {storage: Region[:] = [],items: Region[:] = []}
struct Exits {storage: Exit[:] = [],items: Exit[:] = []}
struct Plan {layouts: Layouts = Layouts {..},regions: Regions = Regions {..},exits: Exits = Exits {..}}
reusable[] var layout_runs: Layout[>..] = [];
reusable[] var region_runs: Region[>..] = [];
reusable[] var exit_runs: Exit[>..] = [];
reusable[] var id_runs: u32[>..] = [];
fn ownIds(values: const u32[:]) -> u32[:] {if values.len == 0 {return [];}let owned = id_runs.alloc_slice(values.len);for index in 0..values.len {owned[index] = values[index];}return owned;}
fn freeIds(values: const u32[:]) {if values.len != 0 {let first: const u32& = values[0];let index = id_runs.index_of(first);id_runs.free_slice(id_runs[index..index + values.len]);}}
fn deinit(self: Plan&) {for item in self.layouts.items {freeIds(item.fields);}for item in self.exits.items {freeIds(item.cleanup);freeIds(item.transferred);}blot_support_pooled_buffer::deinit(self.layouts,layout_runs);blot_support_pooled_buffer::deinit(self.regions,region_runs);blot_support_pooled_buffer::deinit(self.exits,exit_runs);}
fn layout(self: Plan&,item: Layout) -> LayoutId,Error {if self.layouts.items.len > 4294967295 {return 0,Error.out_of_memory;}var owned = item;owned.fields = ownIds(item.fields);let index = self.layouts.items.len as u32;let error = blot_support_pooled_buffer::push(self.layouts,owned,layout_runs);if error != Error.none {freeIds(owned.fields);}return index,error;}
fn region(self: Plan&,item: Region) -> RegionId,Error {if self.regions.items.len > 4294967295 {return 0,Error.out_of_memory;}let index = self.regions.items.len as u32;let error = blot_support_pooled_buffer::push(self.regions,item,region_runs);return index,error;}
fn exit(self: Plan&,item: Exit) -> ExitId,Error {if item.kind == ExitKind.trap && item.value.present {return 0,Error.invalid_exit;}if self.exits.items.len > 4294967295 {return 0,Error.out_of_memory;}var owned = item;owned.cleanup = ownIds(item.cleanup);owned.transferred = ownIds(item.transferred);let index = self.exits.items.len as u32;let error = blot_support_pooled_buffer::push(self.exits,owned,exit_runs);if error != Error.none {freeIds(owned.cleanup);freeIds(owned.transferred);}return index,error;}
fn nextEpoch(value: u64) -> u64,Error {if value == 18446744073709551615 {return 0,Error.exhausted;}return value + 1,Error.none;}
