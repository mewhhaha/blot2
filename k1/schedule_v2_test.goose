import syntax;
import scalar_scheduled;
import work;
fn main() {
    let source = "x";
    var nodes = [syntax::Node { tag: 0, start: 0, end: 1 }, syntax::Node { tag: 1, start: 0, end: 1, parent: 1 }];
    var arena, owned = syntax::own(source, nodes);
    assert(owned);
    // Compatibility prototype continues to use its historical 3-visit budget.
    assert(syntax::validate_budget(arena, 3) == 0);
    assert(syntax::validate_budget(arena, 2) == 2);
    var full = work::Meter {};
    assert(syntax::validate_with_work(arena, full, 2) == 0 && full.semantic == 4);
    var exact = work::Meter { semantic: 1048572 };
    assert(syntax::validate_with_work(arena, exact, 2) == 0 && exact.semantic == 1048576);
    var one_less = work::Meter { semantic: 1048573 };
    assert(syntax::validate_with_work(arena, one_less, 2) == 3 && one_less.semantic == 1048576);
    let scalar = "let f: U32 -> U32 = fn x => return x\n";
    var ordinary = work::ScheduledWork {};
    let compiled = scalar_scheduled::run(scalar, ordinary);
    assert(compiled.status == 0 && compiled.bytes.len != 0);
    // Original private schedule consumes 815; the two independent syntax
    // passes each follow six parent edges, adding 12 real node revisits.
    assert(ordinary.meter.semantic == 827);
    var previous_budget = work::ScheduledWork {};
    previous_budget.meter.semantic = 1048576 - 815;
    let denied = scalar_scheduled::run(scalar, previous_budget);
    assert(denied.status == 2 && denied.bytes.len == 0 && previous_budget.failed);
    var at_limit = work::ScheduledWork {};
    at_limit.meter.semantic = 1048576 - 827;
    assert(scalar_scheduled::run(scalar, at_limit).status == 0 && at_limit.meter.semantic == 1048576);
    var near = work::ScheduledWork {};
    near.meter.semantic = 1048576 - 826;
    assert(scalar_scheduled::run(scalar, near).status == 2 && near.failed);
    var padded: u8[>..] = []; padded.append(scalar);
    for i in 1000 { padded.append("\n// a comment\n"); }
    var trailing = work::ScheduledWork {};
    let good = scalar_scheduled::run(padded, trailing);
    assert(good.status == 0 && trailing.meter.semantic == ordinary.meter.semantic);
    print("private work schedule v2 parent-node boundary tests passed");
}
