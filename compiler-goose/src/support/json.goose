// Source-shaped JSON projections use typed values; ownership metadata stays private.
namespace squid_json;
import std;
import .error;
import .option;
struct Options { emit_strings_as_arrays: bool = false,emit_nonportable_numbers_as_strings: bool = false }
enum FrameKind { object,array }
struct Frame { kind: FrameKind = FrameKind.object,first: bool = true }
struct Writer { out: u8[>..]&,options: Options,frames: Frame[256] = [Frame {..};256],depth: i64 = 0,failure: squid_error::Error = squid_error::Error.none }
struct Raw { bytes: const u8[:] }
fn fail(writer: Writer&,error: squid_error::Error) -> squid_error::Error { if writer.failure == squid_error::Error.none { writer.failure = error; } return writer.failure; }
fn quoted(writer: Writer&,text: const u8[:]) -> squid_error::Error {
    if writer.failure != squid_error::Error.none { return writer.failure; } writer.out.push('"'); let hex = "0123456789abcdef";
    for byte in text {
        if byte == '"' || byte == '\\' { writer.out.push('\\'); writer.out.push(byte); }
        else if byte == '\n' { writer.out.append("\\n"); } else if byte == '\r' { writer.out.append("\\r"); } else if byte == '\t' { writer.out.append("\\t"); } else if byte == 8 { writer.out.append("\\b"); } else if byte == 12 { writer.out.append("\\f"); }
        else if byte < 32 { writer.out.append("\\u00"); writer.out.push(hex[byte >> 4]); writer.out.push(hex[byte & 15]); } else { writer.out.push(byte); }
    }
    writer.out.push('"'); return squid_error::Error.none;
}
fn beginObject(writer: Writer&) -> squid_error::Error { if writer.failure != squid_error::Error.none { return writer.failure; } if writer.depth == 256 { return fail(writer,squid_error::Error.module_too_large); } writer.out.push('{'); writer.frames[writer.depth] = Frame { FrameKind.object,true , ..}; writer.depth++; return squid_error::Error.none; }
fn endObject(writer: Writer&) -> squid_error::Error { if writer.failure != squid_error::Error.none { return writer.failure; } assert(writer.depth != 0 && writer.frames[writer.depth - 1].kind == FrameKind.object); writer.depth--; writer.out.push('}'); return squid_error::Error.none; }
fn beginArray(writer: Writer&) -> squid_error::Error { if writer.failure != squid_error::Error.none { return writer.failure; } if writer.depth == 256 { return fail(writer,squid_error::Error.module_too_large); } writer.out.push('['); writer.frames[writer.depth] = Frame { FrameKind.array,true , ..}; writer.depth++; return squid_error::Error.none; }
fn endArray(writer: Writer&) -> squid_error::Error { if writer.failure != squid_error::Error.none { return writer.failure; } assert(writer.depth != 0 && writer.frames[writer.depth - 1].kind == FrameKind.array); writer.depth--; writer.out.push(']'); return squid_error::Error.none; }
fn separator(writer: Writer&,kind: FrameKind) -> squid_error::Error {
    if writer.failure != squid_error::Error.none { return writer.failure; } assert(writer.depth != 0 && writer.frames[writer.depth - 1].kind == kind);
    if !writer.frames[writer.depth - 1].first { writer.out.push(','); } writer.frames[writer.depth - 1].first = false; return squid_error::Error.none;
}
fn key(writer: Writer&,name: const u8[:]) -> squid_error::Error { let separated = separator(writer,FrameKind.object); if separated != squid_error::Error.none { return separated; } let quoted = quoted(writer,name); if quoted != squid_error::Error.none { return quoted; } writer.out.push(':'); return squid_error::Error.none; }
fn field<T>(writer: Writer&,name: const u8[:],value: T) -> squid_error::Error { let named = key(writer,name); if named != squid_error::Error.none { return named; } return write(writer,value); }
fn element<T>(writer: Writer&,value: T) -> squid_error::Error { let separated = separator(writer,FrameKind.array); if separated != squid_error::Error.none { return separated; } return write(writer,value); }
fn nullValue(writer: Writer&) -> squid_error::Error { if writer.failure != squid_error::Error.none { return writer.failure; } writer.out.append("null"); return squid_error::Error.none; }
fn squid_json::squidJsonWrite(value: bool,writer: squid_json::Writer&) -> squid_error::Error { if writer.failure != squid_error::Error.none { return writer.failure; } if value { writer.out.append("true"); } else { writer.out.append("false"); } return squid_error::Error.none; }
fn unsignedValue(writer: Writer&,value: u64) -> squid_error::Error {
    if writer.failure != squid_error::Error.none { return writer.failure; } let quoted = writer.options.emit_nonportable_numbers_as_strings && value > 9007199254740991;
    if quoted { writer.out.push('"'); } format(writer.out,value); if quoted { writer.out.push('"'); } return squid_error::Error.none;
}
fn signedValue(writer: Writer&,value: i64) -> squid_error::Error {
    if writer.failure != squid_error::Error.none { return writer.failure; } let quoted = writer.options.emit_nonportable_numbers_as_strings && (value < -9007199254740991 || value > 9007199254740991);
    if quoted { writer.out.push('"'); } format(writer.out,value); if quoted { writer.out.push('"'); } return squid_error::Error.none;
}
fn squid_json::squidJsonWrite(value: u8,writer: squid_json::Writer&) -> squid_error::Error { squid_json::unsignedValue(writer,value as u64) }
fn squid_json::squidJsonWrite(value: u16,writer: squid_json::Writer&) -> squid_error::Error { squid_json::unsignedValue(writer,value as u64) }
fn squid_json::squidJsonWrite(value: u32,writer: squid_json::Writer&) -> squid_error::Error { squid_json::unsignedValue(writer,value as u64) }
fn squid_json::squidJsonWrite(value: u64,writer: squid_json::Writer&) -> squid_error::Error { squid_json::unsignedValue(writer,value) }
fn squid_json::squidJsonWrite(value: i8,writer: squid_json::Writer&) -> squid_error::Error { squid_json::signedValue(writer,value as i64) }
fn squid_json::squidJsonWrite(value: i16,writer: squid_json::Writer&) -> squid_error::Error { squid_json::signedValue(writer,value as i64) }
fn squid_json::squidJsonWrite(value: i32,writer: squid_json::Writer&) -> squid_error::Error { squid_json::signedValue(writer,value as i64) }
fn squid_json::squidJsonWrite(value: i64,writer: squid_json::Writer&) -> squid_error::Error { squid_json::signedValue(writer,value) }
fn squid_json::squidJsonWrite(value: f32,writer: squid_json::Writer&) -> squid_error::Error {
    if writer.failure != squid_error::Error.none { return writer.failure; }
    if value != value || value - value != 0.0 {
        if !writer.options.emit_nonportable_numbers_as_strings { return squid_json::nullValue(writer); } if value != value { return squid_json::quoted(writer,"nan"); } if value < 0.0 { return squid_json::quoted(writer,"-inf"); } return squid_json::quoted(writer,"inf");
    }
    format(writer.out,value); return squid_error::Error.none;
}
fn squid_json::squidJsonWrite(value: f64,writer: squid_json::Writer&) -> squid_error::Error {
    if writer.failure != squid_error::Error.none { return writer.failure; }
    if value != value || value - value != 0.0 {
        if !writer.options.emit_nonportable_numbers_as_strings { return squid_json::nullValue(writer); } if value != value { return squid_json::quoted(writer,"nan"); } if value < 0.0 { return squid_json::quoted(writer,"-inf"); } return squid_json::quoted(writer,"inf");
    }
    format(writer.out,value); return squid_error::Error.none;
}
fn squid_json::squidJsonWrite(value: const u8[:],writer: squid_json::Writer&) -> squid_error::Error {
    if !writer.options.emit_strings_as_arrays { return squid_json::quoted(writer,value); } let opened = squid_json::beginArray(writer); if opened != squid_error::Error.none { return opened; }
    for byte in value { let error = squid_json::element(writer,byte); if error != squid_error::Error.none { return error; } } return squid_json::endArray(writer);
}
fn squid_json::squidJsonWrite<T>(values: const T[:],writer: squid_json::Writer&) -> squid_error::Error {
    let opened = squid_json::beginArray(writer); if opened != squid_error::Error.none { return opened; } for value in values { let error = squid_json::element(writer,value); if error != squid_error::Error.none { return error; } } return squid_json::endArray(writer);
}
fn squid_support::squidJsonWrite<T>(value: squid_support::Option<T>,writer: squid_json::Writer&) -> squid_error::Error { if !value.present { return squid_json::nullValue(writer); } return squid_json::write(writer,value.value); }
fn squid_json::squidJsonWrite<T>(value: T?,writer: squid_json::Writer&) -> squid_error::Error { if value == null { return squid_json::nullValue(writer); } return squid_json::write(writer,value); }
fn squid_json::squidJsonWrite(value: Raw,writer: squid_json::Writer&) -> squid_error::Error { if writer.failure != squid_error::Error.none { return writer.failure; } writer.out.append(value.bytes); return squid_error::Error.none; }
fn sourceName(name: const u8[:]) -> const u8[:] {
    if name == "unsigned32" { return "u32"; } if name == "floating32" { return "f32"; } if name == "unsigned8" { return "u8"; } if name == "signed32" { return "i32"; } if name == "unsigned64" { return "u64"; } if name == "signed64" { return "i64"; } if name == "floating64" { return "f64"; } if name == "block_" { return "block"; } if name == "loop_" { return "loop"; } if name == "match_" { return "match"; } if name == "opaque_" { return "opaque"; } if name == "guard_" { return "guard"; } if name == "recursive_" { return "recursive"; } if name == "reusable_" { return "reusable"; } if name == "simd_" { return "simd"; } if name == "namespace_" { return "namespace"; } if name == "varint_" { return "varint"; } return name;
}
fn enumName(writer: Writer&,name: const u8[:]) -> squid_error::Error { quoted(writer,sourceName(name)) }
fn enumValue<T>(writer: Writer&,value: T) -> squid_error::Error {
    match value { const for <N,V> in variants<T> { V payload => { return enumName(writer,N); }, } }
}
fn jsonStringify<T>(value: T,writer: Writer&) -> squid_error::Error {
    let opened = beginObject(writer); if opened != squid_error::Error.none { return opened; }
    const for <N,A> in fields<T> { let error = field(writer,sourceName(N),value.A); if error != squid_error::Error.none { return error; } } return endObject(writer);
}
fn toBytes<T>(value: T,out: u8[>..]&,options: Options = Options {..}) -> squid_error::Error { var writer = Writer { out,options , ..}; let error = write(writer,value); if error != squid_error::Error.none { return error; } return writer.failure; }
fn unionValue<T>(writer: Writer&,value: T) -> squid_error::Error {
    match value {
        const for <N,V> in variants<T> {
            V payload => {
                var field_count: i64 = 0; const for <FN,A> in fields<V> { field_count++; }
                if field_count == 0 { return enumName(writer,N); }
                let opened = beginObject(writer); if opened != squid_error::Error.none { return opened; } let named = key(writer,sourceName(N)); if named != squid_error::Error.none { return named; } let written = jsonStringify(payload,writer); if written != squid_error::Error.none { return written; } return endObject(writer);
            },
        }
    }
}

fn objectField(writer: Writer&,name: const u8[:]) -> squid_error::Error { return key(writer,name); }

fn write<JsonWriter,T>(writer:JsonWriter&,value:T)->squid_error::Error {return value.squidJsonWrite(writer);}
fn write(writer:Writer&,value:const u8[:])->squid_error::Error {return squidJsonWrite(value,writer);}
