// Full immutable Core worker packets. All references become typed local runs.
// Generated concrete codecs are source, and have not been compiled or verified.
namespace blot_core_packet;
import backend.collection_ops;
import backend.opaque_storage;
import check.capability_contracts;
import check.capability_flow;
import check.core;
import check.effects;
import check.numeric_proof_contracts;
import check.numeric_proof_headers;
import check.numeric_proof_terms;
import check.types;
import parse.ast;
import reuse.principal_interface;
import reuse.dependency_payload;
import support.blake3;
import support.bytes;
import support.error;
import support.native;
import support.option;

type Error = blot_error::Error;
let packet_magic: const u8[:] = "BLOTCORE";
let packet_version: u32 = 1;
let packet_header: i64 = 84;
let packet_limit: i64 = 67108864;
let element_limit: i64 = 4194304;
let depth_limit: i64 = 64;
let schema_digest: u8[32] = [130,58,181,20,204,60,171,32,181,206,67,4,20,104,58,228,218,247,17,123,55,69,145,133,245,119,60,175,88,40,205,129];

enum Run {
    run_u32 { values: u32[:] },
    run_blot_check_numeric_proof_terms__Kind { values: blot_check_numeric_proof_terms::Kind[:] },
    run_blot_check_numeric_proof_terms__Term { values: blot_check_numeric_proof_terms::Term[:] },
    run_blot_check_numeric_proof_contracts__Requirement { values: blot_check_numeric_proof_contracts::Requirement[:] },
    run_blot_check_numeric_proof_headers__Named { values: blot_check_numeric_proof_headers::Named[:] },
    run_blot_check_capability_contracts__Term { values: blot_check_capability_contracts::Term[:] },
    run_blot_check_capability_contracts__Binding { values: blot_check_capability_contracts::Binding[:] },
    run_blot_check_core__FieldName { values: blot_check_core::FieldName[:] },
    run_blot_check_core__RuntimeName { values: blot_check_core::RuntimeName[:] },
    run_blot_check_core__DeclarationDependencies { values: blot_check_core::DeclarationDependencies[:] },
    run_blot_check_core__BindingRef { values: blot_check_core::BindingRef[:] },
    run_blot_check_core__DependencyMember { values: blot_check_core::DependencyMember[:] },
    run_blot_check_core__ErasedDeclarationReference { values: blot_check_core::ErasedDeclarationReference[:] },
    run_blot_check_core__RequestLoopInfo { values: blot_check_core::RequestLoopInfo[:] },
    run_blot_check_core__RequestArm { values: blot_check_core::RequestArm[:] },
    run_blot_check_types__Node { values: blot_check_types::Node[:] },
    run_blot_check_effects__Row { values: blot_check_effects::Row[:] },
    run_blot_check_types__Operation { values: blot_check_types::Operation[:] },
    run_blot_check_types__QuantifierGoals { values: blot_check_types::QuantifierGoals[:] },
    run_blot_check_types__Obligation { values: blot_check_types::Obligation[:] },
    run_blot_check_core__Node { values: blot_check_core::Node[:] },
    run_blot_parse_ast__Span { values: blot_parse_ast::Span[:] },
    run_blot_check_core__Binding { values: blot_check_core::Binding[:] },
    run_blot_check_core__Body { values: blot_check_core::Body[:] },
    run_blot_check_core__Parameter { values: blot_check_core::Parameter[:] },
    run_blot_check_core__CallInfo { values: blot_check_core::CallInfo[:] },
    run_blot_check_core__Merge { values: blot_check_core::Merge[:] },
    run_blot_check_core__List { values: blot_check_core::List[:] },
    run_u8 { values: u8[:] },
    run_blot_check_core__Obligation { values: blot_check_core::Obligation[:] },
    run_blot_check_core__Nominal { values: blot_check_core::Nominal[:] },
    run_blot_check_core__OperationName { values: blot_check_core::OperationName[:] },
    run_blot_check_core__Constructor { values: blot_check_core::Constructor[:] },
    run_blot_check_core__Projection { values: blot_check_core::Projection[:] },
    run_blot_check_core__ProjectionVariant { values: blot_check_core::ProjectionVariant[:] },
    run_blot_check_core__Pattern { values: blot_check_core::Pattern[:] },
    run_blot_check_core__PatternRow { values: blot_check_core::PatternRow[:] },
    run_blot_check_core__MatchArm { values: blot_check_core::MatchArm[:] },
    run_blot_check_core__MatchInfo { values: blot_check_core::MatchInfo[:] },
    run_blot_check_core__UpdateInfo { values: blot_check_core::UpdateInfo[:] },
    run_blot_check_core__UpdateStep { values: blot_check_core::UpdateStep[:] },
    run_blot_check_core__ClosureInfo { values: blot_check_core::ClosureInfo[:] },
    run_blot_check_core__Associated { values: blot_check_core::Associated[:] },
    run_blot_check_core__Contract { values: blot_check_core::Contract[:] },
    run_blot_reuse_principal_interface__ContractMember { values: blot_reuse_principal_interface::ContractMember[:] },
    run_blot_reuse_principal_interface__Implementation { values: blot_reuse_principal_interface::Implementation[:] },
    run_blot_reuse_principal_interface__ImplementationMember { values: blot_reuse_principal_interface::ImplementationMember[:] },
    run_blot_reuse_principal_interface__MemberTemplate { values: blot_reuse_principal_interface::MemberTemplate[:] },
    run_blot_reuse_principal_interface__SelectedProof { values: blot_reuse_principal_interface::SelectedProof[:] },
    run_blot_check_core__SelectedUse { values: blot_check_core::SelectedUse[:] },
    run_blot_check_core__DictionarySelection { values: blot_check_core::DictionarySelection[:] },
    run_blot_check_core__DictionaryUse { values: blot_check_core::DictionaryUse[:] },
    run_blot_check_core__Primitive { values: blot_check_core::Primitive[:] },
    run_blot_check_core__LoopInfo { values: blot_check_core::LoopInfo[:] },
    run_blot_check_core__LoopCarry { values: blot_check_core::LoopCarry[:] },
    run_blot_check_core__ResolverInfo { values: blot_check_core::ResolverInfo[:] },
    run_blot_check_core__OperationValue { values: blot_check_core::OperationValue[:] },
    run_blot_check_core__HandleEffects { values: blot_check_core::HandleEffects[:] },
    run_blot_check_core__Diagnostic { values: blot_check_core::Diagnostic[:] }
}

struct Link { value: Run, next: u32 = 0 }

struct Lease { head: u32, generation: u64, live: bool = true }

reusable var links: Link[>..] = [];

reusable var leases: Lease[>..] = [];

var next_generation: u64 = 1;

reusable[] var pool_u32: u32[>..] = [];

reusable[] var pool_blot_check_numeric_proof_terms__Kind: blot_check_numeric_proof_terms::Kind[>..] = [];

reusable[] var pool_blot_check_numeric_proof_terms__Term: blot_check_numeric_proof_terms::Term[>..] = [];

reusable[] var pool_blot_check_numeric_proof_contracts__Requirement: blot_check_numeric_proof_contracts::Requirement[>..] = [];

reusable[] var pool_blot_check_numeric_proof_headers__Named: blot_check_numeric_proof_headers::Named[>..] = [];

reusable[] var pool_blot_check_capability_contracts__Term: blot_check_capability_contracts::Term[>..] = [];

reusable[] var pool_blot_check_capability_contracts__Binding: blot_check_capability_contracts::Binding[>..] = [];

reusable[] var pool_blot_check_core__FieldName: blot_check_core::FieldName[>..] = [];

reusable[] var pool_blot_check_core__RuntimeName: blot_check_core::RuntimeName[>..] = [];

reusable[] var pool_blot_check_core__DeclarationDependencies: blot_check_core::DeclarationDependencies[>..] = [];

reusable[] var pool_blot_check_core__BindingRef: blot_check_core::BindingRef[>..] = [];

reusable[] var pool_blot_check_core__DependencyMember: blot_check_core::DependencyMember[>..] = [];

reusable[] var pool_blot_check_core__ErasedDeclarationReference: blot_check_core::ErasedDeclarationReference[>..] = [];

reusable[] var pool_blot_check_core__RequestLoopInfo: blot_check_core::RequestLoopInfo[>..] = [];

reusable[] var pool_blot_check_core__RequestArm: blot_check_core::RequestArm[>..] = [];

reusable[] var pool_blot_check_types__Node: blot_check_types::Node[>..] = [];

reusable[] var pool_blot_check_effects__Row: blot_check_effects::Row[>..] = [];

reusable[] var pool_blot_check_types__Operation: blot_check_types::Operation[>..] = [];

reusable[] var pool_blot_check_types__QuantifierGoals: blot_check_types::QuantifierGoals[>..] = [];

reusable[] var pool_blot_check_types__Obligation: blot_check_types::Obligation[>..] = [];

reusable[] var pool_blot_check_core__Node: blot_check_core::Node[>..] = [];

reusable[] var pool_blot_parse_ast__Span: blot_parse_ast::Span[>..] = [];

reusable[] var pool_blot_check_core__Binding: blot_check_core::Binding[>..] = [];

reusable[] var pool_blot_check_core__Body: blot_check_core::Body[>..] = [];

reusable[] var pool_blot_check_core__Parameter: blot_check_core::Parameter[>..] = [];

reusable[] var pool_blot_check_core__CallInfo: blot_check_core::CallInfo[>..] = [];

reusable[] var pool_blot_check_core__Merge: blot_check_core::Merge[>..] = [];

reusable[] var pool_blot_check_core__List: blot_check_core::List[>..] = [];

reusable[] var pool_u8: u8[>..] = [];

reusable[] var pool_blot_check_core__Obligation: blot_check_core::Obligation[>..] = [];

reusable[] var pool_blot_check_core__Nominal: blot_check_core::Nominal[>..] = [];

reusable[] var pool_blot_check_core__OperationName: blot_check_core::OperationName[>..] = [];

reusable[] var pool_blot_check_core__Constructor: blot_check_core::Constructor[>..] = [];

reusable[] var pool_blot_check_core__Projection: blot_check_core::Projection[>..] = [];

reusable[] var pool_blot_check_core__ProjectionVariant: blot_check_core::ProjectionVariant[>..] = [];

reusable[] var pool_blot_check_core__Pattern: blot_check_core::Pattern[>..] = [];

reusable[] var pool_blot_check_core__PatternRow: blot_check_core::PatternRow[>..] = [];

reusable[] var pool_blot_check_core__MatchArm: blot_check_core::MatchArm[>..] = [];

reusable[] var pool_blot_check_core__MatchInfo: blot_check_core::MatchInfo[>..] = [];

reusable[] var pool_blot_check_core__UpdateInfo: blot_check_core::UpdateInfo[>..] = [];

reusable[] var pool_blot_check_core__UpdateStep: blot_check_core::UpdateStep[>..] = [];

reusable[] var pool_blot_check_core__ClosureInfo: blot_check_core::ClosureInfo[>..] = [];

reusable[] var pool_blot_check_core__Associated: blot_check_core::Associated[>..] = [];

reusable[] var pool_blot_check_core__Contract: blot_check_core::Contract[>..] = [];

reusable[] var pool_blot_reuse_principal_interface__ContractMember: blot_reuse_principal_interface::ContractMember[>..] = [];

reusable[] var pool_blot_reuse_principal_interface__Implementation: blot_reuse_principal_interface::Implementation[>..] = [];

reusable[] var pool_blot_reuse_principal_interface__ImplementationMember: blot_reuse_principal_interface::ImplementationMember[>..] = [];

reusable[] var pool_blot_reuse_principal_interface__MemberTemplate: blot_reuse_principal_interface::MemberTemplate[>..] = [];

reusable[] var pool_blot_reuse_principal_interface__SelectedProof: blot_reuse_principal_interface::SelectedProof[>..] = [];

reusable[] var pool_blot_check_core__SelectedUse: blot_check_core::SelectedUse[>..] = [];

reusable[] var pool_blot_check_core__DictionarySelection: blot_check_core::DictionarySelection[>..] = [];

reusable[] var pool_blot_check_core__DictionaryUse: blot_check_core::DictionaryUse[>..] = [];

reusable[] var pool_blot_check_core__Primitive: blot_check_core::Primitive[>..] = [];

reusable[] var pool_blot_check_core__LoopInfo: blot_check_core::LoopInfo[>..] = [];

reusable[] var pool_blot_check_core__LoopCarry: blot_check_core::LoopCarry[>..] = [];

reusable[] var pool_blot_check_core__ResolverInfo: blot_check_core::ResolverInfo[>..] = [];

reusable[] var pool_blot_check_core__OperationValue: blot_check_core::OperationValue[>..] = [];

reusable[] var pool_blot_check_core__HandleEffects: blot_check_core::HandleEffects[>..] = [];

reusable[] var pool_blot_check_core__Diagnostic: blot_check_core::Diagnostic[>..] = [];

struct Owned { module: blot_check_core::Module, lease: u32 = 0, generation: u64 = 0,payload_owner:blot_reuse_dependency_payload::Owner=blot_reuse_dependency_payload::Owner {..} }
struct Writer { output: u8[>..<]&, start: i64, failure: Error = Error.none, remaining: i64 = element_limit }
struct Reader { bytes: const u8[:], at: i64 = 0, remaining: i64 = element_limit, head: u32 = 0 }
fn charge(writer: Writer&, depth: i64) -> bool { if writer.failure != Error.none { return false; } if depth > depth_limit || writer.remaining == 0 { writer.failure = Error.artifact_limit; return false; } writer.remaining--; return true; }
fn debit(reader: Reader&, depth: i64) -> Error { if depth > depth_limit || reader.remaining == 0 { return Error.artifact_limit; } reader.remaining--; return Error.none; }
fn put(writer: Writer&, bits: u64, width: i64) { if writer.failure != Error.none { return; } if writer.output.len - writer.start > packet_limit - width { writer.failure = Error.artifact_limit; return; } for index in width { writer.output.push((bits >> ((index * 8) as u32)) as! u8); } }
fn get(reader: Reader&, width: i64) -> u64, Error { if reader.at > reader.bytes.len || width > reader.bytes.len - reader.at { return 0, Error.invalid_artifact; } var bits: u64 = 0; for index in width { bits |= (reader.bytes[reader.at + index] as u64) << ((index * 8) as u32); } reader.at += width; return bits, Error.none; }
fn remember(reader: Reader&, value: Run) -> Error { if links.len >= 0xffffffff { return Error.out_of_memory; } let at = links.alloc_index(Link { value, reader.head , ..}); reader.head = (at + 1) as u32; return Error.none; }
fn releaseRuns(head: u32) { var next = head; while next != 0 { let at = next - 1; let link = links[at]; next = link.next; match link.value {

    Run.run_u32 run => { pool_u32.free_slice(run.values); },

    Run.run_blot_check_numeric_proof_terms__Kind run => { pool_blot_check_numeric_proof_terms__Kind.free_slice(run.values); },

    Run.run_blot_check_numeric_proof_terms__Term run => { pool_blot_check_numeric_proof_terms__Term.free_slice(run.values); },

    Run.run_blot_check_numeric_proof_contracts__Requirement run => { pool_blot_check_numeric_proof_contracts__Requirement.free_slice(run.values); },

    Run.run_blot_check_numeric_proof_headers__Named run => { pool_blot_check_numeric_proof_headers__Named.free_slice(run.values); },

    Run.run_blot_check_capability_contracts__Term run => { pool_blot_check_capability_contracts__Term.free_slice(run.values); },

    Run.run_blot_check_capability_contracts__Binding run => { pool_blot_check_capability_contracts__Binding.free_slice(run.values); },

    Run.run_blot_check_core__FieldName run => { pool_blot_check_core__FieldName.free_slice(run.values); },

    Run.run_blot_check_core__RuntimeName run => { pool_blot_check_core__RuntimeName.free_slice(run.values); },

    Run.run_blot_check_core__DeclarationDependencies run => { pool_blot_check_core__DeclarationDependencies.free_slice(run.values); },

    Run.run_blot_check_core__BindingRef run => { pool_blot_check_core__BindingRef.free_slice(run.values); },

    Run.run_blot_check_core__DependencyMember run => { pool_blot_check_core__DependencyMember.free_slice(run.values); },

    Run.run_blot_check_core__ErasedDeclarationReference run => { pool_blot_check_core__ErasedDeclarationReference.free_slice(run.values); },

    Run.run_blot_check_core__RequestLoopInfo run => { pool_blot_check_core__RequestLoopInfo.free_slice(run.values); },

    Run.run_blot_check_core__RequestArm run => { pool_blot_check_core__RequestArm.free_slice(run.values); },

    Run.run_blot_check_types__Node run => { pool_blot_check_types__Node.free_slice(run.values); },

    Run.run_blot_check_effects__Row run => { pool_blot_check_effects__Row.free_slice(run.values); },

    Run.run_blot_check_types__Operation run => { pool_blot_check_types__Operation.free_slice(run.values); },

    Run.run_blot_check_types__QuantifierGoals run => { pool_blot_check_types__QuantifierGoals.free_slice(run.values); },

    Run.run_blot_check_types__Obligation run => { pool_blot_check_types__Obligation.free_slice(run.values); },

    Run.run_blot_check_core__Node run => { pool_blot_check_core__Node.free_slice(run.values); },

    Run.run_blot_parse_ast__Span run => { pool_blot_parse_ast__Span.free_slice(run.values); },

    Run.run_blot_check_core__Binding run => { pool_blot_check_core__Binding.free_slice(run.values); },

    Run.run_blot_check_core__Body run => { pool_blot_check_core__Body.free_slice(run.values); },

    Run.run_blot_check_core__Parameter run => { pool_blot_check_core__Parameter.free_slice(run.values); },

    Run.run_blot_check_core__CallInfo run => { pool_blot_check_core__CallInfo.free_slice(run.values); },

    Run.run_blot_check_core__Merge run => { pool_blot_check_core__Merge.free_slice(run.values); },

    Run.run_blot_check_core__List run => { pool_blot_check_core__List.free_slice(run.values); },

    Run.run_u8 run => { pool_u8.free_slice(run.values); },

    Run.run_blot_check_core__Obligation run => { pool_blot_check_core__Obligation.free_slice(run.values); },

    Run.run_blot_check_core__Nominal run => { pool_blot_check_core__Nominal.free_slice(run.values); },

    Run.run_blot_check_core__OperationName run => { pool_blot_check_core__OperationName.free_slice(run.values); },

    Run.run_blot_check_core__Constructor run => { pool_blot_check_core__Constructor.free_slice(run.values); },

    Run.run_blot_check_core__Projection run => { pool_blot_check_core__Projection.free_slice(run.values); },

    Run.run_blot_check_core__ProjectionVariant run => { pool_blot_check_core__ProjectionVariant.free_slice(run.values); },

    Run.run_blot_check_core__Pattern run => { pool_blot_check_core__Pattern.free_slice(run.values); },

    Run.run_blot_check_core__PatternRow run => { pool_blot_check_core__PatternRow.free_slice(run.values); },

    Run.run_blot_check_core__MatchArm run => { pool_blot_check_core__MatchArm.free_slice(run.values); },

    Run.run_blot_check_core__MatchInfo run => { pool_blot_check_core__MatchInfo.free_slice(run.values); },

    Run.run_blot_check_core__UpdateInfo run => { pool_blot_check_core__UpdateInfo.free_slice(run.values); },

    Run.run_blot_check_core__UpdateStep run => { pool_blot_check_core__UpdateStep.free_slice(run.values); },

    Run.run_blot_check_core__ClosureInfo run => { pool_blot_check_core__ClosureInfo.free_slice(run.values); },

    Run.run_blot_check_core__Associated run => { pool_blot_check_core__Associated.free_slice(run.values); },

    Run.run_blot_check_core__Contract run => { pool_blot_check_core__Contract.free_slice(run.values); },

    Run.run_blot_reuse_principal_interface__ContractMember run => { pool_blot_reuse_principal_interface__ContractMember.free_slice(run.values); },

    Run.run_blot_reuse_principal_interface__Implementation run => { pool_blot_reuse_principal_interface__Implementation.free_slice(run.values); },

    Run.run_blot_reuse_principal_interface__ImplementationMember run => { pool_blot_reuse_principal_interface__ImplementationMember.free_slice(run.values); },

    Run.run_blot_reuse_principal_interface__MemberTemplate run => { pool_blot_reuse_principal_interface__MemberTemplate.free_slice(run.values); },

    Run.run_blot_reuse_principal_interface__SelectedProof run => { pool_blot_reuse_principal_interface__SelectedProof.free_slice(run.values); },

    Run.run_blot_check_core__SelectedUse run => { pool_blot_check_core__SelectedUse.free_slice(run.values); },

    Run.run_blot_check_core__DictionarySelection run => { pool_blot_check_core__DictionarySelection.free_slice(run.values); },

    Run.run_blot_check_core__DictionaryUse run => { pool_blot_check_core__DictionaryUse.free_slice(run.values); },

    Run.run_blot_check_core__Primitive run => { pool_blot_check_core__Primitive.free_slice(run.values); },

    Run.run_blot_check_core__LoopInfo run => { pool_blot_check_core__LoopInfo.free_slice(run.values); },

    Run.run_blot_check_core__LoopCarry run => { pool_blot_check_core__LoopCarry.free_slice(run.values); },

    Run.run_blot_check_core__ResolverInfo run => { pool_blot_check_core__ResolverInfo.free_slice(run.values); },

    Run.run_blot_check_core__OperationValue run => { pool_blot_check_core__OperationValue.free_slice(run.values); },

    Run.run_blot_check_core__HandleEffects run => { pool_blot_check_core__HandleEffects.free_slice(run.values); },

    Run.run_blot_check_core__Diagnostic run => { pool_blot_check_core__Diagnostic.free_slice(run.values); },

} links.free(at); } }
fn deinit(self: Owned&) {if self.payload_owner.lease!=0 {self.payload_owner.deinit();self.module=default<blot_check_core::Module>();return;} if self.lease == 0 { return; } let at = self.lease - 1; assert(at < leases.len && leases[at].live && leases[at].generation == self.generation); releaseRuns(leases[at].head); leases[at].live = false; leases.free(at); self.lease = 0; self.generation = 0; self.module = default<blot_check_core::Module>(); }

fn write_bool(writer: Writer&, value: bool, depth: i64) { if !charge(writer, depth) { return; } var bit: u64 = 0; if value { bit = 1; } put(writer, bit, 1); }

fn read_bool(reader: Reader&, depth: i64) -> bool, Error { let charged = debit(reader, depth); if charged != Error.none { return default<bool>(), charged; } let bits, error = get(reader, 1); if error != Error.none { return default<bool>(), error; } if bits > 1 { return false, Error.invalid_artifact; } return bits != 0, Error.none; }

fn write_f32(writer: Writer&, value: f32, depth: i64) { if !charge(writer, depth) { return; } put(writer, blot_native::f32_bits(value) as u64, 4); }

fn read_f32(reader: Reader&, depth: i64) -> f32, Error { let charged = debit(reader, depth); if charged != Error.none { return default<f32>(), charged; } let bits, error = get(reader, 4); if error != Error.none { return default<f32>(), error; } return blot_native::f32_from_bits(bits as u32), Error.none; }

fn write_f64(writer: Writer&, value: f64, depth: i64) { if !charge(writer, depth) { return; } put(writer, blot_native::f64_bits(value), 8); }

fn read_f64(reader: Reader&, depth: i64) -> f64, Error { let charged = debit(reader, depth); if charged != Error.none { return default<f64>(), charged; } let bits, error = get(reader, 8); if error != Error.none { return default<f64>(), error; } return blot_native::f64_from_bits(bits), Error.none; }

fn write_i16(writer: Writer&, value: i16, depth: i64) { if !charge(writer, depth) { return; } put(writer, value as! u64, 2); }

fn read_i16(reader: Reader&, depth: i64) -> i16, Error { let charged = debit(reader, depth); if charged != Error.none { return default<i16>(), charged; } let bits, error = get(reader, 2); if error != Error.none { return default<i16>(), error; } return bits as! i16, Error.none; }

fn write_i32(writer: Writer&, value: i32, depth: i64) { if !charge(writer, depth) { return; } put(writer, value as! u64, 4); }

fn read_i32(reader: Reader&, depth: i64) -> i32, Error { let charged = debit(reader, depth); if charged != Error.none { return default<i32>(), charged; } let bits, error = get(reader, 4); if error != Error.none { return default<i32>(), error; } return bits as! i32, Error.none; }

fn write_i64(writer: Writer&, value: i64, depth: i64) { if !charge(writer, depth) { return; } put(writer, value as! u64, 8); }

fn read_i64(reader: Reader&, depth: i64) -> i64, Error { let charged = debit(reader, depth); if charged != Error.none { return default<i64>(), charged; } let bits, error = get(reader, 8); if error != Error.none { return default<i64>(), error; } return bits as! i64, Error.none; }

fn write_i8(writer: Writer&, value: i8, depth: i64) { if !charge(writer, depth) { return; } put(writer, value as! u64, 1); }

fn read_i8(reader: Reader&, depth: i64) -> i8, Error { let charged = debit(reader, depth); if charged != Error.none { return default<i8>(), charged; } let bits, error = get(reader, 1); if error != Error.none { return default<i8>(), error; } return bits as! i8, Error.none; }

fn write_u16(writer: Writer&, value: u16, depth: i64) { if !charge(writer, depth) { return; } put(writer, value as! u64, 2); }

