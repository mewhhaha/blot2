namespace squid_reuse_purity_diagnostics;
import check.types;
import parse.symbols;
import support.error;
import support.option;

type Error = squid_error::Error;
struct Witness {
    identity: squid_check_types::NominalIdentity,
    family: u32 = 0, member: u32 = 0, compound: bool = false,
    foreign: bool = false, specialized: bool = false, origin_unavailable: bool = false,
    operation_name: squid_support::Option<const u8[:]>,
}
fn clone(witness: Witness, owner: u8[>..<]&) -> Witness {
    var result = witness;
    if witness.operation_name.present {
        let start = owner.len; owner.append(witness.operation_name.value);
        let copied: const u8[:] = owner[start..owner.len]; result.operation_name = squid_support::some<const u8[:]>(copied);
    }
    return result;
}
fn format<O>(pool: squid_parse_symbols::Pool&, module_name: const u8[:], witness: Witness, out: O&) -> Error {
    if !witness.operation_name.present {
        if witness.origin_unavailable { return squid_error::Error.operation_purity_origin_required; }
        if witness.specialized { return squid_error::Error.specialized_purity_display_required; }
        if !witness.foreign && witness.family == 0 { return squid_error::Error.operation_purity_origin_required; }
    }
    out.append("pure evaluation cannot perform ");
    if witness.operation_name.present { out.append(witness.operation_name.value); }
    else if witness.foreign { out.append("squid:compiler::Foreign"); }
    else {
        out.append(module_name); out.append("::"); out.append(squid_parse_symbols::get(pool, witness.family));
        if witness.compound { out.push('.'); out.append(squid_parse_symbols::get(pool, witness.member)); }
    }
    out.append("; sequence an operation with use inside a provider scope");
    return squid_error::Error.none;
}
