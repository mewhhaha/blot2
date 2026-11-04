namespace blot_backend_runtime_identity;
import support.error;
import support.option;

struct Owner { unit: u32, path: const u8[:] }
struct Name { start: u32 = 0, len: u32 = 0 }
struct View { bytes: const u8[:], symbols: const Name[:], owners: const Name[:] }
fn text(view: View, name: Name) -> blot_support::Option<const u8[:]> {
    if name.start > view.bytes.len || name.len > view.bytes.len - name.start { return blot_support::none<const u8[:]>(); }
    return blot_support::some(view.bytes[name.start..name.start + name.len]);
}
fn symbol(view: View, id: u32) -> blot_support::Option<const u8[:]> {
    if id == 0 || id >= view.symbols.len { return blot_support::none<const u8[:]>(); }
    return text(view, view.symbols[id]);
}
fn owner(view: View, id: u32) -> blot_support::Option<const u8[:]> {
    if id == 0 || id > view.owners.len { return blot_support::none<const u8[:]>(); }
    return text(view, view.owners[id - 1]);
}
struct Metadata { bytes: u8[>..<]&, symbols: Name[>..<]&, owners: Name[>..<]& }
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
fn equalBytes(left: const u8[:], right: const u8[:]) -> bool {
    if left.len != right.len { return false; } for byte, index in left { if byte != right[index] { return false; } } return true;
}
fn capture<P>(bytes: u8[>..<]&, names: Name[>..<]&, locations: Name[>..<]&, pool: P&, owners: const Owner[:], unit_count: i64) -> Metadata, blot_error::Error {
    let metadata = Metadata { bytes: bytes, symbols: names, owners: locations };
    if owners.len != unit_count || unit_count >= 4294967295 || pool.entries.len >= 4294967295 { return metadata, blot_error::Error.invalid_identity; }
    var length = pool.bytes.len; locations.clear(); names.clear(); bytes.clear();
    for index in 0..unit_count { locations.push(Name {}); }
    for item, index in owners {
        if item.unit == 0 || item.unit > unit_count || item.path.len == 0 || !validUtf8(item.path) || locations[item.unit - 1].len != 0 { return metadata, blot_error::Error.invalid_identity; }
        for byte in item.path { if byte == 0 { return metadata, blot_error::Error.invalid_identity; } }
        for previous in owners[..index] { if equalBytes(previous.path, item.path) { return metadata, blot_error::Error.invalid_identity; } }
        if length > 4294967295 || item.path.len > 4294967295 - length { return metadata, blot_error::Error.invalid_identity; }
        locations[item.unit - 1] = Name { start: length as u32, len: item.path.len as u32 }; length += item.path.len;
    }
    names.push(Name {});
    for entry in pool.entries {
        if entry.offset > pool.bytes.len || entry.len > pool.bytes.len - entry.offset { return metadata, blot_error::Error.invalid_identity; }
        names.push(Name { start: entry.offset, len: entry.len });
    }
    if length > 4294967295 { return metadata, blot_error::Error.invalid_identity; }
    bytes.append(pool.bytes[..]);
    for index in bytes.len..length { bytes.push(0); }
    for item in owners {
        let location = locations[item.unit - 1];
        for byte, index in item.path { bytes[location.start + index] = byte; }
    }
    return metadata, blot_error::Error.none;
}
fn view(metadata: Metadata&) -> View { View { bytes: metadata.bytes[..], symbols: metadata.symbols[..], owners: metadata.owners[..] } }
fn deinit(metadata: Metadata&) { metadata.bytes.clear(); metadata.symbols.clear(); metadata.owners.clear(); }
