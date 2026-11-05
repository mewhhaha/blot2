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
struct Writer { output: u8[>..<]&, start: i64, failure: Error = blot_error::Error.none, remaining: i64 = element_limit }
struct Reader { bytes: const u8[:], at: i64 = 0, remaining: i64 = element_limit, head: u32 = 0 }
fn charge(writer: Writer&, depth: i64) -> bool { if writer.failure != blot_error::Error.none { return false; } if depth > depth_limit || writer.remaining == 0 { writer.failure = blot_error::Error.artifact_limit; return false; } writer.remaining--; return true; }
fn debit(reader: Reader&, depth: i64) -> Error { if depth > depth_limit || reader.remaining == 0 { return blot_error::Error.artifact_limit; } reader.remaining--; return blot_error::Error.none; }
fn put(writer: Writer&, bits: u64, width: i64) { if writer.failure != blot_error::Error.none { return; } if writer.output.len - writer.start > packet_limit - width { writer.failure = blot_error::Error.artifact_limit; return; } for index in width { writer.output.push((bits >> ((index * 8) as u32)) as! u8); } }
fn get(reader: Reader&, width: i64) -> u64, Error { if reader.at > reader.bytes.len || width > reader.bytes.len - reader.at { return 0, blot_error::Error.invalid_artifact; } var bits: u64 = 0; for index in width { bits |= (reader.bytes[reader.at + index] as u64) << ((index * 8) as u32); } reader.at += width; return bits, blot_error::Error.none; }
fn remember(reader: Reader&, value: Run) -> Error { if links.len >= 0xffffffff { return blot_error::Error.out_of_memory; } let at = links.alloc_index(Link { value, reader.head , ..}); reader.head = (at + 1) as u32; return blot_error::Error.none; }
fn releaseRuns(head: u32) { var next = head; while next != 0 { let at = next - 1; let link = links[at]; next = link.next; match link.value {

    run_u32 run => { pool_u32.free_slice(run.values); },

    run_blot_check_numeric_proof_terms__Kind run => { pool_blot_check_numeric_proof_terms__Kind.free_slice(run.values); },

    run_blot_check_numeric_proof_terms__Term run => { pool_blot_check_numeric_proof_terms__Term.free_slice(run.values); },

    run_blot_check_numeric_proof_contracts__Requirement run => { pool_blot_check_numeric_proof_contracts__Requirement.free_slice(run.values); },

    run_blot_check_numeric_proof_headers__Named run => { pool_blot_check_numeric_proof_headers__Named.free_slice(run.values); },

    run_blot_check_capability_contracts__Term run => { pool_blot_check_capability_contracts__Term.free_slice(run.values); },

    run_blot_check_capability_contracts__Binding run => { pool_blot_check_capability_contracts__Binding.free_slice(run.values); },

    run_blot_check_core__FieldName run => { pool_blot_check_core__FieldName.free_slice(run.values); },

    run_blot_check_core__RuntimeName run => { pool_blot_check_core__RuntimeName.free_slice(run.values); },

    run_blot_check_core__DeclarationDependencies run => { pool_blot_check_core__DeclarationDependencies.free_slice(run.values); },

    run_blot_check_core__BindingRef run => { pool_blot_check_core__BindingRef.free_slice(run.values); },

    run_blot_check_core__DependencyMember run => { pool_blot_check_core__DependencyMember.free_slice(run.values); },

    run_blot_check_core__ErasedDeclarationReference run => { pool_blot_check_core__ErasedDeclarationReference.free_slice(run.values); },

    run_blot_check_core__RequestLoopInfo run => { pool_blot_check_core__RequestLoopInfo.free_slice(run.values); },

    run_blot_check_core__RequestArm run => { pool_blot_check_core__RequestArm.free_slice(run.values); },

    run_blot_check_types__Node run => { pool_blot_check_types__Node.free_slice(run.values); },

    run_blot_check_effects__Row run => { pool_blot_check_effects__Row.free_slice(run.values); },

    run_blot_check_types__Operation run => { pool_blot_check_types__Operation.free_slice(run.values); },

    run_blot_check_types__QuantifierGoals run => { pool_blot_check_types__QuantifierGoals.free_slice(run.values); },

    run_blot_check_types__Obligation run => { pool_blot_check_types__Obligation.free_slice(run.values); },

    run_blot_check_core__Node run => { pool_blot_check_core__Node.free_slice(run.values); },

    run_blot_parse_ast__Span run => { pool_blot_parse_ast__Span.free_slice(run.values); },

    run_blot_check_core__Binding run => { pool_blot_check_core__Binding.free_slice(run.values); },

    run_blot_check_core__Body run => { pool_blot_check_core__Body.free_slice(run.values); },

    run_blot_check_core__Parameter run => { pool_blot_check_core__Parameter.free_slice(run.values); },

    run_blot_check_core__CallInfo run => { pool_blot_check_core__CallInfo.free_slice(run.values); },

    run_blot_check_core__Merge run => { pool_blot_check_core__Merge.free_slice(run.values); },

    run_blot_check_core__List run => { pool_blot_check_core__List.free_slice(run.values); },

    run_u8 run => { pool_u8.free_slice(run.values); },

    run_blot_check_core__Obligation run => { pool_blot_check_core__Obligation.free_slice(run.values); },

    run_blot_check_core__Nominal run => { pool_blot_check_core__Nominal.free_slice(run.values); },

    run_blot_check_core__OperationName run => { pool_blot_check_core__OperationName.free_slice(run.values); },

    run_blot_check_core__Constructor run => { pool_blot_check_core__Constructor.free_slice(run.values); },

    run_blot_check_core__Projection run => { pool_blot_check_core__Projection.free_slice(run.values); },

    run_blot_check_core__ProjectionVariant run => { pool_blot_check_core__ProjectionVariant.free_slice(run.values); },

    run_blot_check_core__Pattern run => { pool_blot_check_core__Pattern.free_slice(run.values); },

    run_blot_check_core__PatternRow run => { pool_blot_check_core__PatternRow.free_slice(run.values); },

    run_blot_check_core__MatchArm run => { pool_blot_check_core__MatchArm.free_slice(run.values); },

    run_blot_check_core__MatchInfo run => { pool_blot_check_core__MatchInfo.free_slice(run.values); },

    run_blot_check_core__UpdateInfo run => { pool_blot_check_core__UpdateInfo.free_slice(run.values); },

    run_blot_check_core__UpdateStep run => { pool_blot_check_core__UpdateStep.free_slice(run.values); },

    run_blot_check_core__ClosureInfo run => { pool_blot_check_core__ClosureInfo.free_slice(run.values); },

    run_blot_check_core__Associated run => { pool_blot_check_core__Associated.free_slice(run.values); },

    run_blot_check_core__Contract run => { pool_blot_check_core__Contract.free_slice(run.values); },

    run_blot_reuse_principal_interface__ContractMember run => { pool_blot_reuse_principal_interface__ContractMember.free_slice(run.values); },

    run_blot_reuse_principal_interface__Implementation run => { pool_blot_reuse_principal_interface__Implementation.free_slice(run.values); },

    run_blot_reuse_principal_interface__ImplementationMember run => { pool_blot_reuse_principal_interface__ImplementationMember.free_slice(run.values); },

    run_blot_reuse_principal_interface__MemberTemplate run => { pool_blot_reuse_principal_interface__MemberTemplate.free_slice(run.values); },

    run_blot_reuse_principal_interface__SelectedProof run => { pool_blot_reuse_principal_interface__SelectedProof.free_slice(run.values); },

    run_blot_check_core__SelectedUse run => { pool_blot_check_core__SelectedUse.free_slice(run.values); },

    run_blot_check_core__DictionarySelection run => { pool_blot_check_core__DictionarySelection.free_slice(run.values); },

    run_blot_check_core__DictionaryUse run => { pool_blot_check_core__DictionaryUse.free_slice(run.values); },

    run_blot_check_core__Primitive run => { pool_blot_check_core__Primitive.free_slice(run.values); },

    run_blot_check_core__LoopInfo run => { pool_blot_check_core__LoopInfo.free_slice(run.values); },

    run_blot_check_core__LoopCarry run => { pool_blot_check_core__LoopCarry.free_slice(run.values); },

    run_blot_check_core__ResolverInfo run => { pool_blot_check_core__ResolverInfo.free_slice(run.values); },

    run_blot_check_core__OperationValue run => { pool_blot_check_core__OperationValue.free_slice(run.values); },

    run_blot_check_core__HandleEffects run => { pool_blot_check_core__HandleEffects.free_slice(run.values); },

    run_blot_check_core__Diagnostic run => { pool_blot_check_core__Diagnostic.free_slice(run.values); },

} links.free(at); } }
fn deinit(receiver: Owned&) {if receiver.payload_owner.lease!=0 {receiver.payload_owner.deinit();receiver.module=default<blot_check_core::Module>();return;} if receiver.lease == 0 { return; } let at = receiver.lease - 1; assert(at < leases.len && leases[at].live && leases[at].generation == receiver.generation); releaseRuns(leases[at].head); leases[at].live = false; leases.free(at); receiver.lease = 0; receiver.generation = 0; receiver.module = default<blot_check_core::Module>(); }

fn write_bool(writer: Writer&, value: bool, depth: i64) { if !charge(writer, depth) { return; } var bit: u64 = 0; if value { bit = 1; } put(writer, bit, 1); }

fn read_bool(reader: Reader&, depth: i64) -> bool, Error { let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<bool>(), charged; } let bits, error = get(reader, 1); if error != blot_error::Error.none { return default<bool>(), error; } if bits > 1 { return false, blot_error::Error.invalid_artifact; } return bits != 0, blot_error::Error.none; }

fn write_f32(writer: Writer&, value: f32, depth: i64) { if !charge(writer, depth) { return; } put(writer, blot_native::f32_bits(value) as u64, 4); }

fn read_f32(reader: Reader&, depth: i64) -> f32, Error { let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<f32>(), charged; } let bits, error = get(reader, 4); if error != blot_error::Error.none { return default<f32>(), error; } return blot_native::f32_from_bits(bits as u32), blot_error::Error.none; }

fn write_f64(writer: Writer&, value: f64, depth: i64) { if !charge(writer, depth) { return; } put(writer, blot_native::f64_bits(value), 8); }

fn read_f64(reader: Reader&, depth: i64) -> f64, Error { let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<f64>(), charged; } let bits, error = get(reader, 8); if error != blot_error::Error.none { return default<f64>(), error; } return blot_native::f64_from_bits(bits), blot_error::Error.none; }

fn write_i16(writer: Writer&, value: i16, depth: i64) { if !charge(writer, depth) { return; } put(writer, value as! u64, 2); }

fn read_i16(reader: Reader&, depth: i64) -> i16, Error { let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<i16>(), charged; } let bits, error = get(reader, 2); if error != blot_error::Error.none { return default<i16>(), error; } return bits as! i16, blot_error::Error.none; }

fn write_i32(writer: Writer&, value: i32, depth: i64) { if !charge(writer, depth) { return; } put(writer, value as! u64, 4); }

fn read_i32(reader: Reader&, depth: i64) -> i32, Error { let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<i32>(), charged; } let bits, error = get(reader, 4); if error != blot_error::Error.none { return default<i32>(), error; } return bits as! i32, blot_error::Error.none; }

fn write_i64(writer: Writer&, value: i64, depth: i64) { if !charge(writer, depth) { return; } put(writer, value as! u64, 8); }

fn read_i64(reader: Reader&, depth: i64) -> i64, Error { let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<i64>(), charged; } let bits, error = get(reader, 8); if error != blot_error::Error.none { return default<i64>(), error; } return bits as! i64, blot_error::Error.none; }

fn write_i8(writer: Writer&, value: i8, depth: i64) { if !charge(writer, depth) { return; } put(writer, value as! u64, 1); }

fn read_i8(reader: Reader&, depth: i64) -> i8, Error { let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<i8>(), charged; } let bits, error = get(reader, 1); if error != blot_error::Error.none { return default<i8>(), error; } return bits as! i8, blot_error::Error.none; }

fn write_u16(writer: Writer&, value: u16, depth: i64) { if !charge(writer, depth) { return; } put(writer, value as! u64, 2); }

fn read_u16(reader: Reader&, depth: i64) -> u16, Error { let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<u16>(), charged; } let bits, error = get(reader, 2); if error != blot_error::Error.none { return default<u16>(), error; } return bits as! u16, blot_error::Error.none; }

fn write_u32(writer: Writer&, value: u32, depth: i64) { if !charge(writer, depth) { return; } put(writer, value as! u64, 4); }

fn read_u32(reader: Reader&, depth: i64) -> u32, Error { let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<u32>(), charged; } let bits, error = get(reader, 4); if error != blot_error::Error.none { return default<u32>(), error; } return bits as! u32, blot_error::Error.none; }

fn write_u64(writer: Writer&, value: u64, depth: i64) { if !charge(writer, depth) { return; } put(writer, value as! u64, 8); }

fn read_u64(reader: Reader&, depth: i64) -> u64, Error { let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<u64>(), charged; } let bits, error = get(reader, 8); if error != blot_error::Error.none { return default<u64>(), error; } return bits as! u64, blot_error::Error.none; }

fn write_u8(writer: Writer&, value: u8, depth: i64) { if !charge(writer, depth) { return; } put(writer, value as! u64, 1); }

fn read_u8(reader: Reader&, depth: i64) -> u8, Error { let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<u8>(), charged; } let bits, error = get(reader, 1); if error != blot_error::Error.none { return default<u8>(), error; } return bits as! u8, blot_error::Error.none; }

fn write_u32___(writer: Writer&, value: const u32[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_u32(writer, element, depth + 1); } }

