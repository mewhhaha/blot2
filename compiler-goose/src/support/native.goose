namespace blot_native;

// Scalar representation and operating-system services only. Compiler stages
// and guest code generation remain Goose code.
extern fn fresh_owner_id() -> u64 = "blot_owner_id";
extern fn f32_bits(value: f32) -> u32 = "blot_f32_bits";
extern fn f32_from_bits(value: u32) -> f32 = "blot_f32_from_bits";
extern fn f64_bits(value: f64) -> u64 = "blot_f64_bits";
extern fn f64_from_bits(value: u64) -> f64 = "blot_f64_from_bits";
extern fn read(fd: i32, first: u8&, count: u64) -> i64 = "blot_read";
extern fn write(fd: i32, first: const u8&, count: u64) -> i64 = "blot_write";
extern fn open_read(path: const u8&) -> i32 = "blot_open_read";
extern fn open_write(path: const u8&, exclusive: bool) -> i32 = "blot_open_write";
extern fn close(fd: i32) -> i32 = "blot_close";
extern fn sync(fd: i32) -> i32 = "blot_sync";
extern fn file_size(fd: i32) -> i64 = "blot_file_size";
extern fn rename_file(before: const u8&, after: const u8&) -> i32 = "blot_rename";
extern fn remove_file(path: const u8&) -> i32 = "blot_remove";
extern fn mkdir(path: const u8&) -> i32 = "blot_mkdir";
extern fn clock_ns() -> u64 = "blot_clock_ns";
extern fn thread_cpu_ns() -> u64 = "blot_thread_cpu_ns";
extern fn peak_rss_kib() -> u64 = "blot_peak_rss_kib";
extern fn thread_id() -> u64 = "blot_thread_id";
extern fn random_u64() -> u64 = "blot_random_u64";
extern fn process_id() -> u32 = "blot_process_id";
extern fn real_path(path: const u8&, out: u8&, capacity: u64) -> i64 = "blot_real_path";
extern fn atomic_add(value: u64&, amount: u64) -> u64 = "blot_atomic_add";
extern fn atomic_sub(value: u64&, amount: u64) -> u64 = "blot_atomic_sub";
extern fn atomic_max(value: u64&, candidate: u64) -> u64 = "blot_atomic_max";
extern fn atomic_load(value: const u64&) -> u64 = "blot_atomic_load";
extern fn atomic_store(value: u64&, next: u64) = "blot_atomic_store";
