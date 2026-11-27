namespace squid_native;

// Scalar representation and operating-system services only. Compiler stages
// and guest code generation remain Goose code.
extern fn fresh_owner_id() -> u64 = "squid_owner_id";
extern fn f32_bits(value: f32) -> u32 = "squid_f32_bits";
extern fn f32_from_bits(value: u32) -> f32 = "squid_f32_from_bits";
extern fn f64_bits(value: f64) -> u64 = "squid_f64_bits";
extern fn f64_from_bits(value: u64) -> f64 = "squid_f64_from_bits";
extern fn copy_u32(dst: u32&, src: const u8&, count: u64) = "squid_copy_u32";
extern fn copy_u8(dst: u8&, src: const u8&, count: u64) = "squid_copy_u8";
extern fn copy_flat(dst: const u8&, src: const u8&, count: u64) = "squid_copy_flat";
extern fn read(fd: i32, first: u8&, count: u64) -> i64 = "squid_read";
extern fn write(fd: i32, first: const u8&, count: u64) -> i64 = "squid_write";
extern fn open_read(path: const u8&) -> i32 = "squid_open_read";
extern fn open_regular(path: const u8&, maximum:u64) -> i32 = "squid_open_regular";
extern fn open_regular_sized(path: const u8&, maximum:u64, size_out:i64&) -> i32 = "squid_open_regular_sized";
extern fn open_regular_nofollow_sized(path: const u8&, maximum:u64, size_out:i64&) -> i32 = "squid_open_regular_nofollow_sized";
extern fn open_write(path: const u8&, exclusive: bool) -> i32 = "squid_open_write";
extern fn close(fd: i32) -> i32 = "squid_close";
extern fn sync(fd: i32) -> i32 = "squid_sync";
extern fn file_size(fd: i32) -> i64 = "squid_file_size";
extern fn rename_file(before: const u8&, after: const u8&) -> i32 = "squid_rename";
extern fn remove_file(path: const u8&) -> i32 = "squid_remove";
extern fn mkdir(path: const u8&) -> i32 = "squid_mkdir";
extern fn clock_ns() -> u64 = "squid_clock_ns";
extern fn thread_cpu_ns() -> u64 = "squid_thread_cpu_ns";
extern fn peak_rss_kib() -> u64 = "squid_peak_rss_kib";
extern fn thread_id() -> u64 = "squid_thread_id";
extern fn random_u64() -> u64 = "squid_random_u64";
extern fn process_id() -> u32 = "squid_process_id";
extern fn real_path(path: const u8&, out: u8&, capacity: u64) -> i64 = "squid_real_path";
extern fn atomic_add(value: u64&, amount: u64) -> u64 = "squid_atomic_add";
extern fn atomic_sub(value: u64&, amount: u64) -> u64 = "squid_atomic_sub";
extern fn atomic_max(value: u64&, candidate: u64) -> u64 = "squid_atomic_max";
extern fn atomic_load(value: const u64&) -> u64 = "squid_atomic_load";
extern fn atomic_store(value: u64&, next: u64) = "squid_atomic_store";
extern fn platform_is_linux() -> u32 = "squid_platform_is_linux";
fn thread_cpu_available() -> bool { platform_is_linux() != 0 }
extern fn i32_bits(value: i32) -> u32 = "squid_i32_bits";
extern fn i32_from_bits(value: u32) -> i32 = "squid_i32_from_bits";
extern fn f32_mul_add(left: f32, right: f32, addend: f32) -> f32 = "squid_f32_mul_add";
extern fn debug_write_raw(first: const u8&, count: u64) = "squid_debug_write";
fn debug_write(bytes: const u8[:]) {
    if bytes.len != 0 { debug_write_raw(bytes[0], bytes.len as u64); }
}
extern fn argument_count()->i64="squid_argument_count";
extern fn argument_size(index:i64)->i64="squid_argument_size";
extern fn argument_copy(index:i64,out:u8&,capacity:u64)->i64="squid_argument_copy";
extern fn environment_size(name:const u8&)->i64="squid_environment_size";
extern fn environment_copy(name:const u8&,out:u8&,capacity:u64)->i64="squid_environment_copy";
extern fn worker_spawn(slot:u32)->i64="squid_worker_spawn";
extern fn worker_descriptor(slot:u32,writing:bool)->i32="squid_worker_descriptor";
extern fn worker_stop(slot:u32)->i32="squid_worker_stop";
extern fn worker_detach()="squid_worker_detach";
extern fn lock_open(path:const u8&)->i32="squid_lock_open";
extern fn try_lock(fd:i32,exclusive:bool)->i32="squid_try_lock";
extern fn unlock(fd:i32)->i32="squid_unlock";
extern fn truncate(fd:i32,length:u64)->i32="squid_truncate";
extern fn pwrite(fd:i32,first:const u8&,count:u64,offset:u64)->i64="squid_pwrite";
extern fn sleep_ms(milliseconds:u64)="squid_sleep_ms";
extern fn available_workers()->u8="squid_available_workers";
extern fn persist_open(count:u32)->u64="squid_persist_open";
extern fn persist_node(handle:u64,unit:u32,priority:u32)->bool="squid_persist_node";
extern fn persist_edge(handle:u64,consumer:u32,producer:u32)->bool="squid_persist_edge";
extern fn persist_claim(handle:u64)->i64="squid_persist_claim";
extern fn persist_publish(handle:u64,id:u32,kind:u32,first:const u8&,length:u64)->bool="squid_persist_publish";
extern fn persist_size(handle:u64,id:u32,kind:u32)->i64="squid_persist_size";
extern fn persist_read(handle:u64,id:u32,kind:u32,first:u8&,length:u64)->bool="squid_persist_read";
extern fn persist_read_at(handle:u64,id:u32,kind:u32,offset:u64,first:const u8&,length:u64)->bool="squid_persist_read_at";
extern fn persist_consumers(handle:u64,id:u32)->u32="squid_persist_consumers";
extern fn persist_kill_child(pid:u32)="squid_persist_kill_child";
extern fn persist_fail(handle:u64)="squid_persist_fail";
extern fn persist_close(handle:u64)="squid_persist_close";
extern fn emit_pool_open(workers:u32)->u64="squid_emit_pool_open";
extern fn emit_pool_close(handle:u64)="squid_emit_pool_close";
extern fn emit_pool_stop(handle:u64)="squid_emit_pool_stop";
extern fn emit_pool_begin_wave(handle:u64,job_count:u32,chunk_size:u32,sync_first:const u8&,sync_len:u64)->bool="squid_emit_pool_begin_wave";
extern fn emit_pool_wait_wave(handle:u64,pids_first:const u32&,pid_count:u32)->bool="squid_emit_pool_wait_wave";
extern fn emit_pool_worker_wait(handle:u64,last_gen:u32)->i64="squid_emit_pool_worker_wait";
extern fn emit_pool_sync_len(handle:u64)->u64="squid_emit_pool_sync_len";
extern fn emit_pool_sync_read(handle:u64,out_first:u8&,len:u64)->bool="squid_emit_pool_sync_read";
extern fn emit_pool_claim_chunk(handle:u64)->u64="squid_emit_pool_claim_chunk";
extern fn emit_pool_lane_append(handle:u64,lane:u32,job_idx:u32,pkt_first:const u8&,len:u64)->bool="squid_emit_pool_lane_append";
extern fn emit_pool_worker_done(handle:u64,ok:bool)="squid_emit_pool_worker_done";
extern fn emit_pool_lane_size(handle:u64,lane:u32)->u64="squid_emit_pool_lane_size";
extern fn emit_pool_lane_read(handle:u64,lane:u32,out_first:u8&,len:u64)->bool="squid_emit_pool_lane_read";
extern fn fork_process()->i64="squid_fork";
extern fn check_reply_open()->u64="squid_check_reply_open";
extern fn check_reply_close(handle:u64)="squid_check_reply_close";
extern fn check_reply_append(handle:u64,first:const u8&,length:u64)->bool="squid_check_reply_append";
extern fn check_reply_size(handle:u64,offset:u64)->i64="squid_check_reply_size";
extern fn check_reply_copy(handle:u64,offset:u64,first:u8&,length:u64)->i64="squid_check_reply_copy";
extern fn job_exit(status:i32)="squid_job_exit";
extern fn detach_session()->i32="squid_detach_session";
extern fn wait_success(pid:u32)->bool="squid_wait_success";
extern fn null_standard_io()="squid_null_standard_io";

