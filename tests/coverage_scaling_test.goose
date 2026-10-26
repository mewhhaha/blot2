import src.model;
import src.frontend;
import src.plan;
import src.fingerprint;
import src.coverage;
import std;
fn coverage_work(callers:u32) -> u64 {
    var source:u8[>..]=[];
    source.append("let identity: forall [T:Type] => T -> T ! {} resources {depth:1,frame:1024} = fn x => return x\n");
    for i in callers { format(source,"pub let run_",i,": U32 -> U32 ! {} resources {depth:2,frame:2048} = fn x => return identity@[U32](x)\n"); }
    var visits:u64=0;
    with_core() { b =>
        var work=Work{..}; var diagnostics:Diagnostic[>..]=[];
        assert(frontend_complete(source,"coverage-scaling",b,work,diagnostics));
        assert(build_plans(b,"",diagnostics)); assert(canonical_schemas(b,diagnostics)); assert(seal_completion(b));
        var validation=Work{..}; assert(validator::validate_core(core_view(b),validator::FRESH,validation,diagnostics));
        var coverage=Work{..}; assert(check_dictionary_coverage(core_view(b),coverage,diagnostics)); visits=coverage.visits;
    };
    return visits;
}
fn test_dictionary_coverage_function_work() {
    let small=coverage_work(16); let large=coverage_work(64);
    // Four times as many independent callers may demand four times the work,
    // but must not trigger a Cartesian scan of callers and unrelated Values.
    assert(small>0 && large>small && large<=small*5);
    print("C07 coverage remains owner-local as independent generic callers grow: ",small," -> ",large);
}
