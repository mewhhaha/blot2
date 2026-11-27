// Original module identity retained for the protocol mapping; implementation is Goose.
namespace squid_reuse_zig_project_frames;
import support.bytes;
import support.error;
import support.io;

type Error = squid_error::Error;
let max_frame_bytes: i64 = 67108864;
let max_metadata_bytes: i64 = 16777216;
let max_revision: u64 = 9007199254740991;

struct RequestFrame { bytes: const u8[:], metadata_length: i64 }
fn metadata(frame: RequestFrame) -> const u8[:] { frame.bytes[..frame.metadata_length] }
fn payload(frame: RequestFrame) -> const u8[:] { frame.bytes[frame.metadata_length..] }
fn checkLengths(metadata: i64, payload: i64) -> Error {
    if metadata <= 0 || metadata > max_metadata_bytes || payload < 0 ||
        payload > max_frame_bytes - 8 - metadata { return squid_error::Error.frame_too_large; }
    return squid_error::Error.none;
}
fn readRequestFrame(reader: squid_io::Reader, bytes: u8[>..]&) -> RequestFrame, bool, Error {
    var header: u8[8] = default<u8[8]>();
    let count, error = squid_io::read_short(reader, header);
    if error != squid_error::Error.none { return RequestFrame { bytes[..0], 0 , ..}, false, error; }
    if count == 0 { return RequestFrame { bytes[..0], 0 , ..}, false, squid_error::Error.none; }
    if count != 8 { return RequestFrame { bytes[..0], 0 , ..}, false, squid_error::Error.truncated_frame; }
    let metadata = squid_bytes::get_u32(header, 0) as i64;
    let payload = squid_bytes::get_u32(header, 4) as i64;
    let checked = checkLengths(metadata, payload);
    if checked != squid_error::Error.none { return RequestFrame { bytes[..0], 0 , ..}, false, checked; }
    // Retain the high-water allocation; only this frame prefix is live.
    let length=metadata+payload;if bytes.len<length {let zeros:u8[4096]=[0;4096];while bytes.len<length {let count=min(length-bytes.len,zeros.len);bytes.append(zeros[..count]);}}
    let read = squid_io::read_all(reader, bytes[..length]);
    if read != squid_error::Error.none {
        if read == squid_error::Error.end_of_stream { return RequestFrame { bytes[..0], 0 , ..}, false, squid_error::Error.truncated_frame; }
        return RequestFrame { bytes[..0], 0 , ..}, false, read;
    }
    return RequestFrame { bytes[..length], metadata , ..}, true, squid_error::Error.none;
}
fn readRequest(reader: squid_io::Reader, bytes: u8[>..<]&) -> bool, Error {
    var header: u8[8] = default<u8[8]>();
    let count, error = squid_io::read_short(reader, header);
    if error != squid_error::Error.none { return false, error; }
    if count == 0 { return false, squid_error::Error.none; }
    if count != 8 { return false, squid_error::Error.truncated_frame; }
    let metadata = squid_bytes::get_u32(header, 0) as i64;
    let payload = squid_bytes::get_u32(header, 4) as i64;
    let checked = checkLengths(metadata, payload);
    if checked != squid_error::Error.none { return false, checked; }
    if payload != 0 { return false, squid_error::Error.request_payload_unsupported; }
    bytes.clear(); bytes.resize(metadata, 0);
    let read = squid_io::read_all(reader, bytes);
    if read != squid_error::Error.none {
        bytes.clear();
        if read == squid_error::Error.end_of_stream { return false, squid_error::Error.truncated_frame; }
        return false, read;
    }
    return true, squid_error::Error.none;
}
fn writeParts(writer: squid_io::Writer, metadata: const u8[:], parts: const u8[:][:]) -> Error {
    var size: i64 = 0;
    for part in parts {
        if part.len > 9223372036854775807 - size { return squid_error::Error.frame_too_large; }
        size += part.len;
    }
    let checked = checkLengths(metadata.len, size);
    if checked != squid_error::Error.none { return checked; }
    var header: u8[8] = default<u8[8]>();
    squid_bytes::put_u32(header, 0, metadata.len as u32);
    squid_bytes::put_u32(header, 4, size as u32);
    let first = squid_io::write_all(writer, header); if first != squid_error::Error.none { return first; }
    let second = squid_io::write_all(writer, metadata); if second != squid_error::Error.none { return second; }
    for part in parts {
        let error = squid_io::write_all(writer, part); if error != squid_error::Error.none { return error; }
    }
    return squid_io::flush(writer);
}
fn write(writer: squid_io::Writer, metadata: const u8[:], payload: const u8[:]) -> Error {
    let parts = [payload];
    return writeParts(writer, metadata, parts);
}