fn read_u16(reader: Reader&, depth: i64) -> u16, Error { let charged = debit(reader, depth); if charged != Error.none { return default<u16>(), charged; } let bits, error = get(reader, 2); if error != Error.none { return default<u16>(), error; } return bits as! u16, Error.none; }

fn write_u32(writer: Writer&, value: u32, depth: i64) { if !charge(writer, depth) { return; } put(writer, value as! u64, 4); }

fn read_u32(reader: Reader&, depth: i64) -> u32, Error { let charged = debit(reader, depth); if charged != Error.none { return default<u32>(), charged; } let bits, error = get(reader, 4); if error != Error.none { return default<u32>(), error; } return bits as! u32, Error.none; }

fn write_u64(writer: Writer&, value: u64, depth: i64) { if !charge(writer, depth) { return; } put(writer, value as! u64, 8); }

fn read_u64(reader: Reader&, depth: i64) -> u64, Error { let charged = debit(reader, depth); if charged != Error.none { return default<u64>(), charged; } let bits, error = get(reader, 8); if error != Error.none { return default<u64>(), error; } return bits as! u64, Error.none; }

fn write_u8(writer: Writer&, value: u8, depth: i64) { if !charge(writer, depth) { return; } put(writer, value as! u64, 1); }

fn read_u8(reader: Reader&, depth: i64) -> u8, Error { let charged = debit(reader, depth); if charged != Error.none { return default<u8>(), charged; } let bits, error = get(reader, 1); if error != Error.none { return default<u8>(), error; } return bits as! u8, Error.none; }

fn write_u32___(writer: Writer&, value: const u32[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_u32(writer, element, depth + 1); } }

