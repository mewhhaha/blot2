#!/usr/bin/env python3
import sys
"""Generate the explicit Goose owned-function table relocation graph."""
import re
from pathlib import Path
root=Path(__file__).resolve().parent.parent
m=(root/'src/model.goose').read_text()
structs={n:[tuple(x.strip().split(': ')) for x in f.split(', ')] for n,f in re.findall(r'struct (\w+) \{ ([^\n]+) \}',m)}
tables=[x for x in re.findall(r'    (\w+): const (\w+)\[:\]',re.search(r'struct Core \{(.*?)\n\}',m,re.S).group(1)) if x[0] not in ('refs','bytes')]
tags={n:i+1 for i,(n,t) in enumerate(tables)}
roles={
'dictionary_realizations':{'type_id':'types','parameters':'binders','arguments':'types','concrete_type':'types','layout':'layouts'},
'names':{'bytes':'bytes'}, 'origins':{'module':'modules'},
'modules':{'name':'names','path':'names','imports':'modules','declarations':'definitions','source':'bytes'},
'binders':{'scope':'scopes','name':'names','origin':'origins','introduction':'dynamic_intro'},
'scopes':{'parent':'scopes','binder':'binders','origin':'origins'},
'types':{'children':'types','fields':'fields','binders':'binders','region':'binders','nat':'terms','domain':'binders','capacity':'terms','contract':'contracts','binder':'binders','origin':'origins'},
'fields':{'name':'names','type_id':'types'},
'layout_premises':{'type_id':'types'},
'contracts':{'layout_premises':'layout_premises','arg':'types','result':'types','binders':'binders','requires':'facts','ensures':'facts','on_true':'facts','on_false':'facts','effects':'effects','origin':'origins'},
'effects':{'region':'binders'},
'values':{'type_id':'types','block_id':'blocks','op':'ops','scope':'scopes','origin':'origins'},
'ops':{'args':'values','results':'values','evidence':'evidence','substitutions':'substitutions','scope':'scopes','origin':'origins','imm0':'dynamic_op'},
'blocks':{'merge':'blocks','params':'values','evidence_params':'evidence','ops':'ops','term':'terminators','scope':'scopes','function':'functions','origin':'origins'},
'terminators':{'evidence':'evidence','subject':'values','edges':'edges','discharge':'values','origin':'origins'},
'edges':{'from':'blocks','to':'blocks','args':'values','evidence':'evidence','loop_id':'loops'},
'terms':{'type_id':'types','value':'values','binder':'dynamic_term','args':'terms','scope':'scopes'},
'facts':{'left':'terms','right':'terms','third':'terms','domain':'binders'},
'evidence':{'fact':'facts','contract':'contracts','formal_fact':'facts','call':'ops','scope':'scopes','edge':'edges','operands':'values','premises':'evidence','origin':'origins'},
'loops':{'header':'blocks','body':'blocks','exit':'blocks','index':'values','lower':'terms','upper':'terms','carries':'values','invariant':'evidence','backedges':'edges','exits':'edges'},
'functions':{'environment_bindings':'environment_bindings','name':'names','module':'modules','type_id':'types','contract':'contracts','param':'values','entry':'blocks','blocks':'blocks','captures':'captures','calls':'calls','binders':'binders','export_id':'omit','producer':'definitions','origin':'origins'},
'calls':{'op':'ops','caller':'functions','callee':'functions','contract':'contracts','substitutions':'substitutions'},
'substitutions':{'binder':'binders','value':'dynamic_sub'},
'captures':{'function':'functions','value':'values','local_value':'values','scope':'scopes'},
'loans':{'value':'values','owner':'values','scope':'scopes','begin_op':'ops','end_op':'ops'},
'transitions':{'op':'ops','value':'values','before':'values','after':'values','scope':'scopes'},
'layouts':{'type_id':'types','schema':'schemas','fields':'fields'},
'interfaces':{'abi_digest':'bytes','function':'functions','type_id':'types','contract':'contracts','dependencies':'dependencies','digest':'bytes','producer':'definitions'},
'dependencies':{'producer':'definitions','identity':'bytes','digest':'bytes'},
'receipts':{'producer':'definitions','source_digest':'bytes','semantic_digest':'bytes','dependencies':'dependencies'},
'exports':{'function':'functions','name':'names','arg_type':'types','result_type':'types','substitutions':'substitutions','fields':'fields','input_maxima':'raw','abi_digest':'bytes'},
'definitions':{'name':'names','module':'modules','type_id':'types','value':'values','function':'functions','binders':'binders','origin':'origins'},
'abi_plans':{'contract':'contracts','function':'functions','arg_layout':'layouts','result_layout':'layouts','env_layout':'layouts','dictionaries':'binders','nat_witnesses':'nat_witnesses'},
'nat_witnesses':{'binder':'binders','argument_path':'raw'},
'environment_bindings':{'function':'functions','binder':'binders','source_value':'values'},
'schemas':{'bytes':'bytes','digest':'bytes'},
'callable_adapters':{'op':'ops','target_function':'functions','callback_contract':'contracts','captures':'adapter_captures','environment_layout':'layouts'},
'adapter_captures':{'source':'dynamic_capture'},
'static_objects':{'function':'functions','constructor':'ops','type_id':'types','element_type':'types','domain':'binders','bytes':'bytes','relocations':'static_relocations','producer':'definitions'},
'static_relocations':{'target':'dynamic_relocation','addend':'dynamic_relocation_addend'},
}
def tag(role,row='row'):
 if not role.startswith('dynamic_'): return str(tags[role])
 return {'dynamic_intro':f'(if {row}.introduction_kind == INTRO_FUNCTION {{ {tags["functions"]} }} else if {row}.introduction_kind == INTRO_OPERATION {{ {tags["ops"]} }} else {{ 0 }})',
 'dynamic_term':f'(if {row}.tag == EXPR_ARG || {row}.tag == EXPR_RESULT {{ {tags["contracts"]} }} else {{ {tags["binders"]} }})',
 'dynamic_sub':f'(if {row}.kind == KIND_TYPE {{ {tags["types"]} }} else if {row}.kind == KIND_NAT {{ {tags["terms"]} }} else {{ {tags["binders"]} }})',
 'dynamic_capture':f'(if {row}.kind == KIND_TYPE {{ {tags["types"]} }} else {{ {tags["terms"]} }})',
 'dynamic_relocation':f'(if {row}.kind == STATIC_ADDRESS {{ {tags["static_objects"]} }} else if {row}.kind == STATIC_FUNCTION {{ {tags["functions"]} }} else if {row}.kind == STATIC_DICTIONARY {{ {tags["types"]} }} else {{ {tags["ops"]} }})',
 'dynamic_relocation_addend':f'(if {row}.kind == STATIC_CLOSURE {{ {tags["static_objects"]} }} else {{ 0 }})',
 'dynamic_op':f'operation_reference({row}.tag)',}[role]
