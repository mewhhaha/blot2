import os;
import std;
import source_resolver;
import link_check;
import chain_program;
import chain_target;
import chain_wasm;
import chain_revision;
import chain_public;
import chain_public_check;
fn main() {
 let a=args();assert(a.len==2);let abi:u8[32]=[7;32];var root=source_resolver::open_root(a[1],"pkg");assert(root.status==0);
 let wrapper="pub let f: U32 -> U32 ! {} resources {depth: 2, frame: 0} = fn x => return leaf.f(x)";
 let wc=chain_public::parse(wrapper,"pkg","middle.blot",abi);
 assert(wc.status==0 && chain_public_check::verify(wrapper,wc.name_start,wc.name_end,wc.param_start,wc.param_end,wc.alias_start,wc.alias_end,wc.target_start,wc.target_end,wc.depth,wc.frame));
 assert(!chain_public_check::verify(wrapper,wc.name_start,wc.name_end,wc.param_start,wc.param_end,wc.alias_start,wc.alias_end,wc.target_start,wc.target_end,wc.depth+1,wc.frame));
 var wrong_arg:u8[>..]=[];wrong_arg.append(wrapper);wrong_arg[wrong_arg.len-2]='y';
 assert(!chain_public_check::verify(wrong_arg,wc.name_start,wc.name_end,wc.param_start,wc.param_end,wc.alias_start,wc.alias_end,wc.target_start,wc.target_end,wc.depth,wc.frame));
 let probes=[link_check::Probe {alias:"middle",name:"future"}];
 var p=chain_program::prepare(root.root,"main.blot",abi,probes);assert(p.status==0 && p.plan.nodes.len==2 && p.plan.entries.len==2 && p.plan.snapshot.obs.len==8);
 let bytes=chain_wasm::emit(p.plan,"pkg","main.blot",abi,probes);assert(bytes.len>0 && chain_target::verify(p.plan,"pkg","main.blot",abi,probes,bytes));assert(write_file("before.wasm",bytes));
 for i in bytes.len {var b:u8[>..]=[];b.append(bytes);b[i]^=1;assert(!chain_target::verify(p.plan,"pkg","main.blot",abi,probes,b));}
 for i in bytes.len {assert(!chain_target::verify(p.plan,"pkg","main.blot",abi,probes,bytes[..i]));}
 var forged=copy(p.plan);forged.nodes[0].target=0;assert(!chain_program::verify(forged,"pkg","main.blot",abi,probes));
 var wrong=copy(p.plan);wrong.snapshot.interfaces[0]^=1;assert(!chain_program::verify(wrong,"pkg","main.blot",abi,probes));
 for i in p.plan.nodes.len {
  var bad=copy(p.plan);bad.nodes[i].name_start=-1;assert(!chain_target::verify(bad,"pkg","main.blot",abi,probes,bytes));
  var high=copy(p.plan);high.nodes[i].line_end=9223372036854775807;assert(!chain_target::verify(high,"pkg","main.blot",abi,probes,bytes));
 }
 for i in p.plan.graph.edges.len {var bad=copy(p.plan);bad.graph.edges[i].to=0;assert(!chain_target::verify(bad,"pkg","main.blot",abi,probes,bytes));}
 var obs=copy(p.plan);obs.snapshot.obs[0].from=0;assert(!chain_program::verify(obs,"pkg","main.blot",abi,probes));
 var session=chain_revision::begin(root.root);let cold=chain_revision::update(session,root.root,"main.blot",abi,probes,0);
 assert(cold.status==0 && cold.generation==1 && cold.bytes[..]==bytes[..]);let same=chain_revision::update(session,root.root,"main.blot",abi,probes,0);
 assert(same.status==0 && same.generation==1 && same.target_unchanged && same.semantic_unchanged);
 let leaf=str(a[1],"/leaf.blot");let mid=str(a[1],"/middle.blot");
 assert(write_file(leaf,"pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return 7\n"));
 let body=chain_revision::update(session,root.root,"main.blot",abi,probes,0);
 assert(body.status==0 && body.generation==2 && body.semantic_unchanged && !body.target_unchanged && write_file("after.wasm",body.bytes));
 let old=chain_revision::current(session,"main.blot",abi,probes);
 assert(write_file(leaf,"pub let gone: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return 7\n"));
 let missing=chain_revision::update(session,root.root,"main.blot",abi,probes,0);
 assert(missing.status==4 && missing.lookup.obs.len==2 && !missing.lookup.obs[1].found && session.generation==2 && chain_revision::current(session,"main.blot",abi,probes)[..]==old[..]);
 assert(write_file(leaf,"pub let f: U32 -> U32 ! {} resources {depth: 2, frame: 0} = fn x => return 7\n"));
 let depth=chain_revision::update(session,root.root,"main.blot",abi,probes,0);assert(depth.status==5 && session.generation==2);
 assert(write_file(leaf,"pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 1} = fn x => return 7\n"));
 let frame=chain_revision::update(session,root.root,"main.blot",abi,probes,0);assert(frame.status==5 && session.generation==2);
 assert(write_file(leaf,"import \"./middle.blot\" as middle\npub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return 7\n"));
 let cycle=chain_revision::update(session,root.root,"main.blot",abi,probes,0);assert(cycle.status==15 && session.generation==2);
 assert(write_file(leaf,"pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return 9\n"));
 for i in 1..4 {let fault=chain_revision::update(session,root.root,"main.blot",abi,probes,i as u32);assert(fault.status==20 && session.generation==2 && chain_revision::current(session,"main.blot",abi,probes)[..]==old[..]);}
 assert(write_file(mid,"import \"./leaf.blot\" as leaf\npub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return leaf.f(x)\n"));
 assert(chain_revision::update(session,root.root,"main.blot",abi,probes,0).status==5 && session.generation==2);
 // A public wrapper must not claim a zero frame if its own contract is not zero.
 assert(write_file(mid,"import \"./leaf.blot\" as leaf\npub let f: U32 -> U32 ! {} resources {depth: 2, frame: 1} = fn x => return leaf.f(x)\n"));
 assert(chain_revision::update(session,root.root,"main.blot",abi,probes,0).status==5 && session.generation==2);
 // Replacing the lexical receiver with the parameter cannot bind an import.
 assert(write_file(mid,"import \"./leaf.blot\" as leaf\npub let f: U32 -> U32 ! {} resources {depth: 2, frame: 0} = fn leaf => return leaf.f(leaf)\n"));
 assert(chain_revision::update(session,root.root,"main.blot",abi,probes,0).status!=0 && session.generation==2);
 // Three public modules exercise a forward target index and the composed
 // declared-depth proof across two nested qualified calls.
 assert(write_file(str(a[1],"/step.blot"),"import \"./leaf.blot\" as leaf\npub let f: U32 -> U32 ! {} resources {depth: 2, frame: 0} = fn x => return leaf.f(x)\n"));
 assert(write_file(mid,"import \"./step.blot\" as step\npub let f: U32 -> U32 ! {} resources {depth: 3, frame: 0} = fn x => return step.f(x)\n"));
 let deep=chain_revision::update(session,root.root,"main.blot",abi,probes,0);
 assert(deep.status==0 && deep.generation==3 && write_file("deep.wasm",deep.bytes));
 assert(write_file(str(a[1],"/step.blot"),"import \"./leaf.blot\" as leaf\npub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return leaf.f(x)\n"));
 assert(chain_revision::update(session,root.root,"main.blot",abi,probes,0).status==5 && session.generation==3);
 assert(source_resolver::close_root(root.root));
}