fn read_u32___(reader: Reader&, depth: i64) -> u32[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_u32.alloc_slice(count as i64); let recorded = remember(reader, Run.run_u32 { run , ..});
    if recorded != Error.none { pool_u32.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_u32(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_numeric_proof_terms__Kind___(writer: Writer&, value: const blot_check_numeric_proof_terms::Kind[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_numeric_proof_terms__Kind(writer, element, depth + 1); } }

fn read_blot_check_numeric_proof_terms__Kind___(reader: Reader&, depth: i64) -> blot_check_numeric_proof_terms::Kind[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_numeric_proof_terms__Kind.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_numeric_proof_terms__Kind { run , ..});
    if recorded != Error.none { pool_blot_check_numeric_proof_terms__Kind.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_numeric_proof_terms__Kind(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_numeric_proof_terms__Term___(writer: Writer&, value: const blot_check_numeric_proof_terms::Term[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_numeric_proof_terms__Term(writer, element, depth + 1); } }

fn read_blot_check_numeric_proof_terms__Term___(reader: Reader&, depth: i64) -> blot_check_numeric_proof_terms::Term[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_numeric_proof_terms__Term.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_numeric_proof_terms__Term { run , ..});
    if recorded != Error.none { pool_blot_check_numeric_proof_terms__Term.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_numeric_proof_terms__Term(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_numeric_proof_contracts__Requirement___(writer: Writer&, value: const blot_check_numeric_proof_contracts::Requirement[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_numeric_proof_contracts__Requirement(writer, element, depth + 1); } }

fn read_blot_check_numeric_proof_contracts__Requirement___(reader: Reader&, depth: i64) -> blot_check_numeric_proof_contracts::Requirement[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_numeric_proof_contracts__Requirement.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_numeric_proof_contracts__Requirement { run , ..});
    if recorded != Error.none { pool_blot_check_numeric_proof_contracts__Requirement.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_numeric_proof_contracts__Requirement(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_numeric_proof_headers__Named___(writer: Writer&, value: const blot_check_numeric_proof_headers::Named[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_numeric_proof_headers__Named(writer, element, depth + 1); } }

fn read_blot_check_numeric_proof_headers__Named___(reader: Reader&, depth: i64) -> blot_check_numeric_proof_headers::Named[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_numeric_proof_headers__Named.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_numeric_proof_headers__Named { run , ..});
    if recorded != Error.none { pool_blot_check_numeric_proof_headers__Named.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_numeric_proof_headers__Named(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_capability_contracts__Term___(writer: Writer&, value: const blot_check_capability_contracts::Term[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_capability_contracts__Term(writer, element, depth + 1); } }

fn read_blot_check_capability_contracts__Term___(reader: Reader&, depth: i64) -> blot_check_capability_contracts::Term[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_capability_contracts__Term.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_capability_contracts__Term { run , ..});
    if recorded != Error.none { pool_blot_check_capability_contracts__Term.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_capability_contracts__Term(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_capability_contracts__Binding___(writer: Writer&, value: const blot_check_capability_contracts::Binding[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_capability_contracts__Binding(writer, element, depth + 1); } }

fn read_blot_check_capability_contracts__Binding___(reader: Reader&, depth: i64) -> blot_check_capability_contracts::Binding[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_capability_contracts__Binding.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_capability_contracts__Binding { run , ..});
    if recorded != Error.none { pool_blot_check_capability_contracts__Binding.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_capability_contracts__Binding(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__FieldName___(writer: Writer&, value: const blot_check_core::FieldName[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__FieldName(writer, element, depth + 1); } }

fn read_blot_check_core__FieldName___(reader: Reader&, depth: i64) -> blot_check_core::FieldName[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__FieldName.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__FieldName { run , ..});
    if recorded != Error.none { pool_blot_check_core__FieldName.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__FieldName(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__RuntimeName___(writer: Writer&, value: const blot_check_core::RuntimeName[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__RuntimeName(writer, element, depth + 1); } }

fn read_blot_check_core__RuntimeName___(reader: Reader&, depth: i64) -> blot_check_core::RuntimeName[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__RuntimeName.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__RuntimeName { run , ..});
    if recorded != Error.none { pool_blot_check_core__RuntimeName.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__RuntimeName(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__DeclarationDependencies___(writer: Writer&, value: const blot_check_core::DeclarationDependencies[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__DeclarationDependencies(writer, element, depth + 1); } }

fn read_blot_check_core__DeclarationDependencies___(reader: Reader&, depth: i64) -> blot_check_core::DeclarationDependencies[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__DeclarationDependencies.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__DeclarationDependencies { run , ..});
    if recorded != Error.none { pool_blot_check_core__DeclarationDependencies.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__DeclarationDependencies(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__BindingRef___(writer: Writer&, value: const blot_check_core::BindingRef[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__BindingRef(writer, element, depth + 1); } }

fn read_blot_check_core__BindingRef___(reader: Reader&, depth: i64) -> blot_check_core::BindingRef[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__BindingRef.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__BindingRef { run , ..});
    if recorded != Error.none { pool_blot_check_core__BindingRef.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__BindingRef(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__DependencyMember___(writer: Writer&, value: const blot_check_core::DependencyMember[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__DependencyMember(writer, element, depth + 1); } }

fn read_blot_check_core__DependencyMember___(reader: Reader&, depth: i64) -> blot_check_core::DependencyMember[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__DependencyMember.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__DependencyMember { run , ..});
    if recorded != Error.none { pool_blot_check_core__DependencyMember.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__DependencyMember(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__ErasedDeclarationReference___(writer: Writer&, value: const blot_check_core::ErasedDeclarationReference[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__ErasedDeclarationReference(writer, element, depth + 1); } }

fn read_blot_check_core__ErasedDeclarationReference___(reader: Reader&, depth: i64) -> blot_check_core::ErasedDeclarationReference[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__ErasedDeclarationReference.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__ErasedDeclarationReference { run , ..});
    if recorded != Error.none { pool_blot_check_core__ErasedDeclarationReference.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__ErasedDeclarationReference(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__RequestLoopInfo___(writer: Writer&, value: const blot_check_core::RequestLoopInfo[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__RequestLoopInfo(writer, element, depth + 1); } }

fn read_blot_check_core__RequestLoopInfo___(reader: Reader&, depth: i64) -> blot_check_core::RequestLoopInfo[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__RequestLoopInfo.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__RequestLoopInfo { run , ..});
    if recorded != Error.none { pool_blot_check_core__RequestLoopInfo.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__RequestLoopInfo(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__RequestArm___(writer: Writer&, value: const blot_check_core::RequestArm[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__RequestArm(writer, element, depth + 1); } }

fn read_blot_check_core__RequestArm___(reader: Reader&, depth: i64) -> blot_check_core::RequestArm[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__RequestArm.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__RequestArm { run , ..});
    if recorded != Error.none { pool_blot_check_core__RequestArm.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__RequestArm(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_types__Node___(writer: Writer&, value: const blot_check_types::Node[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_types__Node(writer, element, depth + 1); } }

fn read_blot_check_types__Node___(reader: Reader&, depth: i64) -> blot_check_types::Node[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_types__Node.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_types__Node { run , ..});
    if recorded != Error.none { pool_blot_check_types__Node.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_types__Node(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_effects__Row___(writer: Writer&, value: const blot_check_effects::Row[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_effects__Row(writer, element, depth + 1); } }

fn read_blot_check_effects__Row___(reader: Reader&, depth: i64) -> blot_check_effects::Row[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_effects__Row.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_effects__Row { run , ..});
    if recorded != Error.none { pool_blot_check_effects__Row.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_effects__Row(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_types__Operation___(writer: Writer&, value: const blot_check_types::Operation[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_types__Operation(writer, element, depth + 1); } }

fn read_blot_check_types__Operation___(reader: Reader&, depth: i64) -> blot_check_types::Operation[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_types__Operation.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_types__Operation { run , ..});
    if recorded != Error.none { pool_blot_check_types__Operation.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_types__Operation(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_types__QuantifierGoals___(writer: Writer&, value: const blot_check_types::QuantifierGoals[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_types__QuantifierGoals(writer, element, depth + 1); } }

fn read_blot_check_types__QuantifierGoals___(reader: Reader&, depth: i64) -> blot_check_types::QuantifierGoals[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_types__QuantifierGoals.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_types__QuantifierGoals { run , ..});
    if recorded != Error.none { pool_blot_check_types__QuantifierGoals.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_types__QuantifierGoals(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_types__Obligation___(writer: Writer&, value: const blot_check_types::Obligation[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_types__Obligation(writer, element, depth + 1); } }

fn read_blot_check_types__Obligation___(reader: Reader&, depth: i64) -> blot_check_types::Obligation[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_types__Obligation.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_types__Obligation { run , ..});
    if recorded != Error.none { pool_blot_check_types__Obligation.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_types__Obligation(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__Node___(writer: Writer&, value: const blot_check_core::Node[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__Node(writer, element, depth + 1); } }

fn read_blot_check_core__Node___(reader: Reader&, depth: i64) -> blot_check_core::Node[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__Node.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__Node { run , ..});
    if recorded != Error.none { pool_blot_check_core__Node.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__Node(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_parse_ast__Span___(writer: Writer&, value: const blot_parse_ast::Span[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_parse_ast__Span(writer, element, depth + 1); } }

fn read_blot_parse_ast__Span___(reader: Reader&, depth: i64) -> blot_parse_ast::Span[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_parse_ast__Span.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_parse_ast__Span { run , ..});
    if recorded != Error.none { pool_blot_parse_ast__Span.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_parse_ast__Span(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__Binding___(writer: Writer&, value: const blot_check_core::Binding[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__Binding(writer, element, depth + 1); } }

fn read_blot_check_core__Binding___(reader: Reader&, depth: i64) -> blot_check_core::Binding[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__Binding.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__Binding { run , ..});
    if recorded != Error.none { pool_blot_check_core__Binding.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__Binding(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__Body___(writer: Writer&, value: const blot_check_core::Body[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__Body(writer, element, depth + 1); } }

fn read_blot_check_core__Body___(reader: Reader&, depth: i64) -> blot_check_core::Body[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__Body.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__Body { run , ..});
    if recorded != Error.none { pool_blot_check_core__Body.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__Body(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__Parameter___(writer: Writer&, value: const blot_check_core::Parameter[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__Parameter(writer, element, depth + 1); } }

fn read_blot_check_core__Parameter___(reader: Reader&, depth: i64) -> blot_check_core::Parameter[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__Parameter.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__Parameter { run , ..});
    if recorded != Error.none { pool_blot_check_core__Parameter.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__Parameter(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__CallInfo___(writer: Writer&, value: const blot_check_core::CallInfo[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__CallInfo(writer, element, depth + 1); } }

fn read_blot_check_core__CallInfo___(reader: Reader&, depth: i64) -> blot_check_core::CallInfo[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__CallInfo.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__CallInfo { run , ..});
    if recorded != Error.none { pool_blot_check_core__CallInfo.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__CallInfo(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__Merge___(writer: Writer&, value: const blot_check_core::Merge[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__Merge(writer, element, depth + 1); } }

fn read_blot_check_core__Merge___(reader: Reader&, depth: i64) -> blot_check_core::Merge[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__Merge.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__Merge { run , ..});
    if recorded != Error.none { pool_blot_check_core__Merge.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__Merge(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__List___(writer: Writer&, value: const blot_check_core::List[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__List(writer, element, depth + 1); } }

fn read_blot_check_core__List___(reader: Reader&, depth: i64) -> blot_check_core::List[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__List.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__List { run , ..});
    if recorded != Error.none { pool_blot_check_core__List.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__List(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_u8___(writer: Writer&, value: const u8[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_u8(writer, element, depth + 1); } }

fn read_u8___(reader: Reader&, depth: i64) -> u8[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_u8.alloc_slice(count as i64); let recorded = remember(reader, Run.run_u8 { run , ..});
    if recorded != Error.none { pool_u8.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_u8(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__Obligation___(writer: Writer&, value: const blot_check_core::Obligation[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__Obligation(writer, element, depth + 1); } }

fn read_blot_check_core__Obligation___(reader: Reader&, depth: i64) -> blot_check_core::Obligation[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__Obligation.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__Obligation { run , ..});
    if recorded != Error.none { pool_blot_check_core__Obligation.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__Obligation(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__Nominal___(writer: Writer&, value: const blot_check_core::Nominal[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__Nominal(writer, element, depth + 1); } }

fn read_blot_check_core__Nominal___(reader: Reader&, depth: i64) -> blot_check_core::Nominal[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__Nominal.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__Nominal { run , ..});
    if recorded != Error.none { pool_blot_check_core__Nominal.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__Nominal(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__OperationName___(writer: Writer&, value: const blot_check_core::OperationName[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__OperationName(writer, element, depth + 1); } }

fn read_blot_check_core__OperationName___(reader: Reader&, depth: i64) -> blot_check_core::OperationName[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__OperationName.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__OperationName { run , ..});
    if recorded != Error.none { pool_blot_check_core__OperationName.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__OperationName(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__Constructor___(writer: Writer&, value: const blot_check_core::Constructor[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__Constructor(writer, element, depth + 1); } }

fn read_blot_check_core__Constructor___(reader: Reader&, depth: i64) -> blot_check_core::Constructor[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__Constructor.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__Constructor { run , ..});
    if recorded != Error.none { pool_blot_check_core__Constructor.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__Constructor(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__Projection___(writer: Writer&, value: const blot_check_core::Projection[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__Projection(writer, element, depth + 1); } }

fn read_blot_check_core__Projection___(reader: Reader&, depth: i64) -> blot_check_core::Projection[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__Projection.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__Projection { run , ..});
    if recorded != Error.none { pool_blot_check_core__Projection.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__Projection(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__ProjectionVariant___(writer: Writer&, value: const blot_check_core::ProjectionVariant[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__ProjectionVariant(writer, element, depth + 1); } }

fn read_blot_check_core__ProjectionVariant___(reader: Reader&, depth: i64) -> blot_check_core::ProjectionVariant[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__ProjectionVariant.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__ProjectionVariant { run , ..});
    if recorded != Error.none { pool_blot_check_core__ProjectionVariant.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__ProjectionVariant(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__Pattern___(writer: Writer&, value: const blot_check_core::Pattern[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__Pattern(writer, element, depth + 1); } }

fn read_blot_check_core__Pattern___(reader: Reader&, depth: i64) -> blot_check_core::Pattern[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__Pattern.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__Pattern { run , ..});
    if recorded != Error.none { pool_blot_check_core__Pattern.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__Pattern(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__PatternRow___(writer: Writer&, value: const blot_check_core::PatternRow[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__PatternRow(writer, element, depth + 1); } }

fn read_blot_check_core__PatternRow___(reader: Reader&, depth: i64) -> blot_check_core::PatternRow[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__PatternRow.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__PatternRow { run , ..});
    if recorded != Error.none { pool_blot_check_core__PatternRow.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__PatternRow(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__MatchArm___(writer: Writer&, value: const blot_check_core::MatchArm[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__MatchArm(writer, element, depth + 1); } }

fn read_blot_check_core__MatchArm___(reader: Reader&, depth: i64) -> blot_check_core::MatchArm[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__MatchArm.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__MatchArm { run , ..});
    if recorded != Error.none { pool_blot_check_core__MatchArm.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__MatchArm(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__MatchInfo___(writer: Writer&, value: const blot_check_core::MatchInfo[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__MatchInfo(writer, element, depth + 1); } }

fn read_blot_check_core__MatchInfo___(reader: Reader&, depth: i64) -> blot_check_core::MatchInfo[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__MatchInfo.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__MatchInfo { run , ..});
    if recorded != Error.none { pool_blot_check_core__MatchInfo.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__MatchInfo(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__UpdateInfo___(writer: Writer&, value: const blot_check_core::UpdateInfo[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__UpdateInfo(writer, element, depth + 1); } }

fn read_blot_check_core__UpdateInfo___(reader: Reader&, depth: i64) -> blot_check_core::UpdateInfo[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__UpdateInfo.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__UpdateInfo { run , ..});
    if recorded != Error.none { pool_blot_check_core__UpdateInfo.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__UpdateInfo(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__UpdateStep___(writer: Writer&, value: const blot_check_core::UpdateStep[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__UpdateStep(writer, element, depth + 1); } }

fn read_blot_check_core__UpdateStep___(reader: Reader&, depth: i64) -> blot_check_core::UpdateStep[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__UpdateStep.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__UpdateStep { run , ..});
    if recorded != Error.none { pool_blot_check_core__UpdateStep.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__UpdateStep(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__ClosureInfo___(writer: Writer&, value: const blot_check_core::ClosureInfo[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__ClosureInfo(writer, element, depth + 1); } }

fn read_blot_check_core__ClosureInfo___(reader: Reader&, depth: i64) -> blot_check_core::ClosureInfo[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__ClosureInfo.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__ClosureInfo { run , ..});
    if recorded != Error.none { pool_blot_check_core__ClosureInfo.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__ClosureInfo(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__Associated___(writer: Writer&, value: const blot_check_core::Associated[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__Associated(writer, element, depth + 1); } }

fn read_blot_check_core__Associated___(reader: Reader&, depth: i64) -> blot_check_core::Associated[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__Associated.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__Associated { run , ..});
    if recorded != Error.none { pool_blot_check_core__Associated.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__Associated(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__Contract___(writer: Writer&, value: const blot_check_core::Contract[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__Contract(writer, element, depth + 1); } }

fn read_blot_check_core__Contract___(reader: Reader&, depth: i64) -> blot_check_core::Contract[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__Contract.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__Contract { run , ..});
    if recorded != Error.none { pool_blot_check_core__Contract.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__Contract(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_reuse_principal_interface__ContractMember___(writer: Writer&, value: const blot_reuse_principal_interface::ContractMember[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_reuse_principal_interface__ContractMember(writer, element, depth + 1); } }

fn read_blot_reuse_principal_interface__ContractMember___(reader: Reader&, depth: i64) -> blot_reuse_principal_interface::ContractMember[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_reuse_principal_interface__ContractMember.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_reuse_principal_interface__ContractMember { run , ..});
    if recorded != Error.none { pool_blot_reuse_principal_interface__ContractMember.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_reuse_principal_interface__ContractMember(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_reuse_principal_interface__Implementation___(writer: Writer&, value: const blot_reuse_principal_interface::Implementation[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_reuse_principal_interface__Implementation(writer, element, depth + 1); } }

fn read_blot_reuse_principal_interface__Implementation___(reader: Reader&, depth: i64) -> blot_reuse_principal_interface::Implementation[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_reuse_principal_interface__Implementation.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_reuse_principal_interface__Implementation { run , ..});
    if recorded != Error.none { pool_blot_reuse_principal_interface__Implementation.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_reuse_principal_interface__Implementation(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_reuse_principal_interface__ImplementationMember___(writer: Writer&, value: const blot_reuse_principal_interface::ImplementationMember[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_reuse_principal_interface__ImplementationMember(writer, element, depth + 1); } }

fn read_blot_reuse_principal_interface__ImplementationMember___(reader: Reader&, depth: i64) -> blot_reuse_principal_interface::ImplementationMember[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_reuse_principal_interface__ImplementationMember.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_reuse_principal_interface__ImplementationMember { run , ..});
    if recorded != Error.none { pool_blot_reuse_principal_interface__ImplementationMember.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_reuse_principal_interface__ImplementationMember(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_reuse_principal_interface__MemberTemplate___(writer: Writer&, value: const blot_reuse_principal_interface::MemberTemplate[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_reuse_principal_interface__MemberTemplate(writer, element, depth + 1); } }

fn read_blot_reuse_principal_interface__MemberTemplate___(reader: Reader&, depth: i64) -> blot_reuse_principal_interface::MemberTemplate[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_reuse_principal_interface__MemberTemplate.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_reuse_principal_interface__MemberTemplate { run , ..});
    if recorded != Error.none { pool_blot_reuse_principal_interface__MemberTemplate.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_reuse_principal_interface__MemberTemplate(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_reuse_principal_interface__SelectedProof___(writer: Writer&, value: const blot_reuse_principal_interface::SelectedProof[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_reuse_principal_interface__SelectedProof(writer, element, depth + 1); } }

fn read_blot_reuse_principal_interface__SelectedProof___(reader: Reader&, depth: i64) -> blot_reuse_principal_interface::SelectedProof[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_reuse_principal_interface__SelectedProof.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_reuse_principal_interface__SelectedProof { run , ..});
    if recorded != Error.none { pool_blot_reuse_principal_interface__SelectedProof.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_reuse_principal_interface__SelectedProof(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__SelectedUse___(writer: Writer&, value: const blot_check_core::SelectedUse[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__SelectedUse(writer, element, depth + 1); } }

fn read_blot_check_core__SelectedUse___(reader: Reader&, depth: i64) -> blot_check_core::SelectedUse[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__SelectedUse.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__SelectedUse { run , ..});
    if recorded != Error.none { pool_blot_check_core__SelectedUse.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__SelectedUse(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__DictionarySelection___(writer: Writer&, value: const blot_check_core::DictionarySelection[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__DictionarySelection(writer, element, depth + 1); } }

fn read_blot_check_core__DictionarySelection___(reader: Reader&, depth: i64) -> blot_check_core::DictionarySelection[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__DictionarySelection.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__DictionarySelection { run , ..});
    if recorded != Error.none { pool_blot_check_core__DictionarySelection.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__DictionarySelection(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__DictionaryUse___(writer: Writer&, value: const blot_check_core::DictionaryUse[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__DictionaryUse(writer, element, depth + 1); } }

fn read_blot_check_core__DictionaryUse___(reader: Reader&, depth: i64) -> blot_check_core::DictionaryUse[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__DictionaryUse.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__DictionaryUse { run , ..});
    if recorded != Error.none { pool_blot_check_core__DictionaryUse.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__DictionaryUse(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__Primitive___(writer: Writer&, value: const blot_check_core::Primitive[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__Primitive(writer, element, depth + 1); } }

fn read_blot_check_core__Primitive___(reader: Reader&, depth: i64) -> blot_check_core::Primitive[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__Primitive.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__Primitive { run , ..});
    if recorded != Error.none { pool_blot_check_core__Primitive.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__Primitive(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__LoopInfo___(writer: Writer&, value: const blot_check_core::LoopInfo[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__LoopInfo(writer, element, depth + 1); } }

fn read_blot_check_core__LoopInfo___(reader: Reader&, depth: i64) -> blot_check_core::LoopInfo[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__LoopInfo.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__LoopInfo { run , ..});
    if recorded != Error.none { pool_blot_check_core__LoopInfo.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__LoopInfo(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__LoopCarry___(writer: Writer&, value: const blot_check_core::LoopCarry[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__LoopCarry(writer, element, depth + 1); } }

fn read_blot_check_core__LoopCarry___(reader: Reader&, depth: i64) -> blot_check_core::LoopCarry[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__LoopCarry.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__LoopCarry { run , ..});
    if recorded != Error.none { pool_blot_check_core__LoopCarry.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__LoopCarry(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__ResolverInfo___(writer: Writer&, value: const blot_check_core::ResolverInfo[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__ResolverInfo(writer, element, depth + 1); } }

fn read_blot_check_core__ResolverInfo___(reader: Reader&, depth: i64) -> blot_check_core::ResolverInfo[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__ResolverInfo.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__ResolverInfo { run , ..});
    if recorded != Error.none { pool_blot_check_core__ResolverInfo.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__ResolverInfo(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__OperationValue___(writer: Writer&, value: const blot_check_core::OperationValue[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__OperationValue(writer, element, depth + 1); } }

fn read_blot_check_core__OperationValue___(reader: Reader&, depth: i64) -> blot_check_core::OperationValue[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__OperationValue.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__OperationValue { run , ..});
    if recorded != Error.none { pool_blot_check_core__OperationValue.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__OperationValue(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__HandleEffects___(writer: Writer&, value: const blot_check_core::HandleEffects[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__HandleEffects(writer, element, depth + 1); } }

fn read_blot_check_core__HandleEffects___(reader: Reader&, depth: i64) -> blot_check_core::HandleEffects[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__HandleEffects.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__HandleEffects { run , ..});
    if recorded != Error.none { pool_blot_check_core__HandleEffects.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__HandleEffects(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_check_core__Diagnostic___(writer: Writer&, value: const blot_check_core::Diagnostic[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__Diagnostic(writer, element, depth + 1); } }

fn read_blot_check_core__Diagnostic___(reader: Reader&, depth: i64) -> blot_check_core::Diagnostic[:], Error {
    let charged = debit(reader, depth); if charged != Error.none { return [], charged; }
    let count, error = get(reader, 8); if error != Error.none { return [], error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return [], Error.artifact_limit; } if count == 0 { return [], Error.none; }
    let run = pool_blot_check_core__Diagnostic.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__Diagnostic { run , ..});
    if recorded != Error.none { pool_blot_check_core__Diagnostic.free_slice(run); return [], recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__Diagnostic(reader, depth + 1); if failure != Error.none { return [], failure; } run[index] = value; } return run, Error.none;
}

fn write_blot_support__Option_blot_check_numeric_proof_terms__Proposition_(writer: Writer&, value: blot_support::Option<blot_check_numeric_proof_terms::Proposition>, depth: i64) { if !charge(writer, depth) { return; } write_bool(writer, value.present, depth + 1); if value.present { write_blot_check_numeric_proof_terms__Proposition(writer, value.value, depth + 1); } }

fn read_blot_support__Option_blot_check_numeric_proof_terms__Proposition_(reader: Reader&, depth: i64) -> blot_support::Option<blot_check_numeric_proof_terms::Proposition>, Error { var result = blot_support::none<blot_check_numeric_proof_terms::Proposition>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; } let present, error = read_bool(reader, depth + 1); if error != Error.none { return result, error; } if present { let value, failure = read_blot_check_numeric_proof_terms__Proposition(reader, depth + 1); if failure != Error.none { return result, failure; } result = blot_support::some(value); } return result, Error.none; }

fn write_blot_support__Option_blot_parse_ast__Span_(writer: Writer&, value: blot_support::Option<blot_parse_ast::Span>, depth: i64) { if !charge(writer, depth) { return; } write_bool(writer, value.present, depth + 1); if value.present { write_blot_parse_ast__Span(writer, value.value, depth + 1); } }

fn read_blot_support__Option_blot_parse_ast__Span_(reader: Reader&, depth: i64) -> blot_support::Option<blot_parse_ast::Span>, Error { var result = blot_support::none<blot_parse_ast::Span>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; } let present, error = read_bool(reader, depth + 1); if error != Error.none { return result, error; } if present { let value, failure = read_blot_parse_ast__Span(reader, depth + 1); if failure != Error.none { return result, failure; } result = blot_support::some(value); } return result, Error.none; }

fn write_blot_check_core__Module(writer: Writer&, value: blot_check_core::Module, depth: i64) {
    if !charge(writer, depth) { return; }

    write_bool(writer, value.has_rank_contracts, depth + 1);

    write_bool(writer, value.has_usage_contracts, depth + 1);

    write_bool(writer, value.has_numeric_proofs, depth + 1);

    write_blot_check_numeric_proof_headers__Named___(writer, value.proof_contracts, depth + 1);

    write_blot_check_capability_contracts__Collection(writer, value.capability_contracts, depth + 1);

    write_blot_check_core__FieldName___(writer, value.field_names, depth + 1);

    write_blot_check_core__RuntimeName___(writer, value.runtime_names, depth + 1);

    write_blot_check_core__RuntimeName___(writer, value.source_names, depth + 1);

    write_blot_check_core__DeclarationDependencies___(writer, value.declaration_dependencies, depth + 1);

    write_blot_check_core__BindingRef___(writer, value.dependency_references, depth + 1);

    write_blot_check_core__DependencyMember___(writer, value.dependency_members, depth + 1);

    write_blot_check_core__ErasedDeclarationReference___(writer, value.erased_declaration_references, depth + 1);

    write_blot_check_core__RequestLoopInfo___(writer, value.request_loops, depth + 1);

    write_blot_check_core__RequestArm___(writer, value.request_arms, depth + 1);

    write_u32___(writer, value.tag_calls, depth + 1);

    write_u32(writer, value.unit, depth + 1);

    write_blot_check_core__Types(writer, value.types, depth + 1);

    write_blot_check_core__Node___(writer, value.nodes, depth + 1);

    write_blot_parse_ast__Span___(writer, value.spans, depth + 1);

    write_u32___(writer, value.extra, depth + 1);

    write_blot_check_core__Binding___(writer, value.bindings, depth + 1);

    write_blot_check_core__Body___(writer, value.bodies, depth + 1);

    write_blot_check_core__Parameter___(writer, value.parameters, depth + 1);

    write_blot_check_core__BindingRef___(writer, value.references, depth + 1);

    write_blot_check_core__CallInfo___(writer, value.calls, depth + 1);

    write_blot_check_core__Merge___(writer, value.merges, depth + 1);

    write_blot_check_core__List___(writer, value.merge_ranges, depth + 1);

    write_u8___(writer, value.names, depth + 1);

    write_blot_check_core__Obligation___(writer, value.obligations, depth + 1);

    write_blot_check_core__Nominal___(writer, value.nominals, depth + 1);

    write_blot_check_core__OperationName___(writer, value.operation_names, depth + 1);

    write_blot_check_core__Constructor___(writer, value.constructors, depth + 1);

    write_blot_check_core__Projection___(writer, value.projections, depth + 1);

    write_blot_check_core__ProjectionVariant___(writer, value.projection_variants, depth + 1);

    write_blot_check_core__Pattern___(writer, value.patterns, depth + 1);

    write_blot_check_core__PatternRow___(writer, value.pattern_rows, depth + 1);

    write_blot_check_core__MatchArm___(writer, value.match_arms, depth + 1);

    write_blot_check_core__MatchInfo___(writer, value.matches, depth + 1);

    write_blot_check_core__UpdateInfo___(writer, value.updates, depth + 1);

    write_blot_check_core__UpdateStep___(writer, value.update_steps, depth + 1);

    write_blot_check_core__ClosureInfo___(writer, value.closures, depth + 1);

    write_blot_check_core__Associated___(writer, value.associated, depth + 1);

    write_blot_check_core__Contract___(writer, value.contracts, depth + 1);

    write_blot_reuse_principal_interface__ContractMember___(writer, value.contract_members, depth + 1);

    write_blot_reuse_principal_interface__Implementation___(writer, value.implementations, depth + 1);

    write_blot_reuse_principal_interface__ImplementationMember___(writer, value.implementation_members, depth + 1);

    write_blot_reuse_principal_interface__MemberTemplate___(writer, value.member_templates, depth + 1);

    write_blot_reuse_principal_interface__SelectedProof___(writer, value.selected_proofs, depth + 1);

    write_blot_reuse_principal_interface__ImplementationMember___(writer, value.selected_members, depth + 1);

    write_u32___(writer, value.selected_edges, depth + 1);

    write_blot_check_core__SelectedUse___(writer, value.selected_uses, depth + 1);

    write_blot_check_core__DictionarySelection___(writer, value.dictionary_selections, depth + 1);

    write_blot_check_core__DictionaryUse___(writer, value.dictionary_uses, depth + 1);

    write_blot_check_core__Primitive___(writer, value.primitives, depth + 1);

    write_blot_check_core__LoopInfo___(writer, value.loops, depth + 1);

    write_blot_check_core__LoopCarry___(writer, value.loop_carries, depth + 1);

    write_blot_check_core__ResolverInfo___(writer, value.resolver_ops, depth + 1);

    write_blot_check_core__OperationValue___(writer, value.operation_values, depth + 1);

    write_blot_check_core__HandleEffects___(writer, value.handle_effects, depth + 1);

    write_u32___(writer, value.dispatch_signatures, depth + 1);

    write_blot_check_core__Diagnostic___(writer, value.diagnostics, depth + 1);

    write_i64(writer, value.body_lowerings, depth + 1);

}

fn read_blot_check_core__Module(reader: Reader&, depth: i64) -> blot_check_core::Module, Error {
    var result = default<blot_check_core::Module>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_bool(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.has_rank_contracts = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.has_usage_contracts = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.has_numeric_proofs = decoded; }

    { let decoded, error = read_blot_check_numeric_proof_headers__Named___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.proof_contracts = decoded; }

    { let decoded, error = read_blot_check_capability_contracts__Collection(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.capability_contracts = decoded; }

    { let decoded, error = read_blot_check_core__FieldName___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.field_names = decoded; }

    { let decoded, error = read_blot_check_core__RuntimeName___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.runtime_names = decoded; }

    { let decoded, error = read_blot_check_core__RuntimeName___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.source_names = decoded; }

    { let decoded, error = read_blot_check_core__DeclarationDependencies___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.declaration_dependencies = decoded; }

    { let decoded, error = read_blot_check_core__BindingRef___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.dependency_references = decoded; }

    { let decoded, error = read_blot_check_core__DependencyMember___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.dependency_members = decoded; }

    { let decoded, error = read_blot_check_core__ErasedDeclarationReference___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.erased_declaration_references = decoded; }

    { let decoded, error = read_blot_check_core__RequestLoopInfo___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.request_loops = decoded; }

    { let decoded, error = read_blot_check_core__RequestArm___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.request_arms = decoded; }

    { let decoded, error = read_u32___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.tag_calls = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.unit = decoded; }

    { let decoded, error = read_blot_check_core__Types(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.types = decoded; }

    { let decoded, error = read_blot_check_core__Node___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.nodes = decoded; }

    { let decoded, error = read_blot_parse_ast__Span___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.spans = decoded; }

    { let decoded, error = read_u32___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.extra = decoded; }

    { let decoded, error = read_blot_check_core__Binding___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.bindings = decoded; }

    { let decoded, error = read_blot_check_core__Body___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.bodies = decoded; }

    { let decoded, error = read_blot_check_core__Parameter___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.parameters = decoded; }

    { let decoded, error = read_blot_check_core__BindingRef___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.references = decoded; }

    { let decoded, error = read_blot_check_core__CallInfo___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.calls = decoded; }

    { let decoded, error = read_blot_check_core__Merge___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.merges = decoded; }

    { let decoded, error = read_blot_check_core__List___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.merge_ranges = decoded; }

    { let decoded, error = read_u8___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.names = decoded; }

    { let decoded, error = read_blot_check_core__Obligation___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.obligations = decoded; }

    { let decoded, error = read_blot_check_core__Nominal___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.nominals = decoded; }

    { let decoded, error = read_blot_check_core__OperationName___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.operation_names = decoded; }

    { let decoded, error = read_blot_check_core__Constructor___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.constructors = decoded; }

    { let decoded, error = read_blot_check_core__Projection___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.projections = decoded; }

    { let decoded, error = read_blot_check_core__ProjectionVariant___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.projection_variants = decoded; }

    { let decoded, error = read_blot_check_core__Pattern___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.patterns = decoded; }

    { let decoded, error = read_blot_check_core__PatternRow___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.pattern_rows = decoded; }

    { let decoded, error = read_blot_check_core__MatchArm___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.match_arms = decoded; }

    { let decoded, error = read_blot_check_core__MatchInfo___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.matches = decoded; }

    { let decoded, error = read_blot_check_core__UpdateInfo___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.updates = decoded; }

    { let decoded, error = read_blot_check_core__UpdateStep___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.update_steps = decoded; }

    { let decoded, error = read_blot_check_core__ClosureInfo___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.closures = decoded; }

    { let decoded, error = read_blot_check_core__Associated___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.associated = decoded; }

    { let decoded, error = read_blot_check_core__Contract___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.contracts = decoded; }

    { let decoded, error = read_blot_reuse_principal_interface__ContractMember___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.contract_members = decoded; }

    { let decoded, error = read_blot_reuse_principal_interface__Implementation___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.implementations = decoded; }

    { let decoded, error = read_blot_reuse_principal_interface__ImplementationMember___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.implementation_members = decoded; }

    { let decoded, error = read_blot_reuse_principal_interface__MemberTemplate___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.member_templates = decoded; }

    { let decoded, error = read_blot_reuse_principal_interface__SelectedProof___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.selected_proofs = decoded; }

    { let decoded, error = read_blot_reuse_principal_interface__ImplementationMember___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.selected_members = decoded; }

    { let decoded, error = read_u32___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.selected_edges = decoded; }

    { let decoded, error = read_blot_check_core__SelectedUse___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.selected_uses = decoded; }

    { let decoded, error = read_blot_check_core__DictionarySelection___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.dictionary_selections = decoded; }

    { let decoded, error = read_blot_check_core__DictionaryUse___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.dictionary_uses = decoded; }

    { let decoded, error = read_blot_check_core__Primitive___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.primitives = decoded; }

    { let decoded, error = read_blot_check_core__LoopInfo___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.loops = decoded; }

    { let decoded, error = read_blot_check_core__LoopCarry___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.loop_carries = decoded; }

    { let decoded, error = read_blot_check_core__ResolverInfo___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.resolver_ops = decoded; }

    { let decoded, error = read_blot_check_core__OperationValue___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.operation_values = decoded; }

    { let decoded, error = read_blot_check_core__HandleEffects___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.handle_effects = decoded; }

    { let decoded, error = read_u32___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.dispatch_signatures = decoded; }

    { let decoded, error = read_blot_check_core__Diagnostic___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.diagnostics = decoded; }

    { let decoded, error = read_i64(reader, depth + 1); if error != Error.none { return default<blot_check_core::Module>(), error; } result.body_lowerings = decoded; }

    return result, Error.none;
}

fn write_blot_check_numeric_proof_headers__Named(writer: Writer&, value: blot_check_numeric_proof_headers::Named, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.binding, depth + 1);

    write_blot_check_numeric_proof_headers__Owned(writer, value.header, depth + 1);

}

fn read_blot_check_numeric_proof_headers__Named(reader: Reader&, depth: i64) -> blot_check_numeric_proof_headers::Named, Error {
    var result = default<blot_check_numeric_proof_headers::Named>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_numeric_proof_headers::Named>(), error; } result.binding = decoded; }

    { let decoded, error = read_blot_check_numeric_proof_headers__Owned(reader, depth + 1); if error != Error.none { return default<blot_check_numeric_proof_headers::Named>(), error; } result.header = decoded; }

    return result, Error.none;
}

fn write_blot_check_numeric_proof_headers__Owned(writer: Writer&, value: blot_check_numeric_proof_headers::Owned, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.arity, depth + 1);

    write_u32___(writer, value.value_slots, depth + 1);

    write_u32___(writer, value.proof_slots, depth + 1);

    write_blot_check_numeric_proof_terms__Kind___(writer, value.values, depth + 1);

    write_blot_check_numeric_proof_terms__Term___(writer, value.operands, depth + 1);

    write_blot_check_numeric_proof_contracts__Requirement___(writer, value.requirements, depth + 1);

    write_blot_support__Option_blot_check_numeric_proof_terms__Proposition_(writer, value.result, depth + 1);

}

fn read_blot_check_numeric_proof_headers__Owned(reader: Reader&, depth: i64) -> blot_check_numeric_proof_headers::Owned, Error {
    var result = default<blot_check_numeric_proof_headers::Owned>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_numeric_proof_headers::Owned>(), error; } result.arity = decoded; }

    { let decoded, error = read_u32___(reader, depth + 1); if error != Error.none { return default<blot_check_numeric_proof_headers::Owned>(), error; } result.value_slots = decoded; }

    { let decoded, error = read_u32___(reader, depth + 1); if error != Error.none { return default<blot_check_numeric_proof_headers::Owned>(), error; } result.proof_slots = decoded; }

    { let decoded, error = read_blot_check_numeric_proof_terms__Kind___(reader, depth + 1); if error != Error.none { return default<blot_check_numeric_proof_headers::Owned>(), error; } result.values = decoded; }

    { let decoded, error = read_blot_check_numeric_proof_terms__Term___(reader, depth + 1); if error != Error.none { return default<blot_check_numeric_proof_headers::Owned>(), error; } result.operands = decoded; }

    { let decoded, error = read_blot_check_numeric_proof_contracts__Requirement___(reader, depth + 1); if error != Error.none { return default<blot_check_numeric_proof_headers::Owned>(), error; } result.requirements = decoded; }

    { let decoded, error = read_blot_support__Option_blot_check_numeric_proof_terms__Proposition_(reader, depth + 1); if error != Error.none { return default<blot_check_numeric_proof_headers::Owned>(), error; } result.result = decoded; }

    return result, Error.none;
}

fn write_blot_check_numeric_proof_terms__Kind(writer: Writer&, value: blot_check_numeric_proof_terms::Kind, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        blot_check_numeric_proof_terms::Kind.unsigned32 => { put(writer, 0, 4); 
},

        blot_check_numeric_proof_terms::Kind.array => { put(writer, 1, 4); 
},

        blot_check_numeric_proof_terms::Kind.list => { put(writer, 2, 4); 
},

    }
}

fn read_blot_check_numeric_proof_terms__Kind(reader: Reader&, depth: i64) -> blot_check_numeric_proof_terms::Kind, Error {
    let charged = debit(reader, depth); if charged != Error.none { return default<blot_check_numeric_proof_terms::Kind>(), charged; } let tag, error = get(reader, 4); if error != Error.none { return default<blot_check_numeric_proof_terms::Kind>(), error; }
    match tag {

        0 => { 
return blot_check_numeric_proof_terms::Kind.unsigned32, Error.none; },

        1 => { 
return blot_check_numeric_proof_terms::Kind.array, Error.none; },

        2 => { 
return blot_check_numeric_proof_terms::Kind.list, Error.none; },

        _ => { return default<blot_check_numeric_proof_terms::Kind>(), Error.invalid_artifact; },
    }
}

fn write_blot_check_numeric_proof_terms__Term(writer: Writer&, value: blot_check_numeric_proof_terms::Term, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_numeric_proof_terms__Tag(writer, value.tag, depth + 1);

    write_blot_check_numeric_proof_terms__Kind(writer, value.kind, depth + 1);

    write_u32(writer, value.a, depth + 1);

    write_u32(writer, value.b, depth + 1);

}

fn read_blot_check_numeric_proof_terms__Term(reader: Reader&, depth: i64) -> blot_check_numeric_proof_terms::Term, Error {
    var result = default<blot_check_numeric_proof_terms::Term>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_numeric_proof_terms__Tag(reader, depth + 1); if error != Error.none { return default<blot_check_numeric_proof_terms::Term>(), error; } result.tag = decoded; }

    { let decoded, error = read_blot_check_numeric_proof_terms__Kind(reader, depth + 1); if error != Error.none { return default<blot_check_numeric_proof_terms::Term>(), error; } result.kind = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_numeric_proof_terms::Term>(), error; } result.a = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_numeric_proof_terms::Term>(), error; } result.b = decoded; }

    return result, Error.none;
}

fn write_blot_check_numeric_proof_terms__Tag(writer: Writer&, value: blot_check_numeric_proof_terms::Tag, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        blot_check_numeric_proof_terms::Tag.literal => { put(writer, 0, 4); 
},

        blot_check_numeric_proof_terms::Tag.formal => { put(writer, 1, 4); 
},

        blot_check_numeric_proof_terms::Tag.capture => { put(writer, 2, 4); 
},

        blot_check_numeric_proof_terms::Tag.version => { put(writer, 3, 4); 
},

        blot_check_numeric_proof_terms::Tag.length => { put(writer, 4, 4); 
},

        blot_check_numeric_proof_terms::Tag.complement => { put(writer, 5, 4); 
},

    }
}

fn read_blot_check_numeric_proof_terms__Tag(reader: Reader&, depth: i64) -> blot_check_numeric_proof_terms::Tag, Error {
    let charged = debit(reader, depth); if charged != Error.none { return default<blot_check_numeric_proof_terms::Tag>(), charged; } let tag, error = get(reader, 4); if error != Error.none { return default<blot_check_numeric_proof_terms::Tag>(), error; }
    match tag {

        0 => { 
return blot_check_numeric_proof_terms::Tag.literal, Error.none; },

        1 => { 
return blot_check_numeric_proof_terms::Tag.formal, Error.none; },

        2 => { 
return blot_check_numeric_proof_terms::Tag.capture, Error.none; },

        3 => { 
return blot_check_numeric_proof_terms::Tag.version, Error.none; },

        4 => { 
return blot_check_numeric_proof_terms::Tag.length, Error.none; },

        5 => { 
return blot_check_numeric_proof_terms::Tag.complement, Error.none; },

        _ => { return default<blot_check_numeric_proof_terms::Tag>(), Error.invalid_artifact; },
    }
}

fn write_blot_check_numeric_proof_contracts__Requirement(writer: Writer&, value: blot_check_numeric_proof_contracts::Requirement, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.before, depth + 1);

    write_blot_check_numeric_proof_terms__Proposition(writer, value.proposition, depth + 1);

}

fn read_blot_check_numeric_proof_contracts__Requirement(reader: Reader&, depth: i64) -> blot_check_numeric_proof_contracts::Requirement, Error {
    var result = default<blot_check_numeric_proof_contracts::Requirement>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_numeric_proof_contracts::Requirement>(), error; } result.before = decoded; }

    { let decoded, error = read_blot_check_numeric_proof_terms__Proposition(reader, depth + 1); if error != Error.none { return default<blot_check_numeric_proof_contracts::Requirement>(), error; } result.proposition = decoded; }

    return result, Error.none;
}

fn write_blot_check_numeric_proof_terms__Proposition(writer: Writer&, value: blot_check_numeric_proof_terms::Proposition, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_numeric_proof_terms__Relation(writer, value.relation, depth + 1);

    write_u32(writer, value.left, depth + 1);

    write_u32(writer, value.right, depth + 1);

}

fn read_blot_check_numeric_proof_terms__Proposition(reader: Reader&, depth: i64) -> blot_check_numeric_proof_terms::Proposition, Error {
    var result = default<blot_check_numeric_proof_terms::Proposition>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_numeric_proof_terms__Relation(reader, depth + 1); if error != Error.none { return default<blot_check_numeric_proof_terms::Proposition>(), error; } result.relation = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_numeric_proof_terms::Proposition>(), error; } result.left = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_numeric_proof_terms::Proposition>(), error; } result.right = decoded; }

    return result, Error.none;
}

fn write_blot_check_numeric_proof_terms__Relation(writer: Writer&, value: blot_check_numeric_proof_terms::Relation, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        blot_check_numeric_proof_terms::Relation.eq => { put(writer, 0, 4); 
},

        blot_check_numeric_proof_terms::Relation.lt => { put(writer, 1, 4); 
},

        blot_check_numeric_proof_terms::Relation.le => { put(writer, 2, 4); 
},

        blot_check_numeric_proof_terms::Relation.add_fits => { put(writer, 3, 4); 
},

        blot_check_numeric_proof_terms::Relation.sub_fits => { put(writer, 4, 4); 
},

        blot_check_numeric_proof_terms::Relation.index => { put(writer, 5, 4); 
},

    }
}

fn read_blot_check_numeric_proof_terms__Relation(reader: Reader&, depth: i64) -> blot_check_numeric_proof_terms::Relation, Error {
    let charged = debit(reader, depth); if charged != Error.none { return default<blot_check_numeric_proof_terms::Relation>(), charged; } let tag, error = get(reader, 4); if error != Error.none { return default<blot_check_numeric_proof_terms::Relation>(), error; }
    match tag {

        0 => { 
return blot_check_numeric_proof_terms::Relation.eq, Error.none; },

        1 => { 
return blot_check_numeric_proof_terms::Relation.lt, Error.none; },

        2 => { 
return blot_check_numeric_proof_terms::Relation.le, Error.none; },

        3 => { 
return blot_check_numeric_proof_terms::Relation.add_fits, Error.none; },

        4 => { 
return blot_check_numeric_proof_terms::Relation.sub_fits, Error.none; },

        5 => { 
return blot_check_numeric_proof_terms::Relation.index, Error.none; },

        _ => { return default<blot_check_numeric_proof_terms::Relation>(), Error.invalid_artifact; },
    }
}

fn write_blot_check_capability_contracts__Collection(writer: Writer&, value: blot_check_capability_contracts::Collection, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_capability_contracts__Term___(writer, value.nodes, depth + 1);

    write_u32___(writer, value.words, depth + 1);

    write_blot_check_capability_contracts__Binding___(writer, value.bindings, depth + 1);

}

fn read_blot_check_capability_contracts__Collection(reader: Reader&, depth: i64) -> blot_check_capability_contracts::Collection, Error {
    var result = default<blot_check_capability_contracts::Collection>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_capability_contracts__Term___(reader, depth + 1); if error != Error.none { return default<blot_check_capability_contracts::Collection>(), error; } result.nodes = decoded; }

    { let decoded, error = read_u32___(reader, depth + 1); if error != Error.none { return default<blot_check_capability_contracts::Collection>(), error; } result.words = decoded; }

    { let decoded, error = read_blot_check_capability_contracts__Binding___(reader, depth + 1); if error != Error.none { return default<blot_check_capability_contracts::Collection>(), error; } result.bindings = decoded; }

    return result, Error.none;
}

fn write_blot_check_capability_contracts__Term(writer: Writer&, value: blot_check_capability_contracts::Term, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_capability_contracts__Tag(writer, value.tag, depth + 1);

    write_u32(writer, value.a, depth + 1);

    write_u32(writer, value.b, depth + 1);

    write_u32(writer, value.c, depth + 1);

}

fn read_blot_check_capability_contracts__Term(reader: Reader&, depth: i64) -> blot_check_capability_contracts::Term, Error {
    var result = default<blot_check_capability_contracts::Term>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_capability_contracts__Tag(reader, depth + 1); if error != Error.none { return default<blot_check_capability_contracts::Term>(), error; } result.tag = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_capability_contracts::Term>(), error; } result.a = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_capability_contracts::Term>(), error; } result.b = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_capability_contracts::Term>(), error; } result.c = decoded; }

    return result, Error.none;
}

fn write_blot_check_capability_contracts__Tag(writer: Writer&, value: blot_check_capability_contracts::Tag, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        blot_check_capability_contracts::Tag.empty => { put(writer, 0, 4); 
},

        blot_check_capability_contracts::Tag.unknown => { put(writer, 1, 4); 
},

        blot_check_capability_contracts::Tag.parameter => { put(writer, 2, 4); 
},

        blot_check_capability_contracts::Tag.authority => { put(writer, 3, 4); 
},

        blot_check_capability_contracts::Tag.captures => { put(writer, 4, 4); 
},

        blot_check_capability_contracts::Tag.product => { put(writer, 5, 4); 
},

        blot_check_capability_contracts::Tag.record => { put(writer, 6, 4); 
},

        blot_check_capability_contracts::Tag.wrapped => { put(writer, 7, 4); 
},

        blot_check_capability_contracts::Tag.join => { put(writer, 8, 4); 
},

        blot_check_capability_contracts::Tag.project => { put(writer, 9, 4); 
},

        blot_check_capability_contracts::Tag.elements => { put(writer, 10, 4); 
},

        blot_check_capability_contracts::Tag.argument => { put(writer, 11, 4); 
},

        blot_check_capability_contracts::Tag.callable => { put(writer, 12, 4); 
},

    }
}

fn read_blot_check_capability_contracts__Tag(reader: Reader&, depth: i64) -> blot_check_capability_contracts::Tag, Error {
    let charged = debit(reader, depth); if charged != Error.none { return default<blot_check_capability_contracts::Tag>(), charged; } let tag, error = get(reader, 4); if error != Error.none { return default<blot_check_capability_contracts::Tag>(), error; }
    match tag {

        0 => { 
return blot_check_capability_contracts::Tag.empty, Error.none; },

        1 => { 
return blot_check_capability_contracts::Tag.unknown, Error.none; },

        2 => { 
return blot_check_capability_contracts::Tag.parameter, Error.none; },

        3 => { 
return blot_check_capability_contracts::Tag.authority, Error.none; },

        4 => { 
return blot_check_capability_contracts::Tag.captures, Error.none; },

        5 => { 
return blot_check_capability_contracts::Tag.product, Error.none; },

        6 => { 
return blot_check_capability_contracts::Tag.record, Error.none; },

        7 => { 
return blot_check_capability_contracts::Tag.wrapped, Error.none; },

        8 => { 
return blot_check_capability_contracts::Tag.join, Error.none; },

        9 => { 
return blot_check_capability_contracts::Tag.project, Error.none; },

        10 => { 
return blot_check_capability_contracts::Tag.elements, Error.none; },

        11 => { 
return blot_check_capability_contracts::Tag.argument, Error.none; },

        12 => { 
return blot_check_capability_contracts::Tag.callable, Error.none; },

        _ => { return default<blot_check_capability_contracts::Tag>(), Error.invalid_artifact; },
    }
}

fn write_blot_check_capability_contracts__Binding(writer: Writer&, value: blot_check_capability_contracts::Binding, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.binding, depth + 1);

    write_u32(writer, value.root, depth + 1);

}

fn read_blot_check_capability_contracts__Binding(reader: Reader&, depth: i64) -> blot_check_capability_contracts::Binding, Error {
    var result = default<blot_check_capability_contracts::Binding>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_capability_contracts::Binding>(), error; } result.binding = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_capability_contracts::Binding>(), error; } result.root = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__FieldName(writer: Writer&, value: blot_check_core::FieldName, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.symbol, depth + 1);

    write_blot_check_core__Name(writer, value.spelling, depth + 1);

}

fn read_blot_check_core__FieldName(reader: Reader&, depth: i64) -> blot_check_core::FieldName, Error {
    var result = default<blot_check_core::FieldName>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::FieldName>(), error; } result.symbol = decoded; }

    { let decoded, error = read_blot_check_core__Name(reader, depth + 1); if error != Error.none { return default<blot_check_core::FieldName>(), error; } result.spelling = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__Name(writer: Writer&, value: blot_check_core::Name, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.start, depth + 1);

    write_u32(writer, value.len, depth + 1);

}

fn read_blot_check_core__Name(reader: Reader&, depth: i64) -> blot_check_core::Name, Error {
    var result = default<blot_check_core::Name>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Name>(), error; } result.start = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Name>(), error; } result.len = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__RuntimeName(writer: Writer&, value: blot_check_core::RuntimeName, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.binding, depth + 1);

    write_u32(writer, value.point, depth + 1);

}

fn read_blot_check_core__RuntimeName(reader: Reader&, depth: i64) -> blot_check_core::RuntimeName, Error {
    var result = default<blot_check_core::RuntimeName>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::RuntimeName>(), error; } result.binding = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::RuntimeName>(), error; } result.point = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__DeclarationDependencies(writer: Writer&, value: blot_check_core::DeclarationDependencies, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_core__List(writer, value.references, depth + 1);

    write_blot_check_core__List(writer, value.members, depth + 1);

    write_u32(writer, value.runtime_metadata, depth + 1);

}

fn read_blot_check_core__DeclarationDependencies(reader: Reader&, depth: i64) -> blot_check_core::DeclarationDependencies, Error {
    var result = default<blot_check_core::DeclarationDependencies>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::DeclarationDependencies>(), error; } result.references = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::DeclarationDependencies>(), error; } result.members = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::DeclarationDependencies>(), error; } result.runtime_metadata = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__List(writer: Writer&, value: blot_check_core::List, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.start, depth + 1);

    write_u32(writer, value.len, depth + 1);

}

fn read_blot_check_core__List(reader: Reader&, depth: i64) -> blot_check_core::List, Error {
    var result = default<blot_check_core::List>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::List>(), error; } result.start = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::List>(), error; } result.len = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__BindingRef(writer: Writer&, value: blot_check_core::BindingRef, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.unit, depth + 1);

    write_u32(writer, value.binding, depth + 1);

}

fn read_blot_check_core__BindingRef(reader: Reader&, depth: i64) -> blot_check_core::BindingRef, Error {
    var result = default<blot_check_core::BindingRef>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::BindingRef>(), error; } result.unit = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::BindingRef>(), error; } result.binding = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__DependencyMember(writer: Writer&, value: blot_check_core::DependencyMember, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.name, depth + 1);

    write_blot_check_types__Operator(writer, value.operator, depth + 1);

}

fn read_blot_check_core__DependencyMember(reader: Reader&, depth: i64) -> blot_check_core::DependencyMember, Error {
    var result = default<blot_check_core::DependencyMember>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::DependencyMember>(), error; } result.name = decoded; }

    { let decoded, error = read_blot_check_types__Operator(reader, depth + 1); if error != Error.none { return default<blot_check_core::DependencyMember>(), error; } result.operator = decoded; }

    return result, Error.none;
}

fn write_blot_check_types__Operator(writer: Writer&, value: blot_check_types::Operator, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        blot_check_types::Operator.none => { put(writer, 0, 4); 
},

        blot_check_types::Operator.add => { put(writer, 1, 4); 
},

        blot_check_types::Operator.sub => { put(writer, 2, 4); 
},

        blot_check_types::Operator.mul => { put(writer, 3, 4); 
},

        blot_check_types::Operator.div => { put(writer, 4, 4); 
},

        blot_check_types::Operator.rem => { put(writer, 5, 4); 
},

        blot_check_types::Operator.equal => { put(writer, 6, 4); 
},

        blot_check_types::Operator.not_equal => { put(writer, 7, 4); 
},

        blot_check_types::Operator.less => { put(writer, 8, 4); 
},

        blot_check_types::Operator.less_equal => { put(writer, 9, 4); 
},

        blot_check_types::Operator.greater => { put(writer, 10, 4); 
},

        blot_check_types::Operator.greater_equal => { put(writer, 11, 4); 
},

        blot_check_types::Operator.bit_and => { put(writer, 12, 4); 
},

        blot_check_types::Operator.bit_or => { put(writer, 13, 4); 
},

        blot_check_types::Operator.bit_xor => { put(writer, 14, 4); 
},

        blot_check_types::Operator.shift_left => { put(writer, 15, 4); 
},

        blot_check_types::Operator.shift_right => { put(writer, 16, 4); 
},

    }
}

fn read_blot_check_types__Operator(reader: Reader&, depth: i64) -> blot_check_types::Operator, Error {
    let charged = debit(reader, depth); if charged != Error.none { return default<blot_check_types::Operator>(), charged; } let tag, error = get(reader, 4); if error != Error.none { return default<blot_check_types::Operator>(), error; }
    match tag {

        0 => { 
return blot_check_types::Operator.none, Error.none; },

        1 => { 
return blot_check_types::Operator.add, Error.none; },

        2 => { 
return blot_check_types::Operator.sub, Error.none; },

        3 => { 
return blot_check_types::Operator.mul, Error.none; },

        4 => { 
return blot_check_types::Operator.div, Error.none; },

        5 => { 
return blot_check_types::Operator.rem, Error.none; },

        6 => { 
return blot_check_types::Operator.equal, Error.none; },

        7 => { 
return blot_check_types::Operator.not_equal, Error.none; },

        8 => { 
return blot_check_types::Operator.less, Error.none; },

        9 => { 
return blot_check_types::Operator.less_equal, Error.none; },

        10 => { 
return blot_check_types::Operator.greater, Error.none; },

        11 => { 
return blot_check_types::Operator.greater_equal, Error.none; },

        12 => { 
return blot_check_types::Operator.bit_and, Error.none; },

        13 => { 
return blot_check_types::Operator.bit_or, Error.none; },

        14 => { 
return blot_check_types::Operator.bit_xor, Error.none; },

        15 => { 
return blot_check_types::Operator.shift_left, Error.none; },

        16 => { 
return blot_check_types::Operator.shift_right, Error.none; },

        _ => { return default<blot_check_types::Operator>(), Error.invalid_artifact; },
    }
}

fn write_blot_check_core__ErasedDeclarationReference(writer: Writer&, value: blot_check_core::ErasedDeclarationReference, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.node, depth + 1);

    write_blot_check_core__BindingRef(writer, value.target, depth + 1);

}

fn read_blot_check_core__ErasedDeclarationReference(reader: Reader&, depth: i64) -> blot_check_core::ErasedDeclarationReference, Error {
    var result = default<blot_check_core::ErasedDeclarationReference>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::ErasedDeclarationReference>(), error; } result.node = decoded; }

    { let decoded, error = read_blot_check_core__BindingRef(reader, depth + 1); if error != Error.none { return default<blot_check_core::ErasedDeclarationReference>(), error; } result.target = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__RequestLoopInfo(writer: Writer&, value: blot_check_core::RequestLoopInfo, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.computation, depth + 1);

    write_u32(writer, value.action_type, depth + 1);

    write_u32(writer, value.value_type, depth + 1);

    write_u32(writer, value.result_type, depth + 1);

    write_u32(writer, value.state_type, depth + 1);

    write_blot_check_core__List(writer, value.arms, depth + 1);

    write_u32(writer, value.completion_pattern, depth + 1);

    write_u32(writer, value.completion_body, depth + 1);

    write_blot_check_core__List(writer, value.completion_state_bindings, depth + 1);

    write_blot_check_core__List(writer, value.carries, depth + 1);

    write_u32(writer, value.return_target, depth + 1);

}

fn read_blot_check_core__RequestLoopInfo(reader: Reader&, depth: i64) -> blot_check_core::RequestLoopInfo, Error {
    var result = default<blot_check_core::RequestLoopInfo>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::RequestLoopInfo>(), error; } result.computation = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::RequestLoopInfo>(), error; } result.action_type = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::RequestLoopInfo>(), error; } result.value_type = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::RequestLoopInfo>(), error; } result.result_type = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::RequestLoopInfo>(), error; } result.state_type = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::RequestLoopInfo>(), error; } result.arms = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::RequestLoopInfo>(), error; } result.completion_pattern = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::RequestLoopInfo>(), error; } result.completion_body = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::RequestLoopInfo>(), error; } result.completion_state_bindings = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::RequestLoopInfo>(), error; } result.carries = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::RequestLoopInfo>(), error; } result.return_target = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__RequestArm(writer: Writer&, value: blot_check_core::RequestArm, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.operation, depth + 1);

    write_u32(writer, value.callback, depth + 1);

    write_u32(writer, value.selector, depth + 1);

}

fn read_blot_check_core__RequestArm(reader: Reader&, depth: i64) -> blot_check_core::RequestArm, Error {
    var result = default<blot_check_core::RequestArm>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::RequestArm>(), error; } result.operation = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::RequestArm>(), error; } result.callback = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::RequestArm>(), error; } result.selector = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__Types(writer: Writer&, value: blot_check_core::Types, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_types__Node___(writer, value.nodes, depth + 1);

    write_u32___(writer, value.extra, depth + 1);

    write_blot_check_core__EffectRows(writer, value.effects, depth + 1);

    write_blot_check_types__Operation___(writer, value.operations, depth + 1);

    write_blot_check_types__QuantifierGoals___(writer, value.quantifier_goals, depth + 1);

    write_blot_check_types__Obligation___(writer, value.quantifier_obligations, depth + 1);

}

fn read_blot_check_core__Types(reader: Reader&, depth: i64) -> blot_check_core::Types, Error {
    var result = default<blot_check_core::Types>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_types__Node___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Types>(), error; } result.nodes = decoded; }

    { let decoded, error = read_u32___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Types>(), error; } result.extra = decoded; }

    { let decoded, error = read_blot_check_core__EffectRows(reader, depth + 1); if error != Error.none { return default<blot_check_core::Types>(), error; } result.effects = decoded; }

    { let decoded, error = read_blot_check_types__Operation___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Types>(), error; } result.operations = decoded; }

    { let decoded, error = read_blot_check_types__QuantifierGoals___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Types>(), error; } result.quantifier_goals = decoded; }

    { let decoded, error = read_blot_check_types__Obligation___(reader, depth + 1); if error != Error.none { return default<blot_check_core::Types>(), error; } result.quantifier_obligations = decoded; }

    return result, Error.none;
}

fn write_blot_check_types__Node(writer: Writer&, value: blot_check_types::Node, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_types__Tag(writer, value.tag, depth + 1);

    write_u8(writer, value.closed_height, depth + 1);

    write_u16(writer, value.closed_generation, depth + 1);

    write_u32(writer, value.a, depth + 1);

    write_u32(writer, value.b, depth + 1);

    write_u32(writer, value.c, depth + 1);

}

fn read_blot_check_types__Node(reader: Reader&, depth: i64) -> blot_check_types::Node, Error {
    var result = default<blot_check_types::Node>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_types__Tag(reader, depth + 1); if error != Error.none { return default<blot_check_types::Node>(), error; } result.tag = decoded; }

    { let decoded, error = read_u8(reader, depth + 1); if error != Error.none { return default<blot_check_types::Node>(), error; } result.closed_height = decoded; }

    { let decoded, error = read_u16(reader, depth + 1); if error != Error.none { return default<blot_check_types::Node>(), error; } result.closed_generation = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_types::Node>(), error; } result.a = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_types::Node>(), error; } result.b = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_types::Node>(), error; } result.c = decoded; }

    return result, Error.none;
}

fn write_blot_check_types__Tag(writer: Writer&, value: blot_check_types::Tag, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        blot_check_types::Tag.absent => { put(writer, 0, 4); 
},

        blot_check_types::Tag.unit => { put(writer, 1, 4); 
},

        blot_check_types::Tag.boolean => { put(writer, 2, 4); 
},

        blot_check_types::Tag.unsigned32 => { put(writer, 3, 4); 
},

        blot_check_types::Tag.floating32 => { put(writer, 4, 4); 
},

        blot_check_types::Tag.never => { put(writer, 5, 4); 
},

        blot_check_types::Tag.variable => { put(writer, 6, 4); 
},

        blot_check_types::Tag.function => { put(writer, 7, 4); 
},

        blot_check_types::Tag.product => { put(writer, 8, 4); 
},

        blot_check_types::Tag.record => { put(writer, 9, 4); 
},

        blot_check_types::Tag.nominal => { put(writer, 10, 4); 
},

        blot_check_types::Tag.array => { put(writer, 11, 4); 
},

        blot_check_types::Tag.list => { put(writer, 12, 4); 
},

        blot_check_types::Tag.cursor => { put(writer, 13, 4); 
},

        blot_check_types::Tag.type_constructor => { put(writer, 14, 4); 
},

        blot_check_types::Tag.resolver => { put(writer, 15, 4); 
},

        blot_check_types::Tag.provider => { put(writer, 16, 4); 
},

        blot_check_types::Tag.state_provider => { put(writer, 17, 4); 
},

        blot_check_types::Tag.projection => { put(writer, 18, 4); 
},

        blot_check_types::Tag.scoped => { put(writer, 19, 4); 
},

        blot_check_types::Tag.instance_selection => { put(writer, 20, 4); 
},

        blot_check_types::Tag.erased_proof => { put(writer, 21, 4); 
},

        blot_check_types::Tag.forall => { put(writer, 22, 4); 
},

        blot_check_types::Tag.existential => { put(writer, 23, 4); 
},

        blot_check_types::Tag.bound => { put(writer, 24, 4); 
},

        blot_check_types::Tag.rigid => { put(writer, 25, 4); 
},

        blot_check_types::Tag.usage => { put(writer, 26, 4); 
},

        blot_check_types::Tag.instance_version => { put(writer, 27, 4); 
},

    }
}

fn read_blot_check_types__Tag(reader: Reader&, depth: i64) -> blot_check_types::Tag, Error {
    let charged = debit(reader, depth); if charged != Error.none { return default<blot_check_types::Tag>(), charged; } let tag, error = get(reader, 4); if error != Error.none { return default<blot_check_types::Tag>(), error; }
    match tag {

        0 => { 
return blot_check_types::Tag.absent, Error.none; },

        1 => { 
return blot_check_types::Tag.unit, Error.none; },

        2 => { 
return blot_check_types::Tag.boolean, Error.none; },

        3 => { 
return blot_check_types::Tag.unsigned32, Error.none; },

        4 => { 
return blot_check_types::Tag.floating32, Error.none; },

        5 => { 
return blot_check_types::Tag.never, Error.none; },

        6 => { 
return blot_check_types::Tag.variable, Error.none; },

        7 => { 
return blot_check_types::Tag.function, Error.none; },

        8 => { 
return blot_check_types::Tag.product, Error.none; },

        9 => { 
return blot_check_types::Tag.record, Error.none; },

        10 => { 
return blot_check_types::Tag.nominal, Error.none; },

        11 => { 
return blot_check_types::Tag.array, Error.none; },

        12 => { 
return blot_check_types::Tag.list, Error.none; },

        13 => { 
return blot_check_types::Tag.cursor, Error.none; },

        14 => { 
return blot_check_types::Tag.type_constructor, Error.none; },

        15 => { 
return blot_check_types::Tag.resolver, Error.none; },

        16 => { 
return blot_check_types::Tag.provider, Error.none; },

        17 => { 
return blot_check_types::Tag.state_provider, Error.none; },

        18 => { 
return blot_check_types::Tag.projection, Error.none; },

        19 => { 
return blot_check_types::Tag.scoped, Error.none; },

        20 => { 
return blot_check_types::Tag.instance_selection, Error.none; },

        21 => { 
return blot_check_types::Tag.erased_proof, Error.none; },

        22 => { 
return blot_check_types::Tag.forall, Error.none; },

        23 => { 
return blot_check_types::Tag.existential, Error.none; },

        24 => { 
return blot_check_types::Tag.bound, Error.none; },

        25 => { 
return blot_check_types::Tag.rigid, Error.none; },

        26 => { 
return blot_check_types::Tag.usage, Error.none; },

        27 => { 
return blot_check_types::Tag.instance_version, Error.none; },

        _ => { return default<blot_check_types::Tag>(), Error.invalid_artifact; },
    }
}

fn write_blot_check_core__EffectRows(writer: Writer&, value: blot_check_core::EffectRows, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_effects__Row___(writer, value.rows, depth + 1);

    write_u32___(writer, value.labels, depth + 1);

    write_u32(writer, value.variable_count, depth + 1);

}

fn read_blot_check_core__EffectRows(reader: Reader&, depth: i64) -> blot_check_core::EffectRows, Error {
    var result = default<blot_check_core::EffectRows>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_effects__Row___(reader, depth + 1); if error != Error.none { return default<blot_check_core::EffectRows>(), error; } result.rows = decoded; }

    { let decoded, error = read_u32___(reader, depth + 1); if error != Error.none { return default<blot_check_core::EffectRows>(), error; } result.labels = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::EffectRows>(), error; } result.variable_count = decoded; }

    return result, Error.none;
}

fn write_blot_check_effects__Row(writer: Writer&, value: blot_check_effects::Row, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_effects__List(writer, value.labels, depth + 1);

    write_blot_check_effects__Tail(writer, value.tail, depth + 1);

    write_u32(writer, value.cursor, depth + 1);

}

fn read_blot_check_effects__Row(reader: Reader&, depth: i64) -> blot_check_effects::Row, Error {
    var result = default<blot_check_effects::Row>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_effects__List(reader, depth + 1); if error != Error.none { return default<blot_check_effects::Row>(), error; } result.labels = decoded; }

    { let decoded, error = read_blot_check_effects__Tail(reader, depth + 1); if error != Error.none { return default<blot_check_effects::Row>(), error; } result.tail = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_effects::Row>(), error; } result.cursor = decoded; }

    return result, Error.none;
}

fn write_blot_check_effects__List(writer: Writer&, value: blot_check_effects::List, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.start, depth + 1);

    write_u32(writer, value.len, depth + 1);

}

fn read_blot_check_effects__List(reader: Reader&, depth: i64) -> blot_check_effects::List, Error {
    var result = default<blot_check_effects::List>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_effects::List>(), error; } result.start = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_effects::List>(), error; } result.len = decoded; }

    return result, Error.none;
}

fn write_blot_check_effects__Tail(writer: Writer&, value: blot_check_effects::Tail, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        blot_check_effects::Tail.closed => { put(writer, 0, 4); 
},

        blot_check_effects::Tail.variable payload => { put(writer, 1, 4); 
write_u32(writer, payload.value, depth + 1); 
},

        blot_check_effects::Tail.parameter payload => { put(writer, 2, 4); 
write_u32(writer, payload.value, depth + 1); 
},

        blot_check_effects::Tail.formal payload => { put(writer, 3, 4); 
write_u32(writer, payload.value, depth + 1); 
},

    }
}

fn read_blot_check_effects__Tail(reader: Reader&, depth: i64) -> blot_check_effects::Tail, Error {
    let charged = debit(reader, depth); if charged != Error.none { return default<blot_check_effects::Tail>(), charged; } let tag, error = get(reader, 4); if error != Error.none { return default<blot_check_effects::Tail>(), error; }
    match tag {

        0 => { 
return blot_check_effects::Tail.closed, Error.none; },

        1 => { 
let value, failure_value = read_u32(reader, depth + 1); if failure_value != Error.none { return default<blot_check_effects::Tail>(), failure_value; } 
return blot_check_effects::Tail.variable { value: value , ..}, Error.none; },

        2 => { 
let value, failure_value = read_u32(reader, depth + 1); if failure_value != Error.none { return default<blot_check_effects::Tail>(), failure_value; } 
return blot_check_effects::Tail.parameter { value: value , ..}, Error.none; },

        3 => { 
let value, failure_value = read_u32(reader, depth + 1); if failure_value != Error.none { return default<blot_check_effects::Tail>(), failure_value; } 
return blot_check_effects::Tail.formal { value: value , ..}, Error.none; },

        _ => { return default<blot_check_effects::Tail>(), Error.invalid_artifact; },
    }
}

fn write_blot_check_types__Operation(writer: Writer&, value: blot_check_types::Operation, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_types__NominalIdentity(writer, value.identity, depth + 1);

    write_blot_check_types__List(writer, value.arguments, depth + 1);

    write_blot_check_types__NominalIdentity(writer, value.instance, depth + 1);

}

fn read_blot_check_types__Operation(reader: Reader&, depth: i64) -> blot_check_types::Operation, Error {
    var result = default<blot_check_types::Operation>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != Error.none { return default<blot_check_types::Operation>(), error; } result.identity = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_check_types::Operation>(), error; } result.arguments = decoded; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != Error.none { return default<blot_check_types::Operation>(), error; } result.instance = decoded; }

    return result, Error.none;
}

fn write_blot_check_types__NominalIdentity(writer: Writer&, value: blot_check_types::NominalIdentity, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.unit, depth + 1);

    write_u32(writer, value.decl, depth + 1);

}

fn read_blot_check_types__NominalIdentity(reader: Reader&, depth: i64) -> blot_check_types::NominalIdentity, Error {
    var result = default<blot_check_types::NominalIdentity>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_types::NominalIdentity>(), error; } result.unit = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_types::NominalIdentity>(), error; } result.decl = decoded; }

    return result, Error.none;
}

fn write_blot_check_types__List(writer: Writer&, value: blot_check_types::List, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.start, depth + 1);

    write_u32(writer, value.len, depth + 1);

}

fn read_blot_check_types__List(reader: Reader&, depth: i64) -> blot_check_types::List, Error {
    var result = default<blot_check_types::List>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_types::List>(), error; } result.start = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_types::List>(), error; } result.len = decoded; }

    return result, Error.none;
}

fn write_blot_check_types__QuantifierGoals(writer: Writer&, value: blot_check_types::QuantifierGoals, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.owner, depth + 1);

    write_blot_check_types__List(writer, value.goals, depth + 1);

}

fn read_blot_check_types__QuantifierGoals(reader: Reader&, depth: i64) -> blot_check_types::QuantifierGoals, Error {
    var result = default<blot_check_types::QuantifierGoals>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_types::QuantifierGoals>(), error; } result.owner = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_check_types::QuantifierGoals>(), error; } result.goals = decoded; }

    return result, Error.none;
}

fn write_blot_check_types__Obligation(writer: Writer&, value: blot_check_types::Obligation, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.ty, depth + 1);

    write_blot_check_types__ObligationKind(writer, value.kind, depth + 1);

    write_u32(writer, value.source, depth + 1);

    write_u32(writer, value.name, depth + 1);

    write_u32(writer, value.result, depth + 1);

    write_u32(writer, value.other, depth + 1);

    write_u32(writer, value.signature, depth + 1);

    write_blot_check_types__Operator(writer, value.operator, depth + 1);

    write_blot_check_types__NominalIdentity(writer, value.identity, depth + 1);

    write_bool(writer, value.explicit, depth + 1);

    write_blot_support__Option_blot_parse_ast__Span_(writer, value.qualification_span, depth + 1);

    write_u32(writer, value.qualification_unit, depth + 1);

}

fn read_blot_check_types__Obligation(reader: Reader&, depth: i64) -> blot_check_types::Obligation, Error {
    var result = default<blot_check_types::Obligation>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_types::Obligation>(), error; } result.ty = decoded; }

    { let decoded, error = read_blot_check_types__ObligationKind(reader, depth + 1); if error != Error.none { return default<blot_check_types::Obligation>(), error; } result.kind = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_types::Obligation>(), error; } result.source = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_types::Obligation>(), error; } result.name = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_types::Obligation>(), error; } result.result = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_types::Obligation>(), error; } result.other = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_types::Obligation>(), error; } result.signature = decoded; }

    { let decoded, error = read_blot_check_types__Operator(reader, depth + 1); if error != Error.none { return default<blot_check_types::Obligation>(), error; } result.operator = decoded; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != Error.none { return default<blot_check_types::Obligation>(), error; } result.identity = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != Error.none { return default<blot_check_types::Obligation>(), error; } result.explicit = decoded; }

    { let decoded, error = read_blot_support__Option_blot_parse_ast__Span_(reader, depth + 1); if error != Error.none { return default<blot_check_types::Obligation>(), error; } result.qualification_span = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_types::Obligation>(), error; } result.qualification_unit = decoded; }

    return result, Error.none;
}

fn write_blot_check_types__ObligationKind(writer: Writer&, value: blot_check_types::ObligationKind, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        blot_check_types::ObligationKind.arithmetic => { put(writer, 0, 4); 
},

        blot_check_types::ObligationKind.ordered => { put(writer, 1, 4); 
},

        blot_check_types::ObligationKind.equality => { put(writer, 2, 4); 
},

        blot_check_types::ObligationKind.integer => { put(writer, 3, 4); 
},

        blot_check_types::ObligationKind.field => { put(writer, 4, 4); 
},

        blot_check_types::ObligationKind.writable_field => { put(writer, 5, 4); 
},

        blot_check_types::ObligationKind.dispatch => { put(writer, 6, 4); 
},

        blot_check_types::ObligationKind.result_dispatch => { put(writer, 7, 4); 
},

        blot_check_types::ObligationKind.monad_factory => { put(writer, 8, 4); 
},

        blot_check_types::ObligationKind.resolver_dispatch => { put(writer, 9, 4); 
},

        blot_check_types::ObligationKind.resolver_shape => { put(writer, 10, 4); 
},

        blot_check_types::ObligationKind.effect_operation => { put(writer, 11, 4); 
},

        blot_check_types::ObligationKind.effect_handler => { put(writer, 12, 4); 
},

        blot_check_types::ObligationKind.receiver => { put(writer, 13, 4); 
},

        blot_check_types::ObligationKind.update => { put(writer, 14, 4); 
},

        blot_check_types::ObligationKind.type_rep => { put(writer, 15, 4); 
},

        blot_check_types::ObligationKind.effect_rep => { put(writer, 16, 4); 
},

        blot_check_types::ObligationKind.type_head => { put(writer, 17, 4); 
},

        blot_check_types::ObligationKind.collection => { put(writer, 18, 4); 
},

        blot_check_types::ObligationKind.record_merge => { put(writer, 19, 4); 
},

        blot_check_types::ObligationKind.callee_use => { put(writer, 20, 4); 
},

        blot_check_types::ObligationKind.type_eq => { put(writer, 21, 4); 
},

        blot_check_types::ObligationKind.contract => { put(writer, 22, 4); 
},

        blot_check_types::ObligationKind.task_receive => { put(writer, 23, 4); 
},

    }
}

fn read_blot_check_types__ObligationKind(reader: Reader&, depth: i64) -> blot_check_types::ObligationKind, Error {
    let charged = debit(reader, depth); if charged != Error.none { return default<blot_check_types::ObligationKind>(), charged; } let tag, error = get(reader, 4); if error != Error.none { return default<blot_check_types::ObligationKind>(), error; }
    match tag {

        0 => { 
return blot_check_types::ObligationKind.arithmetic, Error.none; },

        1 => { 
return blot_check_types::ObligationKind.ordered, Error.none; },

        2 => { 
return blot_check_types::ObligationKind.equality, Error.none; },

        3 => { 
return blot_check_types::ObligationKind.integer, Error.none; },

        4 => { 
return blot_check_types::ObligationKind.field, Error.none; },

        5 => { 
return blot_check_types::ObligationKind.writable_field, Error.none; },

        6 => { 
return blot_check_types::ObligationKind.dispatch, Error.none; },

        7 => { 
return blot_check_types::ObligationKind.result_dispatch, Error.none; },

        8 => { 
return blot_check_types::ObligationKind.monad_factory, Error.none; },

        9 => { 
return blot_check_types::ObligationKind.resolver_dispatch, Error.none; },

        10 => { 
return blot_check_types::ObligationKind.resolver_shape, Error.none; },

        11 => { 
return blot_check_types::ObligationKind.effect_operation, Error.none; },

        12 => { 
return blot_check_types::ObligationKind.effect_handler, Error.none; },

        13 => { 
return blot_check_types::ObligationKind.receiver, Error.none; },

        14 => { 
return blot_check_types::ObligationKind.update, Error.none; },

        15 => { 
return blot_check_types::ObligationKind.type_rep, Error.none; },

        16 => { 
return blot_check_types::ObligationKind.effect_rep, Error.none; },

        17 => { 
return blot_check_types::ObligationKind.type_head, Error.none; },

        18 => { 
return blot_check_types::ObligationKind.collection, Error.none; },

        19 => { 
return blot_check_types::ObligationKind.record_merge, Error.none; },

        20 => { 
return blot_check_types::ObligationKind.callee_use, Error.none; },

        21 => { 
return blot_check_types::ObligationKind.type_eq, Error.none; },

        22 => { 
return blot_check_types::ObligationKind.contract, Error.none; },

        23 => { 
return blot_check_types::ObligationKind.task_receive, Error.none; },

        _ => { return default<blot_check_types::ObligationKind>(), Error.invalid_artifact; },
    }
}

fn write_blot_parse_ast__Span(writer: Writer&, value: blot_parse_ast::Span, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.start, depth + 1);

    write_u32(writer, value.end, depth + 1);

}

fn read_blot_parse_ast__Span(reader: Reader&, depth: i64) -> blot_parse_ast::Span, Error {
    var result = default<blot_parse_ast::Span>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_parse_ast::Span>(), error; } result.start = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_parse_ast::Span>(), error; } result.end = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__Node(writer: Writer&, value: blot_check_core::Node, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_core__Tag(writer, value.tag, depth + 1);

    write_blot_check_core__Op(writer, value.op, depth + 1);

    write_u32(writer, value.ty, depth + 1);

    write_u32(writer, value.a, depth + 1);

    write_u32(writer, value.b, depth + 1);

    write_u32(writer, value.c, depth + 1);

}

fn read_blot_check_core__Node(reader: Reader&, depth: i64) -> blot_check_core::Node, Error {
    var result = default<blot_check_core::Node>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_core__Tag(reader, depth + 1); if error != Error.none { return default<blot_check_core::Node>(), error; } result.tag = decoded; }

    { let decoded, error = read_blot_check_core__Op(reader, depth + 1); if error != Error.none { return default<blot_check_core::Node>(), error; } result.op = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Node>(), error; } result.ty = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Node>(), error; } result.a = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Node>(), error; } result.b = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Node>(), error; } result.c = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__Tag(writer: Writer&, value: blot_check_core::Tag, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        blot_check_core::Tag.invalid => { put(writer, 0, 4); 
},

        blot_check_core::Tag.constant => { put(writer, 1, 4); 
},

        blot_check_core::Tag.reference => { put(writer, 2, 4); 
},

        blot_check_core::Tag.scalar => { put(writer, 3, 4); 
},

        blot_check_core::Tag.logical => { put(writer, 4, 4); 
},

        blot_check_core::Tag.call => { put(writer, 5, 4); 
},

        blot_check_core::Tag.if_value => { put(writer, 6, 4); 
},

        blot_check_core::Tag.block_ => { put(writer, 7, 4); 
},

        blot_check_core::Tag.suite => { put(writer, 8, 4); 
},

        blot_check_core::Tag.bind => { put(writer, 9, 4); 
},

        blot_check_core::Tag.return_ => { put(writer, 10, 4); 
},

        blot_check_core::Tag.if_stmt => { put(writer, 11, 4); 
},

        blot_check_core::Tag.product => { put(writer, 12, 4); 
},

        blot_check_core::Tag.record => { put(writer, 13, 4); 
},

        blot_check_core::Tag.construct => { put(writer, 14, 4); 
},

        blot_check_core::Tag.project => { put(writer, 15, 4); 
},

        blot_check_core::Tag.match_ => { put(writer, 16, 4); 
},

        blot_check_core::Tag.pattern_bind => { put(writer, 17, 4); 
},

        blot_check_core::Tag.update => { put(writer, 18, 4); 
},

        blot_check_core::Tag.array => { put(writer, 19, 4); 
},

        blot_check_core::Tag.array_op => { put(writer, 20, 4); 
},

        blot_check_core::Tag.closure => { put(writer, 21, 4); 
},

        blot_check_core::Tag.apply => { put(writer, 22, 4); 
},

        blot_check_core::Tag.constructor_function => { put(writer, 23, 4); 
},

        blot_check_core::Tag.associated => { put(writer, 24, 4); 
},

        blot_check_core::Tag.primitive_function => { put(writer, 25, 4); 
},

        blot_check_core::Tag.panic => { put(writer, 26, 4); 
},

        blot_check_core::Tag.loop_ => { put(writer, 27, 4); 
},

        blot_check_core::Tag.break_ => { put(writer, 28, 4); 
},

        blot_check_core::Tag.type_same => { put(writer, 29, 4); 
},

        blot_check_core::Tag.result_associated => { put(writer, 30, 4); 
},

        blot_check_core::Tag.type_constructor => { put(writer, 31, 4); 
},

        blot_check_core::Tag.resolver_op => { put(writer, 32, 4); 
},

        blot_check_core::Tag.operation_value => { put(writer, 33, 4); 
},

        blot_check_core::Tag.effect_provider => { put(writer, 34, 4); 
},

        blot_check_core::Tag.state_provider => { put(writer, 35, 4); 
},

        blot_check_core::Tag.handle => { put(writer, 36, 4); 
},

        blot_check_core::Tag.effect_reflection => { put(writer, 37, 4); 
},

        blot_check_core::Tag.computation => { put(writer, 38, 4); 
},

        blot_check_core::Tag.request_loop => { put(writer, 39, 4); 
},

        blot_check_core::Tag.request_decision => { put(writer, 40, 4); 
},

        blot_check_core::Tag.record_merge => { put(writer, 41, 4); 
},

        blot_check_core::Tag.contract_method => { put(writer, 42, 4); 
},

        blot_check_core::Tag.effect_scope => { put(writer, 43, 4); 
},

        blot_check_core::Tag.proof_guard => { put(writer, 44, 4); 
},

        blot_check_core::Tag.package_pack => { put(writer, 45, 4); 
},

        blot_check_core::Tag.package_unpack => { put(writer, 46, 4); 
},

        blot_check_core::Tag.staging => { put(writer, 47, 4); 
},

        blot_check_core::Tag.usage_borrow => { put(writer, 48, 4); 
},

        blot_check_core::Tag.usage_read => { put(writer, 49, 4); 
},

        blot_check_core::Tag.resource_scope => { put(writer, 50, 4); 
},

        blot_check_core::Tag.usage_share => { put(writer, 51, 4); 
},

        blot_check_core::Tag.resource_acquire => { put(writer, 52, 4); 
},

        blot_check_core::Tag.resource_release => { put(writer, 53, 4); 
},

        blot_check_core::Tag.task => { put(writer, 54, 4); 
},

        blot_check_core::Tag.storage => { put(writer, 55, 4); 
},

    }
}

fn read_blot_check_core__Tag(reader: Reader&, depth: i64) -> blot_check_core::Tag, Error {
    let charged = debit(reader, depth); if charged != Error.none { return default<blot_check_core::Tag>(), charged; } let tag, error = get(reader, 4); if error != Error.none { return default<blot_check_core::Tag>(), error; }
    match tag {

        0 => { 
return blot_check_core::Tag.invalid, Error.none; },

        1 => { 
return blot_check_core::Tag.constant, Error.none; },

        2 => { 
return blot_check_core::Tag.reference, Error.none; },

        3 => { 
return blot_check_core::Tag.scalar, Error.none; },

        4 => { 
return blot_check_core::Tag.logical, Error.none; },

        5 => { 
return blot_check_core::Tag.call, Error.none; },

        6 => { 
return blot_check_core::Tag.if_value, Error.none; },

        7 => { 
return blot_check_core::Tag.block_, Error.none; },

        8 => { 
return blot_check_core::Tag.suite, Error.none; },

        9 => { 
return blot_check_core::Tag.bind, Error.none; },

        10 => { 
return blot_check_core::Tag.return_, Error.none; },

        11 => { 
return blot_check_core::Tag.if_stmt, Error.none; },

        12 => { 
return blot_check_core::Tag.product, Error.none; },

        13 => { 
return blot_check_core::Tag.record, Error.none; },

        14 => { 
return blot_check_core::Tag.construct, Error.none; },

        15 => { 
return blot_check_core::Tag.project, Error.none; },

        16 => { 
return blot_check_core::Tag.match_, Error.none; },

        17 => { 
return blot_check_core::Tag.pattern_bind, Error.none; },

        18 => { 
return blot_check_core::Tag.update, Error.none; },

        19 => { 
return blot_check_core::Tag.array, Error.none; },

        20 => { 
return blot_check_core::Tag.array_op, Error.none; },

        21 => { 
return blot_check_core::Tag.closure, Error.none; },

        22 => { 
return blot_check_core::Tag.apply, Error.none; },

        23 => { 
return blot_check_core::Tag.constructor_function, Error.none; },

        24 => { 
return blot_check_core::Tag.associated, Error.none; },

        25 => { 
return blot_check_core::Tag.primitive_function, Error.none; },

        26 => { 
return blot_check_core::Tag.panic, Error.none; },

        27 => { 
return blot_check_core::Tag.loop_, Error.none; },

        28 => { 
return blot_check_core::Tag.break_, Error.none; },

        29 => { 
return blot_check_core::Tag.type_same, Error.none; },

        30 => { 
return blot_check_core::Tag.result_associated, Error.none; },

        31 => { 
return blot_check_core::Tag.type_constructor, Error.none; },

        32 => { 
return blot_check_core::Tag.resolver_op, Error.none; },

        33 => { 
return blot_check_core::Tag.operation_value, Error.none; },

        34 => { 
return blot_check_core::Tag.effect_provider, Error.none; },

        35 => { 
return blot_check_core::Tag.state_provider, Error.none; },

        36 => { 
return blot_check_core::Tag.handle, Error.none; },

        37 => { 
return blot_check_core::Tag.effect_reflection, Error.none; },

        38 => { 
return blot_check_core::Tag.computation, Error.none; },

        39 => { 
return blot_check_core::Tag.request_loop, Error.none; },

        40 => { 
return blot_check_core::Tag.request_decision, Error.none; },

        41 => { 
return blot_check_core::Tag.record_merge, Error.none; },

        42 => { 
return blot_check_core::Tag.contract_method, Error.none; },

        43 => { 
return blot_check_core::Tag.effect_scope, Error.none; },

        44 => { 
return blot_check_core::Tag.proof_guard, Error.none; },

        45 => { 
return blot_check_core::Tag.package_pack, Error.none; },

        46 => { 
return blot_check_core::Tag.package_unpack, Error.none; },

        47 => { 
return blot_check_core::Tag.staging, Error.none; },

        48 => { 
return blot_check_core::Tag.usage_borrow, Error.none; },

        49 => { 
return blot_check_core::Tag.usage_read, Error.none; },

        50 => { 
return blot_check_core::Tag.resource_scope, Error.none; },

        51 => { 
return blot_check_core::Tag.usage_share, Error.none; },

        52 => { 
return blot_check_core::Tag.resource_acquire, Error.none; },

        53 => { 
return blot_check_core::Tag.resource_release, Error.none; },

        54 => { 
return blot_check_core::Tag.task, Error.none; },

        55 => { 
return blot_check_core::Tag.storage, Error.none; },

        _ => { return default<blot_check_core::Tag>(), Error.invalid_artifact; },
    }
}

fn write_blot_check_core__Op(writer: Writer&, value: blot_check_core::Op, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        blot_check_core::Op.none => { put(writer, 0, 4); 
},

        blot_check_core::Op.add => { put(writer, 1, 4); 
},

        blot_check_core::Op.sub => { put(writer, 2, 4); 
},

        blot_check_core::Op.mul => { put(writer, 3, 4); 
},

        blot_check_core::Op.div => { put(writer, 4, 4); 
},

        blot_check_core::Op.rem => { put(writer, 5, 4); 
},

        blot_check_core::Op.equal => { put(writer, 6, 4); 
},

        blot_check_core::Op.not_equal => { put(writer, 7, 4); 
},

        blot_check_core::Op.less => { put(writer, 8, 4); 
},

        blot_check_core::Op.less_equal => { put(writer, 9, 4); 
},

        blot_check_core::Op.greater => { put(writer, 10, 4); 
},

        blot_check_core::Op.greater_equal => { put(writer, 11, 4); 
},

        blot_check_core::Op.bit_and => { put(writer, 12, 4); 
},

        blot_check_core::Op.bit_or => { put(writer, 13, 4); 
},

        blot_check_core::Op.bit_xor => { put(writer, 14, 4); 
},

        blot_check_core::Op.shift_left => { put(writer, 15, 4); 
},

        blot_check_core::Op.shift_right => { put(writer, 16, 4); 
},

        blot_check_core::Op.and_ => { put(writer, 17, 4); 
},

        blot_check_core::Op.or_ => { put(writer, 18, 4); 
},

        blot_check_core::Op.neg => { put(writer, 19, 4); 
},

        blot_check_core::Op.abs => { put(writer, 20, 4); 
},

        blot_check_core::Op.ceil => { put(writer, 21, 4); 
},

        blot_check_core::Op.floor => { put(writer, 22, 4); 
},

        blot_check_core::Op.trunc => { put(writer, 23, 4); 
},

        blot_check_core::Op.sqrt => { put(writer, 24, 4); 
},

        blot_check_core::Op.convert_u32_f32 => { put(writer, 25, 4); 
},

        blot_check_core::Op.convert_f32_u32 => { put(writer, 26, 4); 
},

        blot_check_core::Op.shift_right_signed => { put(writer, 27, 4); 
},

        blot_check_core::Op.min => { put(writer, 28, 4); 
},

        blot_check_core::Op.max => { put(writer, 29, 4); 
},

        blot_check_core::Op.bit_not => { put(writer, 30, 4); 
},

        blot_check_core::Op.bit_andnot => { put(writer, 31, 4); 
},

        blot_check_core::Op.any_true => { put(writer, 32, 4); 
},

        blot_check_core::Op.all_true => { put(writer, 33, 4); 
},

        blot_check_core::Op.select => { put(writer, 34, 4); 
},

        blot_check_core::Op.shuffle => { put(writer, 35, 4); 
},

        blot_check_core::Op.swizzle => { put(writer, 36, 4); 
},

        blot_check_core::Op.broadcast => { put(writer, 37, 4); 
},

        blot_check_core::Op.bits => { put(writer, 38, 4); 
},

        blot_check_core::Op.from_bits => { put(writer, 39, 4); 
},

        blot_check_core::Op.relaxed_madd => { put(writer, 40, 4); 
},

        blot_check_core::Op.relaxed_nmadd => { put(writer, 41, 4); 
},

        blot_check_core::Op.convert_i32_f32 => { put(writer, 42, 4); 
},

        blot_check_core::Op.convert_f32_i32 => { put(writer, 43, 4); 
},

        blot_check_core::Op.continue_ => { put(writer, 44, 4); 
},

    }
}

fn read_blot_check_core__Op(reader: Reader&, depth: i64) -> blot_check_core::Op, Error {
    let charged = debit(reader, depth); if charged != Error.none { return default<blot_check_core::Op>(), charged; } let tag, error = get(reader, 4); if error != Error.none { return default<blot_check_core::Op>(), error; }
    match tag {

        0 => { 
return blot_check_core::Op.none, Error.none; },

        1 => { 
return blot_check_core::Op.add, Error.none; },

        2 => { 
return blot_check_core::Op.sub, Error.none; },

        3 => { 
return blot_check_core::Op.mul, Error.none; },

        4 => { 
return blot_check_core::Op.div, Error.none; },

        5 => { 
return blot_check_core::Op.rem, Error.none; },

        6 => { 
return blot_check_core::Op.equal, Error.none; },

        7 => { 
return blot_check_core::Op.not_equal, Error.none; },

        8 => { 
return blot_check_core::Op.less, Error.none; },

        9 => { 
return blot_check_core::Op.less_equal, Error.none; },

        10 => { 
return blot_check_core::Op.greater, Error.none; },

        11 => { 
return blot_check_core::Op.greater_equal, Error.none; },

        12 => { 
return blot_check_core::Op.bit_and, Error.none; },

        13 => { 
return blot_check_core::Op.bit_or, Error.none; },

        14 => { 
return blot_check_core::Op.bit_xor, Error.none; },

        15 => { 
return blot_check_core::Op.shift_left, Error.none; },

        16 => { 
return blot_check_core::Op.shift_right, Error.none; },

        17 => { 
return blot_check_core::Op.and_, Error.none; },

        18 => { 
return blot_check_core::Op.or_, Error.none; },

        19 => { 
return blot_check_core::Op.neg, Error.none; },

        20 => { 
return blot_check_core::Op.abs, Error.none; },

        21 => { 
return blot_check_core::Op.ceil, Error.none; },

        22 => { 
return blot_check_core::Op.floor, Error.none; },

        23 => { 
return blot_check_core::Op.trunc, Error.none; },

        24 => { 
return blot_check_core::Op.sqrt, Error.none; },

        25 => { 
return blot_check_core::Op.convert_u32_f32, Error.none; },

        26 => { 
return blot_check_core::Op.convert_f32_u32, Error.none; },

        27 => { 
return blot_check_core::Op.shift_right_signed, Error.none; },

        28 => { 
return blot_check_core::Op.min, Error.none; },

        29 => { 
return blot_check_core::Op.max, Error.none; },

        30 => { 
return blot_check_core::Op.bit_not, Error.none; },

        31 => { 
return blot_check_core::Op.bit_andnot, Error.none; },

        32 => { 
return blot_check_core::Op.any_true, Error.none; },

        33 => { 
return blot_check_core::Op.all_true, Error.none; },

        34 => { 
return blot_check_core::Op.select, Error.none; },

        35 => { 
return blot_check_core::Op.shuffle, Error.none; },

        36 => { 
return blot_check_core::Op.swizzle, Error.none; },

        37 => { 
return blot_check_core::Op.broadcast, Error.none; },

        38 => { 
return blot_check_core::Op.bits, Error.none; },

        39 => { 
return blot_check_core::Op.from_bits, Error.none; },

        40 => { 
return blot_check_core::Op.relaxed_madd, Error.none; },

        41 => { 
return blot_check_core::Op.relaxed_nmadd, Error.none; },

        42 => { 
return blot_check_core::Op.convert_i32_f32, Error.none; },

        43 => { 
return blot_check_core::Op.convert_f32_i32, Error.none; },

        44 => { 
return blot_check_core::Op.continue_, Error.none; },

        _ => { return default<blot_check_core::Op>(), Error.invalid_artifact; },
    }
}

fn write_blot_check_core__Binding(writer: Writer&, value: blot_check_core::Binding, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_capability_flow__Contract(writer, value.capability_flow, depth + 1);

    write_blot_check_capability_flow__Parameters(writer, value.capability_parameters, depth + 1);

    write_bool(writer, value.private, depth + 1);

    write_u32(writer, value.initializer, depth + 1);

    write_blot_reuse_principal_interface__Kind(writer, value.kind, depth + 1);

    write_u32(writer, value.ty, depth + 1);

    write_blot_check_types__Scheme(writer, value.scheme, depth + 1);

    write_blot_check_types__List(writer, value.public_variables, depth + 1);

    write_blot_check_types__List(writer, value.public_rows, depth + 1);

    write_bool(writer, value.has_explicit, depth + 1);

    write_u32(writer, value.body_id, depth + 1);

    write_blot_check_core__BindingRef(writer, value.target, depth + 1);

    write_blot_parse_ast__Span(writer, value.span, depth + 1);

}

fn read_blot_check_core__Binding(reader: Reader&, depth: i64) -> blot_check_core::Binding, Error {
    var result = default<blot_check_core::Binding>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_capability_flow__Contract(reader, depth + 1); if error != Error.none { return default<blot_check_core::Binding>(), error; } result.capability_flow = decoded; }

    { let decoded, error = read_blot_check_capability_flow__Parameters(reader, depth + 1); if error != Error.none { return default<blot_check_core::Binding>(), error; } result.capability_parameters = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != Error.none { return default<blot_check_core::Binding>(), error; } result.private = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Binding>(), error; } result.initializer = decoded; }

    { let decoded, error = read_blot_reuse_principal_interface__Kind(reader, depth + 1); if error != Error.none { return default<blot_check_core::Binding>(), error; } result.kind = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Binding>(), error; } result.ty = decoded; }

    { let decoded, error = read_blot_check_types__Scheme(reader, depth + 1); if error != Error.none { return default<blot_check_core::Binding>(), error; } result.scheme = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::Binding>(), error; } result.public_variables = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::Binding>(), error; } result.public_rows = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != Error.none { return default<blot_check_core::Binding>(), error; } result.has_explicit = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Binding>(), error; } result.body_id = decoded; }

    { let decoded, error = read_blot_check_core__BindingRef(reader, depth + 1); if error != Error.none { return default<blot_check_core::Binding>(), error; } result.target = decoded; }

    { let decoded, error = read_blot_parse_ast__Span(reader, depth + 1); if error != Error.none { return default<blot_check_core::Binding>(), error; } result.span = decoded; }

    return result, Error.none;
}

fn write_blot_check_capability_flow__Contract(writer: Writer&, value: blot_check_capability_flow::Contract, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        blot_check_capability_flow::Contract.unknown => { put(writer, 0, 4); 
},

        blot_check_capability_flow::Contract.identity => { put(writer, 1, 4); 
},

        blot_check_capability_flow::Contract.invoke_unit => { put(writer, 2, 4); 
},

        blot_check_capability_flow::Contract.member_unit => { put(writer, 3, 4); 
},

        blot_check_capability_flow::Contract.invoke_with_capability => { put(writer, 4, 4); 
},

        blot_check_capability_flow::Contract.member_first_unit => { put(writer, 5, 4); 
},

        blot_check_capability_flow::Contract.member_second_unit => { put(writer, 6, 4); 
},

        blot_check_capability_flow::Contract.input_shape => { put(writer, 7, 4); 
},

        blot_check_capability_flow::Contract.consume_task => { put(writer, 8, 4); 
},

        blot_check_capability_flow::Contract.scope_task => { put(writer, 9, 4); 
},

        blot_check_capability_flow::Contract.spawn_task => { put(writer, 10, 4); 
},

    }
}

fn read_blot_check_capability_flow__Contract(reader: Reader&, depth: i64) -> blot_check_capability_flow::Contract, Error {
    let charged = debit(reader, depth); if charged != Error.none { return default<blot_check_capability_flow::Contract>(), charged; } let tag, error = get(reader, 4); if error != Error.none { return default<blot_check_capability_flow::Contract>(), error; }
    match tag {

        0 => { 
return blot_check_capability_flow::Contract.unknown, Error.none; },

        1 => { 
return blot_check_capability_flow::Contract.identity, Error.none; },

        2 => { 
return blot_check_capability_flow::Contract.invoke_unit, Error.none; },

        3 => { 
return blot_check_capability_flow::Contract.member_unit, Error.none; },

        4 => { 
return blot_check_capability_flow::Contract.invoke_with_capability, Error.none; },

        5 => { 
return blot_check_capability_flow::Contract.member_first_unit, Error.none; },

        6 => { 
return blot_check_capability_flow::Contract.member_second_unit, Error.none; },

        7 => { 
return blot_check_capability_flow::Contract.input_shape, Error.none; },

        8 => { 
return blot_check_capability_flow::Contract.consume_task, Error.none; },

        9 => { 
return blot_check_capability_flow::Contract.scope_task, Error.none; },

        10 => { 
return blot_check_capability_flow::Contract.spawn_task, Error.none; },

        _ => { return default<blot_check_capability_flow::Contract>(), Error.invalid_artifact; },
    }
}

fn write_blot_check_capability_flow__Parameters(writer: Writer&, value: blot_check_capability_flow::Parameters, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_capability_flow__ParameterResult(writer, value.kind, depth + 1);

    write_u16(writer, value.mask, depth + 1);

    write_u8(writer, value.inputs, depth + 1);

    write_u64(writer, value.invocation_arguments, depth + 1);

    write_u8(writer, value.invocation_count, depth + 1);

}

fn read_blot_check_capability_flow__Parameters(reader: Reader&, depth: i64) -> blot_check_capability_flow::Parameters, Error {
    var result = default<blot_check_capability_flow::Parameters>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_capability_flow__ParameterResult(reader, depth + 1); if error != Error.none { return default<blot_check_capability_flow::Parameters>(), error; } result.kind = decoded; }

    { let decoded, error = read_u16(reader, depth + 1); if error != Error.none { return default<blot_check_capability_flow::Parameters>(), error; } result.mask = decoded; }

    { let decoded, error = read_u8(reader, depth + 1); if error != Error.none { return default<blot_check_capability_flow::Parameters>(), error; } result.inputs = decoded; }

    { let decoded, error = read_u64(reader, depth + 1); if error != Error.none { return default<blot_check_capability_flow::Parameters>(), error; } result.invocation_arguments = decoded; }

    { let decoded, error = read_u8(reader, depth + 1); if error != Error.none { return default<blot_check_capability_flow::Parameters>(), error; } result.invocation_count = decoded; }

    return result, Error.none;
}

fn write_blot_check_capability_flow__ParameterResult(writer: Writer&, value: blot_check_capability_flow::ParameterResult, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        blot_check_capability_flow::ParameterResult.product => { put(writer, 0, 4); 
},

        blot_check_capability_flow::ParameterResult.invoke_unit => { put(writer, 1, 4); 
},

        blot_check_capability_flow::ParameterResult.invalid => { put(writer, 2, 4); 
},

        blot_check_capability_flow::ParameterResult.member_closure_unit => { put(writer, 3, 4); 
},

        blot_check_capability_flow::ParameterResult.captured_unit => { put(writer, 4, 4); 
},

        blot_check_capability_flow::ParameterResult.invoke_input => { put(writer, 5, 4); 
},

        blot_check_capability_flow::ParameterResult.invoke_inputs => { put(writer, 6, 4); 
},

    }
}

fn read_blot_check_capability_flow__ParameterResult(reader: Reader&, depth: i64) -> blot_check_capability_flow::ParameterResult, Error {
    let charged = debit(reader, depth); if charged != Error.none { return default<blot_check_capability_flow::ParameterResult>(), charged; } let tag, error = get(reader, 4); if error != Error.none { return default<blot_check_capability_flow::ParameterResult>(), error; }
    match tag {

        0 => { 
return blot_check_capability_flow::ParameterResult.product, Error.none; },

        1 => { 
return blot_check_capability_flow::ParameterResult.invoke_unit, Error.none; },

        2 => { 
return blot_check_capability_flow::ParameterResult.invalid, Error.none; },

        3 => { 
return blot_check_capability_flow::ParameterResult.member_closure_unit, Error.none; },

        4 => { 
return blot_check_capability_flow::ParameterResult.captured_unit, Error.none; },

        5 => { 
return blot_check_capability_flow::ParameterResult.invoke_input, Error.none; },

        6 => { 
return blot_check_capability_flow::ParameterResult.invoke_inputs, Error.none; },

        _ => { return default<blot_check_capability_flow::ParameterResult>(), Error.invalid_artifact; },
    }
}

fn write_blot_reuse_principal_interface__Kind(writer: Writer&, value: blot_reuse_principal_interface::Kind, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        blot_reuse_principal_interface::Kind.global => { put(writer, 0, 4); 
},

        blot_reuse_principal_interface::Kind.local => { put(writer, 1, 4); 
},

        blot_reuse_principal_interface::Kind.parameter => { put(writer, 2, 4); 
},

        blot_reuse_principal_interface::Kind.external => { put(writer, 3, 4); 
},

    }
}

fn read_blot_reuse_principal_interface__Kind(reader: Reader&, depth: i64) -> blot_reuse_principal_interface::Kind, Error {
    let charged = debit(reader, depth); if charged != Error.none { return default<blot_reuse_principal_interface::Kind>(), charged; } let tag, error = get(reader, 4); if error != Error.none { return default<blot_reuse_principal_interface::Kind>(), error; }
    match tag {

        0 => { 
return blot_reuse_principal_interface::Kind.global, Error.none; },

        1 => { 
return blot_reuse_principal_interface::Kind.local, Error.none; },

        2 => { 
return blot_reuse_principal_interface::Kind.parameter, Error.none; },

        3 => { 
return blot_reuse_principal_interface::Kind.external, Error.none; },

        _ => { return default<blot_reuse_principal_interface::Kind>(), Error.invalid_artifact; },
    }
}

fn write_blot_check_types__Scheme(writer: Writer&, value: blot_check_types::Scheme, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.root, depth + 1);

    write_blot_check_types__List(writer, value.variables, depth + 1);

    write_blot_check_types__List(writer, value.row_variables, depth + 1);

    write_blot_check_types__List(writer, value.closed_rows, depth + 1);

    write_blot_check_types__List(writer, value.obligations, depth + 1);

    write_blot_check_types__List(writer, value.generative, depth + 1);

}

