// Exact ordered field bytes, not a digest. Portable archive schemas are separate.
namespace blot_reuse_validation_image;
import std;
import support.error;
import support.option;
import support.structural;
import check.core;
type Error = blot_error::Error;
struct Image { bytes: const u8[:] = [], lease: u32 = 0, generation: u64 = 0 }
struct Lease { references: u64 = 0, generation: u64 = 0 }
reusable[] var image_leases: Lease[>..] = [];
reusable[] var image_bytes: u8[>..] = [];
var next_generation: u64 = 1;
fn live(self: Image) -> bool { return self.lease != 0 && self.lease <= image_leases.len && image_leases[self.lease - 1].references != 0 && image_leases[self.lease - 1].generation == self.generation; }
fn retain(self: Image) -> Image, Error { if !self.live() { return Image {..}, Error.invalid_artifact; } if image_leases[self.lease - 1].references == 0xffffffffffffffff { return Image {..}, Error.out_of_memory; } image_leases[self.lease - 1].references++; return self, Error.none; }
fn deinit(self: Image&) {
    if self.lease == 0 { assert(self.bytes.len == 0); return; } assert(self.live()); let lease = self.lease - 1; image_leases[lease].references--;
    if image_leases[lease].references == 0 { if self.bytes.len != 0 { let first: const u8& = self.bytes[0]; let at = image_bytes.index_of(first); assert(at >= 0); image_bytes.free_slice(image_bytes[at..at + self.bytes.len]); } image_leases.free(lease); }
    self = Image {..};
}
struct Writer { limit: i64, bytes: u8[>..<]&, failure: Error = Error.none, declined: bool = false }
fn update(self: Writer&, bytes: const u8[:]) {
    if self.failure != Error.none || self.declined { return; } if self.bytes.len > self.limit || bytes.len > self.limit - self.bytes.len { self.declined = true; return; } self.bytes.append(bytes);
}
fn writeInput<S,T>(sink: S&, input: T) { blot_structural::hash(sink, input); }
fn writeInput<S>(sink: S&, input: blot_check_core::Module) { blot_structural::hash(sink, blot_check_core::stampView(input)); }
fn capture<T>(input: T, remaining: i64&) -> blot_support::Option<Image>, Error {
    var bytes: u8[>..<] = []; var writer = Writer { remaining, bytes , ..}; writeInput(writer, input);
    if writer.failure != Error.none { return blot_support::none<Image>(), writer.failure; } if writer.declined { return blot_support::none<Image>(), Error.none; }
    if next_generation == 0xffffffffffffffff || image_leases.len >= 0xffffffff { return blot_support::none<Image>(), Error.out_of_memory; }
    let run = image_bytes.alloc_slice(bytes.len); for byte, index in bytes { run[index] = byte; }
    let generation = next_generation; next_generation++; let lease = image_leases.alloc_index(Lease { 1, generation , ..});
    remaining -= bytes.len; return blot_support::some(Image { run, (lease + 1) as u32, generation , ..}), Error.none;
}
struct Reader { expected: const u8[:], position: i64 = 0, equal: bool = true }
fn update(self: Reader&, bytes: const u8[:]) {
    if !self.equal { return; } if self.position > self.expected.len || bytes.len > self.expected.len - self.position || bytes != self.expected[self.position..self.position + bytes.len] { self.equal = false; return; } self.position += bytes.len;
}
fn matches<T>(self: Image, input: T) -> bool { var reader = Reader { self.bytes , ..}; writeInput(reader, input); return reader.equal && reader.position == self.bytes.len; }
