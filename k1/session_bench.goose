// Private retained scalar benchmark target. This compares only fresh private
// Session compilation with exact same-process hits; it is not a K1/legacy
// compiler or public project benchmark. The Python harness verifies source and
// Wasm hashes, execution and every sample's counters before recording timing.
import os;
import std;
import catalog;
import session_retained;

fn main() {
    let argv = args();
    if argv.len != 2 || (argv[1] != "fresh" && argv[1] != "warm" && argv[1] != "probe" && argv[1] != "verify") { exit(2); }
    let source = "let identity: U32 -> U32 = fn x => return x\n";
    let policy = catalog::semantic_policy();
    var obs = session_retained::Observations { count: 1 };
    obs.values[0] = session_retained::Observation { kind: 8, key_len: 6, found: true, value_len: policy.len as u32 };
    for b, i in "policy" { obs.values[0].key[i] = b; }
    for b, i in policy { obs.values[0].value[i] = b; }
    var warm_session = session_retained::Session {};
    let initial = session_retained::compile(warm_session, source, obs, policy, "", 0);
    if initial.status != 0 || !initial.retained || initial.reused { exit(3); }
    let baseline = copy(initial.bytes);
    if !write_file("session_bench_source.blot", source) || !write_file("session_bench.wasm", baseline) { exit(4); }
    if argv[1] == "probe" { print("{\"mode\":\"probe\"}"); return; }
    if argv[1] == "verify" {
        let warm = session_retained::compile(warm_session, source, obs, policy, "", 0);
        var fresh_session = session_retained::Session {};
        let fresh = session_retained::compile(fresh_session, source, obs, policy, "", 0);
        if warm.status != 0 || fresh.status != 0 || !warm.reused || fresh.reused ||
           !warm.retained || !fresh.retained || warm.bytes[..] != baseline[..] || fresh.bytes[..] != baseline[..] ||
           warm.semantic != fresh.semantic || warm.validation_semantic != fresh.validation_semantic ||
           warm.validation_target_visits != fresh.validation_target_visits || warm_session.fresh_runs != 1 ||
           warm_session.hits != 1 || fresh_session.fresh_runs != 1 || fresh_session.hits != 0 { exit(10); }
        print("{\"mode\":\"verify\"}"); return;
    }
    let count: i64 = 200;
    var fresh_runs: u64 = 0; var hits: u64 = 0;
    let begin = clock_ns();
    if argv[1] == "warm" {
        for i in count {
            let result = session_retained::compile(warm_session, source, obs, policy, "", 0);
            if result.status != 0 || !result.reused || !result.retained || result.bytes[..] != baseline[..] ||
               result.semantic != initial.semantic || result.validation_semantic != initial.validation_semantic ||
               result.validation_target_visits != initial.validation_target_visits { exit(5); }
        }
        fresh_runs = warm_session.fresh_runs; hits = warm_session.hits;
        if fresh_runs != 1 || hits != count { exit(6); }
    } else {
        for i in count {
            var fresh = session_retained::Session {};
            let result = session_retained::compile(fresh, source, obs, policy, "", 0);
            if result.status != 0 || result.reused || !result.retained || result.bytes[..] != baseline[..] ||
               result.semantic != initial.semantic || result.validation_semantic != initial.validation_semantic ||
               result.validation_target_visits != initial.validation_target_visits ||
               fresh.fresh_runs != 1 || fresh.hits != 0 { exit(7); }
            fresh_runs += fresh.fresh_runs; hits += fresh.hits;
        }
        if fresh_runs != count || hits != 0 { exit(8); }
    }
    let elapsed = clock_ns() - begin;
    if elapsed <= 0 { exit(9); }
    var output: u8[>..] = [];
    format(output, "{\"mode\":\"", argv[1], "\",\"iterations\":", count,
        ",\"elapsed_ns\":", elapsed, ",\"fresh_runs\":", fresh_runs,
        ",\"hits\":", hits, ",\"semantic\":", initial.semantic,
        ",\"validation_semantic\":", initial.validation_semantic,
        ",\"validation_target_visits\":", initial.validation_target_visits, "}\n");
    write_stdout(output);
}