fn read_blot_check_types__Scheme(reader: Reader&, depth: i64) -> blot_check_types::Scheme, Error {
    var result = default<blot_check_types::Scheme>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_types::Scheme>(), error; } result.root = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_check_types::Scheme>(), error; } result.variables = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_check_types::Scheme>(), error; } result.row_variables = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_check_types::Scheme>(), error; } result.closed_rows = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_check_types::Scheme>(), error; } result.obligations = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_check_types::Scheme>(), error; } result.generative = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__Body(writer: Writer&, value: blot_check_core::Body, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.binding, depth + 1);

    write_u32(writer, value.root, depth + 1);

    write_blot_check_core__List(writer, value.parameters, depth + 1);

    write_blot_check_types__Scheme(writer, value.scheme, depth + 1);

    write_blot_check_types__List(writer, value.closed_rows, depth + 1);

    write_blot_parse_ast__Span(writer, value.span, depth + 1);

    write_blot_check_core__Name(writer, value.declaration_name, depth + 1);

    write_blot_check_core__Name(writer, value.export_name, depth + 1);

    write_bool(writer, value.exported, depth + 1);

    write_bool(writer, value.runtime, depth + 1);

    write_bool(writer, value.is_function, depth + 1);

}

fn read_blot_check_core__Body(reader: Reader&, depth: i64) -> blot_check_core::Body, Error {
    var result = default<blot_check_core::Body>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Body>(), error; } result.binding = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Body>(), error; } result.root = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::Body>(), error; } result.parameters = decoded; }

    { let decoded, error = read_blot_check_types__Scheme(reader, depth + 1); if error != Error.none { return default<blot_check_core::Body>(), error; } result.scheme = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::Body>(), error; } result.closed_rows = decoded; }

    { let decoded, error = read_blot_parse_ast__Span(reader, depth + 1); if error != Error.none { return default<blot_check_core::Body>(), error; } result.span = decoded; }

    { let decoded, error = read_blot_check_core__Name(reader, depth + 1); if error != Error.none { return default<blot_check_core::Body>(), error; } result.declaration_name = decoded; }

    { let decoded, error = read_blot_check_core__Name(reader, depth + 1); if error != Error.none { return default<blot_check_core::Body>(), error; } result.export_name = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != Error.none { return default<blot_check_core::Body>(), error; } result.exported = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != Error.none { return default<blot_check_core::Body>(), error; } result.runtime = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != Error.none { return default<blot_check_core::Body>(), error; } result.is_function = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__Parameter(writer: Writer&, value: blot_check_core::Parameter, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.binding, depth + 1);

    write_u32(writer, value.ty, depth + 1);

    write_blot_parse_ast__Span(writer, value.span, depth + 1);

    write_bool(writer, value.inferred, depth + 1);

}

