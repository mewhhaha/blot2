"""Authoring helpers: retain all heads, shard sink dispatch by nominal namespace."""
from pathlib import Path
import re
from source_model import clean,balanced,split
ROOT=Path(__file__).resolve().parents[1]/'src'
_registry_cache=None
def registry():
 global _registry_cache
 if _registry_cache is not None:return _registry_cache
 nominal={};aliases={}
 for p in ROOT.rglob('*.goose'):
  s=clean(p.read_text());m=re.search(r'\bnamespace\s+(\w+)\s*;',s)
  if not m:continue
  ns=m[1]
  for d in re.finditer(r'\b(?:struct|enum)\s+(\w+)',s):nominal[ns+'::'+d[1]]=ns
  for d in re.finditer(r'\btype\s+(\w+)\s*=\s*([^;]+);',s):aliases[ns+'::'+d[1]]=(d[2].strip(),ns)
 _registry_cache=(nominal,aliases);return _registry_cache

def owner_namespace(ty,fallback):
 nominal,aliases=registry();ty=ty.strip();seen=set();context=''
 while True:
  ty=re.sub(r'^const\s+','',ty).strip().rstrip('&?').strip()
  if ty.endswith(']'):return fallback
  m=re.match(r'([\w:]+)',ty)
  if not m:return fallback
  key=m[1]
  if '::' not in key and context:key=context+'::'+key
  if key in nominal:return nominal[key]
  if key not in aliases or key in seen:return fallback
  seen.add(key);ty,context=aliases[key]

def function_spans(source,names):
 for m in re.finditer(r'(?m)^fn\s+([\w:]+)(<[^\n(]*>)?\(',source):
  name=m[1]
  if name not in names:continue
  end=balanced(source,m.end()-1,'(',')');body=source.index('{',end);finish=balanced(source,body)+1
  yield {'start':m.start(),'end':finish,'name':name,'generic':m[2] or '', 'parameters':split(source[m.end():end]),'returns':source[end+1:body],'body':source[body:finish]}

def qualify_body(body,family):
 if family=='blot_structural':names=['hash','hashFields']
 else:names=['write','fail','jsonStringify','enumValue','unionValue','beginObject','endObject','beginArray','endArray','key','field','element','nullValue','quoted','unsignedValue','signedValue','sourceName']
 pattern=r'(?<![\w:.])('+ '|'.join(names)+r')\('
 body=re.sub(pattern,lambda m:family+'::'+m[1]+'(',body)
 if family=='blot_json':body=re.sub(r'(?<![\w:])Raw\s*\{','blot_json::Raw{',body)
 return body

def rehead(decl,family):
 params=decl['parameters'];assert len(params)==2,decl
 first,receiver=params;_,ty=receiver.split(':',1)
 ns=owner_namespace(ty,family)
 if family=='blot_structural':name='blotStructuralHash'
 else:name='blotJsonWrite'
 first=first.replace('writer: Writer&','writer: blot_json::Writer&')
 return 'fn '+ns+'::'+name+decl['generic']+'('+receiver+','+first+')'+decl['returns']+qualify_body(decl['body'],family)

def transformed_custom_types(source):
 result=set()
 for m in re.finditer(r'fn\s+(?:\w+::)?blotStructuralHash(?:<[^\n(]*>)?\(',source):
  end=balanced(source,m.end()-1,'(',')');params=split(source[m.end():end]);ty=params[0].split(':',1)[1].strip();result.add(re.sub(r'^const\s+','',ty).rstrip('&').strip())
 return result

def write_generated(target,source,family):
 # A head's body/width/custom projection is retained, only UFCS receiver order
 # and explicit namespace lookup change. Equal heads are intentionally untouched.
 if family=='blot_structural':wanted={'hash'}
 else:wanted={'write'}
 for decl in reversed(list(function_spans(source,wanted))):source=source[:decl['start']]+rehead(decl,family)+source[decl['end']:]
 if family=='blot_json':
  namespace_text=source+'\n'+'\n'.join(p.read_text() for p in ROOT.rglob('*.goose') if p!=target)
  namespaces=sorted({m[1] for m in re.finditer(r'fn\s+(blot_\w+)::blotJsonWrite',namespace_text) if m[1]!=family})
  for ns in namespaces:source+='\nfn '+ns+'::blotJsonWrite<T>(value:T?,writer:blot_json::Writer&)->blot_error::Error {if value==null {return blot_json::nullValue(writer);}return blot_json::write(writer,value);}\n'
 target.write_text(source)
