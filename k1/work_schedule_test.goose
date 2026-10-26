import work;

fn main() {
    var w = work::ScheduledWork {};
    assert(!work::schedule_complete(w));
    for phase in 1..4 {
        assert(work::schedule_begin(w, phase as u32));
        assert(work::scheduled_charge(w, phase as u32, 1).status == 0);
        assert(work::scheduled_charge(w, phase as u32, 2).status == 0);
        assert(work::schedule_end(w, phase as u32));
    }
    assert(work::schedule_skip_proof(w));
    for phase in 5..8 {
        assert(work::schedule_begin(w, phase as u32));
        assert(work::scheduled_charge(w, phase as u32, 3).status == 0);
        assert(work::schedule_end(w, phase as u32));
    }
    assert(work::schedule_complete(w));
    assert(w.phases[3] == 3 && w.meter.semantic == 9 && w.meter.phase_semantic[3] == 0);
    assert(!work::schedule_begin(w, 7));
    assert(w.failed && !work::schedule_complete(w));

    var with_proof = work::ScheduledWork {};
    for phase in 1..8 {
        assert(work::schedule_begin(with_proof, phase as u32));
        if phase == 4 {
            assert(work::scheduled_charge(with_proof, phase as u32, 20).status == 0);
        } else {
            assert(work::scheduled_charge(with_proof, phase as u32, 1).status == 0);
        }
        assert(work::schedule_end(with_proof, phase as u32));
    }
    assert(work::schedule_complete(with_proof));
    assert(with_proof.phases[3] == 2 && with_proof.meter.proof_visits == 1);

    var reorder = work::ScheduledWork {};
    assert(!work::schedule_begin(reorder, 2) && reorder.failed);
    assert(!work::schedule_begin(reorder, 1));
    assert(reorder.meter.semantic == 0 && reorder.completed == 0);
    var skip = work::ScheduledWork {};
    assert(!work::schedule_skip_proof(skip) && skip.failed);
    var ongoing = work::ScheduledWork {};
    assert(work::schedule_begin(ongoing, 1));
    assert(!work::schedule_begin(ongoing, 2) && ongoing.failed);
    assert(!work::schedule_end(ongoing, 1));
    var wrong = work::ScheduledWork {};
    assert(work::schedule_begin(wrong, 1));
    assert(work::scheduled_charge(wrong, 2, 1).status == 5 && wrong.failed);
    assert(wrong.meter.semantic == 0);
    var bad_end = work::ScheduledWork {};
    assert(work::schedule_begin(bad_end, 1));
    assert(!work::schedule_end(bad_end, 8) && bad_end.failed);
    var invalid = work::ScheduledWork {};
    invalid.phases[2] = 2;
    assert(!work::schedule_begin(invalid, 1) && invalid.failed);
    var forged_skip = work::ScheduledWork {};
    forged_skip.completed = 1;
    forged_skip.phases[0] = 3;
    assert(!work::schedule_begin(forged_skip, 2) && forged_skip.failed);
    var forged_active = work::ScheduledWork {};
    forged_active.active = 2;
    forged_active.phases[1] = 1;
    assert(work::scheduled_charge(forged_active, 2, 1).status == 5 && forged_active.failed);
    var bad_event = work::ScheduledWork {};
    assert(work::schedule_begin(bad_event, 1));
    assert(work::scheduled_charge(bad_event, 1, 99).status == 5 && bad_event.failed);
    assert(bad_event.meter.semantic == 0);
    var limit = work::ScheduledWork {};
    limit.meter.semantic = 1048575;
    assert(work::schedule_begin(limit, 1));
    assert(work::scheduled_charge(limit, 1, 1).status == 0);
    let denied = work::scheduled_charge(limit, 1, 1);
    assert(denied.status == 1 && denied.quantity == 1 && denied.measured == 1048576);
    assert(limit.failed && limit.meter.semantic == 1048576);
    assert(work::scheduled_charge(limit, 1, 1).status == 5);
    assert(!work::schedule_end(limit, 1));
    var peak = work::Meter {};
    assert(work::charge(peak, 4, 22).status == 0);
    assert(work::charge(peak, 4, 22).status == 0);
    assert(peak.proof_edges == 2 && peak.proof_peak_edges == 2);
    print("ordered work scheduler passed");
}