fn read_blot_check_core__Parameter(reader: Reader&, depth: i64) -> blot_check_core::Parameter, Error {
    var result = default<blot_check_core::Parameter>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Parameter>(), error; } result.binding = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Parameter>(), error; } result.ty = decoded; }

    { let decoded, error = read_blot_parse_ast__Span(reader, depth + 1); if error != Error.none { return default<blot_check_core::Parameter>(), error; } result.span = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != Error.none { return default<blot_check_core::Parameter>(), error; } result.inferred = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__CallInfo(writer: Writer&, value: blot_check_core::CallInfo, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_core__BindingRef(writer, value.target, depth + 1);

    write_u32(writer, value.callee_type, depth + 1);

}

fn read_blot_check_core__CallInfo(reader: Reader&, depth: i64) -> blot_check_core::CallInfo, Error {
    var result = default<blot_check_core::CallInfo>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_core__BindingRef(reader, depth + 1); if error != Error.none { return default<blot_check_core::CallInfo>(), error; } result.target = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::CallInfo>(), error; } result.callee_type = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__Merge(writer: Writer&, value: blot_check_core::Merge, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.node, depth + 1);

    write_u32(writer, value.result, depth + 1);

    write_u32(writer, value.then_binding, depth + 1);

    write_u32(writer, value.else_binding, depth + 1);

}

