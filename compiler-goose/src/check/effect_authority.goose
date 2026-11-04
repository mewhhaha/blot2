// Activation authority never enters semantic catalogs or portable archives.
namespace blot_check_effect_authority;
import support.error;
type Handle = u32;
type Error = blot_error::Error;
let static: Handle = 0;
struct Owner { references: u32 = 1, active: bool = true }
struct Store { owners: Owner[>..]&, live: i64 = 0, active: i64 = 0, max_owners: u32 = 0xffffffff }
fn init(owners: Owner[>..]&) -> Store { return Store { owners }; }
fn deinit(self: Store&) { self.owners.clear(); self.live = 0; self.active = 0; }
fn begin(self: Store&) -> Handle, Error {
    if self.owners.len >= self.max_owners { return 0, Error.authority_limit; }
    self.owners.push(Owner {}); self.live += 1; self.active += 1; return self.owners.len as u32, Error.none;
}
fn ownerIndex(self: const Store&, handle: Handle) -> i64, Error {
    if handle == 0 || handle > self.owners.len || self.owners[handle - 1].references == 0 { return 0, Error.invalid_authority; }
    return (handle - 1) as i64, Error.none;
}
fn requireActive(self: const Store&, handle: Handle) -> Error {
    if handle == static { return Error.none; } let index, error = ownerIndex(self, handle); if error != Error.none { return error; }
    if !self.owners[index].active { return Error.inactive_authority; } return Error.none;
}
fn retain(self: Store&, handle: Handle) -> Error {
    if handle == static { return Error.none; } let index, error = ownerIndex(self, handle); if error != Error.none { return error; }
    if self.owners[index].references == 0xffffffff { return Error.authority_limit; } self.owners[index].references += 1; return Error.none;
}
fn release(self: Store&, handle: Handle) -> Error {
    if handle == static { return Error.none; } let index, error = ownerIndex(self, handle); if error != Error.none { return error; }
    if self.owners[index].references == 1 && self.owners[index].active { return Error.invalid_authority; }
    self.owners[index].references -= 1; if self.owners[index].references == 0 { self.live -= 1; } return Error.none;
}
fn revoke(self: Store&, handle: Handle) -> Error {
    if handle == static { return Error.invalid_authority; } let index, error = ownerIndex(self, handle); if error != Error.none { return error; }
    if self.owners[index].active { self.owners[index].active = false; self.active -= 1; } return Error.none;
}
fn end(self: Store&, handle: Handle) -> Error { let revoked = revoke(self, handle); if revoked != Error.none { return revoked; } return release(self, handle); }
