// Standalone checked-add fixture. The compiler-owned Work is created anew per
// source and must also be used for every revalidation before emission.
import add_frontend;
import add_proof;
import add_core;
import add_wasm;
import scalar_core;
import scalar_plan;
import wasm;
import std;
import os;

fn require(ok: bool, message: u8[:]) { if !ok { abort(str("checked-add wasm: ", message)); } }
fn main() {
    let sources: (const u8[:])[3] = [
        "let f: U32 -> U32 = fn x => return x + 0\n",
        "let f: U32 -> U32 = fn x => do:\n  return x + 0\n",
        "let f: U32 -> U32 = fn x => return do:\n  break x + 0\n"
    ];
    for source, i in sources {
        let candidate = add_frontend::parse(source);
        require(candidate.status == 0, "source");
        var work = add_proof::Work {};
        let built = add_proof::build(add_core::subject(), work);
        require(built.status == 0 && work.terms == 4 && work.edges == 5 && work.proof_visits == 10, "build proof");
        let checked = add_core::make_core(candidate.core, built.proof);
        let plan = add_core::make_plan(checked);
        require(!scalar_core::validate_structure(candidate.core), "v2 structure fence");
        let v2 = scalar_plan::make(candidate.core);
        require(!scalar_plan::validate(v2) && wasm::emit_scalar_v2("f", v2).len == 0, "v2 plan and emitter fence");
        let image = add_wasm::emit(source, plan, work);
        require(image.len > 0 && work.proof_visits == 20 && work.semantic_visits == 20, "checked emit and charge");
        require(write_file(str("add_v4_", i, ".wasm"), image), "write output");
        require(add_wasm::emit(source, plan, work).len > 0 && work.proof_visits == 30, "revalidation charges again");
        var fresh = add_proof::Work {};
        require(add_wasm::emit(source, plan, fresh).len == 0, "fresh uncharged proof rejected");
        require(add_wasm::emit("let f: U32 -> U32 = fn x => return x + 1\n", plan, work).len == 0, "changed source rejected");
        { var bad = plan; bad.opcode = 0x71; require(add_wasm::emit(source, bad, work).len == 0, "opcode"); }
        { var bad = plan; bad.abi = 2; require(add_wasm::emit(source, bad, work).len == 0, "ABI"); }
        { var bad = plan; bad.schema = 2; require(add_wasm::emit(source, bad, work).len == 0, "schema"); }
        { var bad = plan; bad.checked.scope = 2; require(add_wasm::emit(source, bad, work).len == 0, "scope"); }
        { var bad = plan; bad.checked.core.values[2].op_id = 1; require(add_wasm::emit(source, bad, work).len == 0, "Core op"); }
        { var bad = plan; bad.checked.core.values[1].literal = 1; require(add_wasm::emit(source, bad, work).len == 0, "zero"); }
        { var bad = plan; bad.checked.evidence.nodes[2].prior1 = 2; require(add_wasm::emit(source, bad, work).len == 0, "forged prerequisite"); }
        { var bad = plan; bad.checked.evidence.subject.parameter_version = 2; require(add_wasm::emit(source, bad, work).len == 0, "forged version"); }
        { var exact = work; exact.proof_visits = 65526;
          require(add_wasm::emit(source, plan, exact).len > 0 && exact.proof_visits == 65536, "exact proof budget"); }
        { var exhausted = work; exhausted.proof_visits = 65527;
          require(add_wasm::emit(source, plan, exhausted).len == 0 && exhausted.limit == 2 && exhausted.limit_quantity == 3, "proof budget"); }
        { var exact = work; exact.semantic_visits = 1048566;
          require(add_wasm::emit(source, plan, exact).len > 0 && exact.semantic_visits == 1048576, "exact semantic budget"); }
        { var exhausted = work; exhausted.semantic_visits = 1048567;
          require(add_wasm::emit(source, plan, exhausted).len == 0 && exhausted.limit == 3 && exhausted.limit_quantity == 4, "semantic budget"); }
        { var exhausted = work; exhausted.proof_visits = 65536; exhausted.semantic_visits = 1048576;
          require(add_wasm::emit(source, plan, exhausted).len == 0 && exhausted.limit == 3 && exhausted.limit_quantity == 4, "semantic budget first"); }
    }
    print("checked-add Wasm checks passed");
}
