import os;
import std;
import source_resolver;
import link_check;
import multilink_program;
import multilink_target;
import multilink_wasm;
import multilink_revision;
fn main() {
 let a=args();assert(a.len==2);let abi:u8[32]=[7;32];var root=source_resolver::open_root(a[1],"pkg");assert(root.status==0);
 let probes=[link_check::Probe {alias:"lib",name:"future"},link_check::Probe {alias:"missing",name:"future"}];
 var p=multilink_program::prepare(root.root,"main.blot",abi,probes);
 assert(p.status==0 && p.plan.entries.len==3 && p.plan.snapshot.observations.len==9);
 let bytes=multilink_wasm::emit(p.plan,"pkg","main.blot",abi,probes);
 assert(bytes.len>0 && multilink_target::verify(p.plan,"pkg","main.blot",abi,probes,bytes));
 assert(write_file("before.wasm",bytes));
 // Reject swapped providers, extreme forged names and source/edge changes.
 var swap=copy(p.plan);let v=swap.entries[0].provider;swap.entries[0].provider=swap.entries[1].provider;swap.entries[1].provider=v;
 assert(!multilink_program::verify(swap,"pkg","main.blot",abi,probes));
 assert(!multilink_target::verify(swap,"pkg","main.blot",abi,probes,bytes));
 for x in [-1,0,9223372036854775807] {
  var bad=copy(p.plan);bad.entries[0].name_start=x;
  assert(!multilink_program::verify(bad,"pkg","main.blot",abi,probes));
  assert(!multilink_target::verify(bad,"pkg","main.blot",abi,probes,bytes));
  var bad_end=copy(p.plan);bad_end.entries[0].name_end=x;
  assert(!multilink_program::verify(bad_end,"pkg","main.blot",abi,probes));
 }
 for i in p.plan.graph.edges.len {
  var bad=copy(p.plan);bad.graph.edges[i].to=0;
  assert(!multilink_program::verify(bad,"pkg","main.blot",abi,probes));
 }
 var wrong=copy(p.plan);wrong.snapshot.observations[0].found=false;
 assert(!multilink_program::verify(wrong,"pkg","main.blot",abi,probes));

 for i in bytes.len {var b:u8[>..]=[];b.append(bytes);b[i]^=1;assert(!multilink_target::verify(p.plan,"pkg","main.blot",abi,probes,b));}
 for i in bytes.len {assert(!multilink_target::verify(p.plan,"pkg","main.blot",abi,probes,bytes[..i]));}
 var forged=copy(p.plan);forged.entries[1].provider.opcode=3;assert(!multilink_program::verify(forged,"pkg","main.blot",abi,probes));
 var forged2=copy(p.plan);forged2.snapshot.interfaces[0]^=1;assert(!multilink_program::verify(forged2,"pkg","main.blot",abi,probes));
 var session=multilink_revision::begin(root.root);
 let cold=multilink_revision::update(session,root.root,"main.blot",abi,probes,0);assert(cold.status==0 && cold.generation==1 && cold.bytes[..]==bytes[..]);
 let again=multilink_revision::update(session,root.root,"main.blot",abi,probes,0);assert(again.status==0 && again.semantic_unchanged && again.target_unchanged && again.generation==1);
 let provider=str(a[1],"/lib.blot");
 assert(write_file(provider,"pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return 7\n"));
 let body=multilink_revision::update(session,root.root,"main.blot",abi,probes,0);assert(body.status==0 && body.generation==2 && body.semantic_unchanged && !body.target_unchanged);
 assert(write_file("after.wasm",body.bytes));let old=multilink_revision::current(session,"main.blot",abi,probes);
 assert(write_file(provider,"pub let other: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return 7\n"));
 let missing=multilink_revision::update(session,root.root,"main.blot",abi,probes,0);
 assert(missing.status==4 && missing.lookup.observations.len==2 && !missing.lookup.observations[1].found && session.generation==2 && multilink_revision::current(session,"main.blot",abi,probes)[..]==old[..]);
 assert(write_file(provider,"pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 4} = fn x => return 7\n"));
 let frame=multilink_revision::update(session,root.root,"main.blot",abi,probes,0);assert(frame.status==5 && session.generation==2);
 assert(write_file(provider,"pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return 9\n"));
 for i in 1..4 {let fault=multilink_revision::update(session,root.root,"main.blot",abi,probes,i as u32);assert(fault.status==20 && session.generation==2 && multilink_revision::current(session,"main.blot",abi,probes)[..]==old[..]);}
 // The second call's failed member lookup preserves the first call's two
 // observations and adds its own positive alias and negative member.
 let other=str(a[1],"/other.blot");
 assert(write_file(other,"pub let nope: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return 42\n"));
 let second_missing=multilink_revision::update(session,root.root,"main.blot",abi,probes,0);
 assert(second_missing.status==4 && second_missing.lookup.observations.len==4 && !second_missing.lookup.observations[3].found && session.generation==2);
 assert(multilink_revision::current(session,"main.blot",abi,probes)[..]==old[..]);
 assert(write_file(other,"pub let g: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return 42\npub let h: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x & 255\n"));
 // A negative probe becoming positive must invalidate semantic identity even
 // if the emitted target is unchanged.
 assert(write_file(provider,"pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return 7\npub let future: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return 1\n"));
 let positive=multilink_revision::update(session,root.root,"main.blot",abi,probes,0);
 assert(positive.status==0 && positive.generation==3 && !positive.semantic_unchanged && positive.target_unchanged);
 // Reject cross-caller declaration/import collisions, duplicate names, and
 // caller-scoped probes shadowed by any function parameter.
 let mainpath=str(a[1],"/main.blot");
 assert(write_file(mainpath,"import \"./lib.blot\" as lib\nlet lib: U32 -> U32 = fn x => return lib.f(x)\n"));
 assert(multilink_revision::update(session,root.root,"main.blot",abi,probes,0).status!=0 && session.generation==3);
 assert(write_file(mainpath,"import \"./lib.blot\" as lib\nlet first: U32 -> U32 = fn x => return lib.f(x)\nlet first: U32 -> U32 = fn y => return lib.f(y)\n"));
 assert(multilink_revision::update(session,root.root,"main.blot",abi,probes,0).status!=0 && session.generation==3);
 assert(write_file(mainpath,"import \"./lib.blot\" as lib\nlet first: U32 -> U32 = fn x => return lib.f(x)\nlet next: U32 -> U32 = fn missing => return lib.f(missing)\n"));
 assert(multilink_revision::update(session,root.root,"main.blot",abi,probes,0).status!=0 && session.generation==3);
 assert(source_resolver::close_root(root.root));
}
