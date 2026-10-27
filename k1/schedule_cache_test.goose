import session_retained;
import scalar_scheduled;
import catalog;
fn main() {
    let source = "let f: U32 -> U32 = fn x => return x\n";
    var obs = session_retained::Observations {};
    var session = session_retained::Session {};
    let fresh = session_retained::compile(session, source, obs, catalog::semantic_policy(), "", 0);
    assert(fresh.status == 0 && fresh.retained && !fresh.reused && fresh.semantic == 827);
    let warm = session_retained::compile(session, source, obs, catalog::semantic_policy(), "", 0);
    assert(warm.status == 0 && warm.reused && warm.semantic == 827 && session.fresh_runs == 1);
    let i = session.active;
    session.entries[i].visit_schedule = 1;
    session.entries[i].receipt.meter.semantic -= 12;
    session.entries[i].receipt.meter.phase_semantic[1] -= 12;
    // Numeric totals alone still look structurally valid; schedule identity
    // must prevent reuse of the older, cheaper required-work result.
    assert(session_retained::receipt_valid(session.entries[i].receipt));
    assert(!session_retained::entry_valid(session.entries[i]));
    let rebuilt = session_retained::compile(session, source, obs, catalog::semantic_policy(), "", 0);
    assert(rebuilt.status == 0 && !rebuilt.reused && rebuilt.retained && rebuilt.semantic == 827 && session.fresh_runs == 2);
    assert(session.entries[session.active].visit_schedule == scalar_scheduled::private_visit_schedule());
    session.entries[session.active].visit_schedule = 0;
    let missing = session_retained::compile(session, source, obs, catalog::semantic_policy(), "", 0);
    assert(missing.status == 0 && !missing.reused && missing.semantic == 827 && session.fresh_runs == 3);
    session.entries[session.active].visit_schedule = 4294967295;
    let unknown = session_retained::compile(session, source, obs, catalog::semantic_policy(), "", 0);
    assert(unknown.status == 0 && !unknown.reused && unknown.semantic == 827 && session.fresh_runs == 4);
    print("private scalar visit schedule cache invalidation passed");
}
