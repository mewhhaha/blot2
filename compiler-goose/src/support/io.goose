namespace blot_io;
import support.native;
import support.error;

type Error = blot_error::Error;
struct Reader { fd: i32 }
struct Writer { fd: i32 }

fn read_short(reader: Reader, out: u8[:]) -> i64, Error {
    var used: i64 = 0;
    while used < out.len {
        let count = blot_native::read(reader.fd, out[used], (out.len - used) as u64);
        if count < 0 { return used, Error.io; }
        if count == 0 { return used, Error.none; }
        used += count;
    }
    return used, Error.none;
}
fn read_all(reader: Reader, out: u8[:]) -> Error {
    let count, error = read_short(reader, out);
    if error != Error.none { return error; }
    if count != out.len { return Error.end_of_stream; }
    return Error.none;
}
fn write_all(writer: Writer, bytes: const u8[:]) -> Error {
    var used: i64 = 0;
    while used < bytes.len {
        let count = blot_native::write(writer.fd, bytes[used], (bytes.len - used) as u64);
        if count <= 0 { return Error.io; }
        used += count;
    }
    return Error.none;
}
fn flush(writer: Writer) -> Error { return Error.none; }

fn read_file(path: const u8[:], out: u8[>..<]&, maximum: i64) -> Error {
    var terminated: u8[>..] = []; terminated.append(path); terminated.push(0);
    let fd = blot_native::open_read(terminated[0]);
    if fd < 0 { return Error.io; }
    let size = blot_native::file_size(fd);
    if size < 0 || size > maximum { blot_native::close(fd); return Error.overflow; }
    let start = out.len;
    if size > 9223372036854775807 - start { blot_native::close(fd); return Error.overflow; }
    out.resize(start + size, 0);
    let error = read_all(Reader { fd }, out[start..]);
    let closed = blot_native::close(fd);
    if error != Error.none { out.resize(start, 0); return error; }
    if closed < 0 { out.resize(start, 0); return Error.io; }
    return Error.none;
}
fn write_file(path: const u8[:], bytes: const u8[:]) -> Error {
    var terminated: u8[>..] = []; terminated.append(path); terminated.push(0);
    let fd = blot_native::open_write(terminated[0], false);
    if fd < 0 { return Error.io; }
    let error = write_all(Writer { fd }, bytes);
    let closed = blot_native::close(fd);
    if error != Error.none { return error; }
    if closed < 0 { return Error.io; }
    return Error.none;
}
