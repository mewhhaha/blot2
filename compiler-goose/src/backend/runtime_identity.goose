namespace blot_backend_runtime_identity;
import support.error;
import support.option;
import dictionary;
import parse.symbols;

struct Owner { unit: u32, path: const u8[:] }
struct Name { start: u32 = 0, len: u32 = 0 }
struct View { bytes: const u8[:], symbols: const Name[:], owners: const Name[:] }
fn text(view: View, name: Name) -> blot_support::Option<const u8[:]> {
    if name.start > view.bytes.len || name.len > view.bytes.len - name.start { return blot_support::none<const u8[:]>(); }
    return blot_support::some<const u8[:]>(view.bytes[name.start..name.start + name.len]);
}
fn symbol(view: View, id: u32) -> blot_support::Option<const u8[:]> {
    if id == 0 || id >= view.symbols.len { return blot_support::none<const u8[:]>(); }
    return text(view, view.symbols[id]);
}
fn owner(view: View, id: u32) -> blot_support::Option<const u8[:]> {
    if id == 0 || id > view.owners.len { return blot_support::none<const u8[:]>(); }
    return text(view, view.owners[id - 1]);
}
struct Metadata {bytes:u8[:] = default<u8[:]>(),symbols:Name[:] = default<Name[:]>(),owners:Name[:] = default<Name[:]>()}
reusable[] var metadata_bytes:u8[>..]=[];
reusable[] var metadata_names:Name[>..]=[];
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
fn capture(pool:const blot_parse_symbols::Pool&,owners:const Owner[:],unit_count:i64)->Metadata,blot_error::Error {
 var metadata=Metadata {..};let error=captureInto(metadata,pool,owners,unit_count);if error!=blot_error::Error.none {metadata.deinit();return Metadata {..},error;}return metadata,blot_error::Error.none;
}
fn captureInto(metadata:Metadata&,pool:const blot_parse_symbols::Pool&,owners:const Owner[:],unit_count:i64)->blot_error::Error {
 if owners.len!=unit_count||unit_count>=0xffffffff||pool.entries.len>=0xffffffff {return blot_error::Error.invalid_identity;}
 var length=pool.bytes.len;var paths:dictionary<const u8[:],bool> =dictionary<const u8[:],bool> {};
 metadata.owners=metadata_names.alloc_slice(unit_count);for &location in metadata.owners {location=Name {..};}
 for item in owners {
  if item.unit==0||item.unit>unit_count||item.path.len==0||!validUtf8(item.path)||metadata.owners[item.unit-1].len!=0 {return blot_error::Error.invalid_identity;}
  for byte in item.path {if byte==0 {return blot_error::Error.invalid_identity;}}
  if paths.contains(item.path)||length>0xffffffff||item.path.len>0xffffffff-length {return blot_error::Error.invalid_identity;}paths.insert(item.path,true);
  metadata.owners[item.unit-1]=Name {length as u32,item.path.len as u32, ..};length+=item.path.len;
 }
 metadata.symbols=metadata_names.alloc_slice(pool.entries.len+1);metadata.symbols[0]=Name {..};
 for entry,index in pool.entries.items {if entry.offset>pool.bytes.len||entry.len>pool.bytes.len-entry.offset {return blot_error::Error.invalid_identity;}metadata.symbols[index+1]=Name {entry.offset,entry.len, ..};}
 if length>0xffffffff {return blot_error::Error.invalid_identity;}metadata.bytes=metadata_bytes.alloc_slice(length);
 for byte,index in pool.bytes.items {metadata.bytes[index]=byte;}for item in owners {let location=metadata.owners[item.unit-1];for byte,index in item.path {metadata.bytes[location.start+index]=byte;}}return blot_error::Error.none;
}
fn view(metadata:const Metadata&)->View {return View {metadata.bytes,metadata.symbols,metadata.owners, ..};}
fn deinit(metadata:Metadata&) {if metadata.bytes.len!=0 {metadata_bytes.free_slice(metadata.bytes);}if metadata.symbols.len!=0 {metadata_names.free_slice(metadata.symbols);}if metadata.owners.len!=0 {metadata_names.free_slice(metadata.owners);}metadata=Metadata {..};}
fn copy(names:View)->Metadata,blot_error::Error {
 let bytes=metadata_bytes.alloc_slice(names.bytes.len);let symbols=metadata_names.alloc_slice(names.symbols.len);let owners=metadata_names.alloc_slice(names.owners.len);
 for byte,index in names.bytes {bytes[index]=byte;}for name,index in names.symbols {symbols[index]=name;}for name,index in names.owners {owners[index]=name;}return Metadata {bytes,symbols,owners, ..},blot_error::Error.none;
}

fn registeredMetadataBytes(bytes:const u8[:])->const u8[:] {
 if bytes.len==0 {return default<const u8[:]>();}
 let owned=metadata_bytes.realloc_slice(bytes,bytes.len);assert(blot_support::same_slice_identity(owned,bytes));
 let start=metadata_bytes.index_of(owned[0]);return metadata_bytes[start..start+owned.len];
}
fn registeredMetadataNames(names:const Name[:])->const Name[:] {
 if names.len==0 {return default<const Name[:]>();}
 let owned=metadata_names.realloc_slice(names,names.len);assert(blot_support::same_slice_identity(owned,names));
 let start=metadata_names.index_of(owned[0]);return metadata_names[start..start+owned.len];
}
fn registeredMetadataView(value:View)->View {
 return View{bytes:registeredMetadataBytes(value.bytes),symbols:registeredMetadataNames(value.symbols),owners:registeredMetadataNames(value.owners)};
}
