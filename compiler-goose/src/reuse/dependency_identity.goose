// Identity views read existing journals without exclusive mutation authority.
namespace blot_reuse_dependency_payload;
import .dependency_payload;
import backend.runtime_identity;

// Read-only identity publication is valid while any retained journal key lives.
fn registeredIdentityBytes(owner:const Owner&,bytes:const u8[:])->const u8[:] {
 assert(owner.valid());if bytes.len==0 {return default<const u8[:]>();}
 var next=leases[owner.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {
  run_u8 run=>{if blot_support::same_slice_identity(run.values,bytes) {
   let owned=pool_u8.realloc_slice(run.values,run.values.len);assert(blot_support::same_slice_identity(owned,bytes));
   let start=pool_u8.index_of(owned[0]);return pool_u8[start..start+owned.len];
  }},_=>{},
 }}abort("identity bytes must name this live journal's exact run");
}
fn registeredIdentityNames(owner:const Owner&,names:const blot_backend_runtime_identity::Name[:])->const blot_backend_runtime_identity::Name[:] {
 assert(owner.valid());if names.len==0 {return default<const blot_backend_runtime_identity::Name[:]>();}
 var next=leases[owner.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {
  run_header_name run=>{if blot_support::same_slice_identity(run.values,names) {
   let owned=pool_header_name.realloc_slice(run.values,run.values.len);assert(blot_support::same_slice_identity(owned,names));
   let start=pool_header_name.index_of(owned[0]);return pool_header_name[start..start+owned.len];
  }},_=>{},
 }}abort("identity names must name this live journal's exact run");
}
fn registeredIdentity(owner:const Owner&,value:blot_backend_runtime_identity::View)->blot_backend_runtime_identity::View {
 assert(owner.valid());return blot_backend_runtime_identity::View{bytes:registeredIdentityBytes(owner,value.bytes),symbols:registeredIdentityNames(owner,value.symbols),owners:registeredIdentityNames(owner,value.owners)};
}

// Recover the exact existing catalog run without exclusive journal authority.
fn registeredCatalogDigests(owner:const Owner&,source:const HeaderDigest[:])->const HeaderDigest[:] {
 assert(owner.valid());if source.len==0 {return default<const HeaderDigest[:]>();}
 var next=leases[owner.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {
  run_header_digest run=>{if blot_support::same_slice_identity(run.values,source) {
   let owned=pool_header_digest.realloc_slice(run.values,run.values.len);assert(blot_support::same_slice_identity(owned,source));
   let start=pool_header_digest.index_of(owned[0]);assert(start>=0 && owned.len<=pool_header_digest.len-start);
   let result=pool_header_digest[start..start+owned.len];assert(blot_support::same_slice_identity(result,source));return result;
  }},_=>{},
 }}abort("catalog view must name this live journal's exact run");
}

// Recover the exact existing catalog run without exclusive journal authority.
fn registeredCatalogOrder(owner:const Owner&,source:const u32[:])->const u32[:] {
 assert(owner.valid());if source.len==0 {return default<const u32[:]>();}
 var next=leases[owner.lease-1].head;
 while next!=0 {let link=links[next-1];next=link.next;match link.value {
  run_u32 run=>{if blot_support::same_slice_identity(run.values,source) {
   let owned=pool_u32.realloc_slice(run.values,run.values.len);assert(blot_support::same_slice_identity(owned,source));
   let start=pool_u32.index_of(owned[0]);assert(start>=0 && owned.len<=pool_u32.len-start);
   let result=pool_u32[start..start+owned.len];assert(blot_support::same_slice_identity(result,source));return result;
  }},_=>{},
 }}abort("catalog view must name this live journal's exact run");
}