fn read_blot_check_core__Merge(reader: Reader&, depth: i64) -> blot_check_core::Merge, Error {
    var result = default<blot_check_core::Merge>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Merge>(), error; } result.node = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Merge>(), error; } result.result = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Merge>(), error; } result.then_binding = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Merge>(), error; } result.else_binding = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__Obligation(writer: Writer&, value: blot_check_core::Obligation, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.ty, depth + 1);

    write_blot_check_types__ObligationKind(writer, value.kind, depth + 1);

    write_blot_parse_ast__Span(writer, value.span, depth + 1);

    write_u32(writer, value.name, depth + 1);

    write_u32(writer, value.result, depth + 1);

    write_u32(writer, value.other, depth + 1);

    write_u32(writer, value.signature, depth + 1);

    write_blot_check_types__Operator(writer, value.operator, depth + 1);

    write_blot_check_types__NominalIdentity(writer, value.identity, depth + 1);

    write_bool(writer, value.explicit, depth + 1);

    write_blot_support__Option_blot_parse_ast__Span_(writer, value.qualification_span, depth + 1);

    write_u32(writer, value.qualification_unit, depth + 1);

    write_blot_check_core__Name(writer, value.diagnostic_name, depth + 1);

}

fn read_blot_check_core__Obligation(reader: Reader&, depth: i64) -> blot_check_core::Obligation, Error {
    var result = default<blot_check_core::Obligation>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Obligation>(), error; } result.ty = decoded; }

    { let decoded, error = read_blot_check_types__ObligationKind(reader, depth + 1); if error != Error.none { return default<blot_check_core::Obligation>(), error; } result.kind = decoded; }

    { let decoded, error = read_blot_parse_ast__Span(reader, depth + 1); if error != Error.none { return default<blot_check_core::Obligation>(), error; } result.span = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Obligation>(), error; } result.name = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Obligation>(), error; } result.result = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Obligation>(), error; } result.other = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Obligation>(), error; } result.signature = decoded; }

    { let decoded, error = read_blot_check_types__Operator(reader, depth + 1); if error != Error.none { return default<blot_check_core::Obligation>(), error; } result.operator = decoded; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != Error.none { return default<blot_check_core::Obligation>(), error; } result.identity = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != Error.none { return default<blot_check_core::Obligation>(), error; } result.explicit = decoded; }

    { let decoded, error = read_blot_support__Option_blot_parse_ast__Span_(reader, depth + 1); if error != Error.none { return default<blot_check_core::Obligation>(), error; } result.qualification_span = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Obligation>(), error; } result.qualification_unit = decoded; }

    { let decoded, error = read_blot_check_core__Name(reader, depth + 1); if error != Error.none { return default<blot_check_core::Obligation>(), error; } result.diagnostic_name = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__Nominal(writer: Writer&, value: blot_check_core::Nominal, depth: i64) {
    if !charge(writer, depth) { return; }

    write_bool(writer, value.affine, depth + 1);

    write_bool(writer, value.has_usage, depth + 1);

    write_bool(writer, value.closed_storage, depth + 1);

    write_bool(writer, value.private, depth + 1);

    write_bool(writer, value.is_opaque, depth + 1);

    write_blot_backend_opaque_storage__Storage(writer, value.storage, depth + 1);

    write_blot_check_core__Name(writer, value.diagnostic_name, depth + 1);

    write_blot_check_core__Name(writer, value.diagnostic_origin, depth + 1);

    write_blot_check_types__NominalIdentity(writer, value.identity, depth + 1);

    write_blot_check_types__List(writer, value.parameters, depth + 1);

    write_blot_check_types__List(writer, value.variables, depth + 1);

    write_blot_check_core__List(writer, value.constructors, depth + 1);

}

fn read_blot_check_core__Nominal(reader: Reader&, depth: i64) -> blot_check_core::Nominal, Error {
    var result = default<blot_check_core::Nominal>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_bool(reader, depth + 1); if error != Error.none { return default<blot_check_core::Nominal>(), error; } result.affine = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != Error.none { return default<blot_check_core::Nominal>(), error; } result.has_usage = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != Error.none { return default<blot_check_core::Nominal>(), error; } result.closed_storage = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != Error.none { return default<blot_check_core::Nominal>(), error; } result.private = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != Error.none { return default<blot_check_core::Nominal>(), error; } result.is_opaque = decoded; }

    { let decoded, error = read_blot_backend_opaque_storage__Storage(reader, depth + 1); if error != Error.none { return default<blot_check_core::Nominal>(), error; } result.storage = decoded; }

    { let decoded, error = read_blot_check_core__Name(reader, depth + 1); if error != Error.none { return default<blot_check_core::Nominal>(), error; } result.diagnostic_name = decoded; }

    { let decoded, error = read_blot_check_core__Name(reader, depth + 1); if error != Error.none { return default<blot_check_core::Nominal>(), error; } result.diagnostic_origin = decoded; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != Error.none { return default<blot_check_core::Nominal>(), error; } result.identity = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::Nominal>(), error; } result.parameters = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::Nominal>(), error; } result.variables = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::Nominal>(), error; } result.constructors = decoded; }

    return result, Error.none;
}

fn write_blot_backend_opaque_storage__Storage(writer: Writer&, value: blot_backend_opaque_storage::Storage, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_backend_opaque_storage__Kind(writer, value.kind, depth + 1);

    write_u32(writer, value.parameter, depth + 1);

    write_u32(writer, value.selector, depth + 1);

}

fn read_blot_backend_opaque_storage__Storage(reader: Reader&, depth: i64) -> blot_backend_opaque_storage::Storage, Error {
    var result = default<blot_backend_opaque_storage::Storage>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_backend_opaque_storage__Kind(reader, depth + 1); if error != Error.none { return default<blot_backend_opaque_storage::Storage>(), error; } result.kind = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_backend_opaque_storage::Storage>(), error; } result.parameter = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_backend_opaque_storage::Storage>(), error; } result.selector = decoded; }

    return result, Error.none;
}

fn write_blot_backend_opaque_storage__Kind(writer: Writer&, value: blot_backend_opaque_storage::Kind, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        blot_backend_opaque_storage::Kind.unknown => { put(writer, 0, 4); 
},

        blot_backend_opaque_storage::Kind.unit => { put(writer, 1, 4); 
},

        blot_backend_opaque_storage::Kind.boolean => { put(writer, 2, 4); 
},

        blot_backend_opaque_storage::Kind.unsigned32 => { put(writer, 3, 4); 
},

        blot_backend_opaque_storage::Kind.floating32 => { put(writer, 4, 4); 
},

        blot_backend_opaque_storage::Kind.reference => { put(writer, 5, 4); 
},

        blot_backend_opaque_storage::Kind.parameter => { put(writer, 6, 4); 
},

    }
}

fn read_blot_backend_opaque_storage__Kind(reader: Reader&, depth: i64) -> blot_backend_opaque_storage::Kind, Error {
    let charged = debit(reader, depth); if charged != Error.none { return default<blot_backend_opaque_storage::Kind>(), charged; } let tag, error = get(reader, 4); if error != Error.none { return default<blot_backend_opaque_storage::Kind>(), error; }
    match tag {

        0 => { 
return blot_backend_opaque_storage::Kind.unknown, Error.none; },

        1 => { 
return blot_backend_opaque_storage::Kind.unit, Error.none; },

        2 => { 
return blot_backend_opaque_storage::Kind.boolean, Error.none; },

        3 => { 
return blot_backend_opaque_storage::Kind.unsigned32, Error.none; },

        4 => { 
return blot_backend_opaque_storage::Kind.floating32, Error.none; },

        5 => { 
return blot_backend_opaque_storage::Kind.reference, Error.none; },

        6 => { 
return blot_backend_opaque_storage::Kind.parameter, Error.none; },

        _ => { return default<blot_backend_opaque_storage::Kind>(), Error.invalid_artifact; },
    }
}

fn write_blot_check_core__OperationName(writer: Writer&, value: blot_check_core::OperationName, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_types__NominalIdentity(writer, value.identity, depth + 1);

    write_blot_check_core__Name(writer, value.diagnostic_name, depth + 1);

    write_blot_check_core__Name(writer, value.diagnostic_origin, depth + 1);

    write_blot_check_types__List(writer, value.variables, depth + 1);

    write_blot_check_types__List(writer, value.parameters, depth + 1);

    write_u32(writer, value.parameter, depth + 1);

    write_u32(writer, value.result, depth + 1);

}

fn read_blot_check_core__OperationName(reader: Reader&, depth: i64) -> blot_check_core::OperationName, Error {
    var result = default<blot_check_core::OperationName>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != Error.none { return default<blot_check_core::OperationName>(), error; } result.identity = decoded; }

    { let decoded, error = read_blot_check_core__Name(reader, depth + 1); if error != Error.none { return default<blot_check_core::OperationName>(), error; } result.diagnostic_name = decoded; }

    { let decoded, error = read_blot_check_core__Name(reader, depth + 1); if error != Error.none { return default<blot_check_core::OperationName>(), error; } result.diagnostic_origin = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::OperationName>(), error; } result.variables = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::OperationName>(), error; } result.parameters = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::OperationName>(), error; } result.parameter = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::OperationName>(), error; } result.result = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__Constructor(writer: Writer&, value: blot_check_core::Constructor, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_types__NominalIdentity(writer, value.identity, depth + 1);

    write_u32(writer, value.nominal, depth + 1);

    write_u32(writer, value.tag, depth + 1);

    write_blot_check_types__Scheme(writer, value.scheme, depth + 1);

    write_u32(writer, value.payload, depth + 1);

}

fn read_blot_check_core__Constructor(reader: Reader&, depth: i64) -> blot_check_core::Constructor, Error {
    var result = default<blot_check_core::Constructor>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != Error.none { return default<blot_check_core::Constructor>(), error; } result.identity = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Constructor>(), error; } result.nominal = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Constructor>(), error; } result.tag = decoded; }

    { let decoded, error = read_blot_check_types__Scheme(reader, depth + 1); if error != Error.none { return default<blot_check_core::Constructor>(), error; } result.scheme = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Constructor>(), error; } result.payload = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__Projection(writer: Writer&, value: blot_check_core::Projection, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_types__NominalIdentity(writer, value.nominal, depth + 1);

    write_u32(writer, value.field, depth + 1);

    write_u32(writer, value.source_type, depth + 1);

    write_u32(writer, value.result_type, depth + 1);

    write_blot_check_core__List(writer, value.variants, depth + 1);

    write_u32(writer, value.diagnostic_point, depth + 1);

}

fn read_blot_check_core__Projection(reader: Reader&, depth: i64) -> blot_check_core::Projection, Error {
    var result = default<blot_check_core::Projection>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != Error.none { return default<blot_check_core::Projection>(), error; } result.nominal = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Projection>(), error; } result.field = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Projection>(), error; } result.source_type = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Projection>(), error; } result.result_type = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::Projection>(), error; } result.variants = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Projection>(), error; } result.diagnostic_point = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__ProjectionVariant(writer: Writer&, value: blot_check_core::ProjectionVariant, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.tag, depth + 1);

    write_u32(writer, value.field, depth + 1);

}

