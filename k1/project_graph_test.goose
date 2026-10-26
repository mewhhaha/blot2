import std;
import os;
import source_resolver;
import project_graph;
import project_revision;
fn main() {
 let a=args();assert(a.len==3);
 var opened=source_resolver::open_root(a[1],"pkg");assert(opened.status==0);
 let empty:project_graph::Probe[]=[];
 let probes=[project_graph::Probe {base:"main.blot",path:"./optional.blot"},
             project_graph::Probe {base:"main.blot",path:"./a.blot"}];
 var first=project_graph::build(opened.root,"main.blot",probes);
 assert(first.status==0 && first.graph.modules.len==4 && first.graph.edges.len==4 && first.graph.observations.len==2);
 assert(!first.graph.observations[0].found && first.graph.observations[1].found);
 assert(first.graph.package[..]=="pkg");
 var repeat=project_graph::build(opened.root,"main.blot",probes);
 assert(repeat.status==0 && project_graph::same(first.graph,repeat.graph));
 let different_base=[project_graph::Probe {base:"main.blot",path:"./optional.blot"},
                     project_graph::Probe {base:"a.blot",path:"./a.blot"}];
 let different_spelling=[project_graph::Probe {base:"main.blot",path:"./optional.blot"},
                         project_graph::Probe {base:"main.blot",path:"a.blot"}];
 let unsupported_kind=[project_graph::Probe {kind:2,base:"main.blot",path:"./a.blot"}];
 var altered_base=project_graph::build(opened.root,"main.blot",different_base);
 var altered_spelling=project_graph::build(opened.root,"main.blot",different_spelling);
 assert(altered_base.status==0 && !project_graph::same(first.graph,altered_base.graph));
 assert(altered_spelling.status==0 && !project_graph::same(first.graph,altered_spelling.graph));
 assert(project_graph::build(opened.root,"main.blot",unsupported_kind).status==1);
 let main_path=str(a[1],"/main.blot");
 assert(write_file(main_path,"import \"./a.blot\" as renamed\nimport \"./b.blot\" as b\nlet f: U32 -> U32 = fn x => return x\n"));
 var renamed=project_graph::build(opened.root,"main.blot",probes);
 assert(renamed.status==0 && !project_graph::same(first.graph,renamed.graph));
 assert(write_file(main_path,"import \"./a.blot\" as a\nimport \"./b.blot\" as b\nlet f: U32 -> U32 = fn x => return x\n"));
 assert(project_graph::build(opened.root,"../outside/secret.blot",probes).status==1);
 assert(project_graph::build(opened.root,"cycle.blot",empty).status==5);
 assert(project_graph::build(opened.root,"dup.blot",empty).status==1);
 assert(project_graph::build(opened.root,"bad-import.blot",empty).status==1);
 assert(project_graph::build(opened.root,"escape.blot",empty).status==4);
 let escape_probe=[project_graph::Probe {base:"main.blot",path:"./escape-link.blot"}];
 let fifo_probe=[project_graph::Probe {base:"main.blot",path:"./fifo"}];
 assert(project_graph::build(opened.root,"main.blot",escape_probe).status==4);
 assert(project_graph::build(opened.root,"main.blot",fifo_probe).status==4);
 assert(project_graph::build(opened.root,"n0.blot",empty).status==2); // 65 modules
 let max_chain=project_graph::build(opened.root,"m0.blot",empty);
 assert(max_chain.status==0 && max_chain.graph.modules.len==64);
 let max_edges=project_graph::build(opened.root,"edges256.blot",empty);
 assert(max_edges.status==0 && max_edges.graph.edges.len==256);
 assert(project_graph::build(opened.root,"edges257.blot",empty).status==2);
 let nested=project_graph::build(opened.root,"sub/child.blot",empty);
 assert(nested.status==0 && nested.graph.modules.len==2 && nested.graph.edges.len==1);
 assert(project_graph::find(nested.graph.paths,nested.graph.modules,"shared.blot")>=0);
 let absent=project_graph::build(opened.root,"missing-entry.blot",empty);
 assert(absent.status==3 && absent.graph.modules.len==0 && absent.missing[..]=="missing-entry.blot");
 var created=project_revision::begin(opened.root);assert(created.root_handle>=0);
 let one=project_revision::update(created,opened.root,"main.blot",probes,0);
 assert(one.status==0 && one.retained && !one.unchanged && one.generation==1);
 one.graph.sources[0]^=1; // returned graph must not alias the retained version
 let two=project_revision::update(created,opened.root,"main.blot",probes,0);
 assert(two.status==0 && two.retained && two.unchanged && two.generation==1);
 let optional_path=str(a[1],"/optional.blot");
 assert(write_file(optional_path,"let optional: U32 = 1\n"));
 for fault in 1..4 {
  let fail=project_revision::update(created,opened.root,"main.blot",probes,fault as u32);
  assert(fail.status==6 && created.generation==1 && created.versions.len==1);
 }
 let added=project_revision::update(created,opened.root,"main.blot",probes,0);
 assert(added.status==0 && added.retained && !added.unchanged && added.generation==2 && added.graph.observations[0].found);
 let content=added.graph.observations[0];
 assert(added.graph.sources[content.source_start..content.source_end]=="let optional: U32 = 1\n");
 assert(write_file(optional_path,"let optional: U32 = 2\n"));
 let changed=project_revision::update(created,opened.root,"main.blot",probes,0);
 assert(changed.status==0 && changed.retained && !changed.unchanged && changed.generation==3);
 assert(delete_file(optional_path));
 var reverted=project_revision::update(created,opened.root,"main.blot",probes,0);
 assert(reverted.status==0 && reverted.retained && !reverted.unchanged && reverted.generation==4);
 assert(project_graph::same(first.graph,reverted.graph));
 assert(write_file(main_path,"import \"unterminated\n"));
 let invalid_edit=project_revision::update(created,opened.root,"main.blot",probes,0);
 assert(invalid_edit.status==1 && created.generation==4 && created.versions.len==4);
 assert(write_file(main_path,"import \"./a.blot\" as a\nimport \"./b.blot\" as b\nlet f: U32 -> U32 = fn x => return x\n"));
 let valid_revert=project_revision::update(created,opened.root,"main.blot",probes,0);
 assert(valid_revert.status==0 && valid_revert.unchanged && valid_revert.generation==4);
 assert(write_file(main_path,"import \"./not-there.blot\" as missing\n"));
 let missing_edit=project_revision::update(created,opened.root,"main.blot",probes,0);
 assert(missing_edit.status==3 && missing_edit.missing[..]=="not-there.blot" && missing_edit.graph.modules.len==0 && created.generation==4);
 assert(write_file(main_path,"import \"./escape-link.blot\" as outside\n"));
 let escape_edit=project_revision::update(created,opened.root,"main.blot",probes,0);
 assert(escape_edit.status==4 && escape_edit.graph.modules.len==0 && created.generation==4);
 assert(write_file(main_path,"import \"./a.blot\" as a\nimport \"./b.blot\" as b\nlet f: U32 -> U32 = fn x => return x\n"));
 let final_revert=project_revision::update(created,opened.root,"main.blot",probes,0);
 assert(final_revert.status==0 && final_revert.unchanged && final_revert.generation==4);
 let bad=project_revision::update(created,opened.root,"cycle.blot",empty,0);
 assert(bad.status==5 && created.generation==4 && created.versions.len==4);
 var other=source_resolver::open_root(a[2],"pkg");assert(other.status==0);
 let wrong=project_revision::update(created,other.root,"main.blot",probes,0);
 assert(wrong.status==7 && created.generation==4);
 // The bounded retained family declines an additional revision, but returns
 // the successfully rebuilt graph rather than reusing stale state.
 for i in 5 {
  assert(write_file(optional_path,str("let optional: U32 = ",i,"\n")));
  let update=project_revision::update(created,opened.root,"main.blot",probes,0);
  assert(update.status==0 && !update.unchanged && update.graph.observations[0].found);
  if i<4 {assert(update.retained && update.generation==(5+i) as u64);} else {assert(!update.retained && created.generation==8);}
 }
 assert(delete_file(optional_path));
 assert(source_resolver::close_root(other.root));
 assert(source_resolver::close_root(opened.root));
 print("private project graph and retained revision laws passed");
}
