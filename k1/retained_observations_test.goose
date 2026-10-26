import retained_observations;
fn main() {
    let observations = [
        retained_observations::Observation { kind: 1, key: "callee", found: true, value: "interface" },
        retained_observations::Observation { kind: 6, key: "missing", found: false },
        retained_observations::Observation { kind: 8, key: "semantic-policy", found: true, value: "v1" }
    ];
    let current = [
        retained_observations::Entry { kind: 1, key: "callee", value: "interface" },
        retained_observations::Entry { kind: 2, key: "callee", value: "body1" },
        retained_observations::Entry { kind: 8, key: "semantic-policy", value: "v1" }
    ];
    assert(retained_observations::compare(observations, current).status == 0);
    let body_changed = [
        retained_observations::Entry { kind: 1, key: "callee", value: "interface" },
        retained_observations::Entry { kind: 2, key: "callee", value: "body2" },
        retained_observations::Entry { kind: 8, key: "semantic-policy", value: "v1" }
    ];
    assert(retained_observations::compare(observations, body_changed).status == 0);
    let uses_body = [retained_observations::Observation { kind: 2, key: "callee", found: true, value: "body1" }];
    assert(retained_observations::compare(uses_body, current).status == 0);
    assert(retained_observations::compare(uses_body, body_changed).status == 1);
    let origins = [retained_observations::Observation { kind: 7, key: "callee", found: true, value: "a.blot:1" }];
    let moved_origin = [retained_observations::Entry { kind: 7, key: "callee", value: "b.blot:1" }];
    assert(retained_observations::compare(origins, moved_origin).status == 1);
    let empty_value = [retained_observations::Observation { kind: 1, key: "empty", found: true, value: [] }];
    let empty_entry = [retained_observations::Entry { kind: 1, key: "empty", value: [] }];
    assert(retained_observations::compare(empty_value, empty_entry).status == 0);
    let now_present = [
        retained_observations::Entry { kind: 1, key: "callee", value: "interface" },
        retained_observations::Entry { kind: 6, key: "missing", value: [] },
        retained_observations::Entry { kind: 8, key: "semantic-policy", value: "v1" }
    ];
    assert(retained_observations::compare(observations, now_present).status == 1);
    let changed = [
        retained_observations::Entry { kind: 1, key: "callee", value: "changed" },
        retained_observations::Entry { kind: 8, key: "semantic-policy", value: "v1" }
    ];
    assert(retained_observations::compare(observations, changed).status == 1);
    let duplicate = [
        retained_observations::Entry { kind: 1, key: "callee", value: "interface" },
        retained_observations::Entry { kind: 1, key: "callee", value: "interface" }
    ];
    assert(retained_observations::compare(observations, duplicate).status == 2);
    let malformed = [retained_observations::Observation { kind: 1, key: "x", found: false, value: "nonempty" }];
    assert(retained_observations::compare(malformed, current).status == 2);
    let unknown = [retained_observations::Observation { kind: 10, key: "x" }];
    assert(retained_observations::compare(unknown, current).status == 2);
    var entries: retained_observations::Entry[>..] = [];
    for i in 4095 { entries.push(retained_observations::Entry { kind: 1, key: "different", value: [] }); }
    let negative = [retained_observations::Observation { kind: 1, key: "x", found: false }];
    let at = retained_observations::compare(negative, entries);
    assert(at.status == 0 && at.visits == 4096);
    entries.push(retained_observations::Entry { kind: 1, key: "different", value: [] });
    let over = retained_observations::compare(negative, entries);
    assert(over.status == 3 && over.visits == 4096);
    assert(retained_observations::charge_bytes(117440512, 16777216) == 134217728);
    assert(retained_observations::charge_bytes(134217728, 1) == -1);
    assert(retained_observations::charge_bytes(0, -1) == -1);
    assert(retained_observations::charge_bytes(0, 16777217) == -1);
    print("private retained observation laws passed");
}
