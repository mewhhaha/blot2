// Source coordinates borrow filenames only while serializing.
namespace blot_check_diagnostic_location;
import support.error;
struct Location { filename: const u8[:], start: u32, end: u32, offset_encoding: const u8[:] = "utf8_bytes" }
fn init(filename: const u8[:], span: blot_check_core::Span) -> Location { return Location { filename, span.start, span.end }; }
struct Origin { kind: blot_check_staging_origins::Kind, filename: const u8[:], start: u32, end: u32, offset_encoding: const u8[:] = "utf8_bytes" }
fn init(kind: blot_check_staging_origins::Kind, filename: const u8[:], span: blot_check_core::Span) -> Origin { return Origin { kind, filename, span.start, span.end }; }
struct OwnedOrigins { entries: Origin[:] = [] }
fn init(trace: const blot_check_staging_origins::Trace&, paths: const u8[:][:],
        entries: Origin[>..<]&, text: u8[>..<]&) -> OwnedOrigins, blot_error::Error {
    let entry_start = entries.len; let text_start = text.len;
    for origin in trace.items() {
        let unit = origin.location.unit; if unit == 0 || unit > paths.len { entries.pop_n(entries.len - entry_start); text.pop_n(text.len - text_start); return OwnedOrigins {}, blot_error::Error.invalid_unit; }
        let start = text.len; text.append(paths[unit - 1]);
        entries.push(init(origin.kind, text[start..], origin.location.span));
    }
    return OwnedOrigins { entries[entry_start..] }, blot_error::Error.none;
}
fn deinit(self: OwnedOrigins&) { self.entries = []; }
struct WithOrigins<P> { payload: P, origins: const Origin[:] }
fn jsonStringify<P>(self: WithOrigins<P>, stream) -> blot_error::Error {
    let opened = stream.beginObject(); if opened != blot_error::Error.none { return opened; }
    const for <N, A> in fields<P> {
        let field = stream.objectField(N); if field != blot_error::Error.none { return field; }
        let written = stream.write(self.payload.A); if written != blot_error::Error.none { return written; }
    }
    if self.origins.len != 0 {
        let field = stream.objectField("origins"); if field != blot_error::Error.none { return field; }
        let written = stream.write(self.origins); if written != blot_error::Error.none { return written; }
    }
    return stream.endObject();
}
