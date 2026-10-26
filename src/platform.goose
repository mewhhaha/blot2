import std;
extern fn real_path(path: const u8[:], out: u8[>..]&) -> bool = "blot_real_path";
extern fn read_bounded(path: const u8[:], limit: u32, out: u8[>..]&) -> bool = "blot_read_bounded";
extern fn read_line_bounded(limit: u32, out: u8[>..]&) -> u32 = "blot_read_line_bounded";
extern fn write_output_pair(first_path: const u8[:], first_bytes: const u8[:], second_path: const u8[:], second_bytes: const u8[:]) -> bool = "blot_write_output_pair";
extern fn write_generated_atomic(path: const u8[:], bytes: const u8[:]) -> bool = "blot_write_generated_atomic";
