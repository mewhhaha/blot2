// Session admission consumes a valid seed once and preserves rejected ownership.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import reuse.retained_revision;
import reuse.retained_dependency;
import reuse.dependency_payload;
import support.error;
import support.native;
fn main() {
    let options=blot_reuse_project::Options{input_mode:blot_reuse_project::InputMode.project,..};
    for cycle in 0..4 {
        let owner,error=blot_reuse_dependency_payload::init();assert(error==blot_error::Error.none);
        var invalid=blot_reuse_dependency_payload::Owned<blot_reuse_frozen_dependency::FrozenDependency>{default<blot_reuse_frozen_dependency::FrozenDependency>(),owner};
        let rejected,error=blot_reuse_retained_revision::init(invalid,options,blot_native::fresh_owner_id());
        assert(error==blot_error::Error.invalid_artifact && !rejected.valid() && invalid.owner==owner && invalid.owner.unique());invalid.deinit();
        var session,error=blot_reuse_retained_revision::initEmpty(options,blot_native::fresh_owner_id());assert(error==blot_error::Error.none && session.valid());
        let seed=session.state().seed;assert(seed.valid());
        let snapshot=seed.snapshot();assert(snapshot && snapshot.validated && seed.value().symbols.len==1 && seed.value().modules.len==0);
        session.deinit();assert(!session.valid() && !seed.valid());
    }
}
