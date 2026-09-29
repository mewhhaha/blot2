#!/usr/bin/env python3
"""Produce the native core from audited source, with flat semantic identities.

The strict source frontend is retained as a semantic bridge. Normal builds
generate native modules from the current Bend sources, then compile them with
OCaml; running the resulting compiler needs neither Python nor Bend.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
from source_port import Emitter, ml_var, ml_string, write_checked_outputs, BASE_FUNCTIONS
from syntax import Node, load_modules

BASE_FUNCTIONS.update({name: name.lower().replace('.', '_') for name in ('Map.diff.chr', 'Maybe.map', 'U32.xor')})

IDENTIFIED = {
 'model': {'TypeId','RowTail','EffectRow','Ty','ValueReference','Pattern','Predicate',
   'Expr','Function','Constant','Module','Operation','Constructor','DataType','Effect',
   'Signature','CheckedFunction','CheckedConstant','CheckedModule'},
 'types': {'Substitutions'}, 'groups': {'Interface'}, 'dependency': {'Node'},
 'infer': {'Binding'},
}

class Flat(Emitter):
 def definition(self, name):
  parts=name.split('.',1)
  module=self.modules[self.module.imports[parts[0]]] if len(parts)==2 else self.module
  ty=next((t for t in module.types if any(n==parts[-1] for n,_ in t.constructors)),None)
  if ty and ty.name in IDENTIFIED.get(module.name,set()):
   return module.name,ty,parts[0]+'.' if len(parts)==2 else ''
  return None

 def meta_count(self, module, ty, ctor, fields):
  if not fields: return 0
  return 2 if module=='model' and ty.name=='Ty' else 1

 def type(self, ty, variables=None):
  if self.module.name in ('native_io','native_request') and ty.kind in ('type','name') and ty.value=='Array':
   args=[t for t in ty.items if t.kind!='multiplicity']
   if args and args[0].value=='U32': return 'bytes'
  if ty.kind in ('type','name') and ty.value=='NatIndex.Index':
   args=[t for t in ty.items if t.kind!='multiplicity']
   if args and args[0].value=='List' and any(str(t.value).split('.')[-1]=='Version' for t in args[0].items):
    return '('+self.type(args[0],variables)+') Core_index.t'
  return super().type(ty,variables)

 def expression(self,n,scope,variables,monad=None):
  exp=lambda x:self.expression(x,scope,variables,monad)
  if n.kind=='char':return f'(Chr {n.value})'
  if n.kind=='constructor' and n.value=='Chr':return '(Base.char_of_u32 '+exp(n.items[0])+')'
  if n.kind=='constructor':
   found=self.definition(n.value)
   if found:
    module,ty,prefix=found
    ctor=n.value.split('.')[-1]
    return '('+prefix+'make_'+ctor+(' '+' '.join('('+exp(v)+')' for v in n.items) if n.items else ' ()')+')'
   if n.value in ('SNil','SCon'):
    return '(Base.make_Text '+self.constructor(n.value,[exp(x) for x in n.items])+')'
  if n.kind=='call' and n.items[0].kind=='name':
   callee,args=n.items
   kept=[v for v in args if not self.is_type_value(v,variables)]
   if callee.value in ('NatIndex.new','NatIndex.get','NatIndex.set') and args and args[0].value=='List' and any(str(t.value).split('.')[-1]=='Version' for t in args[0].items):
    if callee.value=='NatIndex.new':return 'Core_index.empty'
    if callee.value=='NatIndex.get':return '(Option.value (Core_index.find '+exp(kept[1])+' '+exp(kept[0])+') ~default:'+exp(kept[2])+')'
    return '(Core_index.add '+exp(kept[1])+' '+exp(kept[2])+' '+exp(kept[0])+')'
   if callee.value=='Array.get' and self.module.name=='native_request' and args[0].value=='U32':
    return '(Base.word_buffer_get '+exp(kept[0])+' '+exp(kept[1])+')'
   # Semantically pure alternatives. No mutable request-decoder operation is
   # changed by this demand-preserving specialization of Boolean combinators.
   if self.module.name not in ('native_request','native_io','native_transport'):
    if callee.value=='Bool.pick' and len(kept)==3:
     return '(if '+exp(kept[0])+' then '+exp(kept[1])+' else '+exp(kept[2])+')'
    if callee.value in ('Bool.and','Bool.or') and len(kept)==2:
     return '('+exp(kept[0])+(' && ' if callee.value=='Bool.and' else ' || ')+exp(kept[1])+')'
  return super().expression(n,scope,variables,monad)

 def pattern(self,node):
  guards,bindings,names=[],[],set()
  from collections import Counter
  counts=Counter()
  def count(n):
   if n.kind=='name' and n.value!='_':counts[n.value]+=1
   for child in n.items:
    if isinstance(child,Node):count(child)
  count(node)
  def go(n):
   k=n.kind
   if k=='name':
    if n.value!='_':
     names.add(n.value)
     if counts[n.value]>1:
      tmp=self.fresh('shadow');bindings.append((ml_var(n.value),tmp));return tmp
    return ml_var(n.value)
   if k=='nat':return str(n.value)
   if k=='u32':return f'0x{n.value:08x}l'
   if k=='char':return f'(Chr {n.value})'
   if k=='string':
    if n.value not in self.strings:self.strings[n.value]='s_'+str(len(self.strings))
    tmp=self.fresh('text');guards.append(f'Base.string_eq {tmp} {self.strings[n.value]}');return tmp
   if k=='constructor':
    if n.value=='Chr':
     if n.items[0].kind=='u32':return f'(Chr {n.items[0].value})'
     tmp=self.fresh('char');pat=go(n.items[0]);bindings.append((pat,f'Int32.of_int {tmp}'));return f'(Chr {tmp})'
    if n.value in ('SNil','SCon'):
     tmp=self.fresh('text');oldg,oldb=len(guards),len(bindings)
     raw=self.constructor(n.value,[go(v) for v in n.items])
     innerg,innerb=guards[oldg:],bindings[oldb:];del guards[oldg:];del bindings[oldb:]
     guards.append(f'(match (Base.text_node {tmp}) with {raw} -> '+(' && '.join(innerg) or 'true')+' | _ -> false)')
     bindings.append((raw,'(Base.text_node '+tmp+')'));bindings.extend(innerb);return tmp
    found=self.definition(n.value);meta=[]
    if found:
     module,ty,_=found;meta=['_']*self.meta_count(module,ty,n.value.split('.')[-1],n.items)
    return self.constructor(n.value,meta+[go(v) for v in n.items])
   if k=='tuple':return '('+', '.join(go(v) for v in n.items)+')'
   if k=='list':return '['+'; '.join(go(v) for v in n.items)+']'
   if k=='annotate':return go(n.items[0])
   if k=='binary' and n.value=='<>':return '('+go(n.items[0])+' :: '+go(n.items[1])+')'
   if k=='binary' and n.value=='+':
    count=0;tail=n
    while tail.kind=='binary' and tail.value=='+' and tail.items[0].kind=='nat':
     count+=tail.items[0].value;tail=tail.items[1]
    if tail.kind=='nat':return str(count+tail.value)
    if tail.kind!='name':raise ValueError('unsupported natural pattern')
    tmp=self.fresh('nat');guards.append(f'{tmp} >= {count}')
    if tail.value!='_':names.add(tail.value);bindings.append((ml_var(tail.value),f'({tmp} - {count})'))
    return tmp
   raise ValueError(f'{self.module.name}:{n.line}: unsupported pattern {k}')
  return go(node),guards,bindings,names

 def value_function(self,ty,hashing):
  if ty.kind=='call' and ty.items[0].kind=='name':ty=Node('type',ty.items[0].value,ty.items[1],ty.line)
  name=ty.value;args=[t for t in ty.items if t.kind!='multiplicity']
  if name in ('List','Maybe'):
   f=self.value_function(args[0],hashing);kind='list' if name=='List' else 'option'
   return '(Core_nodes.'+kind+('_hash ' if hashing else '_equal ')+f+')'
  if name=='String':return 'Base.text_hash' if hashing else 'Base.string_eq'
  parts=name.split('.',1);module=self.modules[self.module.imports[parts[0]]] if len(parts)==2 else self.module
  if parts[-1] in IDENTIFIED.get(module.name,set()):
   f=(parts[0]+'.' if len(parts)==2 else '')+'id_'+parts[-1]
   return f if hashing else '(fun a b -> '+f+' a = '+f+' b)'
  if parts[-1]=='MatchArm':
   body=self.value_function(args[0],hashing)
   if hashing:return '(fun (MatchArm (ps,e)) -> Core_nodes.mix (Core_nodes.list_hash id_Pattern ps) ('+body+' e))'
   return '(fun (MatchArm (ps,e)) (MatchArm (qs,f)) -> Core_nodes.list_equal (fun a b -> id_Pattern a = id_Pattern b) ps qs && '+body+' e f)'
  return 'Hashtbl.hash' if hashing else '(=)'

 def factories(self):
  # Native metadata is only valid for this explicitly reviewed type/row schema.
  # A new constructor or changed field must fail the build, never silently be
  # classified as closed/ground by a default metadata arm.
  if self.module.name == 'model':
   expected = {
    'Ty': {'UnitTy':0,'U32Ty':0,'BoolTy':0,'AppliedTy':2,'FunctionTy':3,
     'ParameterTy':1,'VariableTy':1,'NeverTy':0,'F32Ty':0,'ProviderTy':2,
     'StateProviderTy':3,'EffectDescriptorTy':0,'EffectSetTy':0,'ProductTy':1,
     'ArrayTy':1,'FreeTy':2},
    'RowTail': {'ClosedRow':0,'RowVariable':1,'RowParameter':1,'FreeRow':2},
    'EffectRow': {'EffectRow':2},
   }
   for ty in self.module.types:
    if ty.name in expected and {name:len(fields) for name,fields in ty.constructors} != expected[ty.name]:
     raise ValueError(f'Native metadata schema changed: model.{ty.name}; review its layout and metadata before building')
  out=[]
  # ID accessors are available before mutual-reference shape hashing.
  for t in self.module.types:
   if t.name not in IDENTIFIED.get(self.module.name,set()):continue
   arms=[]
   for ctor,fields in t.constructors:
    n=self.meta_count(self.module.name,t,ctor,fields)
    if not fields:
     out.append('let id_'+ctor+' = Core_nodes.fresh_id ()');arms.append('| '+ctor+' -> id_'+ctor)
    else:arms.append('| '+self.constructor(ctor,['identity']+['_']*(n-1+len(fields)))+' -> identity')
   out.append('let id_'+t.name+' = function\n'+'\n'.join(arms))
  if self.module.name=='model':
   out.append('''let type_cost = function
 | AppliedTy (_,info,_,_) | FunctionTy (_,info,_,_,_) | StateProviderTy (_,info,_,_,_)
 | ProviderTy (_,info,_,_) | ProductTy (_,info,_) | ArrayTy (_,info,_)
 | VariableTy (_,info,_) | ParameterTy (_,info,_) | FreeTy (_,info,_,_) -> info lsr 2
 | _ -> 1
let type_flags = function
 | AppliedTy (_,info,_,_) | FunctionTy (_,info,_,_,_) | StateProviderTy (_,info,_,_,_)
 | ProviderTy (_,info,_,_) | ProductTy (_,info,_) | ArrayTy (_,info,_)
 | VariableTy (_,info,_) | ParameterTy (_,info,_) | FreeTy (_,info,_,_) -> info land 3
 | _ -> 0
let pack_type cost flags = ((min 65537 cost) lsl 2) lor flags
let row_flags = function EffectRow (_,_,RowVariable _) -> 2 | _ -> 0
let list_type_info xs =
 let index=ref 0 and cost=ref 1 and flags=ref 0 in
 List.iter (fun ty -> incr index; cost := max !cost (!index + type_cost ty); flags := !flags lor type_flags ty) xs;
 pack_type (1 + max (!index + 1) !cost) !flags''')
  for t in self.module.types:
   if t.name not in IDENTIFIED.get(self.module.name,set()):continue
   unique=(self.module.name,t.name) in [('types','Substitutions'),('infer','Binding')]
   for ctor,fields in t.constructors:
    a=[f'a{i}' for i in range(len(fields))]
    if not fields:out.append('let make_'+ctor+' () = '+ctor);continue
    args=['Core_nodes.fresh_id ()']
    if self.module.name=='model' and t.name=='Ty':
     info={
      'VariableTy':'pack_type 1 1',
      'FunctionTy':'pack_type (1 + max (type_cost a0) (type_cost a1)) (type_flags a0 lor type_flags a1 lor row_flags a2)',
      'ProviderTy':'pack_type 1 (row_flags a1)',
      'StateProviderTy':'pack_type (1 + type_cost a2) (type_flags a2)',
      'ArrayTy':'pack_type (1 + type_cost a0) (type_flags a0)',
      'AppliedTy':'list_type_info a1','ProductTy':'list_type_info a0',
     }.get(ctor,'pack_type 1 0')
     args.append(info)
    value=self.constructor(ctor,['('+v+')' for v in args]+a)
    if unique:
     out.append('let make_'+ctor+' '+' '.join(a)+' = '+value)
    else:
     keytype=' * '.join(self.type(ty) for _,ty in fields)
     key= a[0] if len(a)==1 else '('+', '.join(a)+')'
     b=[f'b{i}' for i in range(len(fields))]
     other= b[0] if len(b)==1 else '('+', '.join(b)+')'
     eq=' && '.join('('+self.value_function(ty,False)+' '+x+' '+y+')' for (_,ty),x,y in zip(fields,a,b))
     h='31'
     for (_,ty),x in zip(fields,a):h='Core_nodes.mix ('+h+') ('+self.value_function(ty,True)+' '+x+')'
     out.append('module Table_'+ctor+' = Core_nodes.Table(struct\n type t = '+keytype+'\n let equal '+key+' '+other+' = '+eq+'\n let hash '+key+' = '+h+'\nend)')
     out.append('let table_'+ctor+' = Domain.DLS.new_key (fun () -> Table_'+ctor+'.create 128)')
     enabled='!Core_nodes.enabled'+('' if t.name in ('TypeId','Ty','EffectRow','RowTail') else ' && !Core_nodes.intern_bodies')
     out.append('let make_'+ctor+' '+' '.join(a)+' =\n if '+enabled+' then begin\n  let table = Table_'+ctor+'.current (Domain.DLS.get table_'+ctor+') in\n  let key = '+key+' in\n  Core_nodes.note "nodes.requests";\n  match Table_'+ctor+'.H.find table key with\n  | value -> Core_nodes.note "nodes.reused"; value\n  | exception Not_found ->\n    let value = '+value+' in\n    Core_nodes.note "nodes.created";\n    Table_'+ctor+'.H.add table key value; value\n end else '+value)

  return out

 def native_headers(self):
  if self.module.name=='types':return ['''module PairCache = Core_nodes.Cache(struct type t = int * int let equal = (=) let hash = Hashtbl.hash end)
module TypeCache = Core_nodes.Cache(struct type t = int let equal = (=) let hash x = x end)
let resolve_cache = Domain.DLS.new_key (fun () -> PairCache.create "resolve")
let row_cache = Domain.DLS.new_key (fun () -> PairCache.create "rows")
let free_cache = Domain.DLS.new_key (fun () -> TypeCache.create "free")''']
  if self.module.name=='groups':return ['''module GraphIdentity = Core_nodes.Identity(struct
 type t = D.t_Node list
 let equal a b = a == b
 let hash = function [] -> 0 | h :: _ -> D.id_Node h
end)
let graph_identities = Domain.DLS.new_key GraphIdentity.create
module GroupCache = Core_nodes.Cache(struct
 type t = int * int list * int * bool
 let equal = (=)
 let hash (body, dependencies, graph, collect) = Core_nodes.mix body (Core_nodes.mix (Core_nodes.list_hash (fun x -> x) dependencies) (Core_nodes.mix graph (Hashtbl.hash collect)))
end)
let group_cache = Domain.DLS.new_key (fun () -> GroupCache.create "groups")''']
  if self.module.name=='infer':return ['''module Scope = Core_scopes.Make(struct
 type t = t_Binding
 let id = id_Binding
 let name = function Binding (_,name,_,_,_) -> name
end)
module OpenBindings = Core_scopes.Filter(struct
 type t = t_Binding
 let id = id_Binding
 let keep = function Binding(_,_,ty,_,predicates) ->
   predicates <> [] || M.type_flags ty <> 0 || M.type_cost ty > 65536
end)''']
  return []

 def native_body(self,f,body):
  name=f.name
  if self.module.name=='index' and name=='find':return 'Base.map_find v_index v_name'
  if self.module.name=='index' and name=='string_bit':return '(if v_character >= Base.string_length v_name then false else v_offset = 0 || ((Core_text.at v_name v_character) lsr (max 0 (32-v_offset))) land 1 <> 0)'
  if self.module.name=='index' and name=='advance_suffix':return 'Base.string_drop v_remaining v_distance'
  if self.module.name=='native_request' and name=='scan_string':return """(if v_valid && Base.string_length v_reversed = 0 then
  let Cursor(words,offset,remaining,strings,string_count)=v_cursor in
  let limit=min v_count remaining in
  let rec validate index =
    if index=limit then None else
    let code=Base.u32_to_nat (Bytes.get_int32_le words (4*(offset+index))) in
    if code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff) then Some index
    else validate(index+1)
  in
  match validate 0 with
  | Some index -> InvalidCharacter(offset+index)
  | None when v_count > remaining -> TruncatedString(offset+remaining)
  | None -> CompleteString(Base.text_of_words words offset v_count, Cursor(words,offset+v_count,remaining-v_count,strings,string_count))
 else """+body+')'
  if self.module.name=='types':
   if name in ('unify_at','unify_rows_at'):
    if name=='unify_at':
     norm='match f_resolve v_substitutions v_left, f_resolve v_substitutions v_right with\n | Done left, Done right -> Core_graph_verify.verify v_subject expected (Core_graph_verify.Value left) (Core_graph_verify.Value right)\n | _ -> Core_graph_verify.normalization_failure ()'
    else:
     norm='Core_graph_verify.verify v_subject expected (Core_graph_verify.Effect (f_resolve_row v_substitutions v_left)) (Core_graph_verify.Effect (f_resolve_row v_substitutions v_right))'
    return '(let answer = '+body+' in\n if !Core_graph_verify.enabled then begin\n  let expected=match answer with Done _ -> Ok () | Fail (M.Diagnostic(code,_,_)) -> Error (Base.text_to_utf8 code) in\n  '+norm+'\n end; answer)'
   if name=='resolve_reference':return '(if M.type_flags v_ty = 0 && M.type_cost v_ty <= 65536 then (Core_nodes.note "resolve.ground"; Done v_ty) else PairCache.memo (Domain.DLS.get resolve_cache) (id_Substitutions v_substitutions, M.id_Ty v_ty) (fun () -> '+body+'))'
   if name=='resolve_row':return '(PairCache.memo (Domain.DLS.get row_cache) (id_Substitutions v_substitutions, M.id_EffectRow v_row) (fun () -> '+body+'))'
   if name=='free':return '(TypeCache.memo (Domain.DLS.get free_cache) (M.id_Ty v_ty) (fun () -> '+body+'))'
  if self.module.name=='infer' and name=='generalizable_variables':return """(match v_candidates with
 | [] -> Done []
 | _ ->
   let Context(globals,locals,labels,_,_,_,_,ambient)=v_context in
   let subs=f_substitutions_of v_state in
   let relevant=Base.list_append (OpenBindings.select globals)
    (Base.list_append (OpenBindings.select locals) (f_label_bindings labels)) in
   match f_binding_free (Base.list_append relevant (f_annotation_bindings (f_annotation_types v_state))) subs with
   | Fail error -> Fail error
   | Done excluded -> Done(T.f_difference v_candidates
      (T.f_union v_blocked (T.f_union excluded (T.f_row_free (T.f_resolve_row subs ambient))))))"""
  if self.module.name=='infer' and name=='lookup_binding':return '(if !Core_nodes.scope_enabled then Scope.lookup v_bindings v_name else '+body+')'
  if self.module.name=='model':
   if name=='name_equal':return 'Base.string_eq v_left v_right'
   if name=='type_id_equal':return '(id_TypeId v_a = id_TypeId v_b || '+body+')'
  if self.module.name=='core_compare':
   kind={'same_module':'Module','same_type':'DataType','same_predicate':'Predicate','same_operation':'Operation','same_ty':'Ty','same_expr':'Expr'}.get(name)
   if kind:
    a,b=[ml_var(p.name) for p in f.parameters if not p.erased]
    return '(M.id_'+kind+' '+a+' = M.id_'+kind+' '+b+' || '+body+')'
  if self.module.name=='groups' and name=='check_group_resolving_graph':return '(match v_graph_result with Fail _ -> '+body+' | Done graph -> GroupCache.memo (Domain.DLS.get group_cache) (M.id_Module v_module, List.map id_Interface v_dependencies, GraphIdentity.get (Domain.DLS.get graph_identities) graph, v_collect) (fun () -> '+body+'))'
  if self.module.name=='infer' and name=='expr_work':return '(Core_nodes.note "inference.steps"; '+body+')'
  return body

 def emit(self):
  header=[f'(* Native core migration from compiler/{self.module.name}.bend.\n Source SHA-256: {self.module.digest}\n Flat identities and native query hooks are specified by bootstrap/generate.py.\n No generated Bend C/JavaScript is edited or executed. *)','open Base']
  for alias,name in self.module.imports.items():header.append(f'module {alias} = Sem_{name}')
  types=[]
  for t in self.module.types:
   variables=set(t.parameters);args=["'"+v.lower() for v in t.parameters]
   prefix='' if not args else (args[0]+' ' if len(args)==1 else '('+', '.join(args)+') ')
   parts=[prefix+'t_'+t.name+' =']
   for ctor,fields in t.constructors:
    n=self.meta_count(self.module.name,t,ctor,fields) if t.name in IDENTIFIED.get(self.module.name,set()) else 0
    payload=['int']*n+[self.type(ty,variables) for _,ty in fields]
    parts.append(' | '+ctor+(' of '+' * '.join(payload) if payload else ''))
   types.append('\n'.join(parts))
  for name in sorted(self.aliases):
   f=self.functions[name]
   if f.parameters:raise ValueError('parameterized alias unsupported')
   types.append('t_'+name+' = '+self.type(f.body))
  if types:header.append('type '+'\nand '.join(types))
  header.extend(self.factories());header.extend(self.native_headers())
  declarations=[]
  for f in self.module.functions:
   if f.name in self.aliases:continue
   parameters=[p for p in f.parameters if not p.erased];variables={p.name for p in f.parameters if p.erased}
   scope={p.name for p in parameters};signature=' -> '.join(([self.type(p.type,variables) for p in parameters] or ['unit'])+[self.type(f.result,variables)])
   quant=' '.join("'"+v.lower() for v in sorted(variables))+'. ' if variables else ''
   body=self.native_body(f,self.expression(f.body,scope,variables))
   declarations.append(f'(* {self.module.name}.bend:{f.line} *)\nf_{f.name} : {quant}{signature} =\nfun '+(' '.join(ml_var(p.name) for p in parameters) or '()')+' ->\n'+body)
  for value,name in self.strings.items():header.append('let '+name+' = Base.text_of_utf8 '+ml_string(value))
  if declarations:header.append('let rec '+'\nand '.join(declarations))
  return '\n\n'.join(header)+'\n'

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--source',type=Path,default=Path(__file__).resolve().parents[2])
 parser.add_argument('--output',type=Path,default=Path(__file__).resolve().parents[1]/'semantic')
 args=parser.parse_args();modules=load_modules(args.source,'native_main');lookup={m.name:m for m in modules}
 outputs={};manifest=[]
 for m in modules:
  if m.name=='native_transport':continue
  text=Flat(m,lookup).emit();name='sem_'+m.name+'.ml';outputs[name]=text
  manifest.append({'module':m.name,'source_sha256':m.digest,'native_sha256':hashlib.sha256(text.encode()).hexdigest(),'functions':len(m.functions),'types':len(m.types)})
 outputs['manifest.json']=json.dumps(manifest,indent=2)+'\n';outputs['modules.txt']='\n'.join('sem_'+m.name for m in modules)+'\n'
 write_checked_outputs(args.output,outputs)
 print(f'Wrote {len(manifest)} source-derived modules; native transport is independently reviewed.')
if __name__=='__main__':main()