fn read_blot_check_core__ProjectionVariant(reader: Reader&, depth: i64) -> blot_check_core::ProjectionVariant, Error {
    var result = default<blot_check_core::ProjectionVariant>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::ProjectionVariant>(), error; } result.tag = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::ProjectionVariant>(), error; } result.field = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__Pattern(writer: Writer&, value: blot_check_core::Pattern, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_core__PatternTag(writer, value.tag, depth + 1);

    write_u32(writer, value.ty, depth + 1);

    write_u32(writer, value.a, depth + 1);

    write_u32(writer, value.b, depth + 1);

    write_u32(writer, value.c, depth + 1);

    write_blot_parse_ast__Span(writer, value.span, depth + 1);

}

fn read_blot_check_core__Pattern(reader: Reader&, depth: i64) -> blot_check_core::Pattern, Error {
    var result = default<blot_check_core::Pattern>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_core__PatternTag(reader, depth + 1); if error != Error.none { return default<blot_check_core::Pattern>(), error; } result.tag = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Pattern>(), error; } result.ty = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Pattern>(), error; } result.a = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Pattern>(), error; } result.b = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Pattern>(), error; } result.c = decoded; }

    { let decoded, error = read_blot_parse_ast__Span(reader, depth + 1); if error != Error.none { return default<blot_check_core::Pattern>(), error; } result.span = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__PatternTag(writer: Writer&, value: blot_check_core::PatternTag, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        blot_check_core::PatternTag.invalid => { put(writer, 0, 4); 
},

        blot_check_core::PatternTag.wildcard => { put(writer, 1, 4); 
},

        blot_check_core::PatternTag.bind => { put(writer, 2, 4); 
},

        blot_check_core::PatternTag.constant => { put(writer, 3, 4); 
},

        blot_check_core::PatternTag.value => { put(writer, 4, 4); 
},

        blot_check_core::PatternTag.product => { put(writer, 5, 4); 
},

        blot_check_core::PatternTag.constructor => { put(writer, 6, 4); 
},

        blot_check_core::PatternTag.record_payload => { put(writer, 7, 4); 
},

    }
}

fn read_blot_check_core__PatternTag(reader: Reader&, depth: i64) -> blot_check_core::PatternTag, Error {
    let charged = debit(reader, depth); if charged != Error.none { return default<blot_check_core::PatternTag>(), charged; } let tag, error = get(reader, 4); if error != Error.none { return default<blot_check_core::PatternTag>(), error; }
    match tag {

        0 => { 
return blot_check_core::PatternTag.invalid, Error.none; },

        1 => { 
return blot_check_core::PatternTag.wildcard, Error.none; },

        2 => { 
return blot_check_core::PatternTag.bind, Error.none; },

        3 => { 
return blot_check_core::PatternTag.constant, Error.none; },

        4 => { 
return blot_check_core::PatternTag.value, Error.none; },

        5 => { 
return blot_check_core::PatternTag.product, Error.none; },

        6 => { 
return blot_check_core::PatternTag.constructor, Error.none; },

        7 => { 
return blot_check_core::PatternTag.record_payload, Error.none; },

        _ => { return default<blot_check_core::PatternTag>(), Error.invalid_artifact; },
    }
}

fn write_blot_check_core__PatternRow(writer: Writer&, value: blot_check_core::PatternRow, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_core__List(writer, value.patterns, depth + 1);

}

fn read_blot_check_core__PatternRow(reader: Reader&, depth: i64) -> blot_check_core::PatternRow, Error {
    var result = default<blot_check_core::PatternRow>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::PatternRow>(), error; } result.patterns = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__MatchArm(writer: Writer&, value: blot_check_core::MatchArm, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_core__List(writer, value.rows, depth + 1);

    write_u32(writer, value.guard, depth + 1);

    write_u32(writer, value.body, depth + 1);

    write_blot_parse_ast__Span(writer, value.span, depth + 1);

}

fn read_blot_check_core__MatchArm(reader: Reader&, depth: i64) -> blot_check_core::MatchArm, Error {
    var result = default<blot_check_core::MatchArm>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::MatchArm>(), error; } result.rows = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::MatchArm>(), error; } result.guard = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::MatchArm>(), error; } result.body = decoded; }

    { let decoded, error = read_blot_parse_ast__Span(reader, depth + 1); if error != Error.none { return default<blot_check_core::MatchArm>(), error; } result.span = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__MatchInfo(writer: Writer&, value: blot_check_core::MatchInfo, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_core__List(writer, value.inputs, depth + 1);

    write_blot_check_core__List(writer, value.arms, depth + 1);

    write_bool(writer, value.statement, depth + 1);

}

fn read_blot_check_core__MatchInfo(reader: Reader&, depth: i64) -> blot_check_core::MatchInfo, Error {
    var result = default<blot_check_core::MatchInfo>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::MatchInfo>(), error; } result.inputs = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::MatchInfo>(), error; } result.arms = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != Error.none { return default<blot_check_core::MatchInfo>(), error; } result.statement = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__UpdateInfo(writer: Writer&, value: blot_check_core::UpdateInfo, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.root, depth + 1);

    write_blot_check_core__List(writer, value.path, depth + 1);

    write_u32(writer, value.value, depth + 1);

    write_u32(writer, value.self_binding, depth + 1);

    write_blot_check_core__List(writer, value.selectors, depth + 1);

}

fn read_blot_check_core__UpdateInfo(reader: Reader&, depth: i64) -> blot_check_core::UpdateInfo, Error {
    var result = default<blot_check_core::UpdateInfo>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::UpdateInfo>(), error; } result.root = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::UpdateInfo>(), error; } result.path = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::UpdateInfo>(), error; } result.value = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::UpdateInfo>(), error; } result.self_binding = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::UpdateInfo>(), error; } result.selectors = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__UpdateStep(writer: Writer&, value: blot_check_core::UpdateStep, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_core__UpdateKind(writer, value.kind, depth + 1);

    write_u32(writer, value.projection, depth + 1);

    write_u32(writer, value.index, depth + 1);

    write_u32(writer, value.source_type, depth + 1);

    write_u32(writer, value.result_type, depth + 1);

}

fn read_blot_check_core__UpdateStep(reader: Reader&, depth: i64) -> blot_check_core::UpdateStep, Error {
    var result = default<blot_check_core::UpdateStep>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_core__UpdateKind(reader, depth + 1); if error != Error.none { return default<blot_check_core::UpdateStep>(), error; } result.kind = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::UpdateStep>(), error; } result.projection = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::UpdateStep>(), error; } result.index = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::UpdateStep>(), error; } result.source_type = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::UpdateStep>(), error; } result.result_type = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__UpdateKind(writer: Writer&, value: blot_check_core::UpdateKind, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        blot_check_core::UpdateKind.field => { put(writer, 0, 4); 
},

        blot_check_core::UpdateKind.index => { put(writer, 1, 4); 
},

    }
}

fn read_blot_check_core__UpdateKind(reader: Reader&, depth: i64) -> blot_check_core::UpdateKind, Error {
    let charged = debit(reader, depth); if charged != Error.none { return default<blot_check_core::UpdateKind>(), charged; } let tag, error = get(reader, 4); if error != Error.none { return default<blot_check_core::UpdateKind>(), error; }
    match tag {

        0 => { 
return blot_check_core::UpdateKind.field, Error.none; },

        1 => { 
return blot_check_core::UpdateKind.index, Error.none; },

        _ => { return default<blot_check_core::UpdateKind>(), Error.invalid_artifact; },
    }
}

fn write_blot_check_core__ClosureInfo(writer: Writer&, value: blot_check_core::ClosureInfo, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.qualifier, depth + 1);

    write_u32(writer, value.body, depth + 1);

    write_blot_check_core__Parameter(writer, value.parameter, depth + 1);

    write_blot_check_core__List(writer, value.captures, depth + 1);

    write_u32(writer, value.function_type, depth + 1);

    write_blot_check_types__List(writer, value.closed_rows, depth + 1);

}

fn read_blot_check_core__ClosureInfo(reader: Reader&, depth: i64) -> blot_check_core::ClosureInfo, Error {
    var result = default<blot_check_core::ClosureInfo>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::ClosureInfo>(), error; } result.qualifier = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::ClosureInfo>(), error; } result.body = decoded; }

    { let decoded, error = read_blot_check_core__Parameter(reader, depth + 1); if error != Error.none { return default<blot_check_core::ClosureInfo>(), error; } result.parameter = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::ClosureInfo>(), error; } result.captures = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::ClosureInfo>(), error; } result.function_type = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::ClosureInfo>(), error; } result.closed_rows = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__Associated(writer: Writer&, value: blot_check_core::Associated, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_types__NominalIdentity(writer, value.identity, depth + 1);

    write_u32(writer, value.member, depth + 1);

    write_blot_check_types__Operator(writer, value.operator, depth + 1);

    write_blot_check_core__BindingRef(writer, value.target, depth + 1);

}

fn read_blot_check_core__Associated(reader: Reader&, depth: i64) -> blot_check_core::Associated, Error {
    var result = default<blot_check_core::Associated>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != Error.none { return default<blot_check_core::Associated>(), error; } result.identity = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Associated>(), error; } result.member = decoded; }

    { let decoded, error = read_blot_check_types__Operator(reader, depth + 1); if error != Error.none { return default<blot_check_core::Associated>(), error; } result.operator = decoded; }

    { let decoded, error = read_blot_check_core__BindingRef(reader, depth + 1); if error != Error.none { return default<blot_check_core::Associated>(), error; } result.target = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__Contract(writer: Writer&, value: blot_check_core::Contract, depth: i64) {
    if !charge(writer, depth) { return; }

    write_bool(writer, value.private, depth + 1);

    write_blot_check_types__NominalIdentity(writer, value.identity, depth + 1);

    write_u32(writer, value.name, depth + 1);

    write_blot_check_types__List(writer, value.parameters, depth + 1);

    write_blot_check_types__List(writer, value.variables, depth + 1);

    write_blot_check_types__List(writer, value.row_variables, depth + 1);

    write_blot_check_types__List(writer, value.predicates, depth + 1);

    write_blot_check_types__List(writer, value.members, depth + 1);

    write_bool(writer, value.requires_implementation, depth + 1);

    write_blot_check_types__List(writer, value.row_parameter_names, depth + 1);

    write_blot_check_types__List(writer, value.row_parameters, depth + 1);

}

fn read_blot_check_core__Contract(reader: Reader&, depth: i64) -> blot_check_core::Contract, Error {
    var result = default<blot_check_core::Contract>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_bool(reader, depth + 1); if error != Error.none { return default<blot_check_core::Contract>(), error; } result.private = decoded; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != Error.none { return default<blot_check_core::Contract>(), error; } result.identity = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::Contract>(), error; } result.name = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::Contract>(), error; } result.parameters = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::Contract>(), error; } result.variables = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::Contract>(), error; } result.row_variables = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::Contract>(), error; } result.predicates = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::Contract>(), error; } result.members = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != Error.none { return default<blot_check_core::Contract>(), error; } result.requires_implementation = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::Contract>(), error; } result.row_parameter_names = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::Contract>(), error; } result.row_parameters = decoded; }

    return result, Error.none;
}

fn write_blot_reuse_principal_interface__ContractMember(writer: Writer&, value: blot_reuse_principal_interface::ContractMember, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_types__NominalIdentity(writer, value.contract, depth + 1);

    write_u32(writer, value.name, depth + 1);

    write_blot_reuse_principal_interface__ContractMemberKind(writer, value.kind, depth + 1);

    write_u32(writer, value.root, depth + 1);

}

fn read_blot_reuse_principal_interface__ContractMember(reader: Reader&, depth: i64) -> blot_reuse_principal_interface::ContractMember, Error {
    var result = default<blot_reuse_principal_interface::ContractMember>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::ContractMember>(), error; } result.contract = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::ContractMember>(), error; } result.name = decoded; }

    { let decoded, error = read_blot_reuse_principal_interface__ContractMemberKind(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::ContractMember>(), error; } result.kind = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::ContractMember>(), error; } result.root = decoded; }

    return result, Error.none;
}

fn write_blot_reuse_principal_interface__ContractMemberKind(writer: Writer&, value: blot_reuse_principal_interface::ContractMemberKind, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        blot_reuse_principal_interface::ContractMemberKind.defined_type => { put(writer, 0, 4); 
},

        blot_reuse_principal_interface::ContractMemberKind.abstract_type => { put(writer, 1, 4); 
},

        blot_reuse_principal_interface::ContractMemberKind.value => { put(writer, 2, 4); 
},

    }
}

fn read_blot_reuse_principal_interface__ContractMemberKind(reader: Reader&, depth: i64) -> blot_reuse_principal_interface::ContractMemberKind, Error {
    let charged = debit(reader, depth); if charged != Error.none { return default<blot_reuse_principal_interface::ContractMemberKind>(), charged; } let tag, error = get(reader, 4); if error != Error.none { return default<blot_reuse_principal_interface::ContractMemberKind>(), error; }
    match tag {

        0 => { 
return blot_reuse_principal_interface::ContractMemberKind.defined_type, Error.none; },

        1 => { 
return blot_reuse_principal_interface::ContractMemberKind.abstract_type, Error.none; },

        2 => { 
return blot_reuse_principal_interface::ContractMemberKind.value, Error.none; },

        _ => { return default<blot_reuse_principal_interface::ContractMemberKind>(), Error.invalid_artifact; },
    }
}

fn write_blot_reuse_principal_interface__Implementation(writer: Writer&, value: blot_reuse_principal_interface::Implementation, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_support__Option_blot_parse_ast__Span_(writer, value.origin_span, depth + 1);

    write_u32(writer, value.declaration, depth + 1);

    write_bool(writer, value.private, depth + 1);

    write_blot_check_types__NominalIdentity(writer, value.identity, depth + 1);

    write_u32(writer, value.name, depth + 1);

    write_blot_check_types__NominalIdentity(writer, value.contract, depth + 1);

    write_blot_check_types__List(writer, value.head, depth + 1);

    write_blot_check_types__List(writer, value.variables, depth + 1);

    write_blot_check_types__List(writer, value.parameter_names, depth + 1);

    write_blot_check_types__List(writer, value.row_variables, depth + 1);

    write_blot_check_types__List(writer, value.row_parameter_names, depth + 1);

    write_blot_check_types__List(writer, value.row_parameters, depth + 1);

    write_blot_check_types__List(writer, value.predicates, depth + 1);

    write_blot_check_types__List(writer, value.members, depth + 1);

}

fn read_blot_reuse_principal_interface__Implementation(reader: Reader&, depth: i64) -> blot_reuse_principal_interface::Implementation, Error {
    var result = default<blot_reuse_principal_interface::Implementation>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_support__Option_blot_parse_ast__Span_(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::Implementation>(), error; } result.origin_span = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::Implementation>(), error; } result.declaration = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::Implementation>(), error; } result.private = decoded; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::Implementation>(), error; } result.identity = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::Implementation>(), error; } result.name = decoded; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::Implementation>(), error; } result.contract = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::Implementation>(), error; } result.head = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::Implementation>(), error; } result.variables = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::Implementation>(), error; } result.parameter_names = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::Implementation>(), error; } result.row_variables = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::Implementation>(), error; } result.row_parameter_names = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::Implementation>(), error; } result.row_parameters = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::Implementation>(), error; } result.predicates = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::Implementation>(), error; } result.members = decoded; }

    return result, Error.none;
}

fn write_blot_reuse_principal_interface__ImplementationMember(writer: Writer&, value: blot_reuse_principal_interface::ImplementationMember, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.name, depth + 1);

    write_blot_reuse_principal_interface__ImplementationMemberKind(writer, value.kind, depth + 1);

    write_u32(writer, value.root, depth + 1);

    write_blot_reuse_principal_interface__ExternalTarget(writer, value.target, depth + 1);

}

fn read_blot_reuse_principal_interface__ImplementationMember(reader: Reader&, depth: i64) -> blot_reuse_principal_interface::ImplementationMember, Error {
    var result = default<blot_reuse_principal_interface::ImplementationMember>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::ImplementationMember>(), error; } result.name = decoded; }

    { let decoded, error = read_blot_reuse_principal_interface__ImplementationMemberKind(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::ImplementationMember>(), error; } result.kind = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::ImplementationMember>(), error; } result.root = decoded; }

    { let decoded, error = read_blot_reuse_principal_interface__ExternalTarget(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::ImplementationMember>(), error; } result.target = decoded; }

    return result, Error.none;
}

fn write_blot_reuse_principal_interface__ImplementationMemberKind(writer: Writer&, value: blot_reuse_principal_interface::ImplementationMemberKind, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        blot_reuse_principal_interface::ImplementationMemberKind.type_ => { put(writer, 0, 4); 
},

        blot_reuse_principal_interface::ImplementationMemberKind.value => { put(writer, 1, 4); 
},

    }
}

fn read_blot_reuse_principal_interface__ImplementationMemberKind(reader: Reader&, depth: i64) -> blot_reuse_principal_interface::ImplementationMemberKind, Error {
    let charged = debit(reader, depth); if charged != Error.none { return default<blot_reuse_principal_interface::ImplementationMemberKind>(), charged; } let tag, error = get(reader, 4); if error != Error.none { return default<blot_reuse_principal_interface::ImplementationMemberKind>(), error; }
    match tag {

        0 => { 
return blot_reuse_principal_interface::ImplementationMemberKind.type_, Error.none; },

        1 => { 
return blot_reuse_principal_interface::ImplementationMemberKind.value, Error.none; },

        _ => { return default<blot_reuse_principal_interface::ImplementationMemberKind>(), Error.invalid_artifact; },
    }
}

fn write_blot_reuse_principal_interface__ExternalTarget(writer: Writer&, value: blot_reuse_principal_interface::ExternalTarget, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.unit, depth + 1);

    write_u32(writer, value.binding, depth + 1);

}

fn read_blot_reuse_principal_interface__ExternalTarget(reader: Reader&, depth: i64) -> blot_reuse_principal_interface::ExternalTarget, Error {
    var result = default<blot_reuse_principal_interface::ExternalTarget>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::ExternalTarget>(), error; } result.unit = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::ExternalTarget>(), error; } result.binding = decoded; }

    return result, Error.none;
}

fn write_blot_reuse_principal_interface__MemberTemplate(writer: Writer&, value: blot_reuse_principal_interface::MemberTemplate, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.binding, depth + 1);

    write_blot_check_types__NominalIdentity(writer, value.contract, depth + 1);

    write_u32(writer, value.name, depth + 1);

    write_blot_check_types__List(writer, value.arguments, depth + 1);

}

fn read_blot_reuse_principal_interface__MemberTemplate(reader: Reader&, depth: i64) -> blot_reuse_principal_interface::MemberTemplate, Error {
    var result = default<blot_reuse_principal_interface::MemberTemplate>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::MemberTemplate>(), error; } result.binding = decoded; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::MemberTemplate>(), error; } result.contract = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::MemberTemplate>(), error; } result.name = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::MemberTemplate>(), error; } result.arguments = decoded; }

    return result, Error.none;
}

fn write_blot_reuse_principal_interface__SelectedProof(writer: Writer&, value: blot_reuse_principal_interface::SelectedProof, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_reuse_principal_interface__ExternalTarget(writer, value.predicate_target, depth + 1);

    write_u32(writer, value.context, depth + 1);

    write_blot_reuse_principal_interface__SelectedProofKind(writer, value.kind, depth + 1);

    write_blot_check_types__Obligation(writer, value.predicate, depth + 1);

    write_blot_check_types__NominalIdentity(writer, value.implementation, depth + 1);

    write_blot_check_types__NominalIdentity(writer, value.contract, depth + 1);

    write_blot_check_types__List(writer, value.arguments, depth + 1);

    write_blot_check_types__List(writer, value.members, depth + 1);

    write_blot_check_types__List(writer, value.prerequisites, depth + 1);

}

fn read_blot_reuse_principal_interface__SelectedProof(reader: Reader&, depth: i64) -> blot_reuse_principal_interface::SelectedProof, Error {
    var result = default<blot_reuse_principal_interface::SelectedProof>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_reuse_principal_interface__ExternalTarget(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::SelectedProof>(), error; } result.predicate_target = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::SelectedProof>(), error; } result.context = decoded; }

    { let decoded, error = read_blot_reuse_principal_interface__SelectedProofKind(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::SelectedProof>(), error; } result.kind = decoded; }

    { let decoded, error = read_blot_check_types__Obligation(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::SelectedProof>(), error; } result.predicate = decoded; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::SelectedProof>(), error; } result.implementation = decoded; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::SelectedProof>(), error; } result.contract = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::SelectedProof>(), error; } result.arguments = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::SelectedProof>(), error; } result.members = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_reuse_principal_interface::SelectedProof>(), error; } result.prerequisites = decoded; }

    return result, Error.none;
}

fn write_blot_reuse_principal_interface__SelectedProofKind(writer: Writer&, value: blot_reuse_principal_interface::SelectedProofKind, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        blot_reuse_principal_interface::SelectedProofKind.implementation => { put(writer, 0, 4); 
},

        blot_reuse_principal_interface::SelectedProofKind.predicate => { put(writer, 1, 4); 
},

    }
}

fn read_blot_reuse_principal_interface__SelectedProofKind(reader: Reader&, depth: i64) -> blot_reuse_principal_interface::SelectedProofKind, Error {
    let charged = debit(reader, depth); if charged != Error.none { return default<blot_reuse_principal_interface::SelectedProofKind>(), charged; } let tag, error = get(reader, 4); if error != Error.none { return default<blot_reuse_principal_interface::SelectedProofKind>(), error; }
    match tag {

        0 => { 
return blot_reuse_principal_interface::SelectedProofKind.implementation, Error.none; },

        1 => { 
return blot_reuse_principal_interface::SelectedProofKind.predicate, Error.none; },

        _ => { return default<blot_reuse_principal_interface::SelectedProofKind>(), Error.invalid_artifact; },
    }
}

fn write_blot_check_core__SelectedUse(writer: Writer&, value: blot_check_core::SelectedUse, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.node, depth + 1);

    write_u32(writer, value.proof, depth + 1);

}

fn read_blot_check_core__SelectedUse(reader: Reader&, depth: i64) -> blot_check_core::SelectedUse, Error {
    var result = default<blot_check_core::SelectedUse>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::SelectedUse>(), error; } result.node = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::SelectedUse>(), error; } result.proof = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__DictionarySelection(writer: Writer&, value: blot_check_core::DictionarySelection, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.owner, depth + 1);

    write_u32(writer, value.quantifier, depth + 1);

    write_u32(writer, value.goal, depth + 1);

    write_blot_check_core__DictionaryProof(writer, value.proof, depth + 1);

    write_blot_check_core__List(writer, value.members, depth + 1);

    write_blot_check_core__List(writer, value.contents, depth + 1);

}

fn read_blot_check_core__DictionarySelection(reader: Reader&, depth: i64) -> blot_check_core::DictionarySelection, Error {
    var result = default<blot_check_core::DictionarySelection>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::DictionarySelection>(), error; } result.owner = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::DictionarySelection>(), error; } result.quantifier = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::DictionarySelection>(), error; } result.goal = decoded; }

    { let decoded, error = read_blot_check_core__DictionaryProof(reader, depth + 1); if error != Error.none { return default<blot_check_core::DictionarySelection>(), error; } result.proof = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::DictionarySelection>(), error; } result.members = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::DictionarySelection>(), error; } result.contents = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__DictionaryProof(writer: Writer&, value: blot_check_core::DictionaryProof, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        blot_check_core::DictionaryProof.selected payload => { put(writer, 0, 4); 
write_u32(writer, payload.value, depth + 1); 
},

        blot_check_core::DictionaryProof.given payload => { put(writer, 1, 4); 
write_blot_check_core__DictionaryGiven(writer, payload.value, depth + 1); 
},

    }
}

fn read_blot_check_core__DictionaryProof(reader: Reader&, depth: i64) -> blot_check_core::DictionaryProof, Error {
    let charged = debit(reader, depth); if charged != Error.none { return default<blot_check_core::DictionaryProof>(), charged; } let tag, error = get(reader, 4); if error != Error.none { return default<blot_check_core::DictionaryProof>(), error; }
    match tag {

        0 => { 
let value, failure_value = read_u32(reader, depth + 1); if failure_value != Error.none { return default<blot_check_core::DictionaryProof>(), failure_value; } 
return blot_check_core::DictionaryProof.selected { value: value , ..}, Error.none; },

        1 => { 
let value, failure_value = read_blot_check_core__DictionaryGiven(reader, depth + 1); if failure_value != Error.none { return default<blot_check_core::DictionaryProof>(), failure_value; } 
return blot_check_core::DictionaryProof.given { value: value , ..}, Error.none; },

        _ => { return default<blot_check_core::DictionaryProof>(), Error.invalid_artifact; },
    }
}

fn write_blot_check_core__DictionaryGiven(writer: Writer&, value: blot_check_core::DictionaryGiven, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.opening, depth + 1);

    write_u32(writer, value.introduction, depth + 1);

    write_u32(writer, value.quantifier, depth + 1);

    write_u32(writer, value.goal, depth + 1);

    write_blot_check_types__List(writer, value.arguments, depth + 1);

}

