import frontend;
import parser;
import syntax;
import work;

fn main() {
    let source = "let f: U32 -> U32 = fn x => do:\n  return do:\n    break x & 255\n";
    var meter = work::Meter {};
    var arena, status = parser::parse_with_work(source, meter);
    assert(status == 0 && arena.source[..] == source && arena.nodes.len > 0);
    let total = meter.semantic;
    assert(total > 0 && meter.phase_semantic[0] > 0 && meter.phase_semantic[1] > 0);
    assert(meter.phase_semantic[4] == 0); // syntax verification is phase 2
    assert(meter.core_operations == 0 && meter.core_blocks == 0); // scratch Core is not published
    assert(meter.source_byte_reads == 0); // telemetry is not implemented here
    assert(syntax::validate(arena) == 0 && parser::verify(arena));

    var again = work::Meter {};
    assert(parser::verify_with_work(arena, again) == 0);
    let check_visits = again.semantic;
    assert(check_visits > 0);
    assert(parser::verify_with_work(arena, again) == 0 && again.semantic == check_visits * 2);

    var exact = work::Meter { semantic: 1048576 - total };
    var exact_arena, exact_status = parser::parse_with_work(source, exact);
    assert(exact_status == 0 && exact.semantic == 1048576 && exact_arena.nodes.len == arena.nodes.len);
    var short = work::Meter { semantic: 1048577 - total };
    var missing, missing_status = parser::parse_with_work(source, short);
    assert(missing_status == 12 && short.semantic == 1048576 && missing.nodes.len == 0 && missing.source.len == 0);

    // Every event boundary in the parse/owned-syntax/revalidation path must
    // return the limit, even when exhaustion occurs while fetching a name or
    // operator token. No partially built Arena may escape.
    for remaining in total {
        var bounded = work::Meter { semantic: 1048576 - remaining };
        var incomplete, limited = parser::parse_with_work(source, bounded);
        assert(limited == 12 && bounded.semantic == 1048576);
        assert(incomplete.nodes.len == 0 && incomplete.source.len == 0);
    }

    var exact_validation = work::Meter { semantic: 1048576 - check_visits };
    assert(parser::verify_with_work(arena, exact_validation) == 0 && exact_validation.semantic == 1048576);
    var short_validation = work::Meter { semantic: 1048577 - check_visits };
    assert(parser::verify_with_work(arena, short_validation) == 3 && short_validation.semantic == 1048576);
    var invalid_phase = work::Meter {};
    assert(syntax::validate_with_work(arena, invalid_phase, 0) == 4 && invalid_phase.semantic == 0);

    var broken = arena;
    broken.nodes[4].target = 0;
    var bad_work = work::Meter {};
    assert(parser::verify_with_work(broken, bad_work) == 1 && bad_work.semantic > 0);

    // Legacy local-budget validation keeps its historical malformed-input
    // precedence, while opt-in metering precharges a represented parent edge.
    var bad_parent = arena;
    bad_parent.nodes[1].parent = 0;
    assert(syntax::validate_budget(bad_parent, 2) == 1);
    var edge_short = work::Meter { semantic: 1048574 };
    assert(syntax::validate_with_work(bad_parent, edge_short, 2) == 3 && edge_short.semantic == 1048576);
    var edge_exact = work::Meter { semantic: 1048573 };
    assert(syntax::validate_with_work(bad_parent, edge_exact, 2) == 1 && edge_exact.semantic == 1048576);

    // Leading trivia does not become semantic AST records. Raw byte reads
    // are bounded independently and deliberately not represented as visits.
    let single = "let f: U32 -> U32 = fn x => return x\n";
    var bare = work::Meter {};
    var simple, simple_status = parser::parse_with_work(single, bare);
    assert(simple_status == 0 && simple.nodes.len > 0);
    var padded: u8[>..] = [];
    for i in 1048577 { padded.push('\n'); }
    padded.append(single);
    var whitespace = work::Meter {};
    var padded_tree, padded_status = parser::parse_with_work(padded, whitespace);
    assert(padded_status == 0 && padded_tree.nodes.len == simple.nodes.len && whitespace.semantic == bare.semantic);
    print("shared parser and syntax work laws passed");
}
