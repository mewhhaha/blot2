import std;
import os;
import work;
import increment_core;
import increment_parse;
import increment_validate;
import increment_compile;
import increment_target;
fn main() {
    let source = "let f: U32 -> U32 = fn x => do:\n  if x < 4294967295:\n    return x + 1\n  else:\n    return x\n";
    var job = increment_compile::Job {};
    var prepared = increment_compile::prepare(source,job);
    assert(prepared.status == 0 && job.active && job.graph.meter.proof_terms == 3 && job.graph.meter.proof_edges == 3);
    assert(increment_validate::verify(source,prepared.core,job.graph.meter,5).status == 0);
    let before = job.graph.meter.semantic;
    assert(increment_validate::verify(source,prepared.core,job.graph.meter,5).status == 0);
    let once = job.graph.meter.semantic - before;
    assert(increment_validate::verify(source,prepared.core,job.graph.meter,5).status == 0);
    assert(job.graph.meter.semantic - before == 2 * once);
    assert(increment_compile::release(job,7).status == 0 && job.graph.meter.proof_edges == 0 && job.graph.meter.proof_terms == 3);
    assert(increment_compile::release(job,7).status == 4);
    // The malformed prerequisite may only be inspected after its own visit.
    var forged_prior = copy(prepared.core); forged_prior.evidence[1].prior = 99;
    var no_edge_visit = work::Meter { proof_visits: 65531 };
    let stopped = increment_validate::verify(source,forged_prior,no_edge_visit,5);
    assert(stopped.status == 2 && no_edge_visit.proof_visits == 65536);
    var one_more = work::Meter { proof_visits: 65530 };
    let invalid = increment_validate::verify(source,forged_prior,one_more,5);
    assert(invalid.status == 1 && one_more.proof_visits == 65536);
    for n in 3 { for field in 4 {
        var altered = copy(prepared.core);
        if field == 0 { altered.terms[n].kind += 1; }
        else if field == 1 { altered.terms[n].value += 1; }
        else if field == 2 { altered.terms[n].version += 1; }
        else { altered.terms[n].literal += 1; }
        var m = work::Meter {};
        assert(increment_validate::verify(source,altered,m,5).status == 1);
    } }
    for n in 2 { for field in 7 {
        var altered = copy(prepared.core);
        if field == 0 { altered.evidence[n].rule += 1; }
        else if field == 1 { altered.evidence[n].scope += 1; }
        else if field == 2 { altered.evidence[n].left += 1; }
        else if field == 3 { altered.evidence[n].right += 1; }
        else if field == 4 { altered.evidence[n].prior += 1; }
        else if field == 5 { altered.evidence[n].result += 1; }
        else { altered.evidence[n].result_version += 1; }
        var m = work::Meter {};
        assert(increment_validate::verify(source,altered,m,5).status == 1);
    } }
    for n in 7 {
        var altered = copy(prepared.core);
        if n == 0 { altered.schema = 2; } else if n == 1 { altered.parameter_version = 2; }
        else if n == 2 { altered.result_version = 1; } else if n == 3 { altered.true_scope = 3; }
        else if n == 4 { altered.false_scope = 2; } else if n == 5 { altered.limit.end = 9223372036854775807; }
        else { altered.add_use.start = -1; }
        var m = work::Meter {};
        assert(increment_validate::verify(source,altered,m,5).status == 1);
    }
    for bad in ["let f: U32 -> U32 = fn x => do:\n  if x <= 4294967295:\n    return x + 1\n  else:\n    return x\n",
      "let f: U32 -> U32 = fn x => do:\n  if x < 4294967295:\n    return x + 2\n  else:\n    return x\n",
      "let f: U32 -> U32 = fn x => do:\n  if x < 4294967295:\n    return x\n  else:\n    return x + 1\n",
      "let f: U32 -> U32 = fn x => do:\n  if y < 4294967295:\n    return x + 1\n  else:\n    return x\n",
      "let f: U32 -> U32 = fn x => do:\n  if x < 4294967295:\n    return y + 1\n  else:\n    return x\n"] {
        var bad_job = increment_compile::Job {};
        let failed = increment_compile::run(bad,bad_job);
        assert(failed.status == 1 && failed.bytes.len == 0 && bad_job.graph.failed);
    }
    var made = increment_compile::Job {};
    let output = increment_compile::run(source,made);
    assert(output.status == 0 && output.bytes.len == 52 && increment_target::verify(output.bytes));
    assert(made.graph.meter.proof_terms == 3 && made.graph.meter.proof_edges == 0 && made.graph.meter.proof_peak_edges == 3);
    assert(write_file("increment_fixture.wasm",output.bytes));
    for i in output.bytes.len {
        var altered: u8[>..] = []; altered.append(output.bytes); altered[i] ^= 1;
        assert(!increment_target::verify(altered) && !increment_target::verify(output.bytes[..i]));
    }
    var long: u8[>..] = []; long.append(output.bytes); long.push(0); assert(!increment_target::verify(long));
    let events = made.graph.meter.semantic;
    var exact_semantic = increment_compile::Job {};
    exact_semantic.graph.meter.semantic = 1048576 - events;
    let exact_output = increment_compile::run(source,exact_semantic);
    assert(exact_output.status == 0 && exact_output.bytes == output.bytes && exact_semantic.graph.meter.semantic == 1048576);
    for i in 0..events {
        var limited = increment_compile::Job {}; limited.graph.meter.semantic = 1048577 - events + i;
        let fail = increment_compile::run(source,limited);
        assert(fail.status == 3 && fail.receipt.quantity == 1 && fail.bytes.len == 0 && limited.graph.failed);
    }
    let proofs = made.graph.meter.proof_visits;
    var exact_proof = increment_compile::Job {};
    exact_proof.graph.meter.proof_visits = 65536 - proofs;
    let exact_proof_output = increment_compile::run(source,exact_proof);
    assert(exact_proof_output.status == 0 && exact_proof_output.bytes == output.bytes && exact_proof.graph.meter.proof_visits == 65536);
    for i in 0..proofs {
        var limited = increment_compile::Job {}; limited.graph.meter.proof_visits = 65537 - proofs + i;
        let fail = increment_compile::run(source,limited);
        assert(fail.status == 2 && fail.receipt.quantity == 2 && fail.bytes.len == 0 && limited.graph.failed);
    }
    var edge = increment_compile::Job {}; edge.graph.meter.proof_edges = 16382;
    let edge_fail = increment_compile::run(source,edge); assert(edge_fail.status == 2 && edge_fail.receipt.quantity == 4 && edge_fail.bytes.len == 0);
    var terms = increment_compile::Job {}; terms.graph.meter.proof_terms = 4094;
    let term_fail = increment_compile::run(source,terms); assert(term_fail.status == 2 && term_fail.receipt.quantity == 3 && term_fail.bytes.len == 0);
    var simultaneous = increment_compile::Job {}; simultaneous.graph.meter.proof_visits = 65536; simultaneous.graph.meter.semantic = 1048576;
    let sim = increment_compile::run(source,simultaneous); assert(sim.status == 3 && sim.receipt.quantity == 1 && sim.bytes.len == 0);
    print("guarded successor source/Core/proof passed");
}
