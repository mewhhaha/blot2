// Sparse provenance supplies diagnostics and grants no code authority.
namespace blot_check_staging_origins;
import support.structural;
import support.error;
import support.option;
struct Source { unit: u32, node: blot_check_core::Id }
struct Location { unit: u32, span: blot_check_core::Span }
struct Record { value: u32, generator: Source }
enum Kind { quote, generator, splice, invocation }
struct Origin { kind: Kind, location: Location }
struct Trace { entries: Origin[8] = [Origin { Kind.quote, Location { 0, blot_check_core::Span { 0, 0 , ..} , ..} , ..}; 8], len: u8 = 0 }
fn add(self: Trace&, kind: Kind, location: Location) -> blot_error::Error {
    for item in items(self) { if item.kind == kind && item.location == location { return blot_error::Error.none; } }
    if self.len == self.entries.len { return blot_error::Error.limit; }
    self.entries[self.len] = Origin { kind, location , ..}; self.len += 1; return blot_error::Error.none;
}
fn items(self: const Trace&) -> const Origin[:] { return self.entries[..self.len]; }
fn generator(records: const Record[:], value: u32) -> blot_support::Option<Source> {
    var start: i64 = 0; var end = records.len;
    while start < end {
        let middle = start + (end - start) / 2; let record = records[middle];
        if record.value == value { return blot_support::Option<Source> { true, record.generator , ..}; }
        if record.value < value { start = middle + 1; } else { end = middle; }
    }
    return blot_support::Option<Source> { false, default<Source>() , ..};
}
fn module(units: const blot_check_core::Module[:], unit: u32) -> const blot_check_core::Module? {
    for &owner, index in units { var identity = owner.unit; if identity == 0 { identity = (index + 1) as u32; } if identity == unit { return owner; } }
    return null;
}
fn sourceLocation(units: const blot_check_core::Module[:], source: Source) -> blot_support::Option<Location> {
    let owner = module(units, source.unit);
    if !owner { return blot_support::Option<Location> { false, default<Location>() , ..}; }
    if source.node == 0 || source.node >= owner.nodes.len || source.node >= owner.spans.len { return blot_support::Option<Location> { false, default<Location>() , ..}; }
    return blot_support::Option<Location> { true, Location { source.unit, owner.span(source.node) , ..} , ..};
}
fn code(trace: Trace&, units: const blot_check_core::Module[:], metadata, invocation: Source,
         selected_generator: blot_support::Option<Source>, splice: bool) -> blot_error::Error {
    let owner = module(units, metadata.unit); if !owner { return blot_error::Error.invalid_origin; }
    var remaining: i64 = 65536; var quotation: blot_support::Option<Location> = blot_support::Option<Location> { false, default<Location>() , ..};
    for node, index in owner.nodes {
        if remaining == 0 { return blot_error::Error.limit; } remaining -= 1;
        if node.tag != blot_check_core::Tag.staging || node.c != blot_check_typed_staging::opCode(blot_check_typed_staging::Op.quote) { continue; }
        if node.a != metadata.identity || node.ty != metadata.ty { continue; }
        if index >= owner.spans.len { return blot_error::Error.invalid_origin; }
        quotation = blot_support::Option<Location> { true, Location { metadata.unit, owner.span(index as u32) , ..} , ..}; break;
    }
    if !quotation.present { return blot_error::Error.invalid_origin; }
    let first = add(trace, Kind.quote, quotation.value); if first != blot_error::Error.none { return first; }
    if selected_generator.present {
        let location = sourceLocation(units, selected_generator.value); if !location.present { return blot_error::Error.invalid_origin; }
        let added = add(trace, Kind.generator, location.value); if added != blot_error::Error.none { return added; }
    }
    var kind = Kind.invocation; if splice { kind = Kind.splice; }
    let location = sourceLocation(units, invocation); if !location.present { return blot_error::Error.invalid_origin; }
    return add(trace, kind, location.value);
}

fn kindCode(value: Kind) -> u32 {
    match value {
        Kind.quote => { return 0; },
        Kind.generator => { return 1; },
        Kind.splice => { return 2; },
        Kind.invocation => { return 3; },
    }
}
fn kindFromCode(code: u32) -> Kind, blot_error::Error {
    match code {
        0 => { return Kind.quote, blot_error::Error.none; },
        1 => { return Kind.generator, blot_error::Error.none; },
        2 => { return Kind.splice, blot_error::Error.none; },
        3 => { return Kind.invocation, blot_error::Error.none; },
        _ => { return Kind.quote, blot_error::Error.invalid_artifact; },
    }
}
fn blot_structural::equal(left: blot_check_staging_origins::Kind, right: blot_check_staging_origins::Kind) -> bool { return left == right; }
fn blot_structural::hash<S>(sink: S&, value: blot_check_staging_origins::Kind) { blot_structural::hash(sink, blot_check_staging_origins::kindCode(value) as! u8); }