extern fn path_kind(path:const u8&)->i32="squid_path_kind";
extern fn directory_open(path:const u8&)->i64="squid_directory_open";
extern fn directory_next(handle:i64,out:u8&,capacity:u64)->i64="squid_directory_next";
extern fn directory_close(handle:i64)->i32="squid_directory_close";
extern fn last_errno()->i32="squid_last_errno";

// Field zero freezes the optional observer snapshot and returns its coverage.
// Other fields read that snapshot; absent native observation returns zero.
extern fn runtime_observation(field:u32)->u64="squid_runtime_observation";
extern fn runtime_memory_mark()="squid_runtime_memory_mark";

// Opaque request transaction transport; all parsing/compilation stays Goose.
extern fn request_start(max_request:u64,max_reply:u64,timeout_ms:u32)->i32="squid_request_start";
extern fn request_begin()->i32="squid_request_begin";
extern fn request_input_fd()->i32="squid_request_input_fd";
extern fn request_token()->u64="squid_request_token";
extern fn request_reply_open()->i32="squid_request_transport_reply_open";
extern fn request_finish(token:u64)->i32="squid_request_transport_finish";
extern fn request_transport_run(reader:i32,writer:i32)->i32="squid_request_transport_run";
extern fn request_fail_oom(token:u64)="squid_request_fail_oom";
extern fn request_fail(token:u64)="squid_request_fail";
