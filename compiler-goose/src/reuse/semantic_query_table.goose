// Complete typed records own their observations. An index hit proves no claim.
namespace blot_reuse_semantic_query_table;
import std;
import support.error;
import support.native;
import support.option;
import support.wyhash;
type Error = blot_error::Error;
enum Kind { refinement, specialization, principal, source_validation, executable }
enum Order { oldest_first, newest_first }
struct Limits {
    records: i64 = 4096, owned_bytes: i64 = 16777216,
    retained_capacity: i64 = 2097152, lookup_work: i64 = 4096,
}
struct Storage {
    inspected_positions: i64 = 0, inspected_dependencies: i64 = 0,
    lookup_declines: i64 = 0, records: i64 = 0, payload_bytes: i64 = 0,
    capacity_bytes: i64 = 0, saturated: i64 = 0,
}
struct Handle<A> { position: u32, owner: u64 }
struct Ends { oldest: u32, newest: u32 }
struct Link { older: blot_support::Option<u32>, newer: blot_support::Option<u32> }
struct Bucket { fingerprint: u64 = 0, ends: Ends, occupied: bool = false }
reusable[] var link_storage: Link[>..] = [];
reusable[] var bucket_storage: Bucket[>..] = [];
struct PositionIndex { buckets: Bucket[:] = [], links: Link[:] = [], count: i64 = 0, bucket_count: i64 = 0 }
fn releaseLinks(items: const Link[:]) {
    if items.len == 0 { return; } let first: const Link& = items[0]; let at = link_storage.index_of(first);
    assert(at >= 0); link_storage.free_slice(link_storage[at..at + items.len]);
}
fn releaseBuckets(items: const Bucket[:]) {
    if items.len == 0 { return; } let first: const Bucket& = items[0]; let at = bucket_storage.index_of(first);
    assert(at >= 0); bucket_storage.free_slice(bucket_storage[at..at + items.len]);
}
fn deinit(self: PositionIndex&) {
    releaseLinks(self.links); releaseBuckets(self.buckets); self = PositionIndex {};
}
fn bucketPosition(self: const PositionIndex&, fingerprint: u64) -> i64 {
    if self.buckets.len == 0 { return -1; }
    var hash = blot_support_wyhash::init(0); hash.value(fingerprint);
    var at = (hash.final() & (self.buckets.len - 1) as u64) as i64;
    for step in self.buckets.len {
        if !self.buckets[at].occupied || self.buckets[at].fingerprint == fingerprint { return at; }
        at = (at + 1) & (self.buckets.len - 1);
    }
    return -1;
}
fn requiredLinks(self: const PositionIndex&, bound: i64) -> i64 {
    if self.count < self.links.len { return self.links.len; }
    var needed = self.links.len * 2; if needed < 16 { needed = 16; }
    if needed > bound { needed = bound; } return needed;
}
fn requiredBuckets(self: const PositionIndex&) -> i64 {
    if self.buckets.len == 0 { return 16; }
    if (self.bucket_count + 1) * 5 > self.buckets.len * 4 { return self.buckets.len * 2; }
    return self.buckets.len;
}
fn resizeIndex(self: PositionIndex&, links: i64, buckets: i64) {
    if links > self.links.len {
        let out = link_storage.alloc_slice(links);
        for index in self.count { out[index] = self.links[index]; }
        releaseLinks(self.links); self.links = out;
    }
    if buckets > self.buckets.len {
        let old = self.buckets;
        self.buckets = bucket_storage.alloc_slice(buckets);
        for index in buckets { self.buckets[index] = Bucket {}; }
        for bucket in old {
            if bucket.occupied { let at = self.bucketPosition(bucket.fingerprint); assert(at >= 0); self.buckets[at] = bucket; }
        }
        releaseBuckets(old);
    }
}
fn publish(self: PositionIndex&, fingerprint: u64) {
    assert(self.count < self.links.len);
    let at = self.bucketPosition(fingerprint); assert(at >= 0);
    let position = self.count as u32;
    var previous = blot_support::none<u32>();
    if self.buckets[at].occupied { previous = blot_support::some(self.buckets[at].ends.newest); }
    self.links[position] = Link { older: previous };
    self.count++;
    if previous.present {
        self.links[previous.value].newer = blot_support::some(position); self.buckets[at].ends.newest = position;
    } else {
        self.buckets[at] = Bucket { fingerprint, Ends { position, position }, true }; self.bucket_count++;
    }
}
struct Cursor {
    index: const PositionIndex&, position: blot_support::Option<u32>, order: Order,
    remaining: i64, inspected: i64 = 0,
}
fn next(self: Cursor&) -> blot_support::Option<u32> {
    if self.remaining == 0 || !self.position.present { return blot_support::none<u32>(); }
    let position = self.position.value; self.remaining--; self.inspected++;
    if self.order == Order.oldest_first { self.position = self.index.links[position].newer; }
    else { self.position = self.index.links[position].older; }
    return blot_support::some(position);
}
fn candidates(self: const PositionIndex&, fingerprint: u64, order: Order, budget: i64) -> Cursor {
    var position = blot_support::none<u32>(); let at = self.bucketPosition(fingerprint);
    if at >= 0 && self.buckets[at].occupied {
        if order == Order.oldest_first { position = blot_support::some(self.buckets[at].ends.oldest); }
        else { position = blot_support::some(self.buckets[at].ends.newest); }
    }
    return Cursor { self, position, order, budget };
}
struct OwnedRecord<K,D,V,A> { key: K, dependencies: D, value: V }
fn deinit<K,D,V,A>(self: OwnedRecord<K,D,V,A>&) { self.key.deinit(); self.dependencies.deinit(); self.value.deinit(); }
struct Builder<K,D,V,A> {
    key: blot_support::Option<K>, dependencies: blot_support::Option<D>, value: blot_support::Option<V>, adapter: A,
}
fn read<K,D,V,A>(self: Builder<K,D,V,A>&, dependencies: D) { assert(!self.dependencies.present); self.dependencies = blot_support::some(dependencies); }
fn stage<K,D,V,A>(self: Builder<K,D,V,A>&, value: V) { assert(!self.value.present); self.value = blot_support::some(value); }
fn abort<K,D,V,A>(self: Builder<K,D,V,A>&) {
    if self.key.present { self.key.value.deinit(); self.key.present = false; }
    if self.dependencies.present { self.dependencies.value.deinit(); self.dependencies.present = false; }
    if self.value.present { self.value.value.deinit(); self.value.present = false; }
}
struct Candidate<K,D,V,A> {
    owner: u64 = 0, record: blot_support::Option<OwnedRecord<K,D,V,A>>, adapter: A,
}
fn complete<K,D,V,A>(self: Builder<K,D,V,A>&) -> blot_support::Option<Candidate<K,D,V,A>> {
    if !self.key.present || !self.dependencies.present || !self.value.present {
        return blot_support::none<Candidate<K,D,V,A>>();
    }
    let record = OwnedRecord<K,D,V,A> { self.key.value, self.dependencies.value, self.value.value };
    if !self.adapter.complete(record) { return blot_support::none<Candidate<K,D,V,A>>(); }
    self.key.present = false; self.dependencies.present = false; self.value.present = false;
    return blot_support::some(Candidate<K,D,V,A> { blot_native::fresh_owner_id(), blot_support::some(record), self.adapter });
}
fn abort<K,D,V,A>(self: Candidate<K,D,V,A>&) {
    if self.record.present { self.record.value.deinit(); self.record.present = false; }
}
struct Prepared { owner: u64, candidate: u64, position: i64, fingerprint: u64, bytes: i64 }
struct Table<K,D,V,A> {
    owner: u64 = 0, records: OwnedRecord<K,D,V,A>[:] = [], backing: OwnedRecord<K,D,V,A>[:] = [],
    index: PositionIndex = PositionIndex {}, limits: Limits = Limits {}, adapter: A,
    owned_bytes: i64 = 0, capacity_bytes: i64 = 0, saturated: i64 = 0,
}
fn init<K,D,V,A>(adapter: A, limits: Limits = Limits {}) -> Table<K,D,V,A> {
    return Table<K,D,V,A> { owner: blot_native::fresh_owner_id(), limits: limits, adapter: adapter };
}
fn storage<K,D,V,A>(self: const Table<K,D,V,A>&) -> Storage {
    return Storage { records: self.records.len, payload_bytes: self.owned_bytes,
        capacity_bytes: self.capacity_bytes, saturated: self.saturated };
}
fn deinit<K,D,V,A>(self: Table<K,D,V,A>&) {
    for index in self.records.len { self.records[index].deinit(); }
    self.adapter.releaseRecords(self.backing); self.index.deinit();
    self.backing = []; self.records = []; self.owned_bytes = 0; self.capacity_bytes = 0;
    self.owner = 0;
}
fn begin<K,D,V,A>(self: const Table<K,D,V,A>&, owned_key: K) -> Builder<K,D,V,A> {
    return Builder<K,D,V,A> { key: blot_support::some(owned_key), adapter: self.adapter };
}
fn canAdmit<K,D,V,A>(self: const Table<K,D,V,A>&, minimum_bytes: i64) -> bool {
    return self.records.len < self.limits.records && self.records.len < 4294967295 &&
        minimum_bytes >= 0 && self.owned_bytes <= self.limits.owned_bytes &&
        minimum_bytes <= self.limits.owned_bytes - self.owned_bytes;
}
fn saturate<K,D,V,A>(self: Table<K,D,V,A>&) { if self.saturated != 9223372036854775807 { self.saturated++; } }
fn prepare<K,D,V,A>(self: Table<K,D,V,A>&, candidate: const Candidate<K,D,V,A>&) -> blot_support::Option<Prepared>, Error {
    if !candidate.record.present || !self.adapter.complete(candidate.record.value) { return blot_support::none<Prepared>(), Error.none; }
    let bytes = self.adapter.bytes(candidate.record.value);
    if !self.canAdmit(bytes) { self.saturate(); return blot_support::none<Prepared>(), Error.none; }
    var capacity = self.backing.len;
    if self.records.len == capacity {
        capacity *= 2; if capacity < 16 { capacity = 16; }
        if capacity > self.limits.records { capacity = self.limits.records; }
    }
    let links = self.index.requiredLinks(self.limits.records); let buckets = self.index.requiredBuckets();
    // These are the actual typed pool runs. Growth is prepared while all old
    // owners remain live, and never publishes a record or a position early.
    var temporary = self.capacity_bytes;
    if capacity != self.backing.len { temporary += capacity * self.adapter.recordBytes(); }
    if links != self.index.links.len { temporary += links * bytes_of([Link {}]).len; }
    if buckets != self.index.buckets.len { temporary += buckets * bytes_of([Bucket {}]).len; }
    if temporary > self.limits.retained_capacity { self.saturate(); return blot_support::none<Prepared>(), Error.none; }
    if capacity != self.backing.len {
        let out, error = self.adapter.allocateRecords(capacity);
        if error != Error.none { return blot_support::none<Prepared>(), error; }
        for record, index in self.records { out[index] = record; }
        self.adapter.releaseRecords(self.backing); self.backing = out;
        self.records = out[..self.index.count];
    }
    self.index.resizeIndex(links, buckets);
    self.capacity_bytes = self.backing.len * self.adapter.recordBytes() +
        self.index.links.len * bytes_of([Link {}]).len + self.index.buckets.len * bytes_of([Bucket {}]).len;
    return blot_support::some(Prepared { self.owner, candidate.owner, self.records.len,
        self.adapter.fingerprint(candidate.record.value.key), bytes }), Error.none;
}
fn validPrepared<K,D,V,A>(self: const Table<K,D,V,A>&, prepared: Prepared, candidate: const Candidate<K,D,V,A>&) -> bool {
    if !candidate.record.present { return false; }
    return prepared.owner == self.owner && prepared.candidate == candidate.owner && prepared.position == self.records.len &&
        prepared.fingerprint == self.adapter.fingerprint(candidate.record.value.key) && prepared.bytes == self.adapter.bytes(candidate.record.value);
}
fn publish<K,D,V,A>(self: Table<K,D,V,A>&, prepared: Prepared, candidate: Candidate<K,D,V,A>&) -> Handle<A> {
    assert(self.validPrepared(prepared, candidate)); assert(self.records.len == self.index.count);
    self.backing[self.records.len] = candidate.record.value; candidate.record.present = false;
    self.records = self.backing[..self.records.len + 1]; self.index.publish(prepared.fingerprint);
    self.owned_bytes += prepared.bytes;
    return Handle<A> { prepared.position as u32, self.owner };
}
fn get<K,D,V,A>(self: const Table<K,D,V,A>&, handle: Handle<A>) -> const OwnedRecord<K,D,V,A>? {
    if handle.owner != self.owner || handle.position >= self.records.len { return null; }
    return self.records[handle.position];
}
fn candidates<K,D,V,A>(self: const Table<K,D,V,A>&, fingerprint: u64, order: Order) -> Cursor {
    return self.index.candidates(fingerprint, order, self.limits.lookup_work);
}
fn kindCode(kind: Kind) -> u8 {
    match kind { Kind.refinement => 0, Kind.specialization => 1, Kind.principal => 2, Kind.source_validation => 3, Kind.executable => 4 }
}
fn kindFromCode(code: u8) -> Kind, bool {
    match code { 0 => { return Kind.refinement, true; }, 1 => { return Kind.specialization, true; },
        2 => { return Kind.principal, true; }, 3 => { return Kind.source_validation, true; },
        4 => { return Kind.executable, true; }, _ => { return Kind.refinement, false; } }
}
