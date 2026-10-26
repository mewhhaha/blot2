import std;
import proof_scopes;
import work;
fn main() {
    let none = proof_scopes::Handle {};
    // Freeze the isolated fixture schedule for an empty scope with one fact:
    // scope creation; scope visit, fact creation and ownership link;
    // then scope visit, fact visit and ownership link on discharge.
    var schedule = proof_scopes::Job {};
    let s = proof_scopes::open(schedule, none);
    assert(schedule.meter.proof_visits == 1);
    let sf = proof_scopes::add(schedule, s.handle, none, none);
    assert(sf.status == 0 && schedule.meter.proof_visits == 4);
    assert(proof_scopes::close(schedule, s.handle).status == 0 && schedule.meter.proof_visits == 7);

    var job = proof_scopes::Job {};
    let root = proof_scopes::open(job, none); assert(root.status == 0);
    let a = proof_scopes::add(job, root.handle, none, none); assert(a.status == 0);
    let b = proof_scopes::add(job, root.handle, none, none); assert(b.status == 0);
    let c = proof_scopes::add(job, root.handle, a.handle, b.handle); assert(c.status == 0);
    assert(job.meter.proof_edges == 5 && job.entries[a.handle.index - 1].fact.dependents == 1);
    let child = proof_scopes::open(job, root.handle); assert(child.status == 0);
    let d = proof_scopes::add(job, child.handle, c.handle, a.handle); assert(d.status == 0);
    assert(job.meter.proof_edges == 8 && job.meter.proof_peak_edges == 8);
    assert(proof_scopes::close(job, child.handle).status == 0);
    assert(job.meter.proof_edges == 5 && job.entries[a.handle.index - 1].fact.dependents == 1);
    assert(proof_scopes::close(job, root.handle).status == 0);
    assert(job.meter.proof_edges == 0 && job.meter.proof_peak_edges == 8 && !job.failed);
    let new_root = proof_scopes::open(job, none); assert(new_root.status == 0);
    assert(new_root.handle.index == root.handle.index && new_root.handle.generation != root.handle.generation);
    let new_fact = proof_scopes::add(job, new_root.handle, none, none); assert(new_fact.status == 0);
    assert(new_fact.handle.index == a.handle.index && new_fact.handle.generation != a.handle.generation);
    assert(proof_scopes::add(job, new_root.handle, a.handle, none).status == 1);
    assert(job.failed && proof_scopes::close(job, new_root.handle).status == 1);
    let failed_length = job.entries.len;
    assert(proof_scopes::allocate(job).status == 1 && job.entries.len == failed_length);
    assert(proof_scopes::ancestor(job, new_root.handle, new_root.handle).status == 1);

    var live_child = proof_scopes::Job {};
    let parent = proof_scopes::open(live_child, none);
    let nested = proof_scopes::open(live_child, parent.handle);
    assert(nested.status == 0 && proof_scopes::close(live_child, parent.handle).status == 1 && live_child.failed);

    var unrelated = proof_scopes::Job {};
    let x = proof_scopes::open(unrelated, none);
    let y = proof_scopes::open(unrelated, none);
    let xf = proof_scopes::add(unrelated, x.handle, none, none);
    assert(proof_scopes::add(unrelated, y.handle, xf.handle, none).status == 1 && unrelated.failed);

    var exact = proof_scopes::Job {};
    exact.meter.proof_edges = 16383;
    let es = proof_scopes::open(exact, none);
    let ef = proof_scopes::add(exact, es.handle, none, none);
    assert(ef.status == 0 && exact.meter.proof_edges == 16384);
    assert(proof_scopes::close(exact, es.handle).status == 0 && exact.meter.proof_edges == 16383);
    assert(proof_scopes::add(exact, es.handle, none, none).status == 1 && exact.failed);

    var partial = proof_scopes::Job {};
    partial.meter.proof_edges = 16382;
    let ps = proof_scopes::open(partial, none);
    let pf = proof_scopes::add(partial, ps.handle, none, none); assert(pf.status == 0);
    let rejected = proof_scopes::add(partial, ps.handle, pf.handle, none);
    assert(rejected.status == 2 && rejected.receipt.status == 2 && rejected.receipt.quantity == 4);
    assert(partial.failed && partial.meter.proof_edges == 16384 && partial.entries.len == 2);
    assert(proof_scopes::close(partial, ps.handle).status == 1);

    var interrupted = proof_scopes::Job {};
    let iscope = proof_scopes::open(interrupted, none);
    let ia = proof_scopes::add(interrupted, iscope.handle, none, none);
    let ib = proof_scopes::add(interrupted, iscope.handle, ia.handle, none);
    assert(ib.status == 0);
    interrupted.meter.semantic = 1048574;
    let stopped = proof_scopes::close(interrupted, iscope.handle);
    assert(stopped.status == 2 && stopped.receipt.status == 1 && interrupted.failed);
    assert(proof_scopes::close(interrupted, iscope.handle).status == 1);

    var duplicate = proof_scopes::Job {};
    let ds = proof_scopes::open(duplicate, none);
    let da = proof_scopes::add(duplicate, ds.handle, none, none);
    assert(proof_scopes::add(duplicate, ds.handle, da.handle, da.handle).status == 1 && duplicate.failed);

    var simultaneous = proof_scopes::Job {};
    simultaneous.meter.semantic = 1048576;
    simultaneous.meter.proof_edges = 16384;
    let limit = proof_scopes::open(simultaneous, none);
    assert(limit.status == 2 && limit.receipt.status == 1 && limit.receipt.quantity == 1 && simultaneous.failed);

    var proof_limit = proof_scopes::Job {};
    proof_limit.meter.proof_visits = 65536;
    let pl = proof_scopes::open(proof_limit, none);
    assert(pl.status == 2 && pl.receipt.status == 2 && pl.receipt.quantity == 2 && proof_limit.failed);
    print("proof scopes passed");
}