fn read_blot_check_core__DictionaryGiven(reader: Reader&, depth: i64) -> blot_check_core::DictionaryGiven, Error {
    var result = default<blot_check_core::DictionaryGiven>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::DictionaryGiven>(), error; } result.opening = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::DictionaryGiven>(), error; } result.introduction = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::DictionaryGiven>(), error; } result.quantifier = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::DictionaryGiven>(), error; } result.goal = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::DictionaryGiven>(), error; } result.arguments = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__DictionaryUse(writer: Writer&, value: blot_check_core::DictionaryUse, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.node, depth + 1);

    write_u32(writer, value.binding, depth + 1);

    write_u32(writer, value.opening, depth + 1);

    write_u32(writer, value.introduction, depth + 1);

    write_u32(writer, value.quantifier, depth + 1);

    write_u32(writer, value.goal, depth + 1);

    write_u32(writer, value.member, depth + 1);

}

fn read_blot_check_core__DictionaryUse(reader: Reader&, depth: i64) -> blot_check_core::DictionaryUse, Error {
    var result = default<blot_check_core::DictionaryUse>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::DictionaryUse>(), error; } result.node = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::DictionaryUse>(), error; } result.binding = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::DictionaryUse>(), error; } result.opening = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::DictionaryUse>(), error; } result.introduction = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::DictionaryUse>(), error; } result.quantifier = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::DictionaryUse>(), error; } result.goal = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::DictionaryUse>(), error; } result.member = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__Primitive(writer: Writer&, value: blot_check_core::Primitive, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_core__PrimitiveKind(writer, value.kind, depth + 1);

    write_blot_check_core__Op(writer, value.op, depth + 1);

    write_blot_backend_collection_ops__Op(writer, value.array_op, depth + 1);

    write_u8(writer, value.arity, depth + 1);

}

fn read_blot_check_core__Primitive(reader: Reader&, depth: i64) -> blot_check_core::Primitive, Error {
    var result = default<blot_check_core::Primitive>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_core__PrimitiveKind(reader, depth + 1); if error != Error.none { return default<blot_check_core::Primitive>(), error; } result.kind = decoded; }

    { let decoded, error = read_blot_check_core__Op(reader, depth + 1); if error != Error.none { return default<blot_check_core::Primitive>(), error; } result.op = decoded; }

    { let decoded, error = read_blot_backend_collection_ops__Op(reader, depth + 1); if error != Error.none { return default<blot_check_core::Primitive>(), error; } result.array_op = decoded; }

    { let decoded, error = read_u8(reader, depth + 1); if error != Error.none { return default<blot_check_core::Primitive>(), error; } result.arity = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__PrimitiveKind(writer: Writer&, value: blot_check_core::PrimitiveKind, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        blot_check_core::PrimitiveKind.scalar => { put(writer, 0, 4); 
},

        blot_check_core::PrimitiveKind.array => { put(writer, 1, 4); 
},

    }
}

fn read_blot_check_core__PrimitiveKind(reader: Reader&, depth: i64) -> blot_check_core::PrimitiveKind, Error {
    let charged = debit(reader, depth); if charged != Error.none { return default<blot_check_core::PrimitiveKind>(), charged; } let tag, error = get(reader, 4); if error != Error.none { return default<blot_check_core::PrimitiveKind>(), error; }
    match tag {

        0 => { 
return blot_check_core::PrimitiveKind.scalar, Error.none; },

        1 => { 
return blot_check_core::PrimitiveKind.array, Error.none; },

        _ => { return default<blot_check_core::PrimitiveKind>(), Error.invalid_artifact; },
    }
}

fn write_blot_backend_collection_ops__Op(writer: Writer&, value: blot_backend_collection_ops::Op, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        blot_backend_collection_ops::Op.length => { put(writer, 0, 4); 
},

        blot_backend_collection_ops::Op.get => { put(writer, 1, 4); 
},

        blot_backend_collection_ops::Op.set => { put(writer, 2, 4); 
},

        blot_backend_collection_ops::Op.fill => { put(writer, 3, 4); 
},

        blot_backend_collection_ops::Op.generate => { put(writer, 4, 4); 
},

        blot_backend_collection_ops::Op.append => { put(writer, 5, 4); 
},

        blot_backend_collection_ops::Op.prepend => { put(writer, 6, 4); 
},

        blot_backend_collection_ops::Op.identity => { put(writer, 7, 4); 
},

        blot_backend_collection_ops::Op.convert => { put(writer, 8, 4); 
},

        blot_backend_collection_ops::Op.cursor => { put(writer, 9, 4); 
},

        blot_backend_collection_ops::Op.cursor_has => { put(writer, 10, 4); 
},

        blot_backend_collection_ops::Op.cursor_value => { put(writer, 11, 4); 
},

        blot_backend_collection_ops::Op.cursor_advance => { put(writer, 12, 4); 
},

        blot_backend_collection_ops::Op.concat => { put(writer, 13, 4); 
},

        blot_backend_collection_ops::Op.slice => { put(writer, 14, 4); 
},

        blot_backend_collection_ops::Op.simd_load => { put(writer, 15, 4); 
},

        blot_backend_collection_ops::Op.simd_store => { put(writer, 16, 4); 
},

        blot_backend_collection_ops::Op.flatten => { put(writer, 17, 4); 
},

    }
}

fn read_blot_backend_collection_ops__Op(reader: Reader&, depth: i64) -> blot_backend_collection_ops::Op, Error {
    let charged = debit(reader, depth); if charged != Error.none { return default<blot_backend_collection_ops::Op>(), charged; } let tag, error = get(reader, 4); if error != Error.none { return default<blot_backend_collection_ops::Op>(), error; }
    match tag {

        0 => { 
return blot_backend_collection_ops::Op.length, Error.none; },

        1 => { 
return blot_backend_collection_ops::Op.get, Error.none; },

        2 => { 
return blot_backend_collection_ops::Op.set, Error.none; },

        3 => { 
return blot_backend_collection_ops::Op.fill, Error.none; },

        4 => { 
return blot_backend_collection_ops::Op.generate, Error.none; },

        5 => { 
return blot_backend_collection_ops::Op.append, Error.none; },

        6 => { 
return blot_backend_collection_ops::Op.prepend, Error.none; },

        7 => { 
return blot_backend_collection_ops::Op.identity, Error.none; },

        8 => { 
return blot_backend_collection_ops::Op.convert, Error.none; },

        9 => { 
return blot_backend_collection_ops::Op.cursor, Error.none; },

        10 => { 
return blot_backend_collection_ops::Op.cursor_has, Error.none; },

        11 => { 
return blot_backend_collection_ops::Op.cursor_value, Error.none; },

        12 => { 
return blot_backend_collection_ops::Op.cursor_advance, Error.none; },

        13 => { 
return blot_backend_collection_ops::Op.concat, Error.none; },

        14 => { 
return blot_backend_collection_ops::Op.slice, Error.none; },

        15 => { 
return blot_backend_collection_ops::Op.simd_load, Error.none; },

        16 => { 
return blot_backend_collection_ops::Op.simd_store, Error.none; },

        17 => { 
return blot_backend_collection_ops::Op.flatten, Error.none; },

        _ => { return default<blot_backend_collection_ops::Op>(), Error.invalid_artifact; },
    }
}

fn write_blot_check_core__LoopInfo(writer: Writer&, value: blot_check_core::LoopInfo, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_core__LoopKind(writer, value.kind, depth + 1);

    write_u32(writer, value.first, depth + 1);

    write_u32(writer, value.end, depth + 1);

    write_u32(writer, value.pattern, depth + 1);

    write_u32(writer, value.body, depth + 1);

    write_blot_check_core__List(writer, value.carries, depth + 1);

    write_bool(writer, value.can_exit, depth + 1);

}

fn read_blot_check_core__LoopInfo(reader: Reader&, depth: i64) -> blot_check_core::LoopInfo, Error {
    var result = default<blot_check_core::LoopInfo>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_core__LoopKind(reader, depth + 1); if error != Error.none { return default<blot_check_core::LoopInfo>(), error; } result.kind = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::LoopInfo>(), error; } result.first = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::LoopInfo>(), error; } result.end = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::LoopInfo>(), error; } result.pattern = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::LoopInfo>(), error; } result.body = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::LoopInfo>(), error; } result.carries = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != Error.none { return default<blot_check_core::LoopInfo>(), error; } result.can_exit = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__LoopKind(writer: Writer&, value: blot_check_core::LoopKind, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        blot_check_core::LoopKind.forever => { put(writer, 0, 4); 
},

        blot_check_core::LoopKind.range => { put(writer, 1, 4); 
},

        blot_check_core::LoopKind.array => { put(writer, 2, 4); 
},

    }
}

fn read_blot_check_core__LoopKind(reader: Reader&, depth: i64) -> blot_check_core::LoopKind, Error {
    let charged = debit(reader, depth); if charged != Error.none { return default<blot_check_core::LoopKind>(), charged; } let tag, error = get(reader, 4); if error != Error.none { return default<blot_check_core::LoopKind>(), error; }
    match tag {

        0 => { 
return blot_check_core::LoopKind.forever, Error.none; },

        1 => { 
return blot_check_core::LoopKind.range, Error.none; },

        2 => { 
return blot_check_core::LoopKind.array, Error.none; },

        _ => { return default<blot_check_core::LoopKind>(), Error.invalid_artifact; },
    }
}

fn write_blot_check_core__LoopCarry(writer: Writer&, value: blot_check_core::LoopCarry, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.incoming, depth + 1);

    write_u32(writer, value.iteration, depth + 1);

    write_u32(writer, value.backedge, depth + 1);

    write_u32(writer, value.outgoing, depth + 1);

}

fn read_blot_check_core__LoopCarry(reader: Reader&, depth: i64) -> blot_check_core::LoopCarry, Error {
    var result = default<blot_check_core::LoopCarry>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::LoopCarry>(), error; } result.incoming = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::LoopCarry>(), error; } result.iteration = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::LoopCarry>(), error; } result.backedge = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::LoopCarry>(), error; } result.outgoing = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__ResolverInfo(writer: Writer&, value: blot_check_core::ResolverInfo, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_core__ResolverOperation(writer, value.operation, depth + 1);

    write_u32(writer, value.resolver, depth + 1);

    write_blot_check_core__List(writer, value.arguments, depth + 1);

    write_u32(writer, value.member, depth + 1);

    write_blot_check_core__BindingRef(writer, value.method, depth + 1);

    write_u32(writer, value.method_type, depth + 1);

}

fn read_blot_check_core__ResolverInfo(reader: Reader&, depth: i64) -> blot_check_core::ResolverInfo, Error {
    var result = default<blot_check_core::ResolverInfo>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_core__ResolverOperation(reader, depth + 1); if error != Error.none { return default<blot_check_core::ResolverInfo>(), error; } result.operation = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::ResolverInfo>(), error; } result.resolver = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::ResolverInfo>(), error; } result.arguments = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::ResolverInfo>(), error; } result.member = decoded; }

    { let decoded, error = read_blot_check_core__BindingRef(reader, depth + 1); if error != Error.none { return default<blot_check_core::ResolverInfo>(), error; } result.method = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::ResolverInfo>(), error; } result.method_type = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__ResolverOperation(writer: Writer&, value: blot_check_core::ResolverOperation, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        blot_check_core::ResolverOperation.monad => { put(writer, 0, 4); 
},

        blot_check_core::ResolverOperation.pure => { put(writer, 1, 4); 
},

        blot_check_core::ResolverOperation.bind => { put(writer, 2, 4); 
},

        blot_check_core::ResolverOperation.forward => { put(writer, 3, 4); 
},

        blot_check_core::ResolverOperation.iterate => { put(writer, 4, 4); 
},

        blot_check_core::ResolverOperation.run => { put(writer, 5, 4); 
},

    }
}

fn read_blot_check_core__ResolverOperation(reader: Reader&, depth: i64) -> blot_check_core::ResolverOperation, Error {
    let charged = debit(reader, depth); if charged != Error.none { return default<blot_check_core::ResolverOperation>(), charged; } let tag, error = get(reader, 4); if error != Error.none { return default<blot_check_core::ResolverOperation>(), error; }
    match tag {

        0 => { 
return blot_check_core::ResolverOperation.monad, Error.none; },

        1 => { 
return blot_check_core::ResolverOperation.pure, Error.none; },

        2 => { 
return blot_check_core::ResolverOperation.bind, Error.none; },

        3 => { 
return blot_check_core::ResolverOperation.forward, Error.none; },

        4 => { 
return blot_check_core::ResolverOperation.iterate, Error.none; },

        5 => { 
return blot_check_core::ResolverOperation.run, Error.none; },

        _ => { return default<blot_check_core::ResolverOperation>(), Error.invalid_artifact; },
    }
}

fn write_blot_check_core__OperationValue(writer: Writer&, value: blot_check_core::OperationValue, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_types__NominalIdentity(writer, value.identity, depth + 1);

    write_blot_check_types__List(writer, value.arguments, depth + 1);

    write_u32(writer, value.signature, depth + 1);

    write_u32(writer, value.witness, depth + 1);

    write_u32(writer, value.witness_result, depth + 1);

    write_blot_check_types__NominalIdentity(writer, value.instance, depth + 1);

    write_u32(writer, value.capability, depth + 1);

}

fn read_blot_check_core__OperationValue(reader: Reader&, depth: i64) -> blot_check_core::OperationValue, Error {
    var result = default<blot_check_core::OperationValue>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != Error.none { return default<blot_check_core::OperationValue>(), error; } result.identity = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != Error.none { return default<blot_check_core::OperationValue>(), error; } result.arguments = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::OperationValue>(), error; } result.signature = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::OperationValue>(), error; } result.witness = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::OperationValue>(), error; } result.witness_result = decoded; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != Error.none { return default<blot_check_core::OperationValue>(), error; } result.instance = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::OperationValue>(), error; } result.capability = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__HandleEffects(writer: Writer&, value: blot_check_core::HandleEffects, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.node, depth + 1);

    write_u32(writer, value.first, depth + 1);

    write_u32(writer, value.second, depth + 1);

    write_u32(writer, value.extended, depth + 1);

    write_u32(writer, value.residual, depth + 1);

}

fn read_blot_check_core__HandleEffects(reader: Reader&, depth: i64) -> blot_check_core::HandleEffects, Error {
    var result = default<blot_check_core::HandleEffects>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::HandleEffects>(), error; } result.node = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::HandleEffects>(), error; } result.first = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::HandleEffects>(), error; } result.second = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::HandleEffects>(), error; } result.extended = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != Error.none { return default<blot_check_core::HandleEffects>(), error; } result.residual = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__Diagnostic(writer: Writer&, value: blot_check_core::Diagnostic, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_core__Code(writer, value.code, depth + 1);

    write_blot_parse_ast__Span(writer, value.span, depth + 1);

}

fn read_blot_check_core__Diagnostic(reader: Reader&, depth: i64) -> blot_check_core::Diagnostic, Error {
    var result = default<blot_check_core::Diagnostic>(); let charged = debit(reader, depth); if charged != Error.none { return result, charged; }

    { let decoded, error = read_blot_check_core__Code(reader, depth + 1); if error != Error.none { return default<blot_check_core::Diagnostic>(), error; } result.code = decoded; }

    { let decoded, error = read_blot_parse_ast__Span(reader, depth + 1); if error != Error.none { return default<blot_check_core::Diagnostic>(), error; } result.span = decoded; }

    return result, Error.none;
}

fn write_blot_check_core__Code(writer: Writer&, value: blot_check_core::Code, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        blot_check_core::Code.unchecked => { put(writer, 0, 4); 
},

        blot_check_core::Code.unsupported => { put(writer, 1, 4); 
},

        blot_check_core::Code.unresolved_binding => { put(writer, 2, 4); 
},

        blot_check_core::Code.invalid_call => { put(writer, 3, 4); 
},

        blot_check_core::Code.complexity => { put(writer, 4, 4); 
},

    }
}

fn read_blot_check_core__Code(reader: Reader&, depth: i64) -> blot_check_core::Code, Error {
    let charged = debit(reader, depth); if charged != Error.none { return default<blot_check_core::Code>(), charged; } let tag, error = get(reader, 4); if error != Error.none { return default<blot_check_core::Code>(), error; }
    match tag {

        0 => { 
return blot_check_core::Code.unchecked, Error.none; },

        1 => { 
return blot_check_core::Code.unsupported, Error.none; },

        2 => { 
return blot_check_core::Code.unresolved_binding, Error.none; },

        3 => { 
return blot_check_core::Code.invalid_call, Error.none; },

        4 => { 
return blot_check_core::Code.complexity, Error.none; },

        _ => { return default<blot_check_core::Code>(), Error.invalid_artifact; },
    }
}

fn digest(bytes: const u8[:]) -> u8[32] { var hash = blot_support_blake3::State {..}; hash.update(bytes); return hash.final(); }
fn encode(module: const blot_check_core::Module&, output: u8[>..<]&) -> Error {
    let begin = output.len; output.append(packet_magic);
    for index in packet_header - packet_magic.len { output.push(0); }
    var writer = Writer { output: output, start: output.len , ..};
    write_blot_check_core__Module(writer, module, 0);
    if writer.failure != Error.none { output.resize(begin); return writer.failure; }
    let payload = output[begin + packet_header..]; let checksum = digest(payload);
    blot_bytes::put_u32(output[..], begin + 8, packet_version);
    for byte, index in schema_digest { output[begin + 12 + index] = byte; }
    blot_bytes::put_u64(output[..], begin + 44, payload.len as u64);
    for byte, index in checksum { output[begin + 52 + index] = byte; }
    return Error.none;
}
fn decode(bytes: const u8[:]) -> Owned, Error {
    if bytes.len < packet_header || bytes[..8] != packet_magic { return default<Owned>(), Error.invalid_artifact; }
    let version = blot_bytes::get_u32(bytes, 8); if version != packet_version { return default<Owned>(), Error.unsupported_version; }
    if bytes[12..44] != schema_digest[..] { return default<Owned>(), Error.schema_mismatch; }
    let length = blot_bytes::get_u64(bytes, 44); if length > packet_limit as u64 { return default<Owned>(), Error.artifact_limit; }
    if length != (bytes.len - packet_header) as u64 { return default<Owned>(), Error.invalid_artifact; }
    let actual = digest(bytes[packet_header..]); if bytes[52..84] != actual[..] { return default<Owned>(), Error.invalid_artifact; }
    var reader = Reader { bytes: bytes[packet_header..] , ..}; let module, error = read_blot_check_core__Module(reader, 0);
    if error != Error.none || reader.at != reader.bytes.len { releaseRuns(reader.head); if error != Error.none { return default<Owned>(), error; } return default<Owned>(), Error.invalid_artifact; }
    if next_generation == 0xffffffffffffffff || leases.len >= 0xffffffff { releaseRuns(reader.head); return default<Owned>(), Error.out_of_memory; }
    var result = module; result.owner_id = blot_native::fresh_owner_id(); result.types.owner_id = blot_native::fresh_owner_id(); if result.owner_id == 0 || result.types.owner_id == 0 { releaseRuns(reader.head); return default<Owned>(), Error.core_limit; }
    var packages=false;for node in result.nodes {if node.tag==blot_check_core::Tag.package_pack {packages=true;break;}}
    if packages && result.nodes.len!=0 {let run=pool_u32.alloc_slice(result.nodes.len);let error=remember(reader,Run.run_u32{run, ..});if error!=Error.none {pool_u32.free_slice(run);releaseRuns(reader.head);return default<Owned>(),error;}for node,index in result.nodes {run[index]=node.a;}result.package_payloads=run;}
    let generation = next_generation; next_generation++; let lease = leases.alloc_index(Lease { reader.head, generation , ..});
    return Owned { result, (lease + 1) as u32, generation , ..}, Error.none;
}

// A native owned copy uses the same typed dependency journal as principal
// snapshots. It never encodes and decodes an intermediate packet.
fn clone(module:const blot_check_core::Module&)->Owned,Error {
 let copied,error=blot_reuse_dependency_payload::clone(module);if error!=Error.none {return default<Owned>(),error;}
 return Owned {module:copied.value,payload_owner:copied.owner, ..},Error.none;
}
fn mutable(self:Owned&,values:const u32[:])->u32[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_u32 run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_numeric_proof_terms::Kind[:])->blot_check_numeric_proof_terms::Kind[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_numeric_proof_terms__Kind run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_numeric_proof_terms::Term[:])->blot_check_numeric_proof_terms::Term[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_numeric_proof_terms__Term run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_numeric_proof_contracts::Requirement[:])->blot_check_numeric_proof_contracts::Requirement[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_numeric_proof_contracts__Requirement run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_numeric_proof_headers::Named[:])->blot_check_numeric_proof_headers::Named[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_numeric_proof_headers__Named run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_capability_contracts::Term[:])->blot_check_capability_contracts::Term[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_capability_contracts__Term run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_capability_contracts::Binding[:])->blot_check_capability_contracts::Binding[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_capability_contracts__Binding run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::FieldName[:])->blot_check_core::FieldName[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__FieldName run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::RuntimeName[:])->blot_check_core::RuntimeName[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__RuntimeName run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::DeclarationDependencies[:])->blot_check_core::DeclarationDependencies[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__DeclarationDependencies run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::BindingRef[:])->blot_check_core::BindingRef[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__BindingRef run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::DependencyMember[:])->blot_check_core::DependencyMember[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__DependencyMember run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::ErasedDeclarationReference[:])->blot_check_core::ErasedDeclarationReference[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__ErasedDeclarationReference run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::RequestLoopInfo[:])->blot_check_core::RequestLoopInfo[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__RequestLoopInfo run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::RequestArm[:])->blot_check_core::RequestArm[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__RequestArm run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_types::Node[:])->blot_check_types::Node[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_types__Node run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_effects::Row[:])->blot_check_effects::Row[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_effects__Row run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_types::Operation[:])->blot_check_types::Operation[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_types__Operation run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_types::QuantifierGoals[:])->blot_check_types::QuantifierGoals[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_types__QuantifierGoals run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_types::Obligation[:])->blot_check_types::Obligation[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_types__Obligation run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::Node[:])->blot_check_core::Node[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__Node run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_parse_ast::Span[:])->blot_parse_ast::Span[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_parse_ast__Span run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::Binding[:])->blot_check_core::Binding[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__Binding run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::Body[:])->blot_check_core::Body[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__Body run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::Parameter[:])->blot_check_core::Parameter[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__Parameter run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::CallInfo[:])->blot_check_core::CallInfo[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__CallInfo run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::Merge[:])->blot_check_core::Merge[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__Merge run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::List[:])->blot_check_core::List[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__List run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const u8[:])->u8[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_u8 run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::Obligation[:])->blot_check_core::Obligation[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__Obligation run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::Nominal[:])->blot_check_core::Nominal[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__Nominal run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::OperationName[:])->blot_check_core::OperationName[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__OperationName run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::Constructor[:])->blot_check_core::Constructor[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__Constructor run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::Projection[:])->blot_check_core::Projection[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__Projection run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::ProjectionVariant[:])->blot_check_core::ProjectionVariant[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__ProjectionVariant run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::Pattern[:])->blot_check_core::Pattern[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__Pattern run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::PatternRow[:])->blot_check_core::PatternRow[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__PatternRow run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::MatchArm[:])->blot_check_core::MatchArm[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__MatchArm run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::MatchInfo[:])->blot_check_core::MatchInfo[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__MatchInfo run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::UpdateInfo[:])->blot_check_core::UpdateInfo[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__UpdateInfo run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::UpdateStep[:])->blot_check_core::UpdateStep[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__UpdateStep run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::ClosureInfo[:])->blot_check_core::ClosureInfo[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__ClosureInfo run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::Associated[:])->blot_check_core::Associated[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__Associated run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::Contract[:])->blot_check_core::Contract[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__Contract run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_reuse_principal_interface::ContractMember[:])->blot_reuse_principal_interface::ContractMember[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_reuse_principal_interface__ContractMember run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_reuse_principal_interface::Implementation[:])->blot_reuse_principal_interface::Implementation[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_reuse_principal_interface__Implementation run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_reuse_principal_interface::ImplementationMember[:])->blot_reuse_principal_interface::ImplementationMember[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_reuse_principal_interface__ImplementationMember run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_reuse_principal_interface::MemberTemplate[:])->blot_reuse_principal_interface::MemberTemplate[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_reuse_principal_interface__MemberTemplate run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_reuse_principal_interface::SelectedProof[:])->blot_reuse_principal_interface::SelectedProof[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_reuse_principal_interface__SelectedProof run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::SelectedUse[:])->blot_check_core::SelectedUse[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__SelectedUse run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::DictionarySelection[:])->blot_check_core::DictionarySelection[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__DictionarySelection run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::DictionaryUse[:])->blot_check_core::DictionaryUse[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__DictionaryUse run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::Primitive[:])->blot_check_core::Primitive[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__Primitive run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::LoopInfo[:])->blot_check_core::LoopInfo[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__LoopInfo run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::LoopCarry[:])->blot_check_core::LoopCarry[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__LoopCarry run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::ResolverInfo[:])->blot_check_core::ResolverInfo[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__ResolverInfo run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::OperationValue[:])->blot_check_core::OperationValue[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__OperationValue run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::HandleEffects[:])->blot_check_core::HandleEffects[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__HandleEffects run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(self:Owned&,values:const blot_check_core::Diagnostic[:])->blot_check_core::Diagnostic[:] {
 if self.payload_owner.lease!=0 {return self.payload_owner.mutable(values);}
 assert(self.lease!=0&&self.lease-1<leases.len&&leases[self.lease-1].live&&leases[self.lease-1].generation==self.generation);if values.len==0 {return [];}
 var next=leases[self.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {Run.run_blot_check_core__Diagnostic run=>{if run.values .== values {return run.values;}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
