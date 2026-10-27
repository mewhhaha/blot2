// Independent normative anchors; this is not an operation admission gate.
// Normative sources: K1-LANG sections 4, 5, 6, 8; K1-MEM M02, M04-M06,
// M08-M10; K1-CORE C03. All unreviewed concrete cases remain ineligible.
import abi_overload_catalog;
import abi_overload_build;
import abi_overload_verify;
import abi_overload_gaps;
import abi_profile_catalog;
fn main(){
 assert(abi_overload_catalog::count()==80);
 assert(abi_overload_catalog::evidence(0)=="AddFits(a,b)" && abi_overload_catalog::evidence(1)=="SubFits(a,b)" && abi_overload_catalog::evidence(2)=="MulFits(a,b)");
 assert(abi_overload_catalog::evidence(3)=="0<b" && abi_overload_catalog::evidence(4)=="0<b" && abi_overload_catalog::evidence(5)=="b<32" && abi_overload_catalog::evidence(6)=="b<32");
 for i in 7..10 {assert(abi_overload_catalog::operands(i)=="U32,U32" && abi_overload_catalog::result(i)=="U32" && abi_overload_catalog::transition(i)=="modulo-2^32");}
 for i in 10..16 {assert(abi_overload_catalog::result(i)=="Result[U32,declared-error]" && abi_overload_catalog::failure(i)=="typed-error;variant-details-unresolved");}
 for i in 35..39 {assert(abi_overload_catalog::operands(i)=="F32,F32" && abi_overload_catalog::result(i)=="F32" && abi_overload_catalog::transition(i)=="wasm-f32-rounding-nan-set-no-reassociate");}
 assert(abi_overload_catalog::name(39)=="f32.neg" && abi_overload_catalog::transition(39)=="flip-sign-bit");
 assert(abi_overload_catalog::name(47)=="region.reserve" && abi_overload_catalog::failure(47)=="SizeOverflow,NoOwnerSlots,NoContiguousSpace;unchanged-on-error");
 assert(abi_overload_catalog::name(48)=="region.try_alloc" && abi_overload_catalog::failure(48)=="SizeOverflow,NoSpace;unchanged-on-error");
 assert(abi_overload_catalog::name(50)=="env.try_alloc" && abi_overload_catalog::transition(50)=="align4;advance-on-success");
 assert(abi_overload_catalog::name(51)=="dest.split" && abi_overload_catalog::evidence(51)=="k<=c;exclusive-parent" && abi_overload_catalog::transition(51)=="disjoint-child-derivations");
 assert(abi_overload_catalog::name(56)=="builder.append" && abi_overload_catalog::evidence(56)=="n<c;no-live-loans" && abi_overload_catalog::transition(56)=="write-complete-element-before-publish-length;fresh-version");
 assert(abi_overload_catalog::name(57)=="builder.try_append" && abi_overload_catalog::failure(57)=="full-returns-unchanged-builder-and-element");
 assert(abi_overload_catalog::name(59)=="builder.truncate" && abi_overload_catalog::operands(59)=="Builder[r,T,n,c,Resize],U32-m" && abi_overload_catalog::evidence(59)=="m<=n;no-live-loans");
 assert(abi_overload_catalog::name(60)=="builder.freeze" && abi_overload_catalog::result(60)=="exists[d:Domain]=>View[r,T,n,d]" && abi_overload_catalog::transition(60)=="publish-initialized-prefix;fresh-domain");
 assert(abi_overload_catalog::name(64)=="view.slice" && abi_overload_catalog::evidence(64)=="start<=n;count<=n-start" && abi_overload_catalog::transition(64)=="fresh-domain;no-Index-rebranding");
 assert(abi_overload_catalog::name(72)=="region.reset" && abi_overload_catalog::result(72)=="(RegionOwner[r],Space[r])@fresh-epoch" && abi_overload_catalog::transition(72)=="consume-old-authority;top=0;fresh-static-epoch;generation-unchanged");
 assert(abi_overload_catalog::name(75)=="owned.seal" && abi_overload_catalog::transition(75)=="initialize-root;zero-unused;internalize-checked-payload-loans;SealedOwned");
 assert(abi_overload_catalog::name(77)=="owned.open" && abi_overload_catalog::result(77)=="block-result-Q" && abi_overload_catalog::evidence(77)=="SealedOwned;fresh-hidden-r;Q-cannot-retain-r-or-opened-brand");
 assert(abi_profile_catalog::value(1)=="Unit=size0,align1;U32=size4;Bool=size4,valid=0|1;Index=size4;F32=IEEE754-binary32,size4;nonempty-align=4");
 assert(abi_profile_catalog::value(3)=="View=data,length;Dest=data,capacity;EnvDest=data,capacity-bytes;Builder=data,length,capacity;RegionOwner=slot,generation;Space=slot,generation;Owned=slot,generation;OwnedConstruction=slot,generation;Fn=code,environment");
 assert(abi_profile_catalog::value(4)=="fields=base,requested,rounded,top,generation,state,root-schema,root-words;Free=0;Open=1;SealedOwned=2;Retired=3;BuildingOwned=4;slot-zero=invalid;generation-never-wraps");
 assert(abi_profile_catalog::value(7)=="fields=size-bytes,alignment-bytes,flags,schema-id;Plain=1;Share=2;ZeroSized=4;unknown-flags=invalid;schema-id-needs-canonical-schema;dictionary-is-not-source-fabricable");
 let registry=abi_overload_build::canonical();assert(abi_overload_verify::verify(registry));assert(!abi_overload_gaps::publicly_eligible(registry));
 for i in registry.len {var changed=copy(registry);changed[i]^=1;assert(!abi_overload_gaps::publicly_eligible(changed));}
 assert(!abi_overload_gaps::publicly_eligible(""));print("independent normative anchors hold; all provisional ABI admission closed");
}
