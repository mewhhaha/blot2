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
struct PositionIndex { buckets: Bucket[:] = default<Bucket[:]>(), links: Link[:] = default<Link[:]>(), count: i64 = 0, bucket_count: i64 = 0 }
fn releaseLinks(items: const Link[:]) {
    if items.len == 0 { return; } link_storage.free_slice(items);
}
fn releaseBuckets(items: const Bucket[:]) {
    if items.len == 0 { return; } bucket_storage.free_slice(items);
}
fn deinit(self_: PositionIndex&) {
    releaseLinks(self_.links); releaseBuckets(self_.buckets); self_ = PositionIndex {..};
}
fn bucketPosition(self_: const PositionIndex&, fingerprint: u64) -> i64 {
    if self_.buckets.len == 0 { return -1; }
    var hash = blot_support_wyhash::init(0); hash.value(fingerprint);
    var at = (hash.final() & (self_.buckets.len - 1) as u64) as i64;
    for step in self_.buckets.len {
        if !self_.buckets[at].occupied || self_.buckets[at].fingerprint == fingerprint { return at; }
        at = (at + 1) & (self_.buckets.len - 1);
    }
    return -1;
}
fn requiredLinks(self_: const PositionIndex&, bound: i64) -> i64 {
    if self_.count < self_.links.len { return self_.links.len; }
    var needed = self_.links.len * 2; if needed < 16 { needed = 16; }
    if needed > bound { needed = bound; } return needed;
}
fn requiredBuckets(self_: const PositionIndex&) -> i64 {
    if self_.buckets.len == 0 { return 16; }
    if (self_.bucket_count + 1) * 5 > self_.buckets.len * 4 { return self_.buckets.len * 2; }
    return self_.buckets.len;
}
fn resizeIndex(self_: PositionIndex&, links: i64, buckets: i64) {
    if links > self_.links.len {
        let out = link_storage.alloc_slice(links);
        for index in self_.count { out[index] = self_.links[index]; }
        releaseLinks(self_.links); self_.links = out;
    }
    if buckets > self_.buckets.len {
        let old = self_.buckets;
        self_.buckets = bucket_storage.alloc_slice(buckets);
        for index in buckets { self_.buckets[index] = Bucket {..}; }
        for bucket in old {
            if bucket.occupied { let at = self_.bucketPosition(bucket.fingerprint); assert(at >= 0); self_.buckets[at] = bucket; }
        }
        releaseBuckets(old);
    }
}
fn publish(self_: PositionIndex&, fingerprint: u64) {
    assert(self_.count < self_.links.len);
    let at = self_.bucketPosition(fingerprint); assert(at >= 0);
    let position = self_.count as u32;
    var previous = blot_support::none<u32>();
    if self_.buckets[at].occupied { previous = blot_support::some(self_.buckets[at].ends.newest); }
    self_.links[position] = Link { older: previous , ..};
    self_.count++;
    if previous.present {
        self_.links[previous.value].newer = blot_support::some(position); self_.buckets[at].ends.newest = position;
    } else {
        self_.buckets[at] = Bucket { fingerprint, Ends { position, position , ..}, true , ..}; self_.bucket_count++;
    }
}
struct Cursor {
    index: const PositionIndex&, position: blot_support::Option<u32>, order: Order,
    remaining: i64, inspected: i64 = 0,
}
fn next(self_: Cursor&) -> blot_support::Option<u32> {
    if self_.remaining == 0 || !self_.position.present { return blot_support::none<u32>(); }
    let position = self_.position.value; self_.remaining--; self_.inspected++;
    if self_.order == Order.oldest_first { self_.position = self_.index.links[position].newer; }
    else { self_.position = self_.index.links[position].older; }
    return blot_support::some(position);
}
fn candidates(self_: const PositionIndex&, fingerprint: u64, order: Order, budget: i64) -> Cursor {
    var position = blot_support::none<u32>(); let at = self_.bucketPosition(fingerprint);
    if at >= 0 && self_.buckets[at].occupied {
        if order == Order.oldest_first { position = blot_support::some(self_.buckets[at].ends.oldest); }
        else { position = blot_support::some(self_.buckets[at].ends.newest); }
    }
    return Cursor { self_, position, order, budget , ..};
}
struct OwnedRecord<K,D,V,A> { key: K, dependencies: D, value: V }
fn deinit<K,D,V,A>(self_: OwnedRecord<K,D,V,A>&) { self_.key.deinit(); self_.dependencies.deinit(); self_.value.deinit(); }
struct Builder<K,D,V,A> {
    key: blot_support::Option<K>, dependencies: blot_support::Option<D>, value: blot_support::Option<V>, adapter: A,
}
fn read<K,D,V,A>(self_: Builder<K,D,V,A>&, dependencies: D) { assert(!self_.dependencies.present); self_.dependencies = blot_support::some(dependencies); }
fn stage<K,D,V,A>(self_: Builder<K,D,V,A>&, value: V) { assert(!self_.value.present); self_.value = blot_support::some(value); }
fn abort<K,D,V,A>(self_: Builder<K,D,V,A>&) {
    if self_.key.present { self_.key.value.deinit(); self_.key.present = false; }
    if self_.dependencies.present { self_.dependencies.value.deinit(); self_.dependencies.present = false; }
    if self_.value.present { self_.value.value.deinit(); self_.value.present = false; }
}
struct Candidate<K,D,V,A> {
    owner: u64 = 0, record: blot_support::Option<OwnedRecord<K,D,V,A>>, adapter: A,
}
fn complete<K,D,V,A>(self_: Builder<K,D,V,A>&) -> blot_support::Option<Candidate<K,D,V,A>> {
    if !self_.key.present || !self_.dependencies.present || !self_.value.present {
        return blot_support::none<Candidate<K,D,V,A>>();
    }
    let record = OwnedRecord<K,D,V,A> { self_.key.value, self_.dependencies.value, self_.value.value , ..};
    if !self_.adapter.complete(record) { return blot_support::none<Candidate<K,D,V,A>>(); }
    self_.key.present = false; self_.dependencies.present = false; self_.value.present = false;
    return blot_support::some(Candidate<K,D,V,A> { blot_native::fresh_owner_id(), blot_support::some(record), self_.adapter , ..});
}
fn abort<K,D,V,A>(self_: Candidate<K,D,V,A>&) {
    if self_.record.present { self_.record.value.deinit(); self_.record.present = false; }
}
struct Prepared { owner: u64, candidate: u64, position: i64, fingerprint: u64, bytes: i64 }
struct Table<K,D,V,A> {
    owner: u64 = 0, records: OwnedRecord<K,D,V,A>[:] = default<OwnedRecord<K,D,V,A>[:]>(), backing: OwnedRecord<K,D,V,A>[:] = default<OwnedRecord<K,D,V,A>[:]>(),
    index: PositionIndex = PositionIndex {..}, limits: Limits = Limits {..}, adapter: A,
    owned_bytes: i64 = 0, capacity_bytes: i64 = 0, saturated: i64 = 0,
}
fn init<K,D,V,A>(adapter: A, limits: Limits = Limits {..}) -> Table<K,D,V,A> {
    return Table<K,D,V,A> { owner: blot_native::fresh_owner_id(), limits: limits, adapter: adapter , ..};
}
fn storage<K,D,V,A>(self_: const Table<K,D,V,A>&) -> Storage {
    return Storage { records: self_.records.len, payload_bytes: self_.owned_bytes,
        capacity_bytes: self_.capacity_bytes, saturated: self_.saturated , ..};
}
fn deinit<K,D,V,A>(self_: Table<K,D,V,A>&) {
    for index in self_.records.len { self_.records[index].deinit(); }
    self_.adapter.releaseRecords(self_.backing); self_.index.deinit();
    self_.backing = default<OwnedRecord<K,D,V,A>[:]>(); self_.records = default<OwnedRecord<K,D,V,A>[:]>(); self_.owned_bytes = 0; self_.capacity_bytes = 0;
    self_.owner = 0;
}
fn begin<K,D,V,A>(self_: const Table<K,D,V,A>&, owned_key: K) -> Builder<K,D,V,A> {
    return Builder<K,D,V,A> { key: blot_support::some(owned_key), adapter: self_.adapter , ..};
}
fn canAdmit<K,D,V,A>(self_: const Table<K,D,V,A>&, minimum_bytes: i64) -> bool {
    return self_.records.len < self_.limits.records && self_.records.len < 4294967295 &&
        minimum_bytes >= 0 && self_.owned_bytes <= self_.limits.owned_bytes &&
        minimum_bytes <= self_.limits.owned_bytes - self_.owned_bytes;
}
fn saturate<K,D,V,A>(self_: Table<K,D,V,A>&) { if self_.saturated != 9223372036854775807 { self_.saturated++; } }
fn prepare<K,D,V,A>(self_: Table<K,D,V,A>&, candidate: const Candidate<K,D,V,A>&) -> blot_support::Option<Prepared>, Error {
    if !candidate.record.present || !self_.adapter.complete(candidate.record.value) { return blot_support::none<Prepared>(), blot_error::Error.none; }
    let bytes = self_.adapter.bytes(candidate.record.value);
    if !self_.canAdmit(bytes) { self_.saturate(); return blot_support::none<Prepared>(), blot_error::Error.none; }
    var capacity = self_.backing.len;
    if self_.records.len == capacity {
        capacity *= 2; if capacity < 16 { capacity = 16; }
        if capacity > self_.limits.records { capacity = self_.limits.records; }
    }
    let links = self_.index.requiredLinks(self_.limits.records); let buckets = self_.index.requiredBuckets();
    // These are the actual typed pool runs. Growth is prepared while all old
    // owners remain live, and never publishes a record or a position early.
    var temporary = self_.capacity_bytes;
    if capacity != self_.backing.len { temporary += capacity * self_.adapter.recordBytes(); }
    if links != self_.index.links.len { temporary += links * bytes_of([Link {..}]).len; }
    if buckets != self_.index.buckets.len { temporary += buckets * bytes_of([Bucket {..}]).len; }
    if temporary > self_.limits.retained_capacity { self_.saturate(); return blot_support::none<Prepared>(), blot_error::Error.none; }
    if capacity != self_.backing.len {
        let out, error = self_.adapter.allocateRecords(capacity);
        if error != blot_error::Error.none { return blot_support::none<Prepared>(), error; }
        for record, index in self_.adapter.canonicalRecords(self_.backing)[..self_.records.len] { out[index] = record; }
        self_.adapter.releaseRecords(self_.backing); self_.backing = out;
        self_.records = out[..self_.index.count];
    }
    self_.index.resizeIndex(links, buckets);
    self_.capacity_bytes = self_.backing.len * self_.adapter.recordBytes() +
        self_.index.links.len * bytes_of([Link {..}]).len + self_.index.buckets.len * bytes_of([Bucket {..}]).len;
    return blot_support::some(Prepared { self_.owner, candidate.owner, self_.records.len,
        self_.adapter.fingerprint(candidate.record.value.key), bytes , ..}), blot_error::Error.none;
}
fn validPrepared<K,D,V,A>(self_: const Table<K,D,V,A>&, prepared: Prepared, candidate: const Candidate<K,D,V,A>&) -> bool {
    if !candidate.record.present { return false; }
    return prepared.owner == self_.owner && prepared.candidate == candidate.owner && prepared.position == self_.records.len &&
        prepared.fingerprint == self_.adapter.fingerprint(candidate.record.value.key) && prepared.bytes == self_.adapter.bytes(candidate.record.value);
}
fn publish<K,D,V,A>(self_: Table<K,D,V,A>&, prepared: Prepared, candidate: Candidate<K,D,V,A>&) -> Handle<A> {
    assert(self_.validPrepared(prepared, candidate)); assert(self_.records.len == self_.index.count);
    self_.backing[self_.records.len] = self_.adapter.canonicalRecord(candidate.record.value); candidate.record.present = false;
    self_.records = self_.backing[..self_.records.len + 1]; self_.index.publish(prepared.fingerprint);
    self_.owned_bytes += prepared.bytes;
    return Handle<A> { prepared.position as u32, self_.owner , ..};
}
fn get<K,D,V,A>(self_: const Table<K,D,V,A>&, handle: Handle<A>) -> const OwnedRecord<K,D,V,A>? {
    if handle.owner != self_.owner || handle.position >= self_.records.len { return null; }
    return self_.records[handle.position];
}
fn candidates<K,D,V,A>(self_: const Table<K,D,V,A>&, fingerprint: u64, order: Order) -> Cursor {
    return self_.index.candidates(fingerprint, order, self_.limits.lookup_work);
}
fn kindCode(kind: Kind) -> u8 {
    match kind { refinement => 0, specialization => 1, principal => 2, source_validation => 3, executable => 4 }
}
fn kindFromCode(code: u8) -> Kind, bool {
    match code { 0 => { return Kind.refinement, true; }, 1 => { return Kind.specialization, true; },
        2 => { return Kind.principal, true; }, 3 => { return Kind.source_validation, true; },
        4 => { return Kind.executable, true; }, _ => { return Kind.refinement, false; } }
}