b='''// Generated explicit table relocation; runtime implementation is Goose only.
// External definitions are projections, never copied historical implementations.
namespace relocation;
import src.model;
import src.canonical;
struct Projection { source_definition:u32, target_definition:u32 }
struct Ref { table:u32, id:u32 }
struct Pair { table:u32, source:u32, target:u32 }
let PENDING:u32 = 0xffffffff;
fn operation_reference(tag:u32) -> u32 {
'''
b+=f'''    if tag == OP_CALL || tag == OP_CLOSURE || tag == OP_FN_PLACE || tag == OP_GENERIC_BIND {{ return {tags['functions']}; }}
    if tag == OP_TRY_ALLOC || tag == OP_LAYOUT_SIZE || tag == OP_LAYOUT_ALIGN {{ return {tags['types']}; }}
    if tag == OP_NAT_VALUE || tag == OP_REGION_RESET {{ return {tags['binders']}; }}
    if tag == OP_STATIC {{ return {tags['static_objects']}; }}
    return 0;
}}
fn relocate_function(source:Core, source_definition:u32, target:CoreBuilder, target_definition:u32,
                     projections:const Projection[:], work:Work&) -> bool {{
    if !id_ok(source_definition,source.definitions.len) || !id_ok(target_definition,target.definitions.len) {{ return false; }}
    let original=source.definitions[source_definition]; let replacement=target.definitions[target_definition];
    if original.kind != DEF_FUNCTION || replacement.kind != DEF_FUNCTION || original.function == 0 || replacement.function != 0 || replacement.type_id == 0 {{ return false; }}
'''
for n,t in tables:b+=f'    var map_{n}:u32[>..]=[]; for row in source.{n} {{ map_{n}.push(0); }}\n'
b+='''    var queue:Ref[>..]=[]; var paired:Pair[>..]=[];
    fn tick() { if !charge(work,1,LIMIT_VISITS) { return false from relocate_function; } }
    fn mapped(table:u32,id:u32) -> u32 {
        if id == 0 || table == 0 { return id; }
'''
for n,t in tables:b+=f'        if table == {tags[n]} {{ return map_{n}[id]; }}\n'
b+='''        return 0;
    }
    fn assign(table:u32,id:u32,value:u32) {
'''
for n,t in tables:b+=f'        if table == {tags[n]} {{ map_{n}[id]=value; return; }}\n'
b+='''    }
    fn pair(table:u32,a:u32,b:u32) {
        tick(); if a == 0 || b == 0 { if a != b { return false from relocate_function; } return; }
        let old=mapped(table,a); if old != 0 { if old != b { return false from relocate_function; } return; }
        assign(table,a,b); paired.push(Pair {table,a,b});
    }
    fn pair_span(table:u32,a:Span,b:Span) {
        if a.count != b.count { return false from relocate_function; }
        for i in a.count { pair(table,source.refs[a.start+i],target.refs[b.start+i]); }
    }
    fn project(a:u32,b:u32) {
        tick(); if !id_ok(a,source.definitions.len) || !id_ok(b,target.definitions.len) { return false from relocate_function; }
        let x=source.definitions[a]; let y=target.definitions[b];
        if x.kind != y.kind || name_bytes(source,x.name) != name_bytes(core_view(target),y.name) ||
            name_bytes(source,source.modules[x.module].path) != name_bytes(core_view(target),target.modules[y.module].path) { return false from relocate_function; }
        var left:u8[>..]=[]; var right:u8[>..]=[];
        if !canonical_interface(source,x.type_id,left) || !canonical_interface(core_view(target),y.type_id,right) || left != right { return false from relocate_function; }
'''
b+=f'''        map_definitions[a]=b; map_modules[x.module]=y.module;
        if a != source_definition {{ if x.function != 0 {{ if y.function == 0 {{ return false from relocate_function; }} map_functions[x.function]=y.function; }} }}
        if x.kind == DEF_STATIC {{
            if !id_ok(x.value,source.values.len) || !id_ok(y.value,target.values.len) {{ return false from relocate_function; }}
            let old_op=source.values[x.value].op; let new_op=target.values[y.value].op;
            if old_op == 0 || new_op == 0 || source.ops[old_op].tag != OP_STATIC || target.ops[new_op].tag != OP_STATIC {{ return false from relocate_function; }}
            let a=source.ops[old_op].imm0; let b=target.ops[new_op].imm0; let old_static=source.static_objects[a]; let new_static=target.static_objects[b];
            if old_static.kind != new_static.kind || old_static.count != new_static.count || old_static.relocations.count != 0 || new_static.relocations.count != 0 ||
                source.bytes[old_static.bytes.start..old_static.bytes.start+old_static.bytes.count] != target.bytes[new_static.bytes.start..new_static.bytes.start+new_static.bytes.count] {{ return false from relocate_function; }}
            map_values[x.value]=y.value; map_ops[old_op]=new_op; map_static_objects[a]=b;
        }}
        pair({tags['types']},x.type_id,y.type_id); pair_span({tags['binders']},x.binders,y.binders);
    }}
    project(source_definition,target_definition);
    for projection in projections {{ if projection.source_definition == source_definition {{ return false; }} project(projection.source_definition,projection.target_definition); }}
    var cursor:i64=0;
    while cursor < paired.len {{
        tick(); let item=paired[cursor]; cursor++;
'''
# Interface graph pair fields only; external scopes/origins are not semantic identities.
interface={'types','fields','contracts','effects','binders','terms','facts'}
for n,t in tables:
 if n not in interface:continue
 b+=f'        if item.table == {tags[n]} {{ let row=source.{n}[item.source]; let other=target.{n}[item.target];\n'
 for f,ty in structs[t]:
  role=roles[n].get(f)
  if f in ('origin','scope','introduction','introduction_kind','name') or not role:continue
  if role in ('bytes','omit','raw'):continue
  if ty=='Span':b+=f'            pair_span({tag(role)},row.{f},other.{f});\n'
  else:b+=f'            pair({tag(role)},row.{f},other.{f});\n'
 b+='        }\n'
