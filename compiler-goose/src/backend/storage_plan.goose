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
