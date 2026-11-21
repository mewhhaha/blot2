// Shared #run / @build.read syntax names; no semantic checker dependencies.
namespace blot_check_typed_staging;
enum Op { evaluate, read_input }
fn lookup(name: const u8[:]) -> Op, bool {
    if name == "@build.read" { return Op.read_input, true; }
    if name == "@code.evaluate" { return Op.evaluate, true; }
    return Op.evaluate, false;
}
