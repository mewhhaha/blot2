// Original module identity retained for the protocol mapping; implementation is Goose.
namespace blot_reuse_zig_project_frames;
import support.bytes;
import support.error;
import support.io;

type Error = blot_error::Error;
let max_frame_bytes: i64 = 67108864;
let max_metadata_bytes: i64 = 16777216;
let max_revision: u64 = 9007199254740991;

struct RequestFrame { bytes: const u8[:], metadata_length: i64 }
fn metadata(frame: RequestFrame) -> const u8[:] { frame.bytes[..frame.metadata_length] }
fn payload(frame: RequestFrame) -> const u8[:] { frame.bytes[frame.metadata_length..] }
fn checkLengths(metadata: i64, payload: i64) -> Error {
    if metadata <= 0 || metadata > max_metadata_bytes || payload < 0 ||
        payload > max_frame_bytes - 8 - metadata { return Error.frame_too_large; }
    return Error.none;
}
fn readRequestFrame(reader: blot_io::Reader, bytes: u8[>..<]&) -> RequestFrame, bool, Error {
    var header: u8[8] = default<u8[8]>();
    let count, error = blot_io::read_short(reader, header);
    if error != Error.none { return RequestFrame { bytes[..0], 0 }, false, error; }
    if count == 0 { return RequestFrame { bytes[..0], 0 }, false, Error.none; }
    if count != 8 { return RequestFrame { bytes[..0], 0 }, false, Error.truncated_frame; }
    let metadata = blot_bytes::get_u32(header, 0) as i64;
    let payload = blot_bytes::get_u32(header, 4) as i64;
    let checked = checkLengths(metadata, payload);
    if checked != Error.none { return RequestFrame { bytes[..0], 0 }, false, checked; }
    bytes.clear(); bytes.resize(metadata + payload, 0);
    let read = blot_io::read_all(reader, bytes);
    if read != Error.none {
        bytes.clear();
        if read == Error.end_of_stream { return RequestFrame { bytes[..0], 0 }, false, Error.truncated_frame; }
        return RequestFrame { bytes[..0], 0 }, false, read;
    }
    return RequestFrame { bytes, metadata }, true, Error.none;
}
fn readRequest(reader: blot_io::Reader, bytes: u8[>..<]&) -> bool, Error {
    var header: u8[8] = default<u8[8]>();
    let count, error = blot_io::read_short(reader, header);
    if error != Error.none { return false, error; }
    if count == 0 { return false, Error.none; }
    if count != 8 { return false, Error.truncated_frame; }
    let metadata = blot_bytes::get_u32(header, 0) as i64;
    let payload = blot_bytes::get_u32(header, 4) as i64;
    let checked = checkLengths(metadata, payload);
    if checked != Error.none { return false, checked; }
    if payload != 0 { return false, Error.request_payload_unsupported; }
    bytes.clear(); bytes.resize(metadata, 0);
    let read = blot_io::read_all(reader, bytes);
    if read != Error.none {
        bytes.clear();
        if read == Error.end_of_stream { return false, Error.truncated_frame; }
        return false, read;
    }
    return true, Error.none;
}
fn writeParts(writer: blot_io::Writer, metadata: const u8[:], parts: const u8[:][:]) -> Error {
    var size: i64 = 0;
    for part in parts {
        if part.len > 9223372036854775807 - size { return Error.frame_too_large; }
        size += part.len;
    }
    let checked = checkLengths(metadata.len, size);
    if checked != Error.none { return checked; }
    var header: u8[8] = default<u8[8]>();
    blot_bytes::put_u32(header, 0, metadata.len as u32);
    blot_bytes::put_u32(header, 4, size as u32);
    let first = blot_io::write_all(writer, header); if first != Error.none { return first; }
    let second = blot_io::write_all(writer, metadata); if second != Error.none { return second; }
    for part in parts {
        let error = blot_io::write_all(writer, part); if error != Error.none { return error; }
    }
    return blot_io::flush(writer);
}
fn write(writer: blot_io::Writer, metadata: const u8[:], payload: const u8[:]) -> Error {
    let parts = [payload];
    return writeParts(writer, metadata, parts);
}
