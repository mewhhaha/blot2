import retained_scalar;
import retained_observations;
import public_snapshot;

fn same_revision(r: retained_scalar::Revision&, s: public_snapshot::Snapshot&) -> bool {
    for snap in r.snapshots { return retained_scalar::same_snapshot(snap, s); }
    return false;
}
fn main() {
    let abi: u8[32] = [7;32];
    var source: u8[>..] = []; source.append("pub let answer: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x\n");
    var pkg: u8[>..] = []; pkg.append("pkg");
    var module: u8[>..] = []; module.append("main.blot");
    var name: u8[>..] = []; name.append("answer");
    var revision = retained_scalar::Revision {};
    var absent = public_snapshot::Snapshot {};
    assert(retained_scalar::attempt(revision, source, pkg, module, name, abi, absent, false, 0).status == 0);
    var made = public_snapshot::make(source, pkg, module, name, abi);
    var original = copy(made.snapshot);
    source[0] = 'X'; pkg[0] = 'X'; module[0] = 'X'; name[0] = 'X';
    assert(same_revision(revision, original));
    assert(public_snapshot::validate(original, "pkg", "main.blot", "answer", abi));
    source[0] = 'p'; pkg[0] = 'p'; module[0] = 'm'; name[0] = 'a';
    assert(retained_scalar::attempt(revision, source, pkg, module, name, abi, original, true, 0).cache == 1);
    assert(same_revision(revision, original));
    // Test rollback at every failpoint for every retained field, not only wasm.
    for point in 1..6 {
        let generation = revision.generation;
        let outcome = retained_scalar::attempt(revision, source, pkg, module, name, abi, original, true, point);
        assert(outcome.status != 0 && revision.generation == generation);
        assert(same_revision(revision, original));
    }
    // Presence is not identity: an empty value still differs from missing.
    let absent_observation = [retained_observations::Observation { kind: 3, key: "x", found: false }];
    let empty = [retained_observations::Entry { kind: 3, key: "x", value: [] }];
    assert(retained_observations::compare(absent_observation, empty).status == 1);
    let present = [retained_observations::Observation { kind: 3, key: "x", found: true, value: [] }];
    let no_entries: retained_observations::Entry[] = [];
    assert(retained_observations::compare(present, no_entries).status == 1);
    for kind in 1..10 {
      for other in 1..10 {
        let o = [retained_observations::Observation { kind: kind, key: "x", found: true, value: "v" }];
        let e = [retained_observations::Entry { kind: other, key: "x", value: "v" }];
        assert(retained_observations::compare(o, e).status == (if kind == other {0} else {1}));
      }
    }
    print("independent retained rollback and negative observations passed");
}
