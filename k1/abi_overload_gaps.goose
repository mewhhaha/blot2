// Closed list of known qualification gaps for this private schema proposal.
// A zero provisional flag cannot be changed into source or backend authority.
namespace abi_overload_gaps;
fn count()->i64{return 8;}
fn reason(i:i64)->u8[:] {
 if i==0{return "canonical-versioned-overload-ids-and-schemas-not-established";}
 if i==1{return "all-type-mode-overload-and-error-variants-not-established";}
 if i==2{return "primitive-lowering-helper-semantics-not-qualified";}
 if i==3{return "complete-layout-dictionary-and-call-abi-rules-not-validated";}
 if i==4{return "general-m12-schema-manifest-and-wire-admission-not-established";}
 if i==5{return "machine-adapter-target-and-aggregate-result-slot-not-qualified";}
 if i==6{return "frame-resource-and-runtime-loan-evidence-not-qualified";}
 if i==7{return "real-interface-implementation-manifest-certificate-hash-consistency-not-established";}
 return "";
}
// This proposal cannot confer public ABI eligibility even when its exact
// serialized bytes and digest are internally consistent.
fn publicly_eligible(registry:u8[:])->bool {let _=registry;return false;}
