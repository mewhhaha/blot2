// Shared syntax names; no semantic checker dependencies.
namespace blot_check_numeric_proof_terms;
enum Relation { eq, lt, le, add_fits, sub_fits, index }
fn constructor(name: const u8[:]) -> Relation, bool {
    if name == "@proof.eq" { return Relation.eq, true; }
    if name == "@proof.lt" { return Relation.lt, true; }
    if name == "@proof.le" { return Relation.le, true; }
    if name == "@proof.add_fits" { return Relation.add_fits, true; }
    if name == "@proof.sub_fits" { return Relation.sub_fits, true; }
    if name == "@proof.index" { return Relation.index, true; }
    return Relation.eq, false;
}
fn typeName(name: const u8[:]) -> Relation, bool {
    if name == "@proof.U32Eq" { return Relation.eq, true; }
    if name == "@proof.U32Lt" { return Relation.lt, true; }
    if name == "@proof.U32Le" { return Relation.le, true; }
    if name == "@proof.U32AddFits" { return Relation.add_fits, true; }
    if name == "@proof.U32SubFits" { return Relation.sub_fits, true; }
    if name == "@proof.Index" { return Relation.index, true; }
    return Relation.eq, false;
}
fn type_name(name: const u8[:]) -> Relation, bool { return typeName(name); }
