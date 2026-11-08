// Exact ordered field bytes, not a digest. Portable archive schemas are separate.
namespace blot_reuse_validation_image;
import std;
import support.error;
import support.option;
import support.structural;
import check.core;
type Error = blot_error::Error;
struct Image { bytes: const u8[:] = default<const u8[:]>(), lease: u32 = 0, generation: u64 = 0 }
struct Lease { references: u64 = 0, generation: u64 = 0 }
reusable var image_leases: Lease[>..] = [];
reusable[] var image_bytes: u8[>..] = [];
var next_generation: u64 = 1;
fn live(self_: Image) -> bool { return self_.lease != 0 && self_.lease <= image_leases.len && image_leases[self_.lease - 1].references != 0 && image_leases[self_.lease - 1].generation == self_.generation; }
fn retain(self_: Image) -> Image, Error { if !self_.live() { return Image {..}, blot_error::Error.invalid_artifact; } if image_leases[self_.lease - 1].references == 0xffffffffffffffff { return Image {..}, blot_error::Error.out_of_memory; } image_leases[self_.lease - 1].references++; return self_, blot_error::Error.none; }
fn deinit(self_: Image&) {
    if self_.lease == 0 { assert(self_.bytes.len == 0); return; } assert(self_.live()); let lease = self_.lease - 1; image_leases[lease].references--;
    if image_leases[lease].references == 0 { if self_.bytes.len != 0 { image_bytes.free_slice(self_.bytes); } image_leases.free(lease); }
    self_ = Image {..};
}
struct Writer { limit: i64, bytes: u8[>..<]&, failure: Error = blot_error::Error.none, declined: bool = false }
fn update(self_: Writer&, bytes: const u8[:]) {
    if self_.failure != blot_error::Error.none || self_.declined { return; } if self_.bytes.len > self_.limit || bytes.len > self_.limit - self_.bytes.len { self_.declined = true; return; } self_.bytes.append(bytes);
}
fn writeInput<S,T>(sink: S&, input: T) { blot_structural::hash(sink, input); }
fn writeInput(sink: Writer&, input: blot_check_core::Module) { blot_structural::hash(sink, blot_check_core::stampView(input)); }
fn writeInput(sink: Reader&, input: blot_check_core::Module) { blot_structural::hash(sink, blot_check_core::stampView(input)); }
fn capture<T>(input: T, remaining: i64&) -> blot_support::Option<Image>, Error {
    var bytes: u8[>..<] = []; var writer = Writer { remaining, bytes , ..}; writeInput(writer, input);
    if writer.failure != blot_error::Error.none { return blot_support::none<Image>(), writer.failure; } if writer.declined { return blot_support::none<Image>(), blot_error::Error.none; }
    if next_generation == 0xffffffffffffffff || image_leases.len >= 0xffffffff { return blot_support::none<Image>(), blot_error::Error.out_of_memory; }
    let run = image_bytes.alloc_slice(bytes.len); for byte, index in bytes { run[index] = byte; }
    let generation = next_generation; next_generation++; let lease = image_leases.alloc_index(Lease { 1, generation , ..});
    remaining -= bytes.len; return blot_support::some(Image { run, (lease + 1) as u32, generation , ..}), blot_error::Error.none;
}
struct Reader { expected: const u8[:], position: i64 = 0, equal: bool = true }
fn update(self_: Reader&, bytes: const u8[:]) {
    if !self_.equal { return; } if self_.position > self_.expected.len || bytes.len > self_.expected.len - self_.position || bytes != self_.expected[self_.position..self_.position + bytes.len] { self_.equal = false; return; } self_.position += bytes.len;
}
fn matches<T>(self_: Image, input: T) -> bool { var reader = Reader { self_.bytes , ..}; writeInput(reader, input); return reader.equal && reader.position == self_.bytes.len; }
