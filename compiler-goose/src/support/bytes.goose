namespace blot_bytes;
import support.error;

type Error = blot_error::Error;

struct Reader { data: const u8[:], position: i64 = 0 }
struct Writer { data: u8[>..<]& }

fn remaining(reader: Reader) -> i64 { reader.data.len - reader.position }
fn range(reader: Reader, count: i64) -> bool {
    count >= 0 && reader.position >= 0 && reader.position <= reader.data.len &&
        count <= reader.data.len - reader.position
}
fn read(reader: Reader&, count: i64) -> const u8[:], Error {
    if !range(reader, count) { return reader.data[..0], blot_error::Error.end_of_stream; }
    let start = reader.position;
    reader.position += count;
    return reader.data[start..reader.position], blot_error::Error.none;
}
fn skip(reader: Reader&, count: i64) -> Error {
    if !range(reader, count) { return blot_error::Error.end_of_stream; }
    reader.position += count;
    return blot_error::Error.none;
}
fn read_u8(reader: Reader&) -> u8, Error {
    if !range(reader, 1) { return 0, blot_error::Error.end_of_stream; }
    let value = reader.data[reader.position]; reader.position++;
    return value, blot_error::Error.none;
}
fn read_u16(reader: Reader&) -> u16, Error {
    let bytes, error = read(reader, 2);
    if error != blot_error::Error.none { return 0, error; }
    return bytes[0] as u16 | (bytes[1] as u16 << 8), blot_error::Error.none;
}
fn read_u32(reader: Reader&) -> u32, Error {
    let bytes, error = read(reader, 4);
    if error != blot_error::Error.none { return 0, error; }
    return bytes[0] as u32 | (bytes[1] as u32 << 8) |
        (bytes[2] as u32 << 16) | (bytes[3] as u32 << 24), blot_error::Error.none;
}
fn read_u64(reader: Reader&) -> u64, Error {
    let bytes, error = read(reader, 8);
    if error != blot_error::Error.none { return 0, error; }
    var value: u64 = 0;
    for byte, index in bytes { value |= byte as u64 << ((index * 8) as u64); }
    return value, blot_error::Error.none;
}
fn read_uleb32(reader: Reader&) -> u32, Error {
    let start = reader.position;
    var value: u32 = 0;
    for index in 5 {
        let byte, error = read_u8(reader);
        if error != blot_error::Error.none { reader.position = start; return 0, error; }
        if index == 4 && byte > 15 { reader.position = start; return 0, blot_error::Error.overflow; }
        value |= (byte & 127) as u32 << ((index * 7) as u32);
        if byte & 128 == 0 { return value, blot_error::Error.none; }
    }
    reader.position = start;
    return 0, blot_error::Error.overflow;
}
fn read_uleb64(reader: Reader&) -> u64, Error {
    let start = reader.position;
    var value: u64 = 0;
    for index in 10 {
        let byte, error = read_u8(reader);
        if error != blot_error::Error.none { reader.position = start; return 0, error; }
        if index == 9 && byte > 1 { reader.position = start; return 0, blot_error::Error.overflow; }
        value |= (byte & 127) as u64 << ((index * 7) as u64);
        if byte & 128 == 0 { return value, blot_error::Error.none; }
    }
    reader.position = start;
    return 0, blot_error::Error.overflow;
}
fn write_u8(writer: Writer, value: u8) { writer.data.push(value); }
fn write_u16(writer: Writer, value: u16) {
    writer.data.push(value as! u8); writer.data.push((value >> 8) as! u8);
}
fn write_u32(writer: Writer, value: u32) {
    for shift in 4 { writer.data.push((value >> ((shift * 8) as u32)) as! u8); }
}
fn write_u64(writer: Writer, value: u64) {
    for shift in 8 { writer.data.push((value >> ((shift * 8) as u64)) as! u8); }
}
fn write_uleb32(writer: Writer, var value: u32) {
    loop {
        var byte = (value & 127) as u8;
        value >>= 7;
        if value != 0 { byte |= 128; }
        writer.data.push(byte);
        if value == 0 { return; }
    }
}
fn write_uleb64(writer: Writer, var value: u64) {
    loop {
        var byte = (value & 127) as u8;
        value >>= 7;
        if value != 0 { byte |= 128; }
        writer.data.push(byte);
        if value == 0 { return; }
    }
}
fn write_sleb32(writer: Writer, var value: i32) {
    loop {
        var byte = ((value as! u32) & 127) as u8;
        value >>= 7;
        let finished = value == 0 && byte & 64 == 0 || value == -1 && byte & 64 != 0;
        if !finished { byte |= 128; }
        writer.data.push(byte);
        if finished { return; }
    }
}
fn write(writer: Writer, bytes: const u8[:]) { writer.data.append(bytes); }
fn write_slice(writer: Writer, bytes: const u8[:]) {
    write_u32(writer, bytes.len as u32); writer.data.append(bytes);
}
fn read_slice(reader: Reader&, maximum: u32) -> const u8[:], Error {
    let count, error = read_u32(reader);
    if error != blot_error::Error.none { return reader.data[..0], error; }
    if count > maximum { return reader.data[..0], blot_error::Error.overflow; }
    return read(reader, count as i64);
}

fn put_u32(bytes: u8[:], at: i64, value: u32) {
    for shift in 4 { bytes[at + shift] = (value >> ((shift * 8) as u32)) as! u8; }
}
fn put_u64(bytes: u8[:], at: i64, value: u64) {
    for shift in 8 { bytes[at + shift] = (value >> ((shift * 8) as u64)) as! u8; }
}
fn get_u32(bytes: const u8[:], at: i64) -> u32 {
    bytes[at] as u32 | (bytes[at + 1] as u32 << 8) |
        (bytes[at + 2] as u32 << 16) | (bytes[at + 3] as u32 << 24)
}
fn get_u64(bytes: const u8[:], at: i64) -> u64 {
    var value: u64 = 0;
    for shift in 8 { value |= bytes[at + shift] as u64 << ((shift * 8) as u64); }
    return value;
}
