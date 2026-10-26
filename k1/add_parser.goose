// Private addition-aware wrapper around the isolated scalar syntax parser.
// It is not wired into public source admission or the v2 parser.
namespace add_parser;
import add_frontend;
import add_source;
import parser;
import scalar_core;
import syntax;

// Verify the actual original source/Core first. Independently validate every
// syntax node and lexical target against a one-byte bitand projection; then
// retain the original '+' byte in the caller's owned Arena. No source span
// moves and the old parser continues to reject addition directly.
fn verify(arena: syntax::Arena&, core: scalar_core::ScalarCore) -> bool {
    if add_source::validate(arena.source, core) != 0 || syntax::validate(arena) != 0 { return false; }
    var projected: u8[>..] = [];
    projected.append(arena.source);
    projected[core.operator_start] = '&';
    var mapped, ok = syntax::own(projected, arena.nodes);
    return ok && parser::verify(mapped);
}
fn parse(source: u8[:]) -> syntax::Arena, i64 {
    let candidate = add_frontend::parse(source);
    if candidate.status != 0 { return syntax::Arena {}, candidate.status; }
    var projected: u8[>..] = [];
    projected.append(source);
    projected[candidate.core.operator_start] = '&';
    var mapped, status = parser::parse(projected);
    if status != 0 { return syntax::Arena {}, 11; }
    var arena, ok = syntax::own(source, mapped.nodes);
    if !ok || !verify(arena, candidate.core) { return syntax::Arena {}, 11; }
    return arena, 0;
}