b+='''    }
    fn mark(table:u32,id:u32) {
        tick(); if id == 0 || table == 0 || mapped(table,id) != 0 { return; }
'''
b+=f'''        if table == {tags['definitions']} {{ return false from relocate_function; }}
        if table == {tags['functions']} && source.functions[id].producer != 0 && source.functions[id].producer != source_definition {{ return false from relocate_function; }}
        if table == {tags['modules']} {{
            let path=name_bytes(source,source.modules[id].path);
            for row,index in target.modules {{ tick(); if index != 0 && path == name_bytes(core_view(target),row.path) {{ map_modules[id]=index as u32; return; }} }}
            return false from relocate_function;
        }}
        assign(table,id,PENDING); queue.push(Ref {{table,id}});
    }}
    fn mark_span(table:u32,span:Span) {{ for i in span.count {{ mark(table,source.refs[span.start+i]); }} }}
    mark({tags['functions']},original.function);
    cursor=0;
    var scanned:i64=-1;
    while cursor < queue.len || scanned != queue.len {{
        if cursor == queue.len {{
            scanned=queue.len;
            for row,id in source.evidence {{
                if id == 0 {{ continue; }} var scope=row.scope;
                for depth in 65 {{
                    if scope == 0 {{ break; }}
                    if map_scopes[scope] == PENDING {{ mark({tags['evidence']},id as u32); break; }}
                    scope=source.scopes[scope].parent;
                }}
            }}
            for row,id in source.loops {{ if id != 0 && map_functions[source.blocks[row.header].function] == PENDING {{ mark({tags['loops']},id as u32); }} }}
            for row,id in source.interfaces {{ if id != 0 && map_functions[row.function] == PENDING {{ mark({tags['interfaces']},id as u32); }} }}
            for row,id in source.receipts {{ if id != 0 && row.producer == source_definition {{ mark({tags['receipts']},id as u32); }} }}
            for row,id in source.callable_adapters {{ if id != 0 && map_ops[row.op] == PENDING {{ mark({tags['callable_adapters']},id as u32); }} }}
            if cursor == queue.len {{ break; }}
        }}
        tick(); let item=queue[cursor]; cursor++;
'''
for n,t in tables:
 b+=f'        if item.table == {tags[n]} {{ let row=source.{n}[item.id];\n'
 if n=='origins':
  b+='''            if row.module != original.module || row.start < source.origins[original.origin].start || row.end > source.origins[original.origin].end { return false; }
'''
 for f,ty in structs[t]:
  role=roles[n].get(f)
  if not role or role in ('bytes','omit','raw'):continue
  if ty=='Span':b+=f'            mark_span({tag(role)},row.{f});\n'
  else:b+=f'            mark({tag(role)},row.{f});\n'
 b+='        }\n'
