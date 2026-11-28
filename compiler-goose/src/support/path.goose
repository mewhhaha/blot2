// Lexical POSIX paths. Protocol identities are normalized Linux paths.
namespace squid_support_path;
import .error;
import .option;
type Error = squid_error::Error;
struct Component { start: i64, len: i64 }
fn equal(left: const u8[:],right: const u8[:]) -> bool { if left.len != right.len { return false; } for byte,index in left { if byte != right[index] { return false; } } return true; }
fn hasDrive(path: const u8[:]) -> bool {
    if path.len < 3 { return false; }
    let c = path[0];
    let alpha = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
    return alpha && path[1] == ':' && (path[2] == '/' || path[2] == '\\');
}
fn isAbsolute(path: const u8[:]) -> bool {
    return (path.len != 0 && path[0] == '/') || hasDrive(path);
}
fn dirnameEnd(path: const u8[:]) -> squid_support::Option<i64> {
    if path.len == 0 { return squid_support::none<i64>(); }
    let drive = hasDrive(path);
    var end = path.len;
    while end > 0 && (path[end - 1] == '/' || (drive && path[end - 1] == '\\')) { end--; }
    if end == 0 { return squid_support::none<i64>(); }
    if drive && end <= 2 { return squid_support::some(3); }
    var slash = end;
    while slash > 0 && path[slash - 1] != '/' && (!drive || path[slash - 1] != '\\') { slash--; }
    if slash == 0 { return squid_support::none<i64>(); }
    let min_end: i64 = if drive { 3 } else { 1 };
    var directory_end = slash;
    while directory_end > min_end && (path[directory_end - 1] == '/' || (drive && path[directory_end - 1] == '\\')) { directory_end--; }
    return squid_support::some(directory_end);
}
fn components(path: const u8[:],out: Component[>..<]&,allow_backslash: bool = false) -> Error {
    var cursor: i64 = 0; while cursor < path.len {
        while cursor < path.len && (path[cursor] == '/' || (allow_backslash && path[cursor] == '\\')) { cursor++; }
        let start = cursor;
        while cursor < path.len && path[cursor] != '/' && (!allow_backslash || path[cursor] != '\\') { if path[cursor] == 0 { return squid_error::Error.invalid_path; } cursor++; }
        if cursor > start { out.push(Component { start,cursor - start , ..}); }
    } return squid_error::Error.none;
}
fn normalize(path: const u8[:],out: u8[>..<]&) -> Error {
    let drive = hasDrive(path);
    let absolute = drive || (path.len != 0 && path[0] == '/');
    let body = if drive { path[3..] } else { path };
    var parts: Component[>..<] = []; let read = components(body,parts,drive); if read != squid_error::Error.none { return read; }
    var selected: Component[>..<] = [];
    for part in parts {
        let text = body[part.start..part.start + part.len]; if equal(text,".") { continue; }
        if equal(text,"..") {
            if selected.len != 0 { let previous = selected[selected.len - 1]; if !equal(body[previous.start..previous.start + previous.len],"..") { selected.resize(selected.len - 1); continue; } }
            if !absolute { selected.push(part); }
        } else { selected.push(part); }
    }
    if drive { out.push(path[0]); out.push(':'); out.push('/'); }
    else if absolute { out.push('/'); }
    for part,index in selected { if index != 0 { out.push('/'); } out.append(body[part.start..part.start + part.len]); }
    if !absolute && selected.len == 0 { out.push('.'); } return squid_error::Error.none;
}
// Inputs share their identity root. No working-directory lookup or filesystem
// access participates in diagnostic spelling.
fn relative(base: const u8[:],target: const u8[:],out: u8[>..<]&) -> Error {
    var from: u8[>..<] = []; var to: u8[>..<] = []; let a = normalize(base,from); if a != squid_error::Error.none { return a; } let b = normalize(target,to); if b != squid_error::Error.none { return b; }
    let from_drive = hasDrive(from); let to_drive = hasDrive(to);
    if from_drive != to_drive { return squid_error::Error.invalid_path; }
    if from_drive && from[0] != to[0] { return squid_error::Error.invalid_path; }
    let from_absolute = isAbsolute(from); let to_absolute = isAbsolute(to); if from_absolute != to_absolute { return squid_error::Error.invalid_path; }
    let from_body = if from_drive { from[3..] } else { from[..] };
    let to_body = if to_drive { to[3..] } else { to[..] };
    var left: Component[>..<] = []; var right: Component[>..<] = []; let c = components(from_body,left); if c != squid_error::Error.none { return c; } let d = components(to_body,right); if d != squid_error::Error.none { return d; }
    if !from_absolute { if left.len == 1 && equal(from_body,".") { left.clear(); } if right.len == 1 && equal(to_body,".") { right.clear(); } }
    var common: i64 = 0; while common < left.len && common < right.len {
        let x = left[common]; let y = right[common]; if !equal(from_body[x.start..x.start + x.len],to_body[y.start..y.start + y.len]) { break; } common++;
    }
    var written = false;
    for index in common..left.len { if written { out.push('/'); } out.append(".."); written = true; }
    for index in common..right.len { if written { out.push('/'); } let component = right[index]; out.append(to_body[component.start..component.start + component.len]); written = true; }
    if !written { out.push('.'); } return squid_error::Error.none;
}
// std.unicode.utf8ValidateSlice: shortest forms only, no surrogates, at most U+10FFFF.
fn validUtf8(bytes: const u8[:]) -> bool {
    var at = 0;
    while at < bytes.len {
        let lead = bytes[at]; at++;
        if lead < 128 { continue; }
        var count = 0; var code: u32 = 0; var minimum: u32 = 0;
        if lead >= 194 && lead <= 223 { count = 1; code = lead & 31; minimum = 128; }
        else if lead >= 224 && lead <= 239 { count = 2; code = lead & 15; minimum = 2048; }
        else if lead >= 240 && lead <= 244 { count = 3; code = lead & 7; minimum = 65536; }
        else { return false; }
        if count > bytes.len - at { return false; }
        for index in 0..count { let byte = bytes[at]; at++; if byte < 128 || byte > 191 { return false; } code = (code << 6) | (byte & 63); }
        if code < minimum || code > 1114111 || (code >= 55296 && code <= 57343) { return false; }
    }
    return true;
}
