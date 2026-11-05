// Source-shaped JSON projections use typed values; ownership metadata stays private.
namespace blot_json;
import std;
import .error;
import .option;
struct Options { emit_strings_as_arrays: bool = false,emit_nonportable_numbers_as_strings: bool = false }
enum FrameKind { object,array }
struct Frame { kind: FrameKind = FrameKind.object,first: bool = true }
struct Writer { out: u8[>..]&,options: Options,frames: Frame[256] = [Frame {..};256],depth: i64 = 0,failure: blot_error::Error = blot_error::Error.none }
struct Raw { bytes: const u8[:] }
fn fail(writer: Writer&,error: blot_error::Error) -> blot_error::Error { if writer.failure == blot_error::Error.none { writer.failure = error; } return writer.failure; }
fn quoted(writer: Writer&,text: const u8[:]) -> blot_error::Error {
    if writer.failure != blot_error::Error.none { return writer.failure; } writer.out.push('"'); let hex = "0123456789abcdef";
    for byte in text {
        if byte == '"' || byte == '\\' { writer.out.push('\\'); writer.out.push(byte); }
        else if byte == '\n' { writer.out.append("\\n"); } else if byte == '\r' { writer.out.append("\\r"); } else if byte == '\t' { writer.out.append("\\t"); } else if byte == 8 { writer.out.append("\\b"); } else if byte == 12 { writer.out.append("\\f"); }
        else if byte < 32 { writer.out.append("\\u00"); writer.out.push(hex[byte >> 4]); writer.out.push(hex[byte & 15]); } else { writer.out.push(byte); }
    }
    writer.out.push('"'); return blot_error::Error.none;
}
fn beginObject(writer: Writer&) -> blot_error::Error { if writer.failure != blot_error::Error.none { return writer.failure; } if writer.depth == 256 { return fail(writer,blot_error::Error.module_too_large); } writer.out.push('{'); writer.frames[writer.depth] = Frame { FrameKind.object,true , ..}; writer.depth++; return blot_error::Error.none; }
fn endObject(writer: Writer&) -> blot_error::Error { if writer.failure != blot_error::Error.none { return writer.failure; } assert(writer.depth != 0 && writer.frames[writer.depth - 1].kind == FrameKind.object); writer.depth--; writer.out.push('}'); return blot_error::Error.none; }
fn beginArray(writer: Writer&) -> blot_error::Error { if writer.failure != blot_error::Error.none { return writer.failure; } if writer.depth == 256 { return fail(writer,blot_error::Error.module_too_large); } writer.out.push('['); writer.frames[writer.depth] = Frame { FrameKind.array,true , ..}; writer.depth++; return blot_error::Error.none; }
fn endArray(writer: Writer&) -> blot_error::Error { if writer.failure != blot_error::Error.none { return writer.failure; } assert(writer.depth != 0 && writer.frames[writer.depth - 1].kind == FrameKind.array); writer.depth--; writer.out.push(']'); return blot_error::Error.none; }
fn separator(writer: Writer&,kind: FrameKind) -> blot_error::Error {
    if writer.failure != blot_error::Error.none { return writer.failure; } assert(writer.depth != 0 && writer.frames[writer.depth - 1].kind == kind);
    if !writer.frames[writer.depth - 1].first { writer.out.push(','); } writer.frames[writer.depth - 1].first = false; return blot_error::Error.none;
}
fn key(writer: Writer&,name: const u8[:]) -> blot_error::Error { let separated = separator(writer,FrameKind.object); if separated != blot_error::Error.none { return separated; } let quoted = quoted(writer,name); if quoted != blot_error::Error.none { return quoted; } writer.out.push(':'); return blot_error::Error.none; }
fn field<T>(writer: Writer&,name: const u8[:],value: T) -> blot_error::Error { let named = key(writer,name); if named != blot_error::Error.none { return named; } return write(writer,value); }
fn element<T>(writer: Writer&,value: T) -> blot_error::Error { let separated = separator(writer,FrameKind.array); if separated != blot_error::Error.none { return separated; } return write(writer,value); }
fn nullValue(writer: Writer&) -> blot_error::Error { if writer.failure != blot_error::Error.none { return writer.failure; } writer.out.append("null"); return blot_error::Error.none; }
fn write(writer: Writer&,value: bool) -> blot_error::Error { if writer.failure != blot_error::Error.none { return writer.failure; } if value { writer.out.append("true"); } else { writer.out.append("false"); } return blot_error::Error.none; }
fn unsignedValue(writer: Writer&,value: u64) -> blot_error::Error {
    if writer.failure != blot_error::Error.none { return writer.failure; } let quoted = writer.options.emit_nonportable_numbers_as_strings && value > 9007199254740991;
    if quoted { writer.out.push('"'); } format(writer.out,value); if quoted { writer.out.push('"'); } return blot_error::Error.none;
}
fn signedValue(writer: Writer&,value: i64) -> blot_error::Error {
    if writer.failure != blot_error::Error.none { return writer.failure; } let quoted = writer.options.emit_nonportable_numbers_as_strings && (value < -9007199254740991 || value > 9007199254740991);
    if quoted { writer.out.push('"'); } format(writer.out,value); if quoted { writer.out.push('"'); } return blot_error::Error.none;
}
fn write(writer: Writer&,value: u8) -> blot_error::Error { unsignedValue(writer,value as u64) }
fn write(writer: Writer&,value: u16) -> blot_error::Error { unsignedValue(writer,value as u64) }
fn write(writer: Writer&,value: u32) -> blot_error::Error { unsignedValue(writer,value as u64) }
fn write(writer: Writer&,value: u64) -> blot_error::Error { unsignedValue(writer,value) }
fn write(writer: Writer&,value: i8) -> blot_error::Error { signedValue(writer,value as i64) }
fn write(writer: Writer&,value: i16) -> blot_error::Error { signedValue(writer,value as i64) }
fn write(writer: Writer&,value: i32) -> blot_error::Error { signedValue(writer,value as i64) }
fn write(writer: Writer&,value: i64) -> blot_error::Error { signedValue(writer,value) }
fn write(writer: Writer&,value: f32) -> blot_error::Error {
    if writer.failure != blot_error::Error.none { return writer.failure; }
    if value != value || value - value != 0.0 {
        if !writer.options.emit_nonportable_numbers_as_strings { return nullValue(writer); } if value != value { return quoted(writer,"nan"); } if value < 0.0 { return quoted(writer,"-inf"); } return quoted(writer,"inf");
    }
    format(writer.out,value); return blot_error::Error.none;
}
fn write(writer: Writer&,value: f64) -> blot_error::Error {
    if writer.failure != blot_error::Error.none { return writer.failure; }
    if value != value || value - value != 0.0 {
        if !writer.options.emit_nonportable_numbers_as_strings { return nullValue(writer); } if value != value { return quoted(writer,"nan"); } if value < 0.0 { return quoted(writer,"-inf"); } return quoted(writer,"inf");
    }
    format(writer.out,value); return blot_error::Error.none;
}
fn write(writer: Writer&,value: const u8[:]) -> blot_error::Error {
    if !writer.options.emit_strings_as_arrays { return quoted(writer,value); } let opened = beginArray(writer); if opened != blot_error::Error.none { return opened; }
    for byte in value { let error = element(writer,byte); if error != blot_error::Error.none { return error; } } return endArray(writer);
}
fn write<T>(writer: Writer&,values: const T[:]) -> blot_error::Error {
    let opened = beginArray(writer); if opened != blot_error::Error.none { return opened; } for value in values { let error = element(writer,value); if error != blot_error::Error.none { return error; } } return endArray(writer);
}
fn write<T>(writer: Writer&,value: blot_support::Option<T>) -> blot_error::Error { if !value.present { return nullValue(writer); } return write(writer,value.value); }
fn write<T>(writer: Writer&,value: T?) -> blot_error::Error { if value == null { return nullValue(writer); } return write(writer,value); }
fn write(writer: Writer&,value: Raw) -> blot_error::Error { if writer.failure != blot_error::Error.none { return writer.failure; } writer.out.append(value.bytes); return blot_error::Error.none; }
fn sourceName(name: const u8[:]) -> const u8[:] {
    if name == "unsigned32" { return "u32"; } if name == "floating32" { return "f32"; } if name == "block_" { return "block"; } if name == "loop_" { return "loop"; } if name == "match_" { return "match"; } if name == "opaque_" { return "opaque"; } if name == "guard_" { return "guard"; } if name == "recursive_" { return "recursive"; } if name == "reusable_" { return "reusable"; } if name == "simd_" { return "simd"; } if name == "namespace_" { return "namespace"; } if name == "varint_" { return "varint"; } return name;
}
fn enumName(writer: Writer&,name: const u8[:]) -> blot_error::Error { quoted(writer,sourceName(name)) }
fn enumValue<T>(writer: Writer&,value: T) -> blot_error::Error {
    match value { const for <N,V> in variants<T> { V payload => { return enumName(writer,N); }, } }
}
fn jsonStringify<T>(value: T,writer: Writer&) -> blot_error::Error {
    let opened = beginObject(writer); if opened != blot_error::Error.none { return opened; }
    const for <N,A> in fields<T> { let error = field(writer,sourceName(N),value.A); if error != blot_error::Error.none { return error; } } return endObject(writer);
}
fn toBytes<T>(value: T,out: u8[>..]&,options: Options = Options {..}) -> blot_error::Error { var writer = Writer { out,options , ..}; let error = write(writer,value); if error != blot_error::Error.none { return error; } return writer.failure; }
fn unionValue<T>(writer: Writer&,value: T) -> blot_error::Error {
    match value {
        const for <N,V> in variants<T> {
            V payload => {
                var field_count: i64 = 0; const for <FN,A> in fields<V> { field_count++; }
                if field_count == 0 { return enumName(writer,N); }
                let opened = beginObject(writer); if opened != blot_error::Error.none { return opened; } let named = key(writer,sourceName(N)); if named != blot_error::Error.none { return named; } let written = jsonStringify(payload,writer); if written != blot_error::Error.none { return written; } return endObject(writer);
            },
        }
    }
}

fn objectField(writer: Writer&,name: const u8[:]) -> blot_error::Error { return key(writer,name); }