fn read_u32___(reader: Reader&, depth: i64) -> u32[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<u32[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<u32[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<u32[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<u32[:]>(), blot_error::Error.none; }
    let run = pool_u32.alloc_slice(count as i64); let recorded = remember(reader, Run.run_u32 { run , ..});
    if recorded != blot_error::Error.none { pool_u32.free_slice(run); return default<u32[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_u32(reader, depth + 1); if failure != blot_error::Error.none { return default<u32[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_numeric_proof_terms__Kind___(writer: Writer&, value: const blot_check_numeric_proof_terms::Kind[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_numeric_proof_terms__Kind(writer, element, depth + 1); } }

fn read_blot_check_numeric_proof_terms__Kind___(reader: Reader&, depth: i64) -> blot_check_numeric_proof_terms::Kind[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_numeric_proof_terms::Kind[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_numeric_proof_terms::Kind[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_numeric_proof_terms::Kind[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_numeric_proof_terms::Kind[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_numeric_proof_terms__Kind.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_numeric_proof_terms__Kind { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_numeric_proof_terms__Kind.free_slice(run); return default<blot_check_numeric_proof_terms::Kind[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_numeric_proof_terms__Kind(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_numeric_proof_terms::Kind[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_numeric_proof_terms__Term___(writer: Writer&, value: const blot_check_numeric_proof_terms::Term[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_numeric_proof_terms__Term(writer, element, depth + 1); } }

fn read_blot_check_numeric_proof_terms__Term___(reader: Reader&, depth: i64) -> blot_check_numeric_proof_terms::Term[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_numeric_proof_terms::Term[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_numeric_proof_terms::Term[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_numeric_proof_terms::Term[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_numeric_proof_terms::Term[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_numeric_proof_terms__Term.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_numeric_proof_terms__Term { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_numeric_proof_terms__Term.free_slice(run); return default<blot_check_numeric_proof_terms::Term[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_numeric_proof_terms__Term(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_numeric_proof_terms::Term[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_numeric_proof_contracts__Requirement___(writer: Writer&, value: const blot_check_numeric_proof_contracts::Requirement[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_numeric_proof_contracts__Requirement(writer, element, depth + 1); } }

fn read_blot_check_numeric_proof_contracts__Requirement___(reader: Reader&, depth: i64) -> blot_check_numeric_proof_contracts::Requirement[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_numeric_proof_contracts::Requirement[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_numeric_proof_contracts::Requirement[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_numeric_proof_contracts::Requirement[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_numeric_proof_contracts::Requirement[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_numeric_proof_contracts__Requirement.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_numeric_proof_contracts__Requirement { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_numeric_proof_contracts__Requirement.free_slice(run); return default<blot_check_numeric_proof_contracts::Requirement[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_numeric_proof_contracts__Requirement(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_numeric_proof_contracts::Requirement[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_numeric_proof_headers__Named___(writer: Writer&, value: const blot_check_numeric_proof_headers::Named[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_numeric_proof_headers__Named(writer, element, depth + 1); } }

fn read_blot_check_numeric_proof_headers__Named___(reader: Reader&, depth: i64) -> blot_check_numeric_proof_headers::Named[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_numeric_proof_headers::Named[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_numeric_proof_headers::Named[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_numeric_proof_headers::Named[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_numeric_proof_headers::Named[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_numeric_proof_headers__Named.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_numeric_proof_headers__Named { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_numeric_proof_headers__Named.free_slice(run); return default<blot_check_numeric_proof_headers::Named[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_numeric_proof_headers__Named(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_numeric_proof_headers::Named[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_capability_contracts__Term___(writer: Writer&, value: const blot_check_capability_contracts::Term[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_capability_contracts__Term(writer, element, depth + 1); } }

fn read_blot_check_capability_contracts__Term___(reader: Reader&, depth: i64) -> blot_check_capability_contracts::Term[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_capability_contracts::Term[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_capability_contracts::Term[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_capability_contracts::Term[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_capability_contracts::Term[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_capability_contracts__Term.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_capability_contracts__Term { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_capability_contracts__Term.free_slice(run); return default<blot_check_capability_contracts::Term[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_capability_contracts__Term(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_capability_contracts::Term[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_capability_contracts__Binding___(writer: Writer&, value: const blot_check_capability_contracts::Binding[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_capability_contracts__Binding(writer, element, depth + 1); } }

fn read_blot_check_capability_contracts__Binding___(reader: Reader&, depth: i64) -> blot_check_capability_contracts::Binding[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_capability_contracts::Binding[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_capability_contracts::Binding[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_capability_contracts::Binding[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_capability_contracts::Binding[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_capability_contracts__Binding.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_capability_contracts__Binding { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_capability_contracts__Binding.free_slice(run); return default<blot_check_capability_contracts::Binding[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_capability_contracts__Binding(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_capability_contracts::Binding[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__FieldName___(writer: Writer&, value: const blot_check_core::FieldName[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__FieldName(writer, element, depth + 1); } }

fn read_blot_check_core__FieldName___(reader: Reader&, depth: i64) -> blot_check_core::FieldName[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::FieldName[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::FieldName[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::FieldName[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::FieldName[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__FieldName.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__FieldName { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__FieldName.free_slice(run); return default<blot_check_core::FieldName[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__FieldName(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::FieldName[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__RuntimeName___(writer: Writer&, value: const blot_check_core::RuntimeName[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__RuntimeName(writer, element, depth + 1); } }

fn read_blot_check_core__RuntimeName___(reader: Reader&, depth: i64) -> blot_check_core::RuntimeName[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::RuntimeName[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::RuntimeName[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::RuntimeName[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::RuntimeName[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__RuntimeName.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__RuntimeName { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__RuntimeName.free_slice(run); return default<blot_check_core::RuntimeName[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__RuntimeName(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::RuntimeName[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__DeclarationDependencies___(writer: Writer&, value: const blot_check_core::DeclarationDependencies[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__DeclarationDependencies(writer, element, depth + 1); } }

fn read_blot_check_core__DeclarationDependencies___(reader: Reader&, depth: i64) -> blot_check_core::DeclarationDependencies[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::DeclarationDependencies[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::DeclarationDependencies[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::DeclarationDependencies[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::DeclarationDependencies[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__DeclarationDependencies.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__DeclarationDependencies { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__DeclarationDependencies.free_slice(run); return default<blot_check_core::DeclarationDependencies[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__DeclarationDependencies(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::DeclarationDependencies[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__BindingRef___(writer: Writer&, value: const blot_check_core::BindingRef[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__BindingRef(writer, element, depth + 1); } }

fn read_blot_check_core__BindingRef___(reader: Reader&, depth: i64) -> blot_check_core::BindingRef[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::BindingRef[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::BindingRef[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::BindingRef[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::BindingRef[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__BindingRef.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__BindingRef { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__BindingRef.free_slice(run); return default<blot_check_core::BindingRef[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__BindingRef(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::BindingRef[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__DependencyMember___(writer: Writer&, value: const blot_check_core::DependencyMember[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__DependencyMember(writer, element, depth + 1); } }

fn read_blot_check_core__DependencyMember___(reader: Reader&, depth: i64) -> blot_check_core::DependencyMember[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::DependencyMember[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::DependencyMember[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::DependencyMember[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::DependencyMember[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__DependencyMember.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__DependencyMember { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__DependencyMember.free_slice(run); return default<blot_check_core::DependencyMember[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__DependencyMember(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::DependencyMember[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__ErasedDeclarationReference___(writer: Writer&, value: const blot_check_core::ErasedDeclarationReference[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__ErasedDeclarationReference(writer, element, depth + 1); } }

fn read_blot_check_core__ErasedDeclarationReference___(reader: Reader&, depth: i64) -> blot_check_core::ErasedDeclarationReference[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::ErasedDeclarationReference[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::ErasedDeclarationReference[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::ErasedDeclarationReference[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::ErasedDeclarationReference[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__ErasedDeclarationReference.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__ErasedDeclarationReference { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__ErasedDeclarationReference.free_slice(run); return default<blot_check_core::ErasedDeclarationReference[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__ErasedDeclarationReference(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::ErasedDeclarationReference[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__RequestLoopInfo___(writer: Writer&, value: const blot_check_core::RequestLoopInfo[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__RequestLoopInfo(writer, element, depth + 1); } }

fn read_blot_check_core__RequestLoopInfo___(reader: Reader&, depth: i64) -> blot_check_core::RequestLoopInfo[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::RequestLoopInfo[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::RequestLoopInfo[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::RequestLoopInfo[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::RequestLoopInfo[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__RequestLoopInfo.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__RequestLoopInfo { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__RequestLoopInfo.free_slice(run); return default<blot_check_core::RequestLoopInfo[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__RequestLoopInfo(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::RequestLoopInfo[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__RequestArm___(writer: Writer&, value: const blot_check_core::RequestArm[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__RequestArm(writer, element, depth + 1); } }

fn read_blot_check_core__RequestArm___(reader: Reader&, depth: i64) -> blot_check_core::RequestArm[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::RequestArm[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::RequestArm[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::RequestArm[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::RequestArm[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__RequestArm.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__RequestArm { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__RequestArm.free_slice(run); return default<blot_check_core::RequestArm[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__RequestArm(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::RequestArm[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_types__Node___(writer: Writer&, value: const blot_check_types::Node[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_types__Node(writer, element, depth + 1); } }

fn read_blot_check_types__Node___(reader: Reader&, depth: i64) -> blot_check_types::Node[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_types::Node[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_types::Node[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_types::Node[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_types::Node[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_types__Node.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_types__Node { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_types__Node.free_slice(run); return default<blot_check_types::Node[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_types__Node(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_types::Node[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_effects__Row___(writer: Writer&, value: const blot_check_effects::Row[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_effects__Row(writer, element, depth + 1); } }

fn read_blot_check_effects__Row___(reader: Reader&, depth: i64) -> blot_check_effects::Row[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_effects::Row[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_effects::Row[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_effects::Row[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_effects::Row[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_effects__Row.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_effects__Row { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_effects__Row.free_slice(run); return default<blot_check_effects::Row[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_effects__Row(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_effects::Row[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_types__Operation___(writer: Writer&, value: const blot_check_types::Operation[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_types__Operation(writer, element, depth + 1); } }

fn read_blot_check_types__Operation___(reader: Reader&, depth: i64) -> blot_check_types::Operation[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_types::Operation[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_types::Operation[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_types::Operation[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_types::Operation[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_types__Operation.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_types__Operation { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_types__Operation.free_slice(run); return default<blot_check_types::Operation[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_types__Operation(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_types::Operation[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_types__QuantifierGoals___(writer: Writer&, value: const blot_check_types::QuantifierGoals[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_types__QuantifierGoals(writer, element, depth + 1); } }

fn read_blot_check_types__QuantifierGoals___(reader: Reader&, depth: i64) -> blot_check_types::QuantifierGoals[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_types::QuantifierGoals[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_types::QuantifierGoals[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_types::QuantifierGoals[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_types::QuantifierGoals[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_types__QuantifierGoals.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_types__QuantifierGoals { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_types__QuantifierGoals.free_slice(run); return default<blot_check_types::QuantifierGoals[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_types__QuantifierGoals(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_types::QuantifierGoals[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_types__Obligation___(writer: Writer&, value: const blot_check_types::Obligation[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_types__Obligation(writer, element, depth + 1); } }

fn read_blot_check_types__Obligation___(reader: Reader&, depth: i64) -> blot_check_types::Obligation[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_types::Obligation[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_types::Obligation[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_types::Obligation[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_types::Obligation[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_types__Obligation.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_types__Obligation { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_types__Obligation.free_slice(run); return default<blot_check_types::Obligation[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_types__Obligation(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_types::Obligation[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__Node___(writer: Writer&, value: const blot_check_core::Node[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__Node(writer, element, depth + 1); } }

fn read_blot_check_core__Node___(reader: Reader&, depth: i64) -> blot_check_core::Node[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::Node[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::Node[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::Node[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::Node[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__Node.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__Node { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__Node.free_slice(run); return default<blot_check_core::Node[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__Node(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::Node[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_parse_ast__Span___(writer: Writer&, value: const blot_parse_ast::Span[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_parse_ast__Span(writer, element, depth + 1); } }

fn read_blot_parse_ast__Span___(reader: Reader&, depth: i64) -> blot_parse_ast::Span[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_parse_ast::Span[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_parse_ast::Span[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_parse_ast::Span[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_parse_ast::Span[:]>(), blot_error::Error.none; }
    let run = pool_blot_parse_ast__Span.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_parse_ast__Span { run , ..});
    if recorded != blot_error::Error.none { pool_blot_parse_ast__Span.free_slice(run); return default<blot_parse_ast::Span[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_parse_ast__Span(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_parse_ast::Span[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__Binding___(writer: Writer&, value: const blot_check_core::Binding[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__Binding(writer, element, depth + 1); } }

fn read_blot_check_core__Binding___(reader: Reader&, depth: i64) -> blot_check_core::Binding[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::Binding[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::Binding[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::Binding[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::Binding[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__Binding.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__Binding { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__Binding.free_slice(run); return default<blot_check_core::Binding[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__Binding(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::Binding[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__Body___(writer: Writer&, value: const blot_check_core::Body[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__Body(writer, element, depth + 1); } }

fn read_blot_check_core__Body___(reader: Reader&, depth: i64) -> blot_check_core::Body[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::Body[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::Body[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::Body[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::Body[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__Body.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__Body { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__Body.free_slice(run); return default<blot_check_core::Body[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__Body(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::Body[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__Parameter___(writer: Writer&, value: const blot_check_core::Parameter[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__Parameter(writer, element, depth + 1); } }

fn read_blot_check_core__Parameter___(reader: Reader&, depth: i64) -> blot_check_core::Parameter[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::Parameter[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::Parameter[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::Parameter[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::Parameter[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__Parameter.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__Parameter { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__Parameter.free_slice(run); return default<blot_check_core::Parameter[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__Parameter(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::Parameter[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__CallInfo___(writer: Writer&, value: const blot_check_core::CallInfo[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__CallInfo(writer, element, depth + 1); } }

fn read_blot_check_core__CallInfo___(reader: Reader&, depth: i64) -> blot_check_core::CallInfo[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::CallInfo[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::CallInfo[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::CallInfo[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::CallInfo[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__CallInfo.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__CallInfo { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__CallInfo.free_slice(run); return default<blot_check_core::CallInfo[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__CallInfo(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::CallInfo[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__Merge___(writer: Writer&, value: const blot_check_core::Merge[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__Merge(writer, element, depth + 1); } }

fn read_blot_check_core__Merge___(reader: Reader&, depth: i64) -> blot_check_core::Merge[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::Merge[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::Merge[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::Merge[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::Merge[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__Merge.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__Merge { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__Merge.free_slice(run); return default<blot_check_core::Merge[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__Merge(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::Merge[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__List___(writer: Writer&, value: const blot_check_core::List[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__List(writer, element, depth + 1); } }

fn read_blot_check_core__List___(reader: Reader&, depth: i64) -> blot_check_core::List[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::List[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::List[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::List[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::List[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__List.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__List { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__List.free_slice(run); return default<blot_check_core::List[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__List(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::List[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_u8___(writer: Writer&, value: const u8[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_u8(writer, element, depth + 1); } }

fn read_u8___(reader: Reader&, depth: i64) -> u8[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<u8[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<u8[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<u8[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<u8[:]>(), blot_error::Error.none; }
    let run = pool_u8.alloc_slice(count as i64); let recorded = remember(reader, Run.run_u8 { run , ..});
    if recorded != blot_error::Error.none { pool_u8.free_slice(run); return default<u8[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_u8(reader, depth + 1); if failure != blot_error::Error.none { return default<u8[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__Obligation___(writer: Writer&, value: const blot_check_core::Obligation[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__Obligation(writer, element, depth + 1); } }

fn read_blot_check_core__Obligation___(reader: Reader&, depth: i64) -> blot_check_core::Obligation[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::Obligation[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::Obligation[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::Obligation[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::Obligation[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__Obligation.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__Obligation { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__Obligation.free_slice(run); return default<blot_check_core::Obligation[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__Obligation(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::Obligation[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__Nominal___(writer: Writer&, value: const blot_check_core::Nominal[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__Nominal(writer, element, depth + 1); } }

fn read_blot_check_core__Nominal___(reader: Reader&, depth: i64) -> blot_check_core::Nominal[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::Nominal[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::Nominal[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::Nominal[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::Nominal[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__Nominal.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__Nominal { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__Nominal.free_slice(run); return default<blot_check_core::Nominal[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__Nominal(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::Nominal[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__OperationName___(writer: Writer&, value: const blot_check_core::OperationName[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__OperationName(writer, element, depth + 1); } }

fn read_blot_check_core__OperationName___(reader: Reader&, depth: i64) -> blot_check_core::OperationName[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::OperationName[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::OperationName[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::OperationName[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::OperationName[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__OperationName.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__OperationName { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__OperationName.free_slice(run); return default<blot_check_core::OperationName[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__OperationName(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::OperationName[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__Constructor___(writer: Writer&, value: const blot_check_core::Constructor[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__Constructor(writer, element, depth + 1); } }

fn read_blot_check_core__Constructor___(reader: Reader&, depth: i64) -> blot_check_core::Constructor[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::Constructor[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::Constructor[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::Constructor[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::Constructor[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__Constructor.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__Constructor { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__Constructor.free_slice(run); return default<blot_check_core::Constructor[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__Constructor(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::Constructor[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__Projection___(writer: Writer&, value: const blot_check_core::Projection[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__Projection(writer, element, depth + 1); } }

fn read_blot_check_core__Projection___(reader: Reader&, depth: i64) -> blot_check_core::Projection[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::Projection[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::Projection[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::Projection[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::Projection[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__Projection.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__Projection { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__Projection.free_slice(run); return default<blot_check_core::Projection[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__Projection(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::Projection[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__ProjectionVariant___(writer: Writer&, value: const blot_check_core::ProjectionVariant[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__ProjectionVariant(writer, element, depth + 1); } }

fn read_blot_check_core__ProjectionVariant___(reader: Reader&, depth: i64) -> blot_check_core::ProjectionVariant[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::ProjectionVariant[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::ProjectionVariant[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::ProjectionVariant[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::ProjectionVariant[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__ProjectionVariant.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__ProjectionVariant { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__ProjectionVariant.free_slice(run); return default<blot_check_core::ProjectionVariant[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__ProjectionVariant(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::ProjectionVariant[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__Pattern___(writer: Writer&, value: const blot_check_core::Pattern[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__Pattern(writer, element, depth + 1); } }

fn read_blot_check_core__Pattern___(reader: Reader&, depth: i64) -> blot_check_core::Pattern[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::Pattern[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::Pattern[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::Pattern[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::Pattern[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__Pattern.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__Pattern { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__Pattern.free_slice(run); return default<blot_check_core::Pattern[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__Pattern(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::Pattern[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__PatternRow___(writer: Writer&, value: const blot_check_core::PatternRow[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__PatternRow(writer, element, depth + 1); } }

fn read_blot_check_core__PatternRow___(reader: Reader&, depth: i64) -> blot_check_core::PatternRow[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::PatternRow[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::PatternRow[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::PatternRow[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::PatternRow[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__PatternRow.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__PatternRow { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__PatternRow.free_slice(run); return default<blot_check_core::PatternRow[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__PatternRow(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::PatternRow[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__MatchArm___(writer: Writer&, value: const blot_check_core::MatchArm[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__MatchArm(writer, element, depth + 1); } }

fn read_blot_check_core__MatchArm___(reader: Reader&, depth: i64) -> blot_check_core::MatchArm[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::MatchArm[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::MatchArm[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::MatchArm[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::MatchArm[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__MatchArm.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__MatchArm { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__MatchArm.free_slice(run); return default<blot_check_core::MatchArm[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__MatchArm(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::MatchArm[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__MatchInfo___(writer: Writer&, value: const blot_check_core::MatchInfo[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__MatchInfo(writer, element, depth + 1); } }

fn read_blot_check_core__MatchInfo___(reader: Reader&, depth: i64) -> blot_check_core::MatchInfo[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::MatchInfo[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::MatchInfo[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::MatchInfo[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::MatchInfo[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__MatchInfo.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__MatchInfo { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__MatchInfo.free_slice(run); return default<blot_check_core::MatchInfo[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__MatchInfo(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::MatchInfo[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__UpdateInfo___(writer: Writer&, value: const blot_check_core::UpdateInfo[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__UpdateInfo(writer, element, depth + 1); } }

fn read_blot_check_core__UpdateInfo___(reader: Reader&, depth: i64) -> blot_check_core::UpdateInfo[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::UpdateInfo[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::UpdateInfo[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::UpdateInfo[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::UpdateInfo[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__UpdateInfo.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__UpdateInfo { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__UpdateInfo.free_slice(run); return default<blot_check_core::UpdateInfo[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__UpdateInfo(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::UpdateInfo[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__UpdateStep___(writer: Writer&, value: const blot_check_core::UpdateStep[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__UpdateStep(writer, element, depth + 1); } }

fn read_blot_check_core__UpdateStep___(reader: Reader&, depth: i64) -> blot_check_core::UpdateStep[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::UpdateStep[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::UpdateStep[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::UpdateStep[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::UpdateStep[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__UpdateStep.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__UpdateStep { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__UpdateStep.free_slice(run); return default<blot_check_core::UpdateStep[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__UpdateStep(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::UpdateStep[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__ClosureInfo___(writer: Writer&, value: const blot_check_core::ClosureInfo[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__ClosureInfo(writer, element, depth + 1); } }

fn read_blot_check_core__ClosureInfo___(reader: Reader&, depth: i64) -> blot_check_core::ClosureInfo[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::ClosureInfo[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::ClosureInfo[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::ClosureInfo[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::ClosureInfo[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__ClosureInfo.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__ClosureInfo { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__ClosureInfo.free_slice(run); return default<blot_check_core::ClosureInfo[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__ClosureInfo(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::ClosureInfo[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__Associated___(writer: Writer&, value: const blot_check_core::Associated[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__Associated(writer, element, depth + 1); } }

fn read_blot_check_core__Associated___(reader: Reader&, depth: i64) -> blot_check_core::Associated[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::Associated[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::Associated[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::Associated[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::Associated[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__Associated.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__Associated { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__Associated.free_slice(run); return default<blot_check_core::Associated[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__Associated(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::Associated[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__Contract___(writer: Writer&, value: const blot_check_core::Contract[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__Contract(writer, element, depth + 1); } }

fn read_blot_check_core__Contract___(reader: Reader&, depth: i64) -> blot_check_core::Contract[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::Contract[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::Contract[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::Contract[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::Contract[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__Contract.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__Contract { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__Contract.free_slice(run); return default<blot_check_core::Contract[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__Contract(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::Contract[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_reuse_principal_interface__ContractMember___(writer: Writer&, value: const blot_reuse_principal_interface::ContractMember[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_reuse_principal_interface__ContractMember(writer, element, depth + 1); } }

fn read_blot_reuse_principal_interface__ContractMember___(reader: Reader&, depth: i64) -> blot_reuse_principal_interface::ContractMember[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_reuse_principal_interface::ContractMember[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::ContractMember[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_reuse_principal_interface::ContractMember[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_reuse_principal_interface::ContractMember[:]>(), blot_error::Error.none; }
    let run = pool_blot_reuse_principal_interface__ContractMember.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_reuse_principal_interface__ContractMember { run , ..});
    if recorded != blot_error::Error.none { pool_blot_reuse_principal_interface__ContractMember.free_slice(run); return default<blot_reuse_principal_interface::ContractMember[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_reuse_principal_interface__ContractMember(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_reuse_principal_interface::ContractMember[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_reuse_principal_interface__Implementation___(writer: Writer&, value: const blot_reuse_principal_interface::Implementation[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_reuse_principal_interface__Implementation(writer, element, depth + 1); } }

fn read_blot_reuse_principal_interface__Implementation___(reader: Reader&, depth: i64) -> blot_reuse_principal_interface::Implementation[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_reuse_principal_interface::Implementation[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::Implementation[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_reuse_principal_interface::Implementation[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_reuse_principal_interface::Implementation[:]>(), blot_error::Error.none; }
    let run = pool_blot_reuse_principal_interface__Implementation.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_reuse_principal_interface__Implementation { run , ..});
    if recorded != blot_error::Error.none { pool_blot_reuse_principal_interface__Implementation.free_slice(run); return default<blot_reuse_principal_interface::Implementation[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_reuse_principal_interface__Implementation(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_reuse_principal_interface::Implementation[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_reuse_principal_interface__ImplementationMember___(writer: Writer&, value: const blot_reuse_principal_interface::ImplementationMember[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_reuse_principal_interface__ImplementationMember(writer, element, depth + 1); } }

fn read_blot_reuse_principal_interface__ImplementationMember___(reader: Reader&, depth: i64) -> blot_reuse_principal_interface::ImplementationMember[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_reuse_principal_interface::ImplementationMember[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::ImplementationMember[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_reuse_principal_interface::ImplementationMember[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_reuse_principal_interface::ImplementationMember[:]>(), blot_error::Error.none; }
    let run = pool_blot_reuse_principal_interface__ImplementationMember.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_reuse_principal_interface__ImplementationMember { run , ..});
    if recorded != blot_error::Error.none { pool_blot_reuse_principal_interface__ImplementationMember.free_slice(run); return default<blot_reuse_principal_interface::ImplementationMember[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_reuse_principal_interface__ImplementationMember(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_reuse_principal_interface::ImplementationMember[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_reuse_principal_interface__MemberTemplate___(writer: Writer&, value: const blot_reuse_principal_interface::MemberTemplate[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_reuse_principal_interface__MemberTemplate(writer, element, depth + 1); } }

fn read_blot_reuse_principal_interface__MemberTemplate___(reader: Reader&, depth: i64) -> blot_reuse_principal_interface::MemberTemplate[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_reuse_principal_interface::MemberTemplate[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::MemberTemplate[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_reuse_principal_interface::MemberTemplate[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_reuse_principal_interface::MemberTemplate[:]>(), blot_error::Error.none; }
    let run = pool_blot_reuse_principal_interface__MemberTemplate.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_reuse_principal_interface__MemberTemplate { run , ..});
    if recorded != blot_error::Error.none { pool_blot_reuse_principal_interface__MemberTemplate.free_slice(run); return default<blot_reuse_principal_interface::MemberTemplate[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_reuse_principal_interface__MemberTemplate(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_reuse_principal_interface::MemberTemplate[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_reuse_principal_interface__SelectedProof___(writer: Writer&, value: const blot_reuse_principal_interface::SelectedProof[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_reuse_principal_interface__SelectedProof(writer, element, depth + 1); } }

fn read_blot_reuse_principal_interface__SelectedProof___(reader: Reader&, depth: i64) -> blot_reuse_principal_interface::SelectedProof[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_reuse_principal_interface::SelectedProof[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::SelectedProof[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_reuse_principal_interface::SelectedProof[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_reuse_principal_interface::SelectedProof[:]>(), blot_error::Error.none; }
    let run = pool_blot_reuse_principal_interface__SelectedProof.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_reuse_principal_interface__SelectedProof { run , ..});
    if recorded != blot_error::Error.none { pool_blot_reuse_principal_interface__SelectedProof.free_slice(run); return default<blot_reuse_principal_interface::SelectedProof[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_reuse_principal_interface__SelectedProof(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_reuse_principal_interface::SelectedProof[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__SelectedUse___(writer: Writer&, value: const blot_check_core::SelectedUse[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__SelectedUse(writer, element, depth + 1); } }

fn read_blot_check_core__SelectedUse___(reader: Reader&, depth: i64) -> blot_check_core::SelectedUse[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::SelectedUse[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::SelectedUse[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::SelectedUse[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::SelectedUse[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__SelectedUse.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__SelectedUse { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__SelectedUse.free_slice(run); return default<blot_check_core::SelectedUse[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__SelectedUse(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::SelectedUse[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__DictionarySelection___(writer: Writer&, value: const blot_check_core::DictionarySelection[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__DictionarySelection(writer, element, depth + 1); } }

fn read_blot_check_core__DictionarySelection___(reader: Reader&, depth: i64) -> blot_check_core::DictionarySelection[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::DictionarySelection[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::DictionarySelection[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::DictionarySelection[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::DictionarySelection[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__DictionarySelection.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__DictionarySelection { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__DictionarySelection.free_slice(run); return default<blot_check_core::DictionarySelection[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__DictionarySelection(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::DictionarySelection[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__DictionaryUse___(writer: Writer&, value: const blot_check_core::DictionaryUse[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__DictionaryUse(writer, element, depth + 1); } }

fn read_blot_check_core__DictionaryUse___(reader: Reader&, depth: i64) -> blot_check_core::DictionaryUse[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::DictionaryUse[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::DictionaryUse[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::DictionaryUse[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::DictionaryUse[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__DictionaryUse.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__DictionaryUse { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__DictionaryUse.free_slice(run); return default<blot_check_core::DictionaryUse[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__DictionaryUse(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::DictionaryUse[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__Primitive___(writer: Writer&, value: const blot_check_core::Primitive[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__Primitive(writer, element, depth + 1); } }

fn read_blot_check_core__Primitive___(reader: Reader&, depth: i64) -> blot_check_core::Primitive[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::Primitive[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::Primitive[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::Primitive[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::Primitive[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__Primitive.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__Primitive { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__Primitive.free_slice(run); return default<blot_check_core::Primitive[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__Primitive(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::Primitive[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__LoopInfo___(writer: Writer&, value: const blot_check_core::LoopInfo[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__LoopInfo(writer, element, depth + 1); } }

fn read_blot_check_core__LoopInfo___(reader: Reader&, depth: i64) -> blot_check_core::LoopInfo[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::LoopInfo[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::LoopInfo[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::LoopInfo[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::LoopInfo[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__LoopInfo.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__LoopInfo { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__LoopInfo.free_slice(run); return default<blot_check_core::LoopInfo[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__LoopInfo(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::LoopInfo[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__LoopCarry___(writer: Writer&, value: const blot_check_core::LoopCarry[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__LoopCarry(writer, element, depth + 1); } }

fn read_blot_check_core__LoopCarry___(reader: Reader&, depth: i64) -> blot_check_core::LoopCarry[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::LoopCarry[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::LoopCarry[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::LoopCarry[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::LoopCarry[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__LoopCarry.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__LoopCarry { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__LoopCarry.free_slice(run); return default<blot_check_core::LoopCarry[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__LoopCarry(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::LoopCarry[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__ResolverInfo___(writer: Writer&, value: const blot_check_core::ResolverInfo[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__ResolverInfo(writer, element, depth + 1); } }

fn read_blot_check_core__ResolverInfo___(reader: Reader&, depth: i64) -> blot_check_core::ResolverInfo[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::ResolverInfo[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::ResolverInfo[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::ResolverInfo[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::ResolverInfo[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__ResolverInfo.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__ResolverInfo { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__ResolverInfo.free_slice(run); return default<blot_check_core::ResolverInfo[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__ResolverInfo(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::ResolverInfo[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__OperationValue___(writer: Writer&, value: const blot_check_core::OperationValue[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__OperationValue(writer, element, depth + 1); } }

fn read_blot_check_core__OperationValue___(reader: Reader&, depth: i64) -> blot_check_core::OperationValue[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::OperationValue[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::OperationValue[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::OperationValue[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::OperationValue[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__OperationValue.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__OperationValue { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__OperationValue.free_slice(run); return default<blot_check_core::OperationValue[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__OperationValue(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::OperationValue[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__HandleEffects___(writer: Writer&, value: const blot_check_core::HandleEffects[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__HandleEffects(writer, element, depth + 1); } }

fn read_blot_check_core__HandleEffects___(reader: Reader&, depth: i64) -> blot_check_core::HandleEffects[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::HandleEffects[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::HandleEffects[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::HandleEffects[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::HandleEffects[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__HandleEffects.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__HandleEffects { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__HandleEffects.free_slice(run); return default<blot_check_core::HandleEffects[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__HandleEffects(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::HandleEffects[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_check_core__Diagnostic___(writer: Writer&, value: const blot_check_core::Diagnostic[:], depth: i64) { if !charge(writer, depth) { return; } put(writer, value.len as u64, 8); for element in value { write_blot_check_core__Diagnostic(writer, element, depth + 1); } }

fn read_blot_check_core__Diagnostic___(reader: Reader&, depth: i64) -> blot_check_core::Diagnostic[:], Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::Diagnostic[:]>(), charged; }
    let count, error = get(reader, 8); if error != blot_error::Error.none { return default<blot_check_core::Diagnostic[:]>(), error; }
    if count > reader.remaining as u64 || count > element_limit as u64 { return default<blot_check_core::Diagnostic[:]>(), blot_error::Error.artifact_limit; } if count == 0 { return default<blot_check_core::Diagnostic[:]>(), blot_error::Error.none; }
    let run = pool_blot_check_core__Diagnostic.alloc_slice(count as i64); let recorded = remember(reader, Run.run_blot_check_core__Diagnostic { run , ..});
    if recorded != blot_error::Error.none { pool_blot_check_core__Diagnostic.free_slice(run); return default<blot_check_core::Diagnostic[:]>(), recorded; }
    for index in count as i64 { let value, failure = read_blot_check_core__Diagnostic(reader, depth + 1); if failure != blot_error::Error.none { return default<blot_check_core::Diagnostic[:]>(), failure; } run[index] = value; } return run, blot_error::Error.none;
}

fn write_blot_support__Option_blot_check_numeric_proof_terms__Proposition_(writer: Writer&, value: blot_support::Option<blot_check_numeric_proof_terms::Proposition>, depth: i64) { if !charge(writer, depth) { return; } write_bool(writer, value.present, depth + 1); if value.present { write_blot_check_numeric_proof_terms__Proposition(writer, value.value, depth + 1); } }

fn read_blot_support__Option_blot_check_numeric_proof_terms__Proposition_(reader: Reader&, depth: i64) -> blot_support::Option<blot_check_numeric_proof_terms::Proposition>, Error { var result = blot_support::none<blot_check_numeric_proof_terms::Proposition>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; } let present, error = read_bool(reader, depth + 1); if error != blot_error::Error.none { return result, error; } if present { let value, failure = read_blot_check_numeric_proof_terms__Proposition(reader, depth + 1); if failure != blot_error::Error.none { return result, failure; } result = blot_support::some(value); } return result, blot_error::Error.none; }

fn write_blot_support__Option_blot_parse_ast__Span_(writer: Writer&, value: blot_support::Option<blot_parse_ast::Span>, depth: i64) { if !charge(writer, depth) { return; } write_bool(writer, value.present, depth + 1); if value.present { write_blot_parse_ast__Span(writer, value.value, depth + 1); } }

fn read_blot_support__Option_blot_parse_ast__Span_(reader: Reader&, depth: i64) -> blot_support::Option<blot_parse_ast::Span>, Error { var result = blot_support::none<blot_parse_ast::Span>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; } let present, error = read_bool(reader, depth + 1); if error != blot_error::Error.none { return result, error; } if present { let value, failure = read_blot_parse_ast__Span(reader, depth + 1); if failure != blot_error::Error.none { return result, failure; } result = blot_support::some(value); } return result, blot_error::Error.none; }

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
    var result = default<blot_check_core::Module>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_bool(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.has_rank_contracts = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.has_usage_contracts = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.has_numeric_proofs = decoded; }

    { let decoded, error = read_blot_check_numeric_proof_headers__Named___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.proof_contracts = decoded; }

    { let decoded, error = read_blot_check_capability_contracts__Collection(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.capability_contracts = decoded; }

    { let decoded, error = read_blot_check_core__FieldName___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.field_names = decoded; }

    { let decoded, error = read_blot_check_core__RuntimeName___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.runtime_names = decoded; }

    { let decoded, error = read_blot_check_core__RuntimeName___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.source_names = decoded; }

    { let decoded, error = read_blot_check_core__DeclarationDependencies___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.declaration_dependencies = decoded; }

    { let decoded, error = read_blot_check_core__BindingRef___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.dependency_references = decoded; }

    { let decoded, error = read_blot_check_core__DependencyMember___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.dependency_members = decoded; }

    { let decoded, error = read_blot_check_core__ErasedDeclarationReference___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.erased_declaration_references = decoded; }

    { let decoded, error = read_blot_check_core__RequestLoopInfo___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.request_loops = decoded; }

    { let decoded, error = read_blot_check_core__RequestArm___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.request_arms = decoded; }

    { let decoded, error = read_u32___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.tag_calls = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.unit = decoded; }

    { let decoded, error = read_blot_check_core__Types(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.types = decoded; }

    { let decoded, error = read_blot_check_core__Node___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.nodes = decoded; }

    { let decoded, error = read_blot_parse_ast__Span___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.spans = decoded; }

    { let decoded, error = read_u32___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.extra = decoded; }

    { let decoded, error = read_blot_check_core__Binding___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.bindings = decoded; }

    { let decoded, error = read_blot_check_core__Body___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.bodies = decoded; }

    { let decoded, error = read_blot_check_core__Parameter___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.parameters = decoded; }

    { let decoded, error = read_blot_check_core__BindingRef___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.references = decoded; }

    { let decoded, error = read_blot_check_core__CallInfo___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.calls = decoded; }

    { let decoded, error = read_blot_check_core__Merge___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.merges = decoded; }

    { let decoded, error = read_blot_check_core__List___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.merge_ranges = decoded; }

    { let decoded, error = read_u8___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.names = decoded; }

    { let decoded, error = read_blot_check_core__Obligation___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.obligations = decoded; }

    { let decoded, error = read_blot_check_core__Nominal___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.nominals = decoded; }

    { let decoded, error = read_blot_check_core__OperationName___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.operation_names = decoded; }

    { let decoded, error = read_blot_check_core__Constructor___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.constructors = decoded; }

    { let decoded, error = read_blot_check_core__Projection___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.projections = decoded; }

    { let decoded, error = read_blot_check_core__ProjectionVariant___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.projection_variants = decoded; }

    { let decoded, error = read_blot_check_core__Pattern___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.patterns = decoded; }

    { let decoded, error = read_blot_check_core__PatternRow___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.pattern_rows = decoded; }

    { let decoded, error = read_blot_check_core__MatchArm___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.match_arms = decoded; }

    { let decoded, error = read_blot_check_core__MatchInfo___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.matches = decoded; }

    { let decoded, error = read_blot_check_core__UpdateInfo___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.updates = decoded; }

    { let decoded, error = read_blot_check_core__UpdateStep___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.update_steps = decoded; }

    { let decoded, error = read_blot_check_core__ClosureInfo___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.closures = decoded; }

    { let decoded, error = read_blot_check_core__Associated___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.associated = decoded; }

    { let decoded, error = read_blot_check_core__Contract___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.contracts = decoded; }

    { let decoded, error = read_blot_reuse_principal_interface__ContractMember___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.contract_members = decoded; }

    { let decoded, error = read_blot_reuse_principal_interface__Implementation___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.implementations = decoded; }

    { let decoded, error = read_blot_reuse_principal_interface__ImplementationMember___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.implementation_members = decoded; }

    { let decoded, error = read_blot_reuse_principal_interface__MemberTemplate___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.member_templates = decoded; }

    { let decoded, error = read_blot_reuse_principal_interface__SelectedProof___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.selected_proofs = decoded; }

    { let decoded, error = read_blot_reuse_principal_interface__ImplementationMember___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.selected_members = decoded; }

    { let decoded, error = read_u32___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.selected_edges = decoded; }

    { let decoded, error = read_blot_check_core__SelectedUse___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.selected_uses = decoded; }

    { let decoded, error = read_blot_check_core__DictionarySelection___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.dictionary_selections = decoded; }

    { let decoded, error = read_blot_check_core__DictionaryUse___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.dictionary_uses = decoded; }

    { let decoded, error = read_blot_check_core__Primitive___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.primitives = decoded; }

    { let decoded, error = read_blot_check_core__LoopInfo___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.loops = decoded; }

    { let decoded, error = read_blot_check_core__LoopCarry___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.loop_carries = decoded; }

    { let decoded, error = read_blot_check_core__ResolverInfo___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.resolver_ops = decoded; }

    { let decoded, error = read_blot_check_core__OperationValue___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.operation_values = decoded; }

    { let decoded, error = read_blot_check_core__HandleEffects___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.handle_effects = decoded; }

    { let decoded, error = read_u32___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.dispatch_signatures = decoded; }

    { let decoded, error = read_blot_check_core__Diagnostic___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.diagnostics = decoded; }

    { let decoded, error = read_i64(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Module>(), error; } result.body_lowerings = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_numeric_proof_headers__Named(writer: Writer&, value: blot_check_numeric_proof_headers::Named, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.binding, depth + 1);

    write_blot_check_numeric_proof_headers__Owned(writer, value.header, depth + 1);

}

fn read_blot_check_numeric_proof_headers__Named(reader: Reader&, depth: i64) -> blot_check_numeric_proof_headers::Named, Error {
    var result = default<blot_check_numeric_proof_headers::Named>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_numeric_proof_headers::Named>(), error; } result.binding = decoded; }

    { let decoded, error = read_blot_check_numeric_proof_headers__Owned(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_numeric_proof_headers::Named>(), error; } result.header = decoded; }

    return result, blot_error::Error.none;
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
    var result = default<blot_check_numeric_proof_headers::Owned>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_numeric_proof_headers::Owned>(), error; } result.arity = decoded; }

    { let decoded, error = read_u32___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_numeric_proof_headers::Owned>(), error; } result.value_slots = decoded; }

    { let decoded, error = read_u32___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_numeric_proof_headers::Owned>(), error; } result.proof_slots = decoded; }

    { let decoded, error = read_blot_check_numeric_proof_terms__Kind___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_numeric_proof_headers::Owned>(), error; } result.values = decoded; }

    { let decoded, error = read_blot_check_numeric_proof_terms__Term___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_numeric_proof_headers::Owned>(), error; } result.operands = decoded; }

    { let decoded, error = read_blot_check_numeric_proof_contracts__Requirement___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_numeric_proof_headers::Owned>(), error; } result.requirements = decoded; }

    { let decoded, error = read_blot_support__Option_blot_check_numeric_proof_terms__Proposition_(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_numeric_proof_headers::Owned>(), error; } result.result = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_numeric_proof_terms__Kind(writer: Writer&, value: blot_check_numeric_proof_terms::Kind, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        unsigned32 => { put(writer, 0, 4);
},

        array => { put(writer, 1, 4);
},

        list => { put(writer, 2, 4);
},

    }
}

fn read_blot_check_numeric_proof_terms__Kind(reader: Reader&, depth: i64) -> blot_check_numeric_proof_terms::Kind, Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_numeric_proof_terms::Kind>(), charged; } let tag, error = get(reader, 4); if error != blot_error::Error.none { return default<blot_check_numeric_proof_terms::Kind>(), error; }
    match tag {

        0 => {
return blot_check_numeric_proof_terms::Kind.unsigned32, blot_error::Error.none; },

        1 => {
return blot_check_numeric_proof_terms::Kind.array, blot_error::Error.none; },

        2 => {
return blot_check_numeric_proof_terms::Kind.list, blot_error::Error.none; },

        _ => { return default<blot_check_numeric_proof_terms::Kind>(), blot_error::Error.invalid_artifact; },
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
    var result = default<blot_check_numeric_proof_terms::Term>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_numeric_proof_terms__Tag(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_numeric_proof_terms::Term>(), error; } result.tag = decoded; }

    { let decoded, error = read_blot_check_numeric_proof_terms__Kind(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_numeric_proof_terms::Term>(), error; } result.kind = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_numeric_proof_terms::Term>(), error; } result.a = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_numeric_proof_terms::Term>(), error; } result.b = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_numeric_proof_terms__Tag(writer: Writer&, value: blot_check_numeric_proof_terms::Tag, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        literal => { put(writer, 0, 4);
},

        formal => { put(writer, 1, 4);
},

        capture => { put(writer, 2, 4);
},

        version => { put(writer, 3, 4);
},

        length => { put(writer, 4, 4);
},

        complement => { put(writer, 5, 4);
},

    }
}

fn read_blot_check_numeric_proof_terms__Tag(reader: Reader&, depth: i64) -> blot_check_numeric_proof_terms::Tag, Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_numeric_proof_terms::Tag>(), charged; } let tag, error = get(reader, 4); if error != blot_error::Error.none { return default<blot_check_numeric_proof_terms::Tag>(), error; }
    match tag {

        0 => {
return blot_check_numeric_proof_terms::Tag.literal, blot_error::Error.none; },

        1 => {
return blot_check_numeric_proof_terms::Tag.formal, blot_error::Error.none; },

        2 => {
return blot_check_numeric_proof_terms::Tag.capture, blot_error::Error.none; },

        3 => {
return blot_check_numeric_proof_terms::Tag.version, blot_error::Error.none; },

        4 => {
return blot_check_numeric_proof_terms::Tag.length, blot_error::Error.none; },

        5 => {
return blot_check_numeric_proof_terms::Tag.complement, blot_error::Error.none; },

        _ => { return default<blot_check_numeric_proof_terms::Tag>(), blot_error::Error.invalid_artifact; },
    }
}

fn write_blot_check_numeric_proof_contracts__Requirement(writer: Writer&, value: blot_check_numeric_proof_contracts::Requirement, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.before, depth + 1);

    write_blot_check_numeric_proof_terms__Proposition(writer, value.proposition, depth + 1);

}

fn read_blot_check_numeric_proof_contracts__Requirement(reader: Reader&, depth: i64) -> blot_check_numeric_proof_contracts::Requirement, Error {
    var result = default<blot_check_numeric_proof_contracts::Requirement>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_numeric_proof_contracts::Requirement>(), error; } result.before = decoded; }

    { let decoded, error = read_blot_check_numeric_proof_terms__Proposition(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_numeric_proof_contracts::Requirement>(), error; } result.proposition = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_numeric_proof_terms__Proposition(writer: Writer&, value: blot_check_numeric_proof_terms::Proposition, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_numeric_proof_terms__Relation(writer, value.relation, depth + 1);

    write_u32(writer, value.left, depth + 1);

    write_u32(writer, value.right, depth + 1);

}

fn read_blot_check_numeric_proof_terms__Proposition(reader: Reader&, depth: i64) -> blot_check_numeric_proof_terms::Proposition, Error {
    var result = default<blot_check_numeric_proof_terms::Proposition>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_numeric_proof_terms__Relation(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_numeric_proof_terms::Proposition>(), error; } result.relation = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_numeric_proof_terms::Proposition>(), error; } result.left = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_numeric_proof_terms::Proposition>(), error; } result.right = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_numeric_proof_terms__Relation(writer: Writer&, value: blot_check_numeric_proof_terms::Relation, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        eq => { put(writer, 0, 4);
},

        lt => { put(writer, 1, 4);
},

        le => { put(writer, 2, 4);
},

        add_fits => { put(writer, 3, 4);
},

        sub_fits => { put(writer, 4, 4);
},

        index => { put(writer, 5, 4);
},

    }
}

fn read_blot_check_numeric_proof_terms__Relation(reader: Reader&, depth: i64) -> blot_check_numeric_proof_terms::Relation, Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_numeric_proof_terms::Relation>(), charged; } let tag, error = get(reader, 4); if error != blot_error::Error.none { return default<blot_check_numeric_proof_terms::Relation>(), error; }
    match tag {

        0 => {
return blot_check_numeric_proof_terms::Relation.eq, blot_error::Error.none; },

        1 => {
return blot_check_numeric_proof_terms::Relation.lt, blot_error::Error.none; },

        2 => {
return blot_check_numeric_proof_terms::Relation.le, blot_error::Error.none; },

        3 => {
return blot_check_numeric_proof_terms::Relation.add_fits, blot_error::Error.none; },

        4 => {
return blot_check_numeric_proof_terms::Relation.sub_fits, blot_error::Error.none; },

        5 => {
return blot_check_numeric_proof_terms::Relation.index, blot_error::Error.none; },

        _ => { return default<blot_check_numeric_proof_terms::Relation>(), blot_error::Error.invalid_artifact; },
    }
}

fn write_blot_check_capability_contracts__Collection(writer: Writer&, value: blot_check_capability_contracts::Collection, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_capability_contracts__Term___(writer, value.nodes, depth + 1);

    write_u32___(writer, value.words, depth + 1);

    write_blot_check_capability_contracts__Binding___(writer, value.bindings, depth + 1);

}

fn read_blot_check_capability_contracts__Collection(reader: Reader&, depth: i64) -> blot_check_capability_contracts::Collection, Error {
    var result = default<blot_check_capability_contracts::Collection>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_capability_contracts__Term___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_capability_contracts::Collection>(), error; } result.nodes = decoded; }

    { let decoded, error = read_u32___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_capability_contracts::Collection>(), error; } result.words = decoded; }

    { let decoded, error = read_blot_check_capability_contracts__Binding___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_capability_contracts::Collection>(), error; } result.bindings = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_capability_contracts__Term(writer: Writer&, value: blot_check_capability_contracts::Term, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_capability_contracts__Tag(writer, value.tag, depth + 1);

    write_u32(writer, value.a, depth + 1);

    write_u32(writer, value.b, depth + 1);

    write_u32(writer, value.c, depth + 1);

}

fn read_blot_check_capability_contracts__Term(reader: Reader&, depth: i64) -> blot_check_capability_contracts::Term, Error {
    var result = default<blot_check_capability_contracts::Term>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_capability_contracts__Tag(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_capability_contracts::Term>(), error; } result.tag = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_capability_contracts::Term>(), error; } result.a = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_capability_contracts::Term>(), error; } result.b = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_capability_contracts::Term>(), error; } result.c = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_capability_contracts__Tag(writer: Writer&, value: blot_check_capability_contracts::Tag, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        empty => { put(writer, 0, 4);
},

        unknown => { put(writer, 1, 4);
},

        parameter => { put(writer, 2, 4);
},

        authority => { put(writer, 3, 4);
},

        captures => { put(writer, 4, 4);
},

        product => { put(writer, 5, 4);
},

        record => { put(writer, 6, 4);
},

        wrapped => { put(writer, 7, 4);
},

        join => { put(writer, 8, 4);
},

        project => { put(writer, 9, 4);
},

        elements => { put(writer, 10, 4);
},

        argument => { put(writer, 11, 4);
},

        callable => { put(writer, 12, 4);
},

    }
}

fn read_blot_check_capability_contracts__Tag(reader: Reader&, depth: i64) -> blot_check_capability_contracts::Tag, Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_capability_contracts::Tag>(), charged; } let tag, error = get(reader, 4); if error != blot_error::Error.none { return default<blot_check_capability_contracts::Tag>(), error; }
    match tag {

        0 => {
return blot_check_capability_contracts::Tag.empty, blot_error::Error.none; },

        1 => {
return blot_check_capability_contracts::Tag.unknown, blot_error::Error.none; },

        2 => {
return blot_check_capability_contracts::Tag.parameter, blot_error::Error.none; },

        3 => {
return blot_check_capability_contracts::Tag.authority, blot_error::Error.none; },

        4 => {
return blot_check_capability_contracts::Tag.captures, blot_error::Error.none; },

        5 => {
return blot_check_capability_contracts::Tag.product, blot_error::Error.none; },

        6 => {
return blot_check_capability_contracts::Tag.record, blot_error::Error.none; },

        7 => {
return blot_check_capability_contracts::Tag.wrapped, blot_error::Error.none; },

        8 => {
return blot_check_capability_contracts::Tag.join, blot_error::Error.none; },

        9 => {
return blot_check_capability_contracts::Tag.project, blot_error::Error.none; },

        10 => {
return blot_check_capability_contracts::Tag.elements, blot_error::Error.none; },

        11 => {
return blot_check_capability_contracts::Tag.argument, blot_error::Error.none; },

        12 => {
return blot_check_capability_contracts::Tag.callable, blot_error::Error.none; },

        _ => { return default<blot_check_capability_contracts::Tag>(), blot_error::Error.invalid_artifact; },
    }
}

fn write_blot_check_capability_contracts__Binding(writer: Writer&, value: blot_check_capability_contracts::Binding, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.binding, depth + 1);

    write_u32(writer, value.root, depth + 1);

}

fn read_blot_check_capability_contracts__Binding(reader: Reader&, depth: i64) -> blot_check_capability_contracts::Binding, Error {
    var result = default<blot_check_capability_contracts::Binding>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_capability_contracts::Binding>(), error; } result.binding = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_capability_contracts::Binding>(), error; } result.root = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_core__FieldName(writer: Writer&, value: blot_check_core::FieldName, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.symbol, depth + 1);

    write_blot_check_core__Name(writer, value.spelling, depth + 1);

}

fn read_blot_check_core__FieldName(reader: Reader&, depth: i64) -> blot_check_core::FieldName, Error {
    var result = default<blot_check_core::FieldName>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::FieldName>(), error; } result.symbol = decoded; }

    { let decoded, error = read_blot_check_core__Name(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::FieldName>(), error; } result.spelling = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_core__Name(writer: Writer&, value: blot_check_core::Name, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.start, depth + 1);

    write_u32(writer, value.len, depth + 1);

}

fn read_blot_check_core__Name(reader: Reader&, depth: i64) -> blot_check_core::Name, Error {
    var result = default<blot_check_core::Name>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Name>(), error; } result.start = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Name>(), error; } result.len = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_core__RuntimeName(writer: Writer&, value: blot_check_core::RuntimeName, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.binding, depth + 1);

    write_u32(writer, value.point, depth + 1);

}

fn read_blot_check_core__RuntimeName(reader: Reader&, depth: i64) -> blot_check_core::RuntimeName, Error {
    var result = default<blot_check_core::RuntimeName>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::RuntimeName>(), error; } result.binding = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::RuntimeName>(), error; } result.point = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_core__DeclarationDependencies(writer: Writer&, value: blot_check_core::DeclarationDependencies, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_core__List(writer, value.references, depth + 1);

    write_blot_check_core__List(writer, value.members, depth + 1);

    write_u32(writer, value.runtime_metadata, depth + 1);

}

fn read_blot_check_core__DeclarationDependencies(reader: Reader&, depth: i64) -> blot_check_core::DeclarationDependencies, Error {
    var result = default<blot_check_core::DeclarationDependencies>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::DeclarationDependencies>(), error; } result.references = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::DeclarationDependencies>(), error; } result.members = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::DeclarationDependencies>(), error; } result.runtime_metadata = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_core__List(writer: Writer&, value: blot_check_core::List, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.start, depth + 1);

    write_u32(writer, value.len, depth + 1);

}

fn read_blot_check_core__List(reader: Reader&, depth: i64) -> blot_check_core::List, Error {
    var result = default<blot_check_core::List>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::List>(), error; } result.start = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::List>(), error; } result.len = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_core__BindingRef(writer: Writer&, value: blot_check_core::BindingRef, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.unit, depth + 1);

    write_u32(writer, value.binding, depth + 1);

}

fn read_blot_check_core__BindingRef(reader: Reader&, depth: i64) -> blot_check_core::BindingRef, Error {
    var result = default<blot_check_core::BindingRef>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::BindingRef>(), error; } result.unit = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::BindingRef>(), error; } result.binding = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_core__DependencyMember(writer: Writer&, value: blot_check_core::DependencyMember, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.name, depth + 1);

    write_blot_check_types__Operator(writer, value.operator, depth + 1);

}

fn read_blot_check_core__DependencyMember(reader: Reader&, depth: i64) -> blot_check_core::DependencyMember, Error {
    var result = default<blot_check_core::DependencyMember>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::DependencyMember>(), error; } result.name = decoded; }

    { let decoded, error = read_blot_check_types__Operator(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::DependencyMember>(), error; } result.operator = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_types__Operator(writer: Writer&, value: blot_check_types::Operator, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        none => { put(writer, 0, 4);
},

        add => { put(writer, 1, 4);
},

        sub => { put(writer, 2, 4);
},

        mul => { put(writer, 3, 4);
},

        div => { put(writer, 4, 4);
},

        rem => { put(writer, 5, 4);
},

        equal => { put(writer, 6, 4);
},

        not_equal => { put(writer, 7, 4);
},

        less => { put(writer, 8, 4);
},

        less_equal => { put(writer, 9, 4);
},

        greater => { put(writer, 10, 4);
},

        greater_equal => { put(writer, 11, 4);
},

        bit_and => { put(writer, 12, 4);
},

        bit_or => { put(writer, 13, 4);
},

        bit_xor => { put(writer, 14, 4);
},

        shift_left => { put(writer, 15, 4);
},

        shift_right => { put(writer, 16, 4);
},

    }
}

fn read_blot_check_types__Operator(reader: Reader&, depth: i64) -> blot_check_types::Operator, Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_types::Operator>(), charged; } let tag, error = get(reader, 4); if error != blot_error::Error.none { return default<blot_check_types::Operator>(), error; }
    match tag {

        0 => {
return blot_check_types::Operator.none, blot_error::Error.none; },

        1 => {
return blot_check_types::Operator.add, blot_error::Error.none; },

        2 => {
return blot_check_types::Operator.sub, blot_error::Error.none; },

        3 => {
return blot_check_types::Operator.mul, blot_error::Error.none; },

        4 => {
return blot_check_types::Operator.div, blot_error::Error.none; },

        5 => {
return blot_check_types::Operator.rem, blot_error::Error.none; },

        6 => {
return blot_check_types::Operator.equal, blot_error::Error.none; },

        7 => {
return blot_check_types::Operator.not_equal, blot_error::Error.none; },

        8 => {
return blot_check_types::Operator.less, blot_error::Error.none; },

        9 => {
return blot_check_types::Operator.less_equal, blot_error::Error.none; },

        10 => {
return blot_check_types::Operator.greater, blot_error::Error.none; },

        11 => {
return blot_check_types::Operator.greater_equal, blot_error::Error.none; },

        12 => {
return blot_check_types::Operator.bit_and, blot_error::Error.none; },

        13 => {
return blot_check_types::Operator.bit_or, blot_error::Error.none; },

        14 => {
return blot_check_types::Operator.bit_xor, blot_error::Error.none; },

        15 => {
return blot_check_types::Operator.shift_left, blot_error::Error.none; },

        16 => {
return blot_check_types::Operator.shift_right, blot_error::Error.none; },

        _ => { return default<blot_check_types::Operator>(), blot_error::Error.invalid_artifact; },
    }
}

fn write_blot_check_core__ErasedDeclarationReference(writer: Writer&, value: blot_check_core::ErasedDeclarationReference, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.node, depth + 1);

    write_blot_check_core__BindingRef(writer, value.target, depth + 1);

}

fn read_blot_check_core__ErasedDeclarationReference(reader: Reader&, depth: i64) -> blot_check_core::ErasedDeclarationReference, Error {
    var result = default<blot_check_core::ErasedDeclarationReference>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::ErasedDeclarationReference>(), error; } result.node = decoded; }

    { let decoded, error = read_blot_check_core__BindingRef(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::ErasedDeclarationReference>(), error; } result.target = decoded; }

    return result, blot_error::Error.none;
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
    var result = default<blot_check_core::RequestLoopInfo>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::RequestLoopInfo>(), error; } result.computation = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::RequestLoopInfo>(), error; } result.action_type = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::RequestLoopInfo>(), error; } result.value_type = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::RequestLoopInfo>(), error; } result.result_type = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::RequestLoopInfo>(), error; } result.state_type = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::RequestLoopInfo>(), error; } result.arms = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::RequestLoopInfo>(), error; } result.completion_pattern = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::RequestLoopInfo>(), error; } result.completion_body = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::RequestLoopInfo>(), error; } result.completion_state_bindings = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::RequestLoopInfo>(), error; } result.carries = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::RequestLoopInfo>(), error; } result.return_target = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_core__RequestArm(writer: Writer&, value: blot_check_core::RequestArm, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.operation, depth + 1);

    write_u32(writer, value.callback, depth + 1);

    write_u32(writer, value.selector, depth + 1);

}

fn read_blot_check_core__RequestArm(reader: Reader&, depth: i64) -> blot_check_core::RequestArm, Error {
    var result = default<blot_check_core::RequestArm>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::RequestArm>(), error; } result.operation = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::RequestArm>(), error; } result.callback = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::RequestArm>(), error; } result.selector = decoded; }

    return result, blot_error::Error.none;
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
    var result = default<blot_check_core::Types>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_types__Node___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Types>(), error; } result.nodes = decoded; }

    { let decoded, error = read_u32___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Types>(), error; } result.extra = decoded; }

    { let decoded, error = read_blot_check_core__EffectRows(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Types>(), error; } result.effects = decoded; }

    { let decoded, error = read_blot_check_types__Operation___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Types>(), error; } result.operations = decoded; }

    { let decoded, error = read_blot_check_types__QuantifierGoals___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Types>(), error; } result.quantifier_goals = decoded; }

    { let decoded, error = read_blot_check_types__Obligation___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Types>(), error; } result.quantifier_obligations = decoded; }

    return result, blot_error::Error.none;
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
    var result = default<blot_check_types::Node>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_types__Tag(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::Node>(), error; } result.tag = decoded; }

    { let decoded, error = read_u8(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::Node>(), error; } result.closed_height = decoded; }

    { let decoded, error = read_u16(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::Node>(), error; } result.closed_generation = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::Node>(), error; } result.a = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::Node>(), error; } result.b = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::Node>(), error; } result.c = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_types__Tag(writer: Writer&, value: blot_check_types::Tag, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        absent => { put(writer, 0, 4);
},

        unit => { put(writer, 1, 4);
},

        boolean => { put(writer, 2, 4);
},

        unsigned32 => { put(writer, 3, 4);
},

        floating32 => { put(writer, 4, 4);
},

        never => { put(writer, 5, 4);
},

        variable => { put(writer, 6, 4);
},

        function => { put(writer, 7, 4);
},

        product => { put(writer, 8, 4);
},

        record => { put(writer, 9, 4);
},

        nominal => { put(writer, 10, 4);
},

        array => { put(writer, 11, 4);
},

        list => { put(writer, 12, 4);
},

        cursor => { put(writer, 13, 4);
},

        type_constructor => { put(writer, 14, 4);
},

        resolver => { put(writer, 15, 4);
},

        provider => { put(writer, 16, 4);
},

        state_provider => { put(writer, 17, 4);
},

        projection => { put(writer, 18, 4);
},

        scoped => { put(writer, 19, 4);
},

        instance_selection => { put(writer, 20, 4);
},

        erased_proof => { put(writer, 21, 4);
},

        forall => { put(writer, 22, 4);
},

        existential => { put(writer, 23, 4);
},

        bound => { put(writer, 24, 4);
},

        rigid => { put(writer, 25, 4);
},

        usage => { put(writer, 26, 4);
},

        instance_version => { put(writer, 27, 4);
},

    }
}

fn read_blot_check_types__Tag(reader: Reader&, depth: i64) -> blot_check_types::Tag, Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_types::Tag>(), charged; } let tag, error = get(reader, 4); if error != blot_error::Error.none { return default<blot_check_types::Tag>(), error; }
    match tag {

        0 => {
return blot_check_types::Tag.absent, blot_error::Error.none; },

        1 => {
return blot_check_types::Tag.unit, blot_error::Error.none; },

        2 => {
return blot_check_types::Tag.boolean, blot_error::Error.none; },

        3 => {
return blot_check_types::Tag.unsigned32, blot_error::Error.none; },

        4 => {
return blot_check_types::Tag.floating32, blot_error::Error.none; },

        5 => {
return blot_check_types::Tag.never, blot_error::Error.none; },

        6 => {
return blot_check_types::Tag.variable, blot_error::Error.none; },

        7 => {
return blot_check_types::Tag.function, blot_error::Error.none; },

        8 => {
return blot_check_types::Tag.product, blot_error::Error.none; },

        9 => {
return blot_check_types::Tag.record, blot_error::Error.none; },

        10 => {
return blot_check_types::Tag.nominal, blot_error::Error.none; },

        11 => {
return blot_check_types::Tag.array, blot_error::Error.none; },

        12 => {
return blot_check_types::Tag.list, blot_error::Error.none; },

        13 => {
return blot_check_types::Tag.cursor, blot_error::Error.none; },

        14 => {
return blot_check_types::Tag.type_constructor, blot_error::Error.none; },

        15 => {
return blot_check_types::Tag.resolver, blot_error::Error.none; },

        16 => {
return blot_check_types::Tag.provider, blot_error::Error.none; },

        17 => {
return blot_check_types::Tag.state_provider, blot_error::Error.none; },

        18 => {
return blot_check_types::Tag.projection, blot_error::Error.none; },

        19 => {
return blot_check_types::Tag.scoped, blot_error::Error.none; },

        20 => {
return blot_check_types::Tag.instance_selection, blot_error::Error.none; },

        21 => {
return blot_check_types::Tag.erased_proof, blot_error::Error.none; },

        22 => {
return blot_check_types::Tag.forall, blot_error::Error.none; },

        23 => {
return blot_check_types::Tag.existential, blot_error::Error.none; },

        24 => {
return blot_check_types::Tag.bound, blot_error::Error.none; },

        25 => {
return blot_check_types::Tag.rigid, blot_error::Error.none; },

        26 => {
return blot_check_types::Tag.usage, blot_error::Error.none; },

        27 => {
return blot_check_types::Tag.instance_version, blot_error::Error.none; },

        _ => { return default<blot_check_types::Tag>(), blot_error::Error.invalid_artifact; },
    }
}

fn write_blot_check_core__EffectRows(writer: Writer&, value: blot_check_core::EffectRows, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_effects__Row___(writer, value.rows, depth + 1);

    write_u32___(writer, value.labels, depth + 1);

    write_u32(writer, value.variable_count, depth + 1);

}

fn read_blot_check_core__EffectRows(reader: Reader&, depth: i64) -> blot_check_core::EffectRows, Error {
    var result = default<blot_check_core::EffectRows>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_effects__Row___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::EffectRows>(), error; } result.rows = decoded; }

    { let decoded, error = read_u32___(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::EffectRows>(), error; } result.labels = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::EffectRows>(), error; } result.variable_count = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_effects__Row(writer: Writer&, value: blot_check_effects::Row, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_effects__List(writer, value.labels, depth + 1);

    write_blot_check_effects__Tail(writer, value.tail, depth + 1);

    write_u32(writer, value.cursor, depth + 1);

}

fn read_blot_check_effects__Row(reader: Reader&, depth: i64) -> blot_check_effects::Row, Error {
    var result = default<blot_check_effects::Row>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_effects__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_effects::Row>(), error; } result.labels = decoded; }

    { let decoded, error = read_blot_check_effects__Tail(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_effects::Row>(), error; } result.tail = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_effects::Row>(), error; } result.cursor = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_effects__List(writer: Writer&, value: blot_check_effects::List, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.start, depth + 1);

    write_u32(writer, value.len, depth + 1);

}

fn read_blot_check_effects__List(reader: Reader&, depth: i64) -> blot_check_effects::List, Error {
    var result = default<blot_check_effects::List>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_effects::List>(), error; } result.start = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_effects::List>(), error; } result.len = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_effects__Tail(writer: Writer&, value: blot_check_effects::Tail, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        closed => { put(writer, 0, 4);
},

        variable payload => { put(writer, 1, 4);
write_u32(writer, payload.value, depth + 1);
},

        parameter payload => { put(writer, 2, 4);
write_u32(writer, payload.value, depth + 1);
},

        formal payload => { put(writer, 3, 4);
write_u32(writer, payload.value, depth + 1);
},

    }
}

fn read_blot_check_effects__Tail(reader: Reader&, depth: i64) -> blot_check_effects::Tail, Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_effects::Tail>(), charged; } let tag, error = get(reader, 4); if error != blot_error::Error.none { return default<blot_check_effects::Tail>(), error; }
    match tag {

        0 => {
return blot_check_effects::Tail.closed, blot_error::Error.none; },

        1 => {
let value, failure_value = read_u32(reader, depth + 1); if failure_value != blot_error::Error.none { return default<blot_check_effects::Tail>(), failure_value; }
return blot_check_effects::Tail.variable { value: value , ..}, blot_error::Error.none; },

        2 => {
let value, failure_value = read_u32(reader, depth + 1); if failure_value != blot_error::Error.none { return default<blot_check_effects::Tail>(), failure_value; }
return blot_check_effects::Tail.parameter { value: value , ..}, blot_error::Error.none; },

        3 => {
let value, failure_value = read_u32(reader, depth + 1); if failure_value != blot_error::Error.none { return default<blot_check_effects::Tail>(), failure_value; }
return blot_check_effects::Tail.formal { value: value , ..}, blot_error::Error.none; },

        _ => { return default<blot_check_effects::Tail>(), blot_error::Error.invalid_artifact; },
    }
}

fn write_blot_check_types__Operation(writer: Writer&, value: blot_check_types::Operation, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_types__NominalIdentity(writer, value.identity, depth + 1);

    write_blot_check_types__List(writer, value.arguments, depth + 1);

    write_blot_check_types__NominalIdentity(writer, value.instance, depth + 1);

}

fn read_blot_check_types__Operation(reader: Reader&, depth: i64) -> blot_check_types::Operation, Error {
    var result = default<blot_check_types::Operation>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::Operation>(), error; } result.identity = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::Operation>(), error; } result.arguments = decoded; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::Operation>(), error; } result.instance = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_types__NominalIdentity(writer: Writer&, value: blot_check_types::NominalIdentity, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.unit, depth + 1);

    write_u32(writer, value.decl, depth + 1);

}

fn read_blot_check_types__NominalIdentity(reader: Reader&, depth: i64) -> blot_check_types::NominalIdentity, Error {
    var result = default<blot_check_types::NominalIdentity>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::NominalIdentity>(), error; } result.unit = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::NominalIdentity>(), error; } result.decl = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_types__List(writer: Writer&, value: blot_check_types::List, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.start, depth + 1);

    write_u32(writer, value.len, depth + 1);

}

fn read_blot_check_types__List(reader: Reader&, depth: i64) -> blot_check_types::List, Error {
    var result = default<blot_check_types::List>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::List>(), error; } result.start = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::List>(), error; } result.len = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_types__QuantifierGoals(writer: Writer&, value: blot_check_types::QuantifierGoals, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.owner, depth + 1);

    write_blot_check_types__List(writer, value.goals, depth + 1);

}

fn read_blot_check_types__QuantifierGoals(reader: Reader&, depth: i64) -> blot_check_types::QuantifierGoals, Error {
    var result = default<blot_check_types::QuantifierGoals>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::QuantifierGoals>(), error; } result.owner = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::QuantifierGoals>(), error; } result.goals = decoded; }

    return result, blot_error::Error.none;
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
    var result = default<blot_check_types::Obligation>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::Obligation>(), error; } result.ty = decoded; }

    { let decoded, error = read_blot_check_types__ObligationKind(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::Obligation>(), error; } result.kind = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::Obligation>(), error; } result.source = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::Obligation>(), error; } result.name = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::Obligation>(), error; } result.result = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::Obligation>(), error; } result.other = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::Obligation>(), error; } result.signature = decoded; }

    { let decoded, error = read_blot_check_types__Operator(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::Obligation>(), error; } result.operator = decoded; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::Obligation>(), error; } result.identity = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::Obligation>(), error; } result.explicit = decoded; }

    { let decoded, error = read_blot_support__Option_blot_parse_ast__Span_(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::Obligation>(), error; } result.qualification_span = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::Obligation>(), error; } result.qualification_unit = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_types__ObligationKind(writer: Writer&, value: blot_check_types::ObligationKind, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        arithmetic => { put(writer, 0, 4);
},

        ordered => { put(writer, 1, 4);
},

        equality => { put(writer, 2, 4);
},

        integer => { put(writer, 3, 4);
},

        field => { put(writer, 4, 4);
},

        writable_field => { put(writer, 5, 4);
},

        dispatch => { put(writer, 6, 4);
},

        result_dispatch => { put(writer, 7, 4);
},

        monad_factory => { put(writer, 8, 4);
},

        resolver_dispatch => { put(writer, 9, 4);
},

        resolver_shape => { put(writer, 10, 4);
},

        effect_operation => { put(writer, 11, 4);
},

        effect_handler => { put(writer, 12, 4);
},

        receiver => { put(writer, 13, 4);
},

        update => { put(writer, 14, 4);
},

        type_rep => { put(writer, 15, 4);
},

        effect_rep => { put(writer, 16, 4);
},

        type_head => { put(writer, 17, 4);
},

        collection => { put(writer, 18, 4);
},

        record_merge => { put(writer, 19, 4);
},

        callee_use => { put(writer, 20, 4);
},

        type_eq => { put(writer, 21, 4);
},

        contract => { put(writer, 22, 4);
},

        task_receive => { put(writer, 23, 4);
},

    }
}

fn read_blot_check_types__ObligationKind(reader: Reader&, depth: i64) -> blot_check_types::ObligationKind, Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_types::ObligationKind>(), charged; } let tag, error = get(reader, 4); if error != blot_error::Error.none { return default<blot_check_types::ObligationKind>(), error; }
    match tag {

        0 => {
return blot_check_types::ObligationKind.arithmetic, blot_error::Error.none; },

        1 => {
return blot_check_types::ObligationKind.ordered, blot_error::Error.none; },

        2 => {
return blot_check_types::ObligationKind.equality, blot_error::Error.none; },

        3 => {
return blot_check_types::ObligationKind.integer, blot_error::Error.none; },

        4 => {
return blot_check_types::ObligationKind.field, blot_error::Error.none; },

        5 => {
return blot_check_types::ObligationKind.writable_field, blot_error::Error.none; },

        6 => {
return blot_check_types::ObligationKind.dispatch, blot_error::Error.none; },

        7 => {
return blot_check_types::ObligationKind.result_dispatch, blot_error::Error.none; },

        8 => {
return blot_check_types::ObligationKind.monad_factory, blot_error::Error.none; },

        9 => {
return blot_check_types::ObligationKind.resolver_dispatch, blot_error::Error.none; },

        10 => {
return blot_check_types::ObligationKind.resolver_shape, blot_error::Error.none; },

        11 => {
return blot_check_types::ObligationKind.effect_operation, blot_error::Error.none; },

        12 => {
return blot_check_types::ObligationKind.effect_handler, blot_error::Error.none; },

        13 => {
return blot_check_types::ObligationKind.receiver, blot_error::Error.none; },

        14 => {
return blot_check_types::ObligationKind.update, blot_error::Error.none; },

        15 => {
return blot_check_types::ObligationKind.type_rep, blot_error::Error.none; },

        16 => {
return blot_check_types::ObligationKind.effect_rep, blot_error::Error.none; },

        17 => {
return blot_check_types::ObligationKind.type_head, blot_error::Error.none; },

        18 => {
return blot_check_types::ObligationKind.collection, blot_error::Error.none; },

        19 => {
return blot_check_types::ObligationKind.record_merge, blot_error::Error.none; },

        20 => {
return blot_check_types::ObligationKind.callee_use, blot_error::Error.none; },

        21 => {
return blot_check_types::ObligationKind.type_eq, blot_error::Error.none; },

        22 => {
return blot_check_types::ObligationKind.contract, blot_error::Error.none; },

        23 => {
return blot_check_types::ObligationKind.task_receive, blot_error::Error.none; },

        _ => { return default<blot_check_types::ObligationKind>(), blot_error::Error.invalid_artifact; },
    }
}

fn write_blot_parse_ast__Span(writer: Writer&, value: blot_parse_ast::Span, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.start, depth + 1);

    write_u32(writer, value.end, depth + 1);

}

fn read_blot_parse_ast__Span(reader: Reader&, depth: i64) -> blot_parse_ast::Span, Error {
    var result = default<blot_parse_ast::Span>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_parse_ast::Span>(), error; } result.start = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_parse_ast::Span>(), error; } result.end = decoded; }

    return result, blot_error::Error.none;
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
    var result = default<blot_check_core::Node>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_core__Tag(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Node>(), error; } result.tag = decoded; }

    { let decoded, error = read_blot_check_core__Op(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Node>(), error; } result.op = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Node>(), error; } result.ty = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Node>(), error; } result.a = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Node>(), error; } result.b = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Node>(), error; } result.c = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_core__Tag(writer: Writer&, value: blot_check_core::Tag, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        invalid => { put(writer, 0, 4);
},

        constant => { put(writer, 1, 4);
},

        reference => { put(writer, 2, 4);
},

        scalar => { put(writer, 3, 4);
},

        logical => { put(writer, 4, 4);
},

        call => { put(writer, 5, 4);
},

        if_value => { put(writer, 6, 4);
},

        block_ => { put(writer, 7, 4);
},

        suite => { put(writer, 8, 4);
},

        bind => { put(writer, 9, 4);
},

        return_ => { put(writer, 10, 4);
},

        if_stmt => { put(writer, 11, 4);
},

        product => { put(writer, 12, 4);
},

        record => { put(writer, 13, 4);
},

        construct => { put(writer, 14, 4);
},

        project => { put(writer, 15, 4);
},

        match_ => { put(writer, 16, 4);
},

        pattern_bind => { put(writer, 17, 4);
},

        update => { put(writer, 18, 4);
},

        array => { put(writer, 19, 4);
},

        array_op => { put(writer, 20, 4);
},

        closure => { put(writer, 21, 4);
},

        apply => { put(writer, 22, 4);
},

        constructor_function => { put(writer, 23, 4);
},

        associated => { put(writer, 24, 4);
},

        primitive_function => { put(writer, 25, 4);
},

        panic => { put(writer, 26, 4);
},

        loop_ => { put(writer, 27, 4);
},

        break_ => { put(writer, 28, 4);
},

        type_same => { put(writer, 29, 4);
},

        result_associated => { put(writer, 30, 4);
},

        type_constructor => { put(writer, 31, 4);
},

        resolver_op => { put(writer, 32, 4);
},

        operation_value => { put(writer, 33, 4);
},

        effect_provider => { put(writer, 34, 4);
},

        state_provider => { put(writer, 35, 4);
},

        handle => { put(writer, 36, 4);
},

        effect_reflection => { put(writer, 37, 4);
},

        computation => { put(writer, 38, 4);
},

        request_loop => { put(writer, 39, 4);
},

        request_decision => { put(writer, 40, 4);
},

        record_merge => { put(writer, 41, 4);
},

        contract_method => { put(writer, 42, 4);
},

        effect_scope => { put(writer, 43, 4);
},

        proof_guard => { put(writer, 44, 4);
},

        package_pack => { put(writer, 45, 4);
},

        package_unpack => { put(writer, 46, 4);
},

        staging => { put(writer, 47, 4);
},

        usage_borrow => { put(writer, 48, 4);
},

        usage_read => { put(writer, 49, 4);
},

        resource_scope => { put(writer, 50, 4);
},

        usage_share => { put(writer, 51, 4);
},

        resource_acquire => { put(writer, 52, 4);
},

        resource_release => { put(writer, 53, 4);
},

        task => { put(writer, 54, 4);
},

        storage => { put(writer, 55, 4);
},

    }
}

fn read_blot_check_core__Tag(reader: Reader&, depth: i64) -> blot_check_core::Tag, Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::Tag>(), charged; } let tag, error = get(reader, 4); if error != blot_error::Error.none { return default<blot_check_core::Tag>(), error; }
    match tag {

        0 => {
return blot_check_core::Tag.invalid, blot_error::Error.none; },

        1 => {
return blot_check_core::Tag.constant, blot_error::Error.none; },

        2 => {
return blot_check_core::Tag.reference, blot_error::Error.none; },

        3 => {
return blot_check_core::Tag.scalar, blot_error::Error.none; },

        4 => {
return blot_check_core::Tag.logical, blot_error::Error.none; },

        5 => {
return blot_check_core::Tag.call, blot_error::Error.none; },

        6 => {
return blot_check_core::Tag.if_value, blot_error::Error.none; },

        7 => {
return blot_check_core::Tag.block_, blot_error::Error.none; },

        8 => {
return blot_check_core::Tag.suite, blot_error::Error.none; },

        9 => {
return blot_check_core::Tag.bind, blot_error::Error.none; },

        10 => {
return blot_check_core::Tag.return_, blot_error::Error.none; },

        11 => {
return blot_check_core::Tag.if_stmt, blot_error::Error.none; },

        12 => {
return blot_check_core::Tag.product, blot_error::Error.none; },

        13 => {
return blot_check_core::Tag.record, blot_error::Error.none; },

        14 => {
return blot_check_core::Tag.construct, blot_error::Error.none; },

        15 => {
return blot_check_core::Tag.project, blot_error::Error.none; },

        16 => {
return blot_check_core::Tag.match_, blot_error::Error.none; },

        17 => {
return blot_check_core::Tag.pattern_bind, blot_error::Error.none; },

        18 => {
return blot_check_core::Tag.update, blot_error::Error.none; },

        19 => {
return blot_check_core::Tag.array, blot_error::Error.none; },

        20 => {
return blot_check_core::Tag.array_op, blot_error::Error.none; },

        21 => {
return blot_check_core::Tag.closure, blot_error::Error.none; },

        22 => {
return blot_check_core::Tag.apply, blot_error::Error.none; },

        23 => {
return blot_check_core::Tag.constructor_function, blot_error::Error.none; },

        24 => {
return blot_check_core::Tag.associated, blot_error::Error.none; },

        25 => {
return blot_check_core::Tag.primitive_function, blot_error::Error.none; },

        26 => {
return blot_check_core::Tag.panic, blot_error::Error.none; },

        27 => {
return blot_check_core::Tag.loop_, blot_error::Error.none; },

        28 => {
return blot_check_core::Tag.break_, blot_error::Error.none; },

        29 => {
return blot_check_core::Tag.type_same, blot_error::Error.none; },

        30 => {
return blot_check_core::Tag.result_associated, blot_error::Error.none; },

        31 => {
return blot_check_core::Tag.type_constructor, blot_error::Error.none; },

        32 => {
return blot_check_core::Tag.resolver_op, blot_error::Error.none; },

        33 => {
return blot_check_core::Tag.operation_value, blot_error::Error.none; },

        34 => {
return blot_check_core::Tag.effect_provider, blot_error::Error.none; },

        35 => {
return blot_check_core::Tag.state_provider, blot_error::Error.none; },

        36 => {
return blot_check_core::Tag.handle, blot_error::Error.none; },

        37 => {
return blot_check_core::Tag.effect_reflection, blot_error::Error.none; },

        38 => {
return blot_check_core::Tag.computation, blot_error::Error.none; },

        39 => {
return blot_check_core::Tag.request_loop, blot_error::Error.none; },

        40 => {
return blot_check_core::Tag.request_decision, blot_error::Error.none; },

        41 => {
return blot_check_core::Tag.record_merge, blot_error::Error.none; },

        42 => {
return blot_check_core::Tag.contract_method, blot_error::Error.none; },

        43 => {
return blot_check_core::Tag.effect_scope, blot_error::Error.none; },

        44 => {
return blot_check_core::Tag.proof_guard, blot_error::Error.none; },

        45 => {
return blot_check_core::Tag.package_pack, blot_error::Error.none; },

        46 => {
return blot_check_core::Tag.package_unpack, blot_error::Error.none; },

        47 => {
return blot_check_core::Tag.staging, blot_error::Error.none; },

        48 => {
return blot_check_core::Tag.usage_borrow, blot_error::Error.none; },

        49 => {
return blot_check_core::Tag.usage_read, blot_error::Error.none; },

        50 => {
return blot_check_core::Tag.resource_scope, blot_error::Error.none; },

        51 => {
return blot_check_core::Tag.usage_share, blot_error::Error.none; },

        52 => {
return blot_check_core::Tag.resource_acquire, blot_error::Error.none; },

        53 => {
return blot_check_core::Tag.resource_release, blot_error::Error.none; },

        54 => {
return blot_check_core::Tag.task, blot_error::Error.none; },

        55 => {
return blot_check_core::Tag.storage, blot_error::Error.none; },

        _ => { return default<blot_check_core::Tag>(), blot_error::Error.invalid_artifact; },
    }
}

fn write_blot_check_core__Op(writer: Writer&, value: blot_check_core::Op, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        none => { put(writer, 0, 4);
},

        add => { put(writer, 1, 4);
},

        sub => { put(writer, 2, 4);
},

        mul => { put(writer, 3, 4);
},

        div => { put(writer, 4, 4);
},

        rem => { put(writer, 5, 4);
},

        equal => { put(writer, 6, 4);
},

        not_equal => { put(writer, 7, 4);
},

        less => { put(writer, 8, 4);
},

        less_equal => { put(writer, 9, 4);
},

        greater => { put(writer, 10, 4);
},

        greater_equal => { put(writer, 11, 4);
},

        bit_and => { put(writer, 12, 4);
},

        bit_or => { put(writer, 13, 4);
},

        bit_xor => { put(writer, 14, 4);
},

        shift_left => { put(writer, 15, 4);
},

        shift_right => { put(writer, 16, 4);
},

        and_ => { put(writer, 17, 4);
},

        or_ => { put(writer, 18, 4);
},

        neg => { put(writer, 19, 4);
},

        abs => { put(writer, 20, 4);
},

        ceil => { put(writer, 21, 4);
},

        floor => { put(writer, 22, 4);
},

        trunc => { put(writer, 23, 4);
},

        sqrt => { put(writer, 24, 4);
},

        convert_u32_f32 => { put(writer, 25, 4);
},

        convert_f32_u32 => { put(writer, 26, 4);
},

        shift_right_signed => { put(writer, 27, 4);
},

        min => { put(writer, 28, 4);
},

        max => { put(writer, 29, 4);
},

        bit_not => { put(writer, 30, 4);
},

        bit_andnot => { put(writer, 31, 4);
},

        any_true => { put(writer, 32, 4);
},

        all_true => { put(writer, 33, 4);
},

        select => { put(writer, 34, 4);
},

        shuffle => { put(writer, 35, 4);
},

        swizzle => { put(writer, 36, 4);
},

        broadcast => { put(writer, 37, 4);
},

        bits => { put(writer, 38, 4);
},

        from_bits => { put(writer, 39, 4);
},

        relaxed_madd => { put(writer, 40, 4);
},

        relaxed_nmadd => { put(writer, 41, 4);
},

        convert_i32_f32 => { put(writer, 42, 4);
},

        convert_f32_i32 => { put(writer, 43, 4);
},

        continue_ => { put(writer, 44, 4);
},

    }
}

fn read_blot_check_core__Op(reader: Reader&, depth: i64) -> blot_check_core::Op, Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::Op>(), charged; } let tag, error = get(reader, 4); if error != blot_error::Error.none { return default<blot_check_core::Op>(), error; }
    match tag {

        0 => {
return blot_check_core::Op.none, blot_error::Error.none; },

        1 => {
return blot_check_core::Op.add, blot_error::Error.none; },

        2 => {
return blot_check_core::Op.sub, blot_error::Error.none; },

        3 => {
return blot_check_core::Op.mul, blot_error::Error.none; },

        4 => {
return blot_check_core::Op.div, blot_error::Error.none; },

        5 => {
return blot_check_core::Op.rem, blot_error::Error.none; },

        6 => {
return blot_check_core::Op.equal, blot_error::Error.none; },

        7 => {
return blot_check_core::Op.not_equal, blot_error::Error.none; },

        8 => {
return blot_check_core::Op.less, blot_error::Error.none; },

        9 => {
return blot_check_core::Op.less_equal, blot_error::Error.none; },

        10 => {
return blot_check_core::Op.greater, blot_error::Error.none; },

        11 => {
return blot_check_core::Op.greater_equal, blot_error::Error.none; },

        12 => {
return blot_check_core::Op.bit_and, blot_error::Error.none; },

        13 => {
return blot_check_core::Op.bit_or, blot_error::Error.none; },

        14 => {
return blot_check_core::Op.bit_xor, blot_error::Error.none; },

        15 => {
return blot_check_core::Op.shift_left, blot_error::Error.none; },

        16 => {
return blot_check_core::Op.shift_right, blot_error::Error.none; },

        17 => {
return blot_check_core::Op.and_, blot_error::Error.none; },

        18 => {
return blot_check_core::Op.or_, blot_error::Error.none; },

        19 => {
return blot_check_core::Op.neg, blot_error::Error.none; },

        20 => {
return blot_check_core::Op.abs, blot_error::Error.none; },

        21 => {
return blot_check_core::Op.ceil, blot_error::Error.none; },

        22 => {
return blot_check_core::Op.floor, blot_error::Error.none; },

        23 => {
return blot_check_core::Op.trunc, blot_error::Error.none; },

        24 => {
return blot_check_core::Op.sqrt, blot_error::Error.none; },

        25 => {
return blot_check_core::Op.convert_u32_f32, blot_error::Error.none; },

        26 => {
return blot_check_core::Op.convert_f32_u32, blot_error::Error.none; },

        27 => {
return blot_check_core::Op.shift_right_signed, blot_error::Error.none; },

        28 => {
return blot_check_core::Op.min, blot_error::Error.none; },

        29 => {
return blot_check_core::Op.max, blot_error::Error.none; },

        30 => {
return blot_check_core::Op.bit_not, blot_error::Error.none; },

        31 => {
return blot_check_core::Op.bit_andnot, blot_error::Error.none; },

        32 => {
return blot_check_core::Op.any_true, blot_error::Error.none; },

        33 => {
return blot_check_core::Op.all_true, blot_error::Error.none; },

        34 => {
return blot_check_core::Op.select, blot_error::Error.none; },

        35 => {
return blot_check_core::Op.shuffle, blot_error::Error.none; },

        36 => {
return blot_check_core::Op.swizzle, blot_error::Error.none; },

        37 => {
return blot_check_core::Op.broadcast, blot_error::Error.none; },

        38 => {
return blot_check_core::Op.bits, blot_error::Error.none; },

        39 => {
return blot_check_core::Op.from_bits, blot_error::Error.none; },

        40 => {
return blot_check_core::Op.relaxed_madd, blot_error::Error.none; },

        41 => {
return blot_check_core::Op.relaxed_nmadd, blot_error::Error.none; },

        42 => {
return blot_check_core::Op.convert_i32_f32, blot_error::Error.none; },

        43 => {
return blot_check_core::Op.convert_f32_i32, blot_error::Error.none; },

        44 => {
return blot_check_core::Op.continue_, blot_error::Error.none; },

        _ => { return default<blot_check_core::Op>(), blot_error::Error.invalid_artifact; },
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
    var result = default<blot_check_core::Binding>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_capability_flow__Contract(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Binding>(), error; } result.capability_flow = decoded; }

    { let decoded, error = read_blot_check_capability_flow__Parameters(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Binding>(), error; } result.capability_parameters = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Binding>(), error; } result.private = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Binding>(), error; } result.initializer = decoded; }

    { let decoded, error = read_blot_reuse_principal_interface__Kind(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Binding>(), error; } result.kind = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Binding>(), error; } result.ty = decoded; }

    { let decoded, error = read_blot_check_types__Scheme(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Binding>(), error; } result.scheme = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Binding>(), error; } result.public_variables = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Binding>(), error; } result.public_rows = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Binding>(), error; } result.has_explicit = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Binding>(), error; } result.body_id = decoded; }

    { let decoded, error = read_blot_check_core__BindingRef(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Binding>(), error; } result.target = decoded; }

    { let decoded, error = read_blot_parse_ast__Span(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Binding>(), error; } result.span = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_capability_flow__Contract(writer: Writer&, value: blot_check_capability_flow::Contract, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        unknown => { put(writer, 0, 4);
},

        identity => { put(writer, 1, 4);
},

        invoke_unit => { put(writer, 2, 4);
},

        member_unit => { put(writer, 3, 4);
},

        invoke_with_capability => { put(writer, 4, 4);
},

        member_first_unit => { put(writer, 5, 4);
},

        member_second_unit => { put(writer, 6, 4);
},

        input_shape => { put(writer, 7, 4);
},

        consume_task => { put(writer, 8, 4);
},

        scope_task => { put(writer, 9, 4);
},

        spawn_task => { put(writer, 10, 4);
},

    }
}

fn read_blot_check_capability_flow__Contract(reader: Reader&, depth: i64) -> blot_check_capability_flow::Contract, Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_capability_flow::Contract>(), charged; } let tag, error = get(reader, 4); if error != blot_error::Error.none { return default<blot_check_capability_flow::Contract>(), error; }
    match tag {

        0 => {
return blot_check_capability_flow::Contract.unknown, blot_error::Error.none; },

        1 => {
return blot_check_capability_flow::Contract.identity, blot_error::Error.none; },

        2 => {
return blot_check_capability_flow::Contract.invoke_unit, blot_error::Error.none; },

        3 => {
return blot_check_capability_flow::Contract.member_unit, blot_error::Error.none; },

        4 => {
return blot_check_capability_flow::Contract.invoke_with_capability, blot_error::Error.none; },

        5 => {
return blot_check_capability_flow::Contract.member_first_unit, blot_error::Error.none; },

        6 => {
return blot_check_capability_flow::Contract.member_second_unit, blot_error::Error.none; },

        7 => {
return blot_check_capability_flow::Contract.input_shape, blot_error::Error.none; },

        8 => {
return blot_check_capability_flow::Contract.consume_task, blot_error::Error.none; },

        9 => {
return blot_check_capability_flow::Contract.scope_task, blot_error::Error.none; },

        10 => {
return blot_check_capability_flow::Contract.spawn_task, blot_error::Error.none; },

        _ => { return default<blot_check_capability_flow::Contract>(), blot_error::Error.invalid_artifact; },
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
    var result = default<blot_check_capability_flow::Parameters>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_capability_flow__ParameterResult(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_capability_flow::Parameters>(), error; } result.kind = decoded; }

    { let decoded, error = read_u16(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_capability_flow::Parameters>(), error; } result.mask = decoded; }

    { let decoded, error = read_u8(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_capability_flow::Parameters>(), error; } result.inputs = decoded; }

    { let decoded, error = read_u64(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_capability_flow::Parameters>(), error; } result.invocation_arguments = decoded; }

    { let decoded, error = read_u8(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_capability_flow::Parameters>(), error; } result.invocation_count = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_capability_flow__ParameterResult(writer: Writer&, value: blot_check_capability_flow::ParameterResult, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        product => { put(writer, 0, 4);
},

        invoke_unit => { put(writer, 1, 4);
},

        invalid => { put(writer, 2, 4);
},

        member_closure_unit => { put(writer, 3, 4);
},

        captured_unit => { put(writer, 4, 4);
},

        invoke_input => { put(writer, 5, 4);
},

        invoke_inputs => { put(writer, 6, 4);
},

    }
}

fn read_blot_check_capability_flow__ParameterResult(reader: Reader&, depth: i64) -> blot_check_capability_flow::ParameterResult, Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_capability_flow::ParameterResult>(), charged; } let tag, error = get(reader, 4); if error != blot_error::Error.none { return default<blot_check_capability_flow::ParameterResult>(), error; }
    match tag {

        0 => {
return blot_check_capability_flow::ParameterResult.product, blot_error::Error.none; },

        1 => {
return blot_check_capability_flow::ParameterResult.invoke_unit, blot_error::Error.none; },

        2 => {
return blot_check_capability_flow::ParameterResult.invalid, blot_error::Error.none; },

        3 => {
return blot_check_capability_flow::ParameterResult.member_closure_unit, blot_error::Error.none; },

        4 => {
return blot_check_capability_flow::ParameterResult.captured_unit, blot_error::Error.none; },

        5 => {
return blot_check_capability_flow::ParameterResult.invoke_input, blot_error::Error.none; },

        6 => {
return blot_check_capability_flow::ParameterResult.invoke_inputs, blot_error::Error.none; },

        _ => { return default<blot_check_capability_flow::ParameterResult>(), blot_error::Error.invalid_artifact; },
    }
}

fn write_blot_reuse_principal_interface__Kind(writer: Writer&, value: blot_reuse_principal_interface::Kind, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        global => { put(writer, 0, 4);
},

        local => { put(writer, 1, 4);
},

        parameter => { put(writer, 2, 4);
},

        external => { put(writer, 3, 4);
},

    }
}

fn read_blot_reuse_principal_interface__Kind(reader: Reader&, depth: i64) -> blot_reuse_principal_interface::Kind, Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_reuse_principal_interface::Kind>(), charged; } let tag, error = get(reader, 4); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::Kind>(), error; }
    match tag {

        0 => {
return blot_reuse_principal_interface::Kind.global, blot_error::Error.none; },

        1 => {
return blot_reuse_principal_interface::Kind.local, blot_error::Error.none; },

        2 => {
return blot_reuse_principal_interface::Kind.parameter, blot_error::Error.none; },

        3 => {
return blot_reuse_principal_interface::Kind.external, blot_error::Error.none; },

        _ => { return default<blot_reuse_principal_interface::Kind>(), blot_error::Error.invalid_artifact; },
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
    var result = default<blot_check_types::Scheme>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::Scheme>(), error; } result.root = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::Scheme>(), error; } result.variables = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::Scheme>(), error; } result.row_variables = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::Scheme>(), error; } result.closed_rows = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::Scheme>(), error; } result.obligations = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::Scheme>(), error; } result.generative = decoded; }

    return result, blot_error::Error.none;
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
    var result = default<blot_check_core::Body>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Body>(), error; } result.binding = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Body>(), error; } result.root = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Body>(), error; } result.parameters = decoded; }

    { let decoded, error = read_blot_check_types__Scheme(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Body>(), error; } result.scheme = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Body>(), error; } result.closed_rows = decoded; }

    { let decoded, error = read_blot_parse_ast__Span(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Body>(), error; } result.span = decoded; }

    { let decoded, error = read_blot_check_core__Name(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Body>(), error; } result.declaration_name = decoded; }

    { let decoded, error = read_blot_check_core__Name(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Body>(), error; } result.export_name = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Body>(), error; } result.exported = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Body>(), error; } result.runtime = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Body>(), error; } result.is_function = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_core__Parameter(writer: Writer&, value: blot_check_core::Parameter, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.binding, depth + 1);

    write_u32(writer, value.ty, depth + 1);

    write_blot_parse_ast__Span(writer, value.span, depth + 1);

    write_bool(writer, value.inferred, depth + 1);

}

fn read_blot_check_core__Parameter(reader: Reader&, depth: i64) -> blot_check_core::Parameter, Error {
    var result = default<blot_check_core::Parameter>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Parameter>(), error; } result.binding = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Parameter>(), error; } result.ty = decoded; }

    { let decoded, error = read_blot_parse_ast__Span(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Parameter>(), error; } result.span = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Parameter>(), error; } result.inferred = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_core__CallInfo(writer: Writer&, value: blot_check_core::CallInfo, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_core__BindingRef(writer, value.target, depth + 1);

    write_u32(writer, value.callee_type, depth + 1);

}

fn read_blot_check_core__CallInfo(reader: Reader&, depth: i64) -> blot_check_core::CallInfo, Error {
    var result = default<blot_check_core::CallInfo>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_core__BindingRef(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::CallInfo>(), error; } result.target = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::CallInfo>(), error; } result.callee_type = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_core__Merge(writer: Writer&, value: blot_check_core::Merge, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.node, depth + 1);

    write_u32(writer, value.result, depth + 1);

    write_u32(writer, value.then_binding, depth + 1);

    write_u32(writer, value.else_binding, depth + 1);

}

fn read_blot_check_core__Merge(reader: Reader&, depth: i64) -> blot_check_core::Merge, Error {
    var result = default<blot_check_core::Merge>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Merge>(), error; } result.node = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Merge>(), error; } result.result = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Merge>(), error; } result.then_binding = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Merge>(), error; } result.else_binding = decoded; }

    return result, blot_error::Error.none;
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
    var result = default<blot_check_core::Obligation>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Obligation>(), error; } result.ty = decoded; }

    { let decoded, error = read_blot_check_types__ObligationKind(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Obligation>(), error; } result.kind = decoded; }

    { let decoded, error = read_blot_parse_ast__Span(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Obligation>(), error; } result.span = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Obligation>(), error; } result.name = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Obligation>(), error; } result.result = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Obligation>(), error; } result.other = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Obligation>(), error; } result.signature = decoded; }

    { let decoded, error = read_blot_check_types__Operator(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Obligation>(), error; } result.operator = decoded; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Obligation>(), error; } result.identity = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Obligation>(), error; } result.explicit = decoded; }

    { let decoded, error = read_blot_support__Option_blot_parse_ast__Span_(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Obligation>(), error; } result.qualification_span = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Obligation>(), error; } result.qualification_unit = decoded; }

    { let decoded, error = read_blot_check_core__Name(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Obligation>(), error; } result.diagnostic_name = decoded; }

    return result, blot_error::Error.none;
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
    var result = default<blot_check_core::Nominal>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_bool(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Nominal>(), error; } result.affine = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Nominal>(), error; } result.has_usage = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Nominal>(), error; } result.closed_storage = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Nominal>(), error; } result.private = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Nominal>(), error; } result.is_opaque = decoded; }

    { let decoded, error = read_blot_backend_opaque_storage__Storage(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Nominal>(), error; } result.storage = decoded; }

    { let decoded, error = read_blot_check_core__Name(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Nominal>(), error; } result.diagnostic_name = decoded; }

    { let decoded, error = read_blot_check_core__Name(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Nominal>(), error; } result.diagnostic_origin = decoded; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Nominal>(), error; } result.identity = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Nominal>(), error; } result.parameters = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Nominal>(), error; } result.variables = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Nominal>(), error; } result.constructors = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_backend_opaque_storage__Storage(writer: Writer&, value: blot_backend_opaque_storage::Storage, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_backend_opaque_storage__Kind(writer, value.kind, depth + 1);

    write_u32(writer, value.parameter, depth + 1);

    write_u32(writer, value.selector, depth + 1);

}

fn read_blot_backend_opaque_storage__Storage(reader: Reader&, depth: i64) -> blot_backend_opaque_storage::Storage, Error {
    var result = default<blot_backend_opaque_storage::Storage>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_backend_opaque_storage__Kind(reader, depth + 1); if error != blot_error::Error.none { return default<blot_backend_opaque_storage::Storage>(), error; } result.kind = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_backend_opaque_storage::Storage>(), error; } result.parameter = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_backend_opaque_storage::Storage>(), error; } result.selector = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_backend_opaque_storage__Kind(writer: Writer&, value: blot_backend_opaque_storage::Kind, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        unknown => { put(writer, 0, 4);
},

        unit => { put(writer, 1, 4);
},

        boolean => { put(writer, 2, 4);
},

        unsigned32 => { put(writer, 3, 4);
},

        floating32 => { put(writer, 4, 4);
},

        reference => { put(writer, 5, 4);
},

        parameter => { put(writer, 6, 4);
},

    }
}

fn read_blot_backend_opaque_storage__Kind(reader: Reader&, depth: i64) -> blot_backend_opaque_storage::Kind, Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_backend_opaque_storage::Kind>(), charged; } let tag, error = get(reader, 4); if error != blot_error::Error.none { return default<blot_backend_opaque_storage::Kind>(), error; }
    match tag {

        0 => {
return blot_backend_opaque_storage::Kind.unknown, blot_error::Error.none; },

        1 => {
return blot_backend_opaque_storage::Kind.unit, blot_error::Error.none; },

        2 => {
return blot_backend_opaque_storage::Kind.boolean, blot_error::Error.none; },

        3 => {
return blot_backend_opaque_storage::Kind.unsigned32, blot_error::Error.none; },

        4 => {
return blot_backend_opaque_storage::Kind.floating32, blot_error::Error.none; },

        5 => {
return blot_backend_opaque_storage::Kind.reference, blot_error::Error.none; },

        6 => {
return blot_backend_opaque_storage::Kind.parameter, blot_error::Error.none; },

        _ => { return default<blot_backend_opaque_storage::Kind>(), blot_error::Error.invalid_artifact; },
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
    var result = default<blot_check_core::OperationName>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::OperationName>(), error; } result.identity = decoded; }

    { let decoded, error = read_blot_check_core__Name(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::OperationName>(), error; } result.diagnostic_name = decoded; }

    { let decoded, error = read_blot_check_core__Name(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::OperationName>(), error; } result.diagnostic_origin = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::OperationName>(), error; } result.variables = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::OperationName>(), error; } result.parameters = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::OperationName>(), error; } result.parameter = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::OperationName>(), error; } result.result = decoded; }

    return result, blot_error::Error.none;
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
    var result = default<blot_check_core::Constructor>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Constructor>(), error; } result.identity = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Constructor>(), error; } result.nominal = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Constructor>(), error; } result.tag = decoded; }

    { let decoded, error = read_blot_check_types__Scheme(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Constructor>(), error; } result.scheme = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Constructor>(), error; } result.payload = decoded; }

    return result, blot_error::Error.none;
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
    var result = default<blot_check_core::Projection>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Projection>(), error; } result.nominal = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Projection>(), error; } result.field = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Projection>(), error; } result.source_type = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Projection>(), error; } result.result_type = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Projection>(), error; } result.variants = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Projection>(), error; } result.diagnostic_point = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_core__ProjectionVariant(writer: Writer&, value: blot_check_core::ProjectionVariant, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.tag, depth + 1);

    write_u32(writer, value.field, depth + 1);

}

fn read_blot_check_core__ProjectionVariant(reader: Reader&, depth: i64) -> blot_check_core::ProjectionVariant, Error {
    var result = default<blot_check_core::ProjectionVariant>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::ProjectionVariant>(), error; } result.tag = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::ProjectionVariant>(), error; } result.field = decoded; }

    return result, blot_error::Error.none;
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
    var result = default<blot_check_core::Pattern>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_core__PatternTag(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Pattern>(), error; } result.tag = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Pattern>(), error; } result.ty = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Pattern>(), error; } result.a = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Pattern>(), error; } result.b = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Pattern>(), error; } result.c = decoded; }

    { let decoded, error = read_blot_parse_ast__Span(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Pattern>(), error; } result.span = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_core__PatternTag(writer: Writer&, value: blot_check_core::PatternTag, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        invalid => { put(writer, 0, 4);
},

        wildcard => { put(writer, 1, 4);
},

        bind => { put(writer, 2, 4);
},

        constant => { put(writer, 3, 4);
},

        value => { put(writer, 4, 4);
},

        product => { put(writer, 5, 4);
},

        constructor => { put(writer, 6, 4);
},

        record_payload => { put(writer, 7, 4);
},

    }
}

fn read_blot_check_core__PatternTag(reader: Reader&, depth: i64) -> blot_check_core::PatternTag, Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::PatternTag>(), charged; } let tag, error = get(reader, 4); if error != blot_error::Error.none { return default<blot_check_core::PatternTag>(), error; }
    match tag {

        0 => {
return blot_check_core::PatternTag.invalid, blot_error::Error.none; },

        1 => {
return blot_check_core::PatternTag.wildcard, blot_error::Error.none; },

        2 => {
return blot_check_core::PatternTag.bind, blot_error::Error.none; },

        3 => {
return blot_check_core::PatternTag.constant, blot_error::Error.none; },

        4 => {
return blot_check_core::PatternTag.value, blot_error::Error.none; },

        5 => {
return blot_check_core::PatternTag.product, blot_error::Error.none; },

        6 => {
return blot_check_core::PatternTag.constructor, blot_error::Error.none; },

        7 => {
return blot_check_core::PatternTag.record_payload, blot_error::Error.none; },

        _ => { return default<blot_check_core::PatternTag>(), blot_error::Error.invalid_artifact; },
    }
}

fn write_blot_check_core__PatternRow(writer: Writer&, value: blot_check_core::PatternRow, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_core__List(writer, value.patterns, depth + 1);

}

fn read_blot_check_core__PatternRow(reader: Reader&, depth: i64) -> blot_check_core::PatternRow, Error {
    var result = default<blot_check_core::PatternRow>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::PatternRow>(), error; } result.patterns = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_core__MatchArm(writer: Writer&, value: blot_check_core::MatchArm, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_core__List(writer, value.rows, depth + 1);

    write_u32(writer, value.guard_, depth + 1);

    write_u32(writer, value.body, depth + 1);

    write_blot_parse_ast__Span(writer, value.span, depth + 1);

}

fn read_blot_check_core__MatchArm(reader: Reader&, depth: i64) -> blot_check_core::MatchArm, Error {
    var result = default<blot_check_core::MatchArm>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::MatchArm>(), error; } result.rows = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::MatchArm>(), error; } result.guard_ = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::MatchArm>(), error; } result.body = decoded; }

    { let decoded, error = read_blot_parse_ast__Span(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::MatchArm>(), error; } result.span = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_core__MatchInfo(writer: Writer&, value: blot_check_core::MatchInfo, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_core__List(writer, value.inputs, depth + 1);

    write_blot_check_core__List(writer, value.arms, depth + 1);

    write_bool(writer, value.statement, depth + 1);

}

fn read_blot_check_core__MatchInfo(reader: Reader&, depth: i64) -> blot_check_core::MatchInfo, Error {
    var result = default<blot_check_core::MatchInfo>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::MatchInfo>(), error; } result.inputs = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::MatchInfo>(), error; } result.arms = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::MatchInfo>(), error; } result.statement = decoded; }

    return result, blot_error::Error.none;
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
    var result = default<blot_check_core::UpdateInfo>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::UpdateInfo>(), error; } result.root = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::UpdateInfo>(), error; } result.path = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::UpdateInfo>(), error; } result.value = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::UpdateInfo>(), error; } result.self_binding = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::UpdateInfo>(), error; } result.selectors = decoded; }

    return result, blot_error::Error.none;
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
    var result = default<blot_check_core::UpdateStep>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_core__UpdateKind(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::UpdateStep>(), error; } result.kind = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::UpdateStep>(), error; } result.projection = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::UpdateStep>(), error; } result.index = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::UpdateStep>(), error; } result.source_type = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::UpdateStep>(), error; } result.result_type = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_core__UpdateKind(writer: Writer&, value: blot_check_core::UpdateKind, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        field => { put(writer, 0, 4);
},

        index => { put(writer, 1, 4);
},

    }
}

fn read_blot_check_core__UpdateKind(reader: Reader&, depth: i64) -> blot_check_core::UpdateKind, Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::UpdateKind>(), charged; } let tag, error = get(reader, 4); if error != blot_error::Error.none { return default<blot_check_core::UpdateKind>(), error; }
    match tag {

        0 => {
return blot_check_core::UpdateKind.field, blot_error::Error.none; },

        1 => {
return blot_check_core::UpdateKind.index, blot_error::Error.none; },

        _ => { return default<blot_check_core::UpdateKind>(), blot_error::Error.invalid_artifact; },
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
    var result = default<blot_check_core::ClosureInfo>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::ClosureInfo>(), error; } result.qualifier = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::ClosureInfo>(), error; } result.body = decoded; }

    { let decoded, error = read_blot_check_core__Parameter(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::ClosureInfo>(), error; } result.parameter = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::ClosureInfo>(), error; } result.captures = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::ClosureInfo>(), error; } result.function_type = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::ClosureInfo>(), error; } result.closed_rows = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_core__Associated(writer: Writer&, value: blot_check_core::Associated, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_types__NominalIdentity(writer, value.identity, depth + 1);

    write_u32(writer, value.member, depth + 1);

    write_blot_check_types__Operator(writer, value.operator, depth + 1);

    write_blot_check_core__BindingRef(writer, value.target, depth + 1);

}

fn read_blot_check_core__Associated(reader: Reader&, depth: i64) -> blot_check_core::Associated, Error {
    var result = default<blot_check_core::Associated>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Associated>(), error; } result.identity = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Associated>(), error; } result.member = decoded; }

    { let decoded, error = read_blot_check_types__Operator(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Associated>(), error; } result.operator = decoded; }

    { let decoded, error = read_blot_check_core__BindingRef(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Associated>(), error; } result.target = decoded; }

    return result, blot_error::Error.none;
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
    var result = default<blot_check_core::Contract>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_bool(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Contract>(), error; } result.private = decoded; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Contract>(), error; } result.identity = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Contract>(), error; } result.name = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Contract>(), error; } result.parameters = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Contract>(), error; } result.variables = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Contract>(), error; } result.row_variables = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Contract>(), error; } result.predicates = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Contract>(), error; } result.members = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Contract>(), error; } result.requires_implementation = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Contract>(), error; } result.row_parameter_names = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Contract>(), error; } result.row_parameters = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_reuse_principal_interface__ContractMember(writer: Writer&, value: blot_reuse_principal_interface::ContractMember, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_types__NominalIdentity(writer, value.contract, depth + 1);

    write_u32(writer, value.name, depth + 1);

    write_blot_reuse_principal_interface__ContractMemberKind(writer, value.kind, depth + 1);

    write_u32(writer, value.root, depth + 1);

}

fn read_blot_reuse_principal_interface__ContractMember(reader: Reader&, depth: i64) -> blot_reuse_principal_interface::ContractMember, Error {
    var result = default<blot_reuse_principal_interface::ContractMember>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::ContractMember>(), error; } result.contract = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::ContractMember>(), error; } result.name = decoded; }

    { let decoded, error = read_blot_reuse_principal_interface__ContractMemberKind(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::ContractMember>(), error; } result.kind = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::ContractMember>(), error; } result.root = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_reuse_principal_interface__ContractMemberKind(writer: Writer&, value: blot_reuse_principal_interface::ContractMemberKind, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        defined_type => { put(writer, 0, 4);
},

        abstract_type => { put(writer, 1, 4);
},

        value => { put(writer, 2, 4);
},

    }
}

fn read_blot_reuse_principal_interface__ContractMemberKind(reader: Reader&, depth: i64) -> blot_reuse_principal_interface::ContractMemberKind, Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_reuse_principal_interface::ContractMemberKind>(), charged; } let tag, error = get(reader, 4); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::ContractMemberKind>(), error; }
    match tag {

        0 => {
return blot_reuse_principal_interface::ContractMemberKind.defined_type, blot_error::Error.none; },

        1 => {
return blot_reuse_principal_interface::ContractMemberKind.abstract_type, blot_error::Error.none; },

        2 => {
return blot_reuse_principal_interface::ContractMemberKind.value, blot_error::Error.none; },

        _ => { return default<blot_reuse_principal_interface::ContractMemberKind>(), blot_error::Error.invalid_artifact; },
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
    var result = default<blot_reuse_principal_interface::Implementation>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_support__Option_blot_parse_ast__Span_(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::Implementation>(), error; } result.origin_span = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::Implementation>(), error; } result.declaration = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::Implementation>(), error; } result.private = decoded; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::Implementation>(), error; } result.identity = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::Implementation>(), error; } result.name = decoded; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::Implementation>(), error; } result.contract = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::Implementation>(), error; } result.head = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::Implementation>(), error; } result.variables = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::Implementation>(), error; } result.parameter_names = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::Implementation>(), error; } result.row_variables = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::Implementation>(), error; } result.row_parameter_names = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::Implementation>(), error; } result.row_parameters = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::Implementation>(), error; } result.predicates = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::Implementation>(), error; } result.members = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_reuse_principal_interface__ImplementationMember(writer: Writer&, value: blot_reuse_principal_interface::ImplementationMember, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.name, depth + 1);

    write_blot_reuse_principal_interface__ImplementationMemberKind(writer, value.kind, depth + 1);

    write_u32(writer, value.root, depth + 1);

    write_blot_reuse_principal_interface__ExternalTarget(writer, value.target, depth + 1);

}

fn read_blot_reuse_principal_interface__ImplementationMember(reader: Reader&, depth: i64) -> blot_reuse_principal_interface::ImplementationMember, Error {
    var result = default<blot_reuse_principal_interface::ImplementationMember>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::ImplementationMember>(), error; } result.name = decoded; }

    { let decoded, error = read_blot_reuse_principal_interface__ImplementationMemberKind(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::ImplementationMember>(), error; } result.kind = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::ImplementationMember>(), error; } result.root = decoded; }

    { let decoded, error = read_blot_reuse_principal_interface__ExternalTarget(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::ImplementationMember>(), error; } result.target = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_reuse_principal_interface__ImplementationMemberKind(writer: Writer&, value: blot_reuse_principal_interface::ImplementationMemberKind, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        type_ => { put(writer, 0, 4);
},

        value => { put(writer, 1, 4);
},

    }
}

fn read_blot_reuse_principal_interface__ImplementationMemberKind(reader: Reader&, depth: i64) -> blot_reuse_principal_interface::ImplementationMemberKind, Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_reuse_principal_interface::ImplementationMemberKind>(), charged; } let tag, error = get(reader, 4); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::ImplementationMemberKind>(), error; }
    match tag {

        0 => {
return blot_reuse_principal_interface::ImplementationMemberKind.type_, blot_error::Error.none; },

        1 => {
return blot_reuse_principal_interface::ImplementationMemberKind.value, blot_error::Error.none; },

        _ => { return default<blot_reuse_principal_interface::ImplementationMemberKind>(), blot_error::Error.invalid_artifact; },
    }
}

fn write_blot_reuse_principal_interface__ExternalTarget(writer: Writer&, value: blot_reuse_principal_interface::ExternalTarget, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.unit, depth + 1);

    write_u32(writer, value.binding, depth + 1);

}

fn read_blot_reuse_principal_interface__ExternalTarget(reader: Reader&, depth: i64) -> blot_reuse_principal_interface::ExternalTarget, Error {
    var result = default<blot_reuse_principal_interface::ExternalTarget>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::ExternalTarget>(), error; } result.unit = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::ExternalTarget>(), error; } result.binding = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_reuse_principal_interface__MemberTemplate(writer: Writer&, value: blot_reuse_principal_interface::MemberTemplate, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.binding, depth + 1);

    write_blot_check_types__NominalIdentity(writer, value.contract, depth + 1);

    write_u32(writer, value.name, depth + 1);

    write_blot_check_types__List(writer, value.arguments, depth + 1);

}

fn read_blot_reuse_principal_interface__MemberTemplate(reader: Reader&, depth: i64) -> blot_reuse_principal_interface::MemberTemplate, Error {
    var result = default<blot_reuse_principal_interface::MemberTemplate>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::MemberTemplate>(), error; } result.binding = decoded; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::MemberTemplate>(), error; } result.contract = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::MemberTemplate>(), error; } result.name = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::MemberTemplate>(), error; } result.arguments = decoded; }

    return result, blot_error::Error.none;
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
    var result = default<blot_reuse_principal_interface::SelectedProof>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_reuse_principal_interface__ExternalTarget(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::SelectedProof>(), error; } result.predicate_target = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::SelectedProof>(), error; } result.context = decoded; }

    { let decoded, error = read_blot_reuse_principal_interface__SelectedProofKind(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::SelectedProof>(), error; } result.kind = decoded; }

    { let decoded, error = read_blot_check_types__Obligation(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::SelectedProof>(), error; } result.predicate = decoded; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::SelectedProof>(), error; } result.implementation = decoded; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::SelectedProof>(), error; } result.contract = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::SelectedProof>(), error; } result.arguments = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::SelectedProof>(), error; } result.members = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::SelectedProof>(), error; } result.prerequisites = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_reuse_principal_interface__SelectedProofKind(writer: Writer&, value: blot_reuse_principal_interface::SelectedProofKind, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        implementation => { put(writer, 0, 4);
},

        predicate => { put(writer, 1, 4);
},

    }
}

fn read_blot_reuse_principal_interface__SelectedProofKind(reader: Reader&, depth: i64) -> blot_reuse_principal_interface::SelectedProofKind, Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_reuse_principal_interface::SelectedProofKind>(), charged; } let tag, error = get(reader, 4); if error != blot_error::Error.none { return default<blot_reuse_principal_interface::SelectedProofKind>(), error; }
    match tag {

        0 => {
return blot_reuse_principal_interface::SelectedProofKind.implementation, blot_error::Error.none; },

        1 => {
return blot_reuse_principal_interface::SelectedProofKind.predicate, blot_error::Error.none; },

        _ => { return default<blot_reuse_principal_interface::SelectedProofKind>(), blot_error::Error.invalid_artifact; },
    }
}

fn write_blot_check_core__SelectedUse(writer: Writer&, value: blot_check_core::SelectedUse, depth: i64) {
    if !charge(writer, depth) { return; }

    write_u32(writer, value.node, depth + 1);

    write_u32(writer, value.proof, depth + 1);

}

fn read_blot_check_core__SelectedUse(reader: Reader&, depth: i64) -> blot_check_core::SelectedUse, Error {
    var result = default<blot_check_core::SelectedUse>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::SelectedUse>(), error; } result.node = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::SelectedUse>(), error; } result.proof = decoded; }

    return result, blot_error::Error.none;
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
    var result = default<blot_check_core::DictionarySelection>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::DictionarySelection>(), error; } result.owner = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::DictionarySelection>(), error; } result.quantifier = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::DictionarySelection>(), error; } result.goal = decoded; }

    { let decoded, error = read_blot_check_core__DictionaryProof(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::DictionarySelection>(), error; } result.proof = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::DictionarySelection>(), error; } result.members = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::DictionarySelection>(), error; } result.contents = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_core__DictionaryProof(writer: Writer&, value: blot_check_core::DictionaryProof, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        selected payload => { put(writer, 0, 4);
write_u32(writer, payload.value, depth + 1);
},

        given payload => { put(writer, 1, 4);
write_blot_check_core__DictionaryGiven(writer, payload.value, depth + 1);
},

    }
}

fn read_blot_check_core__DictionaryProof(reader: Reader&, depth: i64) -> blot_check_core::DictionaryProof, Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::DictionaryProof>(), charged; } let tag, error = get(reader, 4); if error != blot_error::Error.none { return default<blot_check_core::DictionaryProof>(), error; }
    match tag {

        0 => {
let value, failure_value = read_u32(reader, depth + 1); if failure_value != blot_error::Error.none { return default<blot_check_core::DictionaryProof>(), failure_value; }
return blot_check_core::DictionaryProof.selected { value: value , ..}, blot_error::Error.none; },

        1 => {
let value, failure_value = read_blot_check_core__DictionaryGiven(reader, depth + 1); if failure_value != blot_error::Error.none { return default<blot_check_core::DictionaryProof>(), failure_value; }
return blot_check_core::DictionaryProof.given { value: value , ..}, blot_error::Error.none; },

        _ => { return default<blot_check_core::DictionaryProof>(), blot_error::Error.invalid_artifact; },
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
    var result = default<blot_check_core::DictionaryGiven>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::DictionaryGiven>(), error; } result.opening = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::DictionaryGiven>(), error; } result.introduction = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::DictionaryGiven>(), error; } result.quantifier = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::DictionaryGiven>(), error; } result.goal = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::DictionaryGiven>(), error; } result.arguments = decoded; }

    return result, blot_error::Error.none;
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
    var result = default<blot_check_core::DictionaryUse>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::DictionaryUse>(), error; } result.node = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::DictionaryUse>(), error; } result.binding = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::DictionaryUse>(), error; } result.opening = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::DictionaryUse>(), error; } result.introduction = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::DictionaryUse>(), error; } result.quantifier = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::DictionaryUse>(), error; } result.goal = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::DictionaryUse>(), error; } result.member = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_core__Primitive(writer: Writer&, value: blot_check_core::Primitive, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_core__PrimitiveKind(writer, value.kind, depth + 1);

    write_blot_check_core__Op(writer, value.op, depth + 1);

    write_blot_backend_collection_ops__Op(writer, value.array_op, depth + 1);

    write_u8(writer, value.arity, depth + 1);

}

fn read_blot_check_core__Primitive(reader: Reader&, depth: i64) -> blot_check_core::Primitive, Error {
    var result = default<blot_check_core::Primitive>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_core__PrimitiveKind(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Primitive>(), error; } result.kind = decoded; }

    { let decoded, error = read_blot_check_core__Op(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Primitive>(), error; } result.op = decoded; }

    { let decoded, error = read_blot_backend_collection_ops__Op(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Primitive>(), error; } result.array_op = decoded; }

    { let decoded, error = read_u8(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Primitive>(), error; } result.arity = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_core__PrimitiveKind(writer: Writer&, value: blot_check_core::PrimitiveKind, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        scalar => { put(writer, 0, 4);
},

        array => { put(writer, 1, 4);
},

    }
}

fn read_blot_check_core__PrimitiveKind(reader: Reader&, depth: i64) -> blot_check_core::PrimitiveKind, Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::PrimitiveKind>(), charged; } let tag, error = get(reader, 4); if error != blot_error::Error.none { return default<blot_check_core::PrimitiveKind>(), error; }
    match tag {

        0 => {
return blot_check_core::PrimitiveKind.scalar, blot_error::Error.none; },

        1 => {
return blot_check_core::PrimitiveKind.array, blot_error::Error.none; },

        _ => { return default<blot_check_core::PrimitiveKind>(), blot_error::Error.invalid_artifact; },
    }
}

fn write_blot_backend_collection_ops__Op(writer: Writer&, value: blot_backend_collection_ops::Op, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        length => { put(writer, 0, 4);
},

        get => { put(writer, 1, 4);
},

        set => { put(writer, 2, 4);
},

        fill => { put(writer, 3, 4);
},

        generate => { put(writer, 4, 4);
},

        append => { put(writer, 5, 4);
},

        prepend => { put(writer, 6, 4);
},

        identity => { put(writer, 7, 4);
},

        convert => { put(writer, 8, 4);
},

        cursor => { put(writer, 9, 4);
},

        cursor_has => { put(writer, 10, 4);
},

        cursor_value => { put(writer, 11, 4);
},

        cursor_advance => { put(writer, 12, 4);
},

        concat => { put(writer, 13, 4);
},

        slice => { put(writer, 14, 4);
},

        simd_load => { put(writer, 15, 4);
},

        simd_store => { put(writer, 16, 4);
},

        flatten => { put(writer, 17, 4);
},

    }
}

fn read_blot_backend_collection_ops__Op(reader: Reader&, depth: i64) -> blot_backend_collection_ops::Op, Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_backend_collection_ops::Op>(), charged; } let tag, error = get(reader, 4); if error != blot_error::Error.none { return default<blot_backend_collection_ops::Op>(), error; }
    match tag {

        0 => {
return blot_backend_collection_ops::Op.length, blot_error::Error.none; },

        1 => {
return blot_backend_collection_ops::Op.get, blot_error::Error.none; },

        2 => {
return blot_backend_collection_ops::Op.set, blot_error::Error.none; },

        3 => {
return blot_backend_collection_ops::Op.fill, blot_error::Error.none; },

        4 => {
return blot_backend_collection_ops::Op.generate, blot_error::Error.none; },

        5 => {
return blot_backend_collection_ops::Op.append, blot_error::Error.none; },

        6 => {
return blot_backend_collection_ops::Op.prepend, blot_error::Error.none; },

        7 => {
return blot_backend_collection_ops::Op.identity, blot_error::Error.none; },

        8 => {
return blot_backend_collection_ops::Op.convert, blot_error::Error.none; },

        9 => {
return blot_backend_collection_ops::Op.cursor, blot_error::Error.none; },

        10 => {
return blot_backend_collection_ops::Op.cursor_has, blot_error::Error.none; },

        11 => {
return blot_backend_collection_ops::Op.cursor_value, blot_error::Error.none; },

        12 => {
return blot_backend_collection_ops::Op.cursor_advance, blot_error::Error.none; },

        13 => {
return blot_backend_collection_ops::Op.concat, blot_error::Error.none; },

        14 => {
return blot_backend_collection_ops::Op.slice, blot_error::Error.none; },

        15 => {
return blot_backend_collection_ops::Op.simd_load, blot_error::Error.none; },

        16 => {
return blot_backend_collection_ops::Op.simd_store, blot_error::Error.none; },

        17 => {
return blot_backend_collection_ops::Op.flatten, blot_error::Error.none; },

        _ => { return default<blot_backend_collection_ops::Op>(), blot_error::Error.invalid_artifact; },
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
    var result = default<blot_check_core::LoopInfo>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_core__LoopKind(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::LoopInfo>(), error; } result.kind = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::LoopInfo>(), error; } result.first = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::LoopInfo>(), error; } result.end = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::LoopInfo>(), error; } result.pattern = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::LoopInfo>(), error; } result.body = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::LoopInfo>(), error; } result.carries = decoded; }

    { let decoded, error = read_bool(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::LoopInfo>(), error; } result.can_exit = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_core__LoopKind(writer: Writer&, value: blot_check_core::LoopKind, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        forever => { put(writer, 0, 4);
},

        range => { put(writer, 1, 4);
},

        array => { put(writer, 2, 4);
},

    }
}

fn read_blot_check_core__LoopKind(reader: Reader&, depth: i64) -> blot_check_core::LoopKind, Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::LoopKind>(), charged; } let tag, error = get(reader, 4); if error != blot_error::Error.none { return default<blot_check_core::LoopKind>(), error; }
    match tag {

        0 => {
return blot_check_core::LoopKind.forever, blot_error::Error.none; },

        1 => {
return blot_check_core::LoopKind.range, blot_error::Error.none; },

        2 => {
return blot_check_core::LoopKind.array, blot_error::Error.none; },

        _ => { return default<blot_check_core::LoopKind>(), blot_error::Error.invalid_artifact; },
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
    var result = default<blot_check_core::LoopCarry>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::LoopCarry>(), error; } result.incoming = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::LoopCarry>(), error; } result.iteration = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::LoopCarry>(), error; } result.backedge = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::LoopCarry>(), error; } result.outgoing = decoded; }

    return result, blot_error::Error.none;
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
    var result = default<blot_check_core::ResolverInfo>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_core__ResolverOperation(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::ResolverInfo>(), error; } result.operation = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::ResolverInfo>(), error; } result.resolver = decoded; }

    { let decoded, error = read_blot_check_core__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::ResolverInfo>(), error; } result.arguments = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::ResolverInfo>(), error; } result.member = decoded; }

    { let decoded, error = read_blot_check_core__BindingRef(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::ResolverInfo>(), error; } result.method = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::ResolverInfo>(), error; } result.method_type = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_core__ResolverOperation(writer: Writer&, value: blot_check_core::ResolverOperation, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        monad => { put(writer, 0, 4);
},

        pure => { put(writer, 1, 4);
},

        bind => { put(writer, 2, 4);
},

        forward => { put(writer, 3, 4);
},

        iterate => { put(writer, 4, 4);
},

        run => { put(writer, 5, 4);
},

    }
}

fn read_blot_check_core__ResolverOperation(reader: Reader&, depth: i64) -> blot_check_core::ResolverOperation, Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::ResolverOperation>(), charged; } let tag, error = get(reader, 4); if error != blot_error::Error.none { return default<blot_check_core::ResolverOperation>(), error; }
    match tag {

        0 => {
return blot_check_core::ResolverOperation.monad, blot_error::Error.none; },

        1 => {
return blot_check_core::ResolverOperation.pure, blot_error::Error.none; },

        2 => {
return blot_check_core::ResolverOperation.bind, blot_error::Error.none; },

        3 => {
return blot_check_core::ResolverOperation.forward, blot_error::Error.none; },

        4 => {
return blot_check_core::ResolverOperation.iterate, blot_error::Error.none; },

        5 => {
return blot_check_core::ResolverOperation.run, blot_error::Error.none; },

        _ => { return default<blot_check_core::ResolverOperation>(), blot_error::Error.invalid_artifact; },
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
    var result = default<blot_check_core::OperationValue>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::OperationValue>(), error; } result.identity = decoded; }

    { let decoded, error = read_blot_check_types__List(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::OperationValue>(), error; } result.arguments = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::OperationValue>(), error; } result.signature = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::OperationValue>(), error; } result.witness = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::OperationValue>(), error; } result.witness_result = decoded; }

    { let decoded, error = read_blot_check_types__NominalIdentity(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::OperationValue>(), error; } result.instance = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::OperationValue>(), error; } result.capability = decoded; }

    return result, blot_error::Error.none;
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
    var result = default<blot_check_core::HandleEffects>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::HandleEffects>(), error; } result.node = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::HandleEffects>(), error; } result.first = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::HandleEffects>(), error; } result.second = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::HandleEffects>(), error; } result.extended = decoded; }

    { let decoded, error = read_u32(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::HandleEffects>(), error; } result.residual = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_core__Diagnostic(writer: Writer&, value: blot_check_core::Diagnostic, depth: i64) {
    if !charge(writer, depth) { return; }

    write_blot_check_core__Code(writer, value.code, depth + 1);

    write_blot_parse_ast__Span(writer, value.span, depth + 1);

}

fn read_blot_check_core__Diagnostic(reader: Reader&, depth: i64) -> blot_check_core::Diagnostic, Error {
    var result = default<blot_check_core::Diagnostic>(); let charged = debit(reader, depth); if charged != blot_error::Error.none { return result, charged; }

    { let decoded, error = read_blot_check_core__Code(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Diagnostic>(), error; } result.code = decoded; }

    { let decoded, error = read_blot_parse_ast__Span(reader, depth + 1); if error != blot_error::Error.none { return default<blot_check_core::Diagnostic>(), error; } result.span = decoded; }

    return result, blot_error::Error.none;
}

fn write_blot_check_core__Code(writer: Writer&, value: blot_check_core::Code, depth: i64) {
    if !charge(writer, depth) { return; } match value {

        unchecked => { put(writer, 0, 4);
},

        unsupported => { put(writer, 1, 4);
},

        unresolved_binding => { put(writer, 2, 4);
},

        invalid_call => { put(writer, 3, 4);
},

        complexity => { put(writer, 4, 4);
},

    }
}

fn read_blot_check_core__Code(reader: Reader&, depth: i64) -> blot_check_core::Code, Error {
    let charged = debit(reader, depth); if charged != blot_error::Error.none { return default<blot_check_core::Code>(), charged; } let tag, error = get(reader, 4); if error != blot_error::Error.none { return default<blot_check_core::Code>(), error; }
    match tag {

        0 => {
return blot_check_core::Code.unchecked, blot_error::Error.none; },

        1 => {
return blot_check_core::Code.unsupported, blot_error::Error.none; },

        2 => {
return blot_check_core::Code.unresolved_binding, blot_error::Error.none; },

        3 => {
return blot_check_core::Code.invalid_call, blot_error::Error.none; },

        4 => {
return blot_check_core::Code.complexity, blot_error::Error.none; },

        _ => { return default<blot_check_core::Code>(), blot_error::Error.invalid_artifact; },
    }
}

fn digest(bytes: const u8[:]) -> u8[32] { var hash = blot_support_blake3::State {..}; hash.update(bytes); return hash.final(); }
fn encode(module: const blot_check_core::Module&, output: u8[>..<]&) -> Error {
    let begin = output.len; output.append(packet_magic);
    for index in packet_header - packet_magic.len { output.push(0); }
    var writer = Writer { output: output, start: output.len , ..};
    write_blot_check_core__Module(writer, module, 0);
    if writer.failure != blot_error::Error.none { output.resize(begin); return writer.failure; }
    let payload = output[begin + packet_header..]; let checksum = digest(payload);
    blot_bytes::put_u32(output[..], begin + 8, packet_version);
    for byte, index in schema_digest { output[begin + 12 + index] = byte; }
    blot_bytes::put_u64(output[..], begin + 44, payload.len as u64);
    for byte, index in checksum { output[begin + 52 + index] = byte; }
    return blot_error::Error.none;
}
fn decode(bytes: const u8[:]) -> Owned, Error {
    if bytes.len < packet_header || bytes[..8] != packet_magic { return default<Owned>(), blot_error::Error.invalid_artifact; }
    let version = blot_bytes::get_u32(bytes, 8); if version != packet_version { return default<Owned>(), blot_error::Error.unsupported_version; }
    if bytes[12..44] != schema_digest[..] { return default<Owned>(), blot_error::Error.schema_mismatch; }
    let length = blot_bytes::get_u64(bytes, 44); if length > packet_limit as u64 { return default<Owned>(), blot_error::Error.artifact_limit; }
    if length != (bytes.len - packet_header) as u64 { return default<Owned>(), blot_error::Error.invalid_artifact; }
    let actual = digest(bytes[packet_header..]); if bytes[52..84] != actual[..] { return default<Owned>(), blot_error::Error.invalid_artifact; }
    var reader = Reader { bytes: bytes[packet_header..] , ..}; let module, error = read_blot_check_core__Module(reader, 0);
    if error != blot_error::Error.none || reader.at != reader.bytes.len { releaseRuns(reader.head); if error != blot_error::Error.none { return default<Owned>(), error; } return default<Owned>(), blot_error::Error.invalid_artifact; }
    if next_generation == 0xffffffffffffffff || leases.len >= 0xffffffff { releaseRuns(reader.head); return default<Owned>(), blot_error::Error.out_of_memory; }
    var result = module; result.owner_id = blot_native::fresh_owner_id(); result.types.owner_id = blot_native::fresh_owner_id(); if result.owner_id == 0 || result.types.owner_id == 0 { releaseRuns(reader.head); return default<Owned>(), blot_error::Error.core_limit; }
    var packages=false;for node in result.nodes {if node.tag==blot_check_core::Tag.package_pack {packages=true;break;}}
    if packages && result.nodes.len!=0 {let run=pool_u32.alloc_slice(result.nodes.len);let error=remember(reader,Run.run_u32{run, ..});if error!=blot_error::Error.none {pool_u32.free_slice(run);releaseRuns(reader.head);return default<Owned>(),error;}for node,index in result.nodes {run[index]=node.a;}result.package_payloads=run;}
    let generation = next_generation; next_generation++; let lease = leases.alloc_index(Lease { reader.head, generation , ..});
    return Owned { result, (lease + 1) as u32, generation , ..}, blot_error::Error.none;
}

// A native owned copy uses the same typed dependency journal as principal
// snapshots. It never encodes and decodes an intermediate packet.
fn clone(module:const blot_check_core::Module&)->Owned,Error {
 let copied,error=blot_reuse_dependency_payload::clone(module);if error!=blot_error::Error.none {return default<Owned>(),error;}
 return Owned {module:copied.value,payload_owner:copied.owner, ..},blot_error::Error.none;
}
fn mutable(receiver:Owned&,values:const u32[:])->u32[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<u32[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_u32 run=>{if blot_support::same_slice_identity(run.values,values) {return pool_u32.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_numeric_proof_terms::Kind[:])->blot_check_numeric_proof_terms::Kind[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_numeric_proof_terms::Kind[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_numeric_proof_terms__Kind run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_numeric_proof_terms__Kind.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_numeric_proof_terms::Term[:])->blot_check_numeric_proof_terms::Term[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_numeric_proof_terms::Term[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_numeric_proof_terms__Term run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_numeric_proof_terms__Term.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_numeric_proof_contracts::Requirement[:])->blot_check_numeric_proof_contracts::Requirement[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_numeric_proof_contracts::Requirement[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_numeric_proof_contracts__Requirement run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_numeric_proof_contracts__Requirement.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_numeric_proof_headers::Named[:])->blot_check_numeric_proof_headers::Named[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_numeric_proof_headers::Named[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_numeric_proof_headers__Named run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_numeric_proof_headers__Named.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_capability_contracts::Term[:])->blot_check_capability_contracts::Term[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_capability_contracts::Term[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_capability_contracts__Term run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_capability_contracts__Term.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_capability_contracts::Binding[:])->blot_check_capability_contracts::Binding[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_capability_contracts::Binding[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_capability_contracts__Binding run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_capability_contracts__Binding.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::FieldName[:])->blot_check_core::FieldName[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::FieldName[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__FieldName run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__FieldName.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::RuntimeName[:])->blot_check_core::RuntimeName[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::RuntimeName[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__RuntimeName run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__RuntimeName.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::DeclarationDependencies[:])->blot_check_core::DeclarationDependencies[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::DeclarationDependencies[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__DeclarationDependencies run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__DeclarationDependencies.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::BindingRef[:])->blot_check_core::BindingRef[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::BindingRef[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__BindingRef run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__BindingRef.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::DependencyMember[:])->blot_check_core::DependencyMember[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::DependencyMember[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__DependencyMember run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__DependencyMember.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::ErasedDeclarationReference[:])->blot_check_core::ErasedDeclarationReference[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::ErasedDeclarationReference[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__ErasedDeclarationReference run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__ErasedDeclarationReference.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::RequestLoopInfo[:])->blot_check_core::RequestLoopInfo[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::RequestLoopInfo[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__RequestLoopInfo run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__RequestLoopInfo.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::RequestArm[:])->blot_check_core::RequestArm[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::RequestArm[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__RequestArm run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__RequestArm.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_types::Node[:])->blot_check_types::Node[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_types::Node[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_types__Node run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_types__Node.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_effects::Row[:])->blot_check_effects::Row[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_effects::Row[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_effects__Row run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_effects__Row.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_types::Operation[:])->blot_check_types::Operation[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_types::Operation[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_types__Operation run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_types__Operation.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_types::QuantifierGoals[:])->blot_check_types::QuantifierGoals[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_types::QuantifierGoals[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_types__QuantifierGoals run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_types__QuantifierGoals.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_types::Obligation[:])->blot_check_types::Obligation[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_types::Obligation[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_types__Obligation run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_types__Obligation.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::Node[:])->blot_check_core::Node[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::Node[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Node run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__Node.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_parse_ast::Span[:])->blot_parse_ast::Span[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_parse_ast::Span[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_parse_ast__Span run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_parse_ast__Span.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::Binding[:])->blot_check_core::Binding[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::Binding[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Binding run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__Binding.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::Body[:])->blot_check_core::Body[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::Body[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Body run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__Body.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::Parameter[:])->blot_check_core::Parameter[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::Parameter[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Parameter run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__Parameter.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::CallInfo[:])->blot_check_core::CallInfo[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::CallInfo[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__CallInfo run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__CallInfo.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::Merge[:])->blot_check_core::Merge[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::Merge[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Merge run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__Merge.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::List[:])->blot_check_core::List[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::List[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__List run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__List.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const u8[:])->u8[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<u8[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_u8 run=>{if blot_support::same_slice_identity(run.values,values) {return pool_u8.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::Obligation[:])->blot_check_core::Obligation[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::Obligation[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Obligation run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__Obligation.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::Nominal[:])->blot_check_core::Nominal[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::Nominal[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Nominal run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__Nominal.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::OperationName[:])->blot_check_core::OperationName[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::OperationName[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__OperationName run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__OperationName.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::Constructor[:])->blot_check_core::Constructor[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::Constructor[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Constructor run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__Constructor.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::Projection[:])->blot_check_core::Projection[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::Projection[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Projection run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__Projection.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::ProjectionVariant[:])->blot_check_core::ProjectionVariant[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::ProjectionVariant[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__ProjectionVariant run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__ProjectionVariant.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::Pattern[:])->blot_check_core::Pattern[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::Pattern[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Pattern run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__Pattern.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::PatternRow[:])->blot_check_core::PatternRow[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::PatternRow[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__PatternRow run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__PatternRow.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::MatchArm[:])->blot_check_core::MatchArm[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::MatchArm[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__MatchArm run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__MatchArm.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::MatchInfo[:])->blot_check_core::MatchInfo[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::MatchInfo[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__MatchInfo run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__MatchInfo.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::UpdateInfo[:])->blot_check_core::UpdateInfo[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::UpdateInfo[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__UpdateInfo run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__UpdateInfo.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::UpdateStep[:])->blot_check_core::UpdateStep[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::UpdateStep[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__UpdateStep run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__UpdateStep.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::ClosureInfo[:])->blot_check_core::ClosureInfo[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::ClosureInfo[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__ClosureInfo run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__ClosureInfo.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::Associated[:])->blot_check_core::Associated[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::Associated[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Associated run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__Associated.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::Contract[:])->blot_check_core::Contract[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::Contract[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Contract run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__Contract.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_reuse_principal_interface::ContractMember[:])->blot_reuse_principal_interface::ContractMember[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_reuse_principal_interface::ContractMember[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__ContractMember run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_reuse_principal_interface__ContractMember.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_reuse_principal_interface::Implementation[:])->blot_reuse_principal_interface::Implementation[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_reuse_principal_interface::Implementation[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__Implementation run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_reuse_principal_interface__Implementation.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_reuse_principal_interface::ImplementationMember[:])->blot_reuse_principal_interface::ImplementationMember[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_reuse_principal_interface::ImplementationMember[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__ImplementationMember run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_reuse_principal_interface__ImplementationMember.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_reuse_principal_interface::MemberTemplate[:])->blot_reuse_principal_interface::MemberTemplate[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_reuse_principal_interface::MemberTemplate[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__MemberTemplate run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_reuse_principal_interface__MemberTemplate.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_reuse_principal_interface::SelectedProof[:])->blot_reuse_principal_interface::SelectedProof[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_reuse_principal_interface::SelectedProof[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_reuse_principal_interface__SelectedProof run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_reuse_principal_interface__SelectedProof.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::SelectedUse[:])->blot_check_core::SelectedUse[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::SelectedUse[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__SelectedUse run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__SelectedUse.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::DictionarySelection[:])->blot_check_core::DictionarySelection[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::DictionarySelection[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__DictionarySelection run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__DictionarySelection.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::DictionaryUse[:])->blot_check_core::DictionaryUse[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::DictionaryUse[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__DictionaryUse run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__DictionaryUse.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::Primitive[:])->blot_check_core::Primitive[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::Primitive[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Primitive run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__Primitive.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::LoopInfo[:])->blot_check_core::LoopInfo[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::LoopInfo[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__LoopInfo run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__LoopInfo.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::LoopCarry[:])->blot_check_core::LoopCarry[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::LoopCarry[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__LoopCarry run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__LoopCarry.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::ResolverInfo[:])->blot_check_core::ResolverInfo[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::ResolverInfo[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__ResolverInfo run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__ResolverInfo.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::OperationValue[:])->blot_check_core::OperationValue[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::OperationValue[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__OperationValue run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__OperationValue.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::HandleEffects[:])->blot_check_core::HandleEffects[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::HandleEffects[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__HandleEffects run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__HandleEffects.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
fn mutable(receiver:Owned&,values:const blot_check_core::Diagnostic[:])->blot_check_core::Diagnostic[:] {
 if receiver.payload_owner.lease!=0 {return receiver.payload_owner.mutable(values);}
 assert(receiver.lease!=0&&receiver.lease-1<leases.len&&leases[receiver.lease-1].live&&leases[receiver.lease-1].generation==receiver.generation);if values.len==0 {return default<blot_check_core::Diagnostic[:]>();}
 var next=leases[receiver.lease-1].head;while next!=0 {let link=links[next-1];next=link.next;match link.value {run_blot_check_core__Diagnostic run=>{if blot_support::same_slice_identity(run.values,values) {return pool_blot_check_core__Diagnostic.realloc_slice(run.values,run.values.len);}},_=>{}}}
 abort("mutable Core view must name this private owner's exact live run");
}
