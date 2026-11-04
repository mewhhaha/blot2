// Revision sources own their bytes. Missing entries read the filesystem;
// a present entry without contents hides the file for this revision.
namespace blot_reuse_source_overlays;
import std;
import dictionary;
import support.error;
import support.native;
import support.option;

type Error = blot_error::Error;
struct Source { path: const u8[:], contents: blot_support::Option<const u8[:]> }
struct Set {
    files: dictionary<const u8[:], blot_support::Option<const u8[:]>>&,
    owned: u8[>..<]&,
}
fn utf8_valid(text: const u8[:]) -> bool {
    var at: i64 = 0;
    while at < text.len {
        let first = text[at]; at++;
        if first < 128 { continue; }
        var extra: i64 = 0;
        var value: u32 = 0;
        var minimum: u32 = 0;
        if first >= 194 && first <= 223 { extra = 1; value = first as u32 & 31; minimum = 128; }
        else if first >= 224 && first <= 239 { extra = 2; value = first as u32 & 15; minimum = 2048; }
        else if first >= 240 && first <= 244 { extra = 3; value = first as u32 & 7; minimum = 65536; }
        else { return false; }
        if extra > text.len - at { return false; }
        for index in extra {
            let byte = text[at + index]; if byte & 192 != 128 { return false; }
            value = value << 6 | byte as u32 & 63;
        }
        at += extra;
        if value < minimum || value > 1114111 || value >= 55296 && value <= 57343 { return false; }
    }
    return true;
}
fn normalize(raw: const u8[:], out: u8[>..<]&) {
    out.clear(); out.push('/');
    var components: i64[>..<] = [];
    var at: i64 = 0;
    while at < raw.len {
        while at < raw.len && raw[at] == '/' { at++; }
        let start = at;
        while at < raw.len && raw[at] != '/' { at++; }
        let count = at - start;
        if count == 0 || count == 1 && raw[start] == '.' { continue; }
        if count == 2 && raw[start] == '.' && raw[start + 1] == '.' {
            if components.len != 0 { let previous = components.pop(); out.resize(previous, 0); }
            continue;
        }
        let previous = out.len;
        if out.len > 1 { out.push('/'); }
        components.push(previous); out.append(raw[start..at]);
    }
}
fn canonicalPath(raw: const u8[:], out: u8[>..<]&) -> Error {
    if raw.len == 0 || raw[0] != '/' || !utf8_valid(raw) { return Error.invalid_source_path; }
    for byte in raw { if byte == 0 { return Error.invalid_source_path; } }
    var normalized: u8[>..<] = []; normalize(raw, normalized);
    var end = normalized.len;
    var prefix: u8[>..<] = [];
    var resolved: u8[>..<] = []; resolved.resize(4096, 0);
    loop {
        prefix.clear(); prefix.append(normalized[..end]); prefix.push(0);
        let count = blot_native::real_path(prefix[0], resolved[0], resolved.len as u64);
        if count >= 0 {
            if count >= resolved.len { resolved.resize(count + 1, 0); continue; }
            var joined: u8[>..<] = []; joined.append(resolved[..count]);
            var suffix = end;
            while suffix < normalized.len && normalized[suffix] == '/' { suffix++; }
            if suffix < normalized.len {
                if joined.len == 0 || joined[joined.len - 1] != '/' { joined.push('/'); }
                joined.append(normalized[suffix..]);
            }
            normalize(joined, out); return Error.none;
        }
        if count != -2 { return Error.io; }
        if end <= 1 { return Error.io; }
        var parent = end;
        while parent > 1 && normalized[parent - 1] != '/' { parent--; }
        if parent > 1 { parent--; }
        if parent == end { return Error.io; }
        end = parent;
    }
}
fn init<O>(files: dictionary<const u8[:], blot_support::Option<const u8[:]>>&,
        owned: u8[>..<]&, sources: const Source[:], options: O) -> Set, Error {
    let result = Set { files, owned };
    files.clear(); owned.clear();
    if sources.len > options.max_files { return result, Error.source_limit; }
    var total: i64 = 0;
    for source in sources {
        if source.contents.present {
            let count = source.contents.value.len;
            var remaining: i64 = 0;
            if total < options.max_total_source_bytes { remaining = options.max_total_source_bytes - total; }
            if count > options.max_source_bytes || count > remaining {
                files.clear(); owned.clear(); return result, Error.source_limit;
            }
            total += count;
        }
        var canonical: u8[>..<] = [];
        let error = canonicalPath(source.path, canonical);
        if error != Error.none { files.clear(); owned.clear(); return result, error; }
        if files.contains(canonical) { files.clear(); owned.clear(); return result, Error.duplicate_source_path; }
        let name_start = owned.len; owned.append(canonical); let name_end = owned.len;
        var contents = blot_support::none<const u8[:]>();
        if source.contents.present {
            let content_start = owned.len; owned.append(source.contents.value);
            contents = blot_support::some(owned[content_start..owned.len]);
        }
        files.insert(owned[name_start..name_end], contents);
    }
    return result, Error.none;
}
fn deinit(set: Set&) { set.files.clear(); set.owned.clear(); }
