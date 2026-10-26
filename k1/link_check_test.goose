import std;
import os;
import source_resolver;
import project_graph;
import link_graph_check;
import link_check;
import link_revision;
import link_consumer;
import link_consumer_check;
fn main() {
 let a=args();assert(a.len==3);let abi:u8[32]=[7;32];
 var root=source_resolver::open_root(a[1],"pkg");assert(root.status==0);
 let gp:project_graph::Probe[]=[];
 let probes=[link_check::Probe {alias:"lib",name:"future"}];
 var graph=project_graph::build(root.root,"main.blot",gp);assert(graph.status==0);
 assert(link_graph_check::verify(graph.graph,"pkg","main.blot"));
 var first=link_check::check(graph.graph,"pkg","main.blot",abi,probes);
 assert(first.status==0 && first.snapshot.caller_depth==2 && first.snapshot.observations.len==4);
 assert(first.snapshot.observations[0].found && first.snapshot.observations[1].found &&
        first.snapshot.observations[2].found && !first.snapshot.observations[3].found);
 assert(first.snapshot.interfaces.len>0);
 // Imported alias/producer and exact member spans cannot be forged.
 let old=graph.graph.edges[0];graph.graph.edges[0].to=0;
 assert(!link_graph_check::verify(graph.graph,"pkg","main.blot"));
 assert(link_check::check(graph.graph,"pkg","main.blot",abi,probes).status!=0);
 graph.graph.edges[0]=old;
 let absent_alias_probe=[link_check::Probe {alias:"absent",name:"future"}];
 let ordinary_negative=link_check::check(graph.graph,"pkg","main.blot",abi,absent_alias_probe);
 assert(ordinary_negative.status==0 && ordinary_negative.snapshot.observations.len==3 && !ordinary_negative.snapshot.observations[2].found);
 var session=link_revision::begin(root.root);assert(session.root_handle>=0);
 let cold=link_revision::update(session,root.root,"main.blot",abi,probes,0);
 assert(cold.status==0 && cold.retained && !cold.unchanged && cold.generation==1);
 let warm=link_revision::update(session,root.root,"main.blot",abi,probes,0);
 assert(warm.status==0 && warm.retained && warm.unchanged && warm.generation==1);
 let provider=str(a[1],"/lib.blot");
 // Changing only the checked provider body retains the same complete narrow
 // semantic interface, so the caller snapshot remains byte-identical.
 assert(write_file(provider,"pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return 7\n"));
 let body=link_revision::update(session,root.root,"main.blot",abi,probes,0);
 assert(body.status==0 && body.unchanged && body.generation==1);
 // A private declaration cannot satisfy the missing public-member lookup.
 assert(write_file(provider,"pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return 7\nlet future: U32 -> U32 = fn x => return x\n"));
 let private_member=link_revision::update(session,root.root,"main.blot",abi,probes,0);
 assert(private_member.status==0 && private_member.unchanged && !private_member.snapshot.observations[3].found);
 // Adding the previously missing public name flips the negative lookup.
 assert(write_file(provider,"pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return 7\npub let future: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x\n"));
 let added=link_revision::update(session,root.root,"main.blot",abi,probes,0);
 assert(added.status==0 && !added.unchanged && added.generation==2 && added.snapshot.observations[3].found);
 // Removing a required export returns its source-bound negative observation;
 // it must not publish a partial successful revision.
 assert(write_file(provider,"pub let future: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x\n"));
 let missing=link_revision::update(session,root.root,"main.blot",abi,probes,0);
 assert(missing.status==4 && missing.snapshot.observations.len==2 && !missing.snapshot.observations[1].found && session.generation==2);
 assert(write_file(provider,"pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => return x < 1\n"));
 let wrong_type=link_revision::update(session,root.root,"main.blot",abi,probes,0);
 assert(wrong_type.status==5 && session.generation==2);
 assert(write_file(provider,"pub let f: U32 -> U32 ! {} resources {depth: 128, frame: 0} = fn x => return x\n"));
 let too_deep=link_revision::update(session,root.root,"main.blot",abi,probes,0);
 assert(too_deep.status==5 && session.generation==2);
 assert(write_file(provider,"pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x\npub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x\n"));
 let duplicate=link_revision::update(session,root.root,"main.blot",abi,probes,0);
 assert(duplicate.status!=0 && session.generation==2);
 // Provider modules must also reject same-scope import/declaration collisions.
 let dependency=str(a[1],"/dep.blot");
 assert(write_file(dependency,"pub let dep: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x\n"));
 assert(write_file(provider,"import \"./dep.blot\" as f\npub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x\n"));
 let provider_shadow=link_revision::update(session,root.root,"main.blot",abi,probes,0);
 assert(provider_shadow.status!=0 && session.generation==2 && session.versions.len==2);
 assert(delete_file(dependency));
 assert(write_file(provider,"pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return 7\npub let future: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x\n"));
 let revert=link_revision::update(session,root.root,"main.blot",abi,probes,0);
 assert(revert.status==0 && revert.unchanged && revert.generation==2);
 // A valid published resource-contract change invalidates the semantic
 // caller observation even though the provider body remains unchanged.
 assert(write_file(provider,"pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 4} = fn x => return 7\npub let future: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x\n"));
 let contract_change=link_revision::update(session,root.root,"main.blot",abi,probes,0);
 assert(contract_change.status==0 && !contract_change.unchanged && contract_change.generation==3);
 assert(write_file(provider,"pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return 7\npub let future: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x\n"));
 let contract_revert=link_revision::update(session,root.root,"main.blot",abi,probes,0);
 assert(contract_revert.status==0 && !contract_revert.unchanged && contract_revert.generation==4);
 for fault in 1..4 {let interrupted=link_revision::update(session,root.root,"main.blot",abi,probes,fault as u32);
  assert(interrupted.status==20 && session.generation==4 && session.versions.len==4);}
 let entry_path=str(a[1],"/main.blot");
 assert(write_file(entry_path,"import \"./lib.blot\" as lib\nlet caller: U32 -> U32 = fn x => return other.f(x)\n"));
 let bad_alias=link_revision::update(session,root.root,"main.blot",abi,probes,0);
 assert(bad_alias.status==3 && bad_alias.snapshot.observations.len==1 && !bad_alias.snapshot.observations[0].found && session.generation==4);
 // A lexical parameter or declaration named lib shadows the import receiver;
 // it must never resolve as the module alias in this restricted fixture.
 let valid_line="let caller: U32 -> U32 = fn abc => return lib.f(abc)\n";
 let shadow_line="let caller: U32 -> U32 = fn lib => return lib.f(lib)\n";
 let valid_call=link_consumer::parse(valid_line);
 assert(valid_call.status==0 && !link_consumer_check::verify(shadow_line,valid_call));
 assert(write_file(entry_path,"import \"./lib.blot\" as lib\nlet caller: U32 -> U32 = fn lib => return lib.f(lib)\n"));
 let shadow=link_revision::update(session,root.root,"main.blot",abi,probes,0);
 assert(shadow.status!=0 && session.generation==4);
 let valid_name="let abc: U32 -> U32 = fn x => return lib.f(x)\n";
 let shadow_name="let lib: U32 -> U32 = fn x => return lib.f(x)\n";
 let name_call=link_consumer::parse(valid_name);
 assert(name_call.status==0 && !link_consumer_check::verify(shadow_name,name_call));
 assert(write_file(entry_path,"import \"./lib.blot\" as lib\nlet lib: U32 -> U32 = fn x => return lib.f(x)\n"));
 let declaration_shadow=link_revision::update(session,root.root,"main.blot",abi,probes,0);
 assert(declaration_shadow.status!=0 && session.generation==4);
 assert(write_file(entry_path,"import \"./lib.blot\" as lib\nlet caller: U32 -> U32 = fn x => return lib.f(x)\n"));
 // Optional probes are caller-scoped. A local parameter/declaration is not a
 // negative module lookup even if no import with that spelling exists.
 let parameter_probe=[link_check::Probe {alias:"x",name:"future"}];
 let declaration_probe=[link_check::Probe {alias:"caller",name:"future"}];
 assert(link_revision::update(session,root.root,"main.blot",abi,parameter_probe,0).status==1 && session.generation==4);
 assert(link_revision::update(session,root.root,"main.blot",abi,declaration_probe,0).status==1 && session.generation==4);
 let x_path=str(a[1],"/x.blot");
 assert(write_file(entry_path,"import \"./lib.blot\" as lib\nimport \"./x.blot\" as x\nlet caller: U32 -> U32 = fn x => return lib.f(x)\n"));
 assert(write_file(x_path,"pub let future: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn z => return z\n"));
 assert(link_revision::update(session,root.root,"main.blot",abi,parameter_probe,0).status==1 && session.generation==4);
 assert(write_file(x_path,"pub let other: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn z => return z\n"));
 assert(link_revision::update(session,root.root,"main.blot",abi,parameter_probe,0).status==1 && session.generation==4);
 assert(delete_file(x_path));
 assert(write_file(entry_path,"import \"./lib.blot\" as lib\nlet caller: U32 -> U32 = fn x => return lib.f(x)\n"));
 let other_abi:u8[32]=[8;32];
 let abi_change=link_revision::update(session,root.root,"main.blot",other_abi,probes,0);
 assert(abi_change.status==0 && !abi_change.unchanged && abi_change.generation==5);
 let abi_revert=link_revision::update(session,root.root,"main.blot",abi,probes,0);
 assert(abi_revert.status==0 && !abi_revert.unchanged && abi_revert.generation==6);
 var other=source_resolver::open_root(a[2],"pkg");assert(other.status==0);
 assert(link_revision::update(session,other.root,"main.blot",abi,probes,0).status==21 && session.generation==6);
 assert(source_resolver::close_root(other.root));assert(source_resolver::close_root(root.root));
 print("private source-bound cross-module interface and observation laws passed");
}