b+='''    }
    // No optional decline occurs after this point. The owning build transaction
    // handles process allocation failure and atomically publishes only validation.
'''
# Assign all maps and reserve destinations except terms copied afterward with exact intern.
for n,t in tables:
 if n in ('modules','definitions','terms'):continue
 b+=f'''    for value,id in map_{n} {{ if value == PENDING {{ map_{n}[id]=target.{n}.len as u32; target.{n}.push({t} {{..}}); }} }}\n'''
b+='''    fn span(table:u32,old:Span) -> Span {
        let result=Span {start:target.refs.len as u32,count:old.count};
        for i in old.count { target.refs.push(mapped(table,source.refs[old.start+i])); } return result;
    }
    fn bytes(old:Span) -> Span {
        let result=Span {start:target.bytes.len as u32,count:old.count}; target.bytes.append(source.bytes[old.start..old.start+old.count]); return result;
    }
'''
# Terms original order is guaranteed topological, preserve and intern source IDs in new graph.
b+='''    for old,id in source.terms {
        if id == 0 || map_terms[id] != PENDING { continue; }
        var row=old;
'''
for f,ty in structs['Term']:
 role=roles['terms'].get(f)
 if not role:continue
 b+=f'        row.{f}='+ (f'span({tag(role)},old.{f});\n' if ty=='Span' else f'mapped({tag(role)},old.{f});\n')
b+='''        var existing:u32=0;
        for candidate,index in target.terms {
            if index == 0 { continue; }
            if row.tag == EXPR_LITERAL && candidate.tag == EXPR_LITERAL && row.literal == candidate.literal { existing=index as u32; break; }
            if row.tag == EXPR_BINDER && candidate.tag == EXPR_BINDER && row.binder == candidate.binder { existing=index as u32; break; }
        }
        if existing == 0 { existing=target.terms.len as u32; target.terms.push(row); }
        map_terms[id]=existing;
    }
'''
for n,t in tables:
 if n in ('modules','definitions','terms'):continue
 b+=f'''    for item in queue {{ if item.table != {tags[n]} {{ continue; }} let old=source.{n}[item.id]; var row=old;\n'''
 for f,ty in structs[t]:
  role=roles[n].get(f)
  if not role:continue
  if role=='omit':b+=f'        row.{f}=0;\n'
  elif role=='bytes':b+=f'        row.{f}=bytes(old.{f});\n'
  elif ty=='Span':b+=f'        row.{f}=span({0 if role=="raw" else tag(role)},old.{f});\n'
  else:b+=f'        row.{f}=mapped({tag(role)},old.{f});\n'
 if n=='origins':b+='''        row.start=replacement.origin != 0 ? old.start : old.start;
'''.replace('        row.start=replacement.origin != 0 ? old.start : old.start;\n','''        row.start=old.start-source.origins[original.origin].start+target.origins[replacement.origin].start;
        row.end=old.end-source.origins[original.origin].start+target.origins[replacement.origin].start;
''')
 b+=f'        target.{n}[map_{n}[item.id]]=row;\n    }}\n'
b+='''    target.definitions[target_definition].function=map_functions[original.function];
    return true;
}
'''
destination=root/'src/relocate.goose'
if '--check' in sys.argv:
    if not destination.exists() or destination.read_text()!=b:
        print('stale generated file: '+str(destination),file=sys.stderr)
        raise SystemExit(1)
else:
    destination.write_text(b)
