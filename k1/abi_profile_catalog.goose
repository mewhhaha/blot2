// Private versioned policy inventory, not the qualified K1 ABI hash. Entries
// deliberately encode only the families and fixed rules shown below.
namespace abi_profile_catalog;
fn count()->i64{return 15;}
fn key(i:i64)->u8[:] {
 if i==0{return "profile";}if i==1{return "scalar";}if i==2{return "aggregate";}if i==3{return "descriptors";}
 if i==4{return "owner";}if i==5{return "allocator";}if i==6{return "builder";}if i==7{return "dictionary";}
 if i==8{return "calls";}if i==9{return "existentials";}if i==10{return "limits";}if i==11{return "wire";}
 if i==12{return "wire-status";}if i==13{return "wire-lifecycle";}if i==14{return "primitive-families";}return "";
}
fn value(i:i64)->u8[:] {
 if i==0{return "PRIVATE-K1-ABI-CANDIDATE1;digest=BLAKE3-256;byte-order=little;word=4";}
 if i==1{return "Unit=size0,align1;U32=size4;Bool=size4,valid=0|1;Index=size4;F32=IEEE754-binary32,size4;nonempty-align=4";}
 if i==2{return "record=fields-in-declaration-order;sum=tag-u32+largest-payload;inactive-words=zero;array-stride=element-size;headers=none;zero-view=0,0;zero-sized-view=0,n";}
 if i==3{return "View=data,length;Dest=data,capacity;EnvDest=data,capacity-bytes;Builder=data,length,capacity;RegionOwner=slot,generation;Space=slot,generation;Owned=slot,generation;OwnedConstruction=slot,generation;Fn=code,environment";}
 if i==4{return "fields=base,requested,rounded,top,generation,state,root-schema,root-words;Free=0;Open=1;SealedOwned=2;Retired=3;BuildingOwned=4;slot-zero=invalid;generation-never-wraps";}
 if i==5{return "page=65536;granule=4096;pool-default=16777216;owners-default=256;owners-max=4096;owner-bytes=32;frame-default=1048576;frame-max=16777216;window-default=65536;capsule=256;memory-max=1073741824;reservation=first-fit;zero-reservation=slot-no-block";}
 if i==6{return "begin=exclusive-dest-to-empty-builder;append=write-complete-then-length;read=initialized-prefix;truncate=resize-only;freeze=consume,fresh-domain;discard=consume;mutation-requires-no-live-loans";}
 if i==7{return "fields=size-bytes,alignment-bytes,flags,schema-id;Plain=1;Share=2;ZeroSized=4;unknown-flags=invalid;schema-id-needs-canonical-schema;dictionary-is-not-source-fabricable";}
 if i==8{return "params=environment,result-slot-if-indirect,layout-dictionaries-binder-order,unmapped-Nat-witnesses,source-argument;Region-Domain-proof=erased;Unit=no-arg-or-result;scalar=i32|f32;aggregate=indirect;generic=indirect;indirect-result=no-machine-result;no-multivalue";}
 if i==9{return "Nat-prefix=one-u32-per-hidden-Nat-in-binder-order;Domain=zero-words;payload-follows-prefix;no-prefix-dedup;prefix-counts-toward-layout-limits";}
 if i==10{return "Plain-max=16-words;aggregate-max=64-words;environment-max=64-words;sum-max=4-arms;Plain-nodes=32;Plain-leaves=64;Plain-guards=32;depth-max=128;linear-memory-max=1GiB";}
 if i==11{return "tag=0x4b310001;header=u32[abi,export,status,payload,required,item-count,detail,reserved];payload-offset=32;descriptor=u32[count,byte-offset];align=4;dest-omitted;wire-fields=source-order;output=descriptor,canonical-data;overlapping-inputs=copied-independently;zero-padding";}
 if i==12{return "Ok=0;InvalidInput=1;OutputTooSmall=2;ReservationFailed=3;Busy=4;FrameLimit=5;LanguageError=6;Poisoned=host-only;required-only-on-ok-or-too-small;payload-only-on-ok";}
 if i==13{return "guard,validate,frame-preflight,reserve,copy-freeze-inputs,allocate-dest,invoke-once,check-output-capacity,copy-output,publish-header-last,end-loans,close,restore-frame,release-guard";}
 if i==14{return "scalar-comparison;bool;checked-u32;wrapping-u32;f32;region.reserve;region.try_alloc;env.try_alloc;dest.split;builder.begin;builder.append;builder.try_append;builder.set;builder.truncate;builder.freeze;builder.discard;view.read;view.try_read;view.slice;index.try_make;space.end;region.reset;region.close;owned.begin;owned.seal;owned.abort;owned.open;owned.close;fn.place";}
 return "";
}
