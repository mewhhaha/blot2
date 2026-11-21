from pathlib import Path
import json,re,sys
from normalize_syntax import normalize,finish_syntax
R=Path(__file__).resolve().parents[1]/'src'
M=json.loads((R.parent/'build/project-packet-model.json').read_text());D=M['definitions']
def q(t,n):return re.sub(r'(?<![\w:])\b\w+\b(?!::)',lambda m:n+'::'+m[0] if n+'::'+m[0] in D else m[0],t)
imports=set(M['imports'])|{'support.project_packet','check.type_store_packet','check.check_packet_owner'}
C=['// Concrete owner/context reconstruction for copied checker/lowering jobs.','namespace blot_project_packet;']+['import '+x+';' for x in sorted(imports)]
# Checked is immutable except its separately restored mutable solver store. Raw
# read tables retain the concrete packet owner; diagnostics have native clones.
fields=D['blot_check_check::Checked'][2]
C+=['fn put(self:Writer&,value:blot_check_check::Checked) {if !self.enter() {return;}'+''.join('put(self,value.'+f+');' for f,t in fields if f!='owner')+'self.depth--;}']
C+=['''fn get(self:Reader&,value:blot_check_check::Checked&) {
 if !self.enter() {return;}value=default<blot_check_check::Checked>();let owner,error=blot_check_check::newCheckedOwner();if error!=Error.none {self.failure=error;self.depth--;return;}value.owner=owner;
'''+''.join('get(self,value.'+f+');' for f,t in fields if f!='owner')+'''
 if self.failure!=Error.none {value.types.deinit();value.parameter_patterns.deinit();value.owner.deinit();value=default<blot_check_check::Checked>();self.depth--;return;}
 let diagnostics=value.diagnostics;value.diagnostics=default<blot_check_check::Diagnostic[:]>();let cloned,error=blot_check_check::cloneDiagnostics(value.owner,diagnostics);if error!=Error.none {value.types.deinit();value.parameter_patterns.deinit();value.owner.deinit();value=default<blot_check_check::Checked>();self.failure=error;self.depth--;return;}value.diagnostics=cloned;
 if value.editor.present&&value.editor.value.context.present {let source=value.editor.value.context.value;value.editor.value.context=blot_support::none<blot_reuse_hole_diagnostics::Snapshot>();let context,error=source.clone();if error!=Error.none {value.deinit();self.failure=error;self.depth--;return;}value.editor.value.context=blot_support::Option<blot_reuse_hole_diagnostics::Snapshot>{true,context};}
 let attached=blot_check_check::attachCheckedPacket(value.owner,self.owner);if attached!=Error.none {value.deinit();self.failure=attached;}self.depth--;
}''']
C+=['''fn put(self:Writer&,value:blot_check_types::Store) {let snapshot,error=blot_check_type_store_snapshot::viewPacketStore(value);if error!=blot_error::Error.none {self.failure=error;return;}put(self,snapshot);}
fn get(self:Reader&,value:blot_check_types::Store&) {var snapshot=default<blot_check_type_store_snapshot::Snapshot>();get(self,snapshot);if self.failure!=Error.none {return;}let store,error=blot_check_types::initPooled();if error!=Error.none {self.failure=error;return;}value=store;let restored=blot_check_type_store_snapshot::restorePacketStore(snapshot,value);if restored!=Error.none {value.deinit();self.failure=restored;}}
fn put(self:Writer&,value:blot_check_parameter_patterns::Store) {if value.lease==0 {assert(value.generation==0);put(self,default<const blot_check_parameter_patterns::Node[:]>());put(self,default<const u32[:]>());return;}put(self,value.nodes().items);put(self,value.extra().items);}
fn get(self:Reader&,value:blot_check_parameter_patterns::Store&) {var nodes:blot_check_parameter_patterns::Node[:]=[];var words:u32[:]=[];get(self,nodes);get(self,words);if self.failure!=Error.none {return;}let store,error=blot_check_parameter_patterns::initPooled();if error!=Error.none {self.failure=error;return;}var restored=store;restored.nodes().append(nodes);restored.extra().append(words);self.failure=restored.nodes().failure;if self.failure==Error.none {self.failure=restored.extra().failure;}if self.failure!=Error.none {restored.deinit();return;}value=blot_check_parameter_patterns::checkedView(restored);}
fn put(self:Writer&,value:blot_parse_symbols::Pool) {put(self,value.read_only);put(self,value.missing_name);put(self,value.bytes.items);put(self,value.entries.items);put(self,value.buckets.items);}
fn get(self:Reader&,value:blot_parse_symbols::Pool&) {var read_only=false;var missing=false;var bytes:u8[:]=[];var entries:blot_parse_symbols::Entry[:]=[];var buckets:u32[:]=[];get(self,read_only);get(self,missing);get(self,bytes);get(self,entries);get(self,buckets);if self.failure!=Error.none {return;}for entry in entries {if entry.offset>bytes.len||entry.len>bytes.len-entry.offset {self.failure=Error.invalid_artifact;return;}}for symbol in buckets {if symbol>entries.len {self.failure=Error.invalid_artifact;return;}}let pool,error=blot_parse_symbols::initPooled();if error!=Error.none {self.failure=error;return;}value=pool;value.bytes.append(bytes);value.entries.append(entries);value.buckets.append(buckets);self.failure=value.bytes.failure;if self.failure==Error.none {self.failure=value.entries.failure;}if self.failure==Error.none {self.failure=value.buckets.failure;}if self.failure!=Error.none {value.deinit();return;}value.read_only=read_only;value.missing_name=missing;}
''']
# Tree data is copied into the canonical syntax owner; ordinal lanes are exact.
fs=[]
for f,t in D['blot_parse_ast::Tree'][2]:
 if t.endswith('&'):
  bt=q(t[:-1],'blot_parse_ast');table=D[bt];item=dict(table[2])['items'];fs.append((f,q(item,table[3])))
C+=['fn put(self:Writer&,value:blot_parse_ast::Tree) {put(self,value.lease!=0);if value.lease==0 {return;}put(self,value.has_typed_staging);'+''.join('put(self,value.'+f+'.items);' for f,t in fs)+'}']
C+=['fn get(self:Reader&,value:blot_parse_ast::Tree&) {var present=false;get(self,present);if self.failure!=Error.none||!present {value=blot_parse_ast::Tree{..};return;}var staging=false;get(self,staging);'+''.join('var '+f+':'+t+'=[];get(self,'+f+');' for f,t in fs)+'''if self.failure!=Error.none {return;}if nodes.len!=spans.len {self.failure=Error.invalid_artifact;return;}for root in roots {if root>=nodes.len {self.failure=Error.invalid_artifact;return;}}let tree,error=blot_parse_ast::initPooled();if error!=Error.none {self.failure=error;return;}value=tree;value.nodes.clear();value.spans.clear();value.has_typed_staging=staging;'''+''.join('value.'+f+'.append('+f+');' for f,t in fs)+'self.failure=value.failure();if self.failure!=Error.none {value.deinit();}}']
types={'bool','u8','u16','u32','u64','i8','i16','i32','i64','f32','f64'}|{name.split('::')[-1] for name in D}
source=finish_syntax(normalize('\n'.join(C)+'\n',types))
source=re.sub(r'(\b\w+:\s*)((?:const\s+)?[A-Za-z_]\w*(?:::\w+)*(?:<[^{};\n]+>)?(?:\[:\])+)(\s*=\s*)\[\]',lambda m:m[1]+m[2]+m[3]+'default<'+m[2]+'>()',source)
(R/'support/project_packet_contexts.goose').write_text(source)
