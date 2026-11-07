// Shared syntax names; no semantic checker dependencies.
namespace blot_check_typed_staging;
enum Op { quote, splice, lift, emit, run, describe, same, fields, evaluate }
fn lookup(name: const u8[:]) -> Op, bool {
    if name == "@code.evaluate" { return Op.evaluate, true; }
    if name == "@code.quote" { return Op.quote, true; }
    if name == "@code.splice" { return Op.splice, true; }
    if name == "@code.lift" { return Op.lift, true; }
    if name == "@code.emit" { return Op.emit, true; }
    if name == "@code.run" { return Op.run, true; }
    if name == "@code.describe" { return Op.describe, true; }
    if name == "@descriptor.same" { return Op.same, true; }
    if name == "@descriptor.fields" { return Op.fields, true; }
    return Op.quote, false;
}
