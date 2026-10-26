import work;
import scalar_scheduled;
import scalar_pipeline_work_test;
import os;

fn main() {
    let source = "let less: U32 -> Bool = fn x => return do:\n  break x < 7\n";
    var legacy = work::Meter {};
    let baseline = run(source, legacy);
    assert(baseline.status == 0 && baseline.bytes.len > 0);
    var job = work::ScheduledWork {};
    let built = scalar_scheduled::run(source, job);
    assert(built.status == 0 && built.bytes[..] == baseline.bytes[..]);
    assert(work::schedule_complete(job) && job.phases[3] == 3);
    assert(job.meter.semantic == legacy.semantic && job.meter.phase_semantic == legacy.phase_semantic);
    assert(job.meter.target_visits == legacy.target_visits && job.meter.proof_edges == 0);
    let required = job.meter.semantic;
    var exact = work::ScheduledWork {};
    exact.meter.semantic = 1048576 - required;
    assert(scalar_scheduled::run(source, exact).status == 0 && exact.meter.semantic == 1048576);
    for available in required {
        var limited = work::ScheduledWork {};
        limited.meter.semantic = 1048576 - available;
        let blocked = scalar_scheduled::run(source, limited);
        assert(blocked.status == 2 && blocked.bytes.len == 0);
        assert(limited.failed && limited.meter.gate == 9 && limited.meter.semantic == 1048576);
        assert(scalar_scheduled::run(source, limited).status == 4);
    }
    var invalid = work::ScheduledWork {};
    let bad = scalar_scheduled::run("let f: U32 -> U32 = fn x => return x + 1", invalid);
    assert(bad.status == 1 && bad.source_status != 0 && bad.bytes.len == 0 && invalid.failed);
    var wrong = work::ScheduledWork {};
    assert(work::schedule_begin(wrong, 1));
    assert(work::charge(wrong.meter, 2, 1).status == 5);
    assert(!work::schedule_end(wrong, 1) && wrong.failed);
    var gap = work::ScheduledWork {};
    assert(work::schedule_begin(gap, 1) && work::schedule_end(gap, 1));
    assert(work::charge(gap.meter, 1, 1).status == 5);
    assert(!work::schedule_begin(gap, 2) && gap.failed);
    var telemetry = work::ScheduledWork {};
    assert(work::schedule_begin(telemetry, 1));
    assert(work::target_visit(telemetry.meter).status == 5);
    assert(!work::schedule_end(telemetry, 1) && telemetry.failed);
    assert(write_file("scalar_scheduled.wasm", built.bytes));
    print("private scheduled scalar pipeline laws passed");
}
