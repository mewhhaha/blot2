from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1] / 'src'
# Source authoring only. Emit finite JSON overloads from the current model;
# never compile, execute or claim to verify a Goose module.
def clean(s):
 out=[];i=0
 while i<len(s):
  if s.startswith('//',i):
   end=s.find('\n',i);i=len(s) if end<0 else end;continue
  if s.startswith('/*',i):
   end=s.find('*/',i+2);i=len(s) if end<0 else end+2;continue
  if s[i] in '\"\'':
   q=s[i];j=i+1
   while j<len(s):
    if s[j]=='\\':j+=2;continue
    if s[j]==q:j+=1;break
    j+=1
   out.append(s[i:j]);i=j;continue
  out.append(s[i]);i+=1
 return ''.join(out)
def balanced(s,start,op='{',cl='}'):
 depth=1;i=start+1
 while i<len(s):
  c=s[i]
  if c in '\"\'':
   q=c;i+=1
   while i<len(s):
    if s[i]=='\\':i+=2;continue
    if s[i]==q:break
    i+=1
  elif c==op:depth+=1
  elif c==cl:
   depth-=1
   if depth==0:return i
  i+=1
 raise ValueError('unterminated authoring declaration')
def split(s,sep=','):
 out=[];start=0;i=0;stack=[]
 while i<len(s):
  c=s[i]
  if c in '\"\'':
   q=c;i+=1
   while i<len(s):
    if s[i]=='\\':i+=2;continue
    if s[i]==q:break
    i+=1
  elif c in '[{(<':stack.append(c)
  elif c in ']})>':
   if stack:stack.pop()
  elif c==sep and not stack:out.append(s[start:i].strip());start=i+1
  i+=1
 if s[start:].strip():out.append(s[start:].strip())
 return out
def fields(body):
 result=[]
 for item in split(body):
  name,ty=item.split(':',1);ty=split(ty,'=')[0].strip()
  result.append((name.strip(),ty))
 return result

SKIP = {'support/json_adapters.goose'}
models = {}
custom = {}
arrays = set()
imports = set()
primitives = {'bool','u8','u16','u32','u64','i8','i16','i32','i64','f32','f64'}
for path in sorted(ROOT.rglob('*.goose')):
    if path.relative_to(ROOT).as_posix() in SKIP:
        continue
    text = clean(path.read_text())
    match = re.search(r'\bnamespace\s+(\w+)\s*;', text)
    if match is None:
        continue
    ns = match[1]
    module = path.relative_to(ROOT).with_suffix('').as_posix().replace('/','.')
    for match in re.finditer(r'\benum\s+(\w+)\s*\{', text):
        end = balanced(text, match.end()-1)
        models[ns+'::'+match[1]] = ('{' in text[match.end():end], module)
    for match in re.finditer(r'\bfn\s+jsonStringify\s*(?:<([^>]+)>)?\s*\(', text):
        if ns == 'blot_json':
            continue
        end = balanced(text, match.end()-1, '(', ')')
        parameters = split(text[match.end():end])
        if not parameters or ':' not in parameters[0]:
            continue
        receiver = parameters[0].split(':',1)[1].strip()
        receiver = re.sub(r'^const\s+', '', receiver).rstrip('&').strip()
        if receiver.startswith('blot_'):
            qualified = receiver
        else:
            qualified = ns+'::'+receiver
        if match[1]:
            generic = match[1]
        else:
            generic = None
        body = text.find('{', end)
        returns_error = '->' in text[end:body]
        output_bytes = len(parameters) > 1 and 'u8[' in parameters[1]
        custom[qualified] = (ns, generic, module, returns_error, output_bytes)
    for match in re.finditer(r'\b(?:struct|enum)\s+\w+\s*\{', text):
        end = balanced(text, match.end()-1)
        for raw in re.finditer(r'(?<![\w:])(?:const\s+)?((?:\w+::)?\w+)\s*\[(\d+)\]', text[match.end():end]):
            inner, width = raw.groups()
            if inner not in primitives and '::' not in inner:
                inner = ns+'::'+inner
            arrays.add((inner, int(width), module))

out = ['// Generated source by tools/write_json_adapters.py; unverified.',
       '// Exact overloads keep custom wire projections and enum tags explicit.',
       'namespace blot_json;', 'import support.json;']
for _, (_, module) in models.items():
    imports.add(module)
for _, (_, _, module, _, _) in custom.items():
    imports.add(module)
for _, _, module in arrays:
    imports.add(module)
out.extend('import '+module+';' for module in sorted(imports) if module != 'support.json')
for name, (payload, _) in sorted(models.items()):
    if name in custom:
        continue
    implementation = 'unionValue' if payload else 'enumValue'
    out.append('fn write(writer:Writer&,value:'+name+')->blot_error::Error {return '+implementation+'(writer,value);}')
for name, (ns, generic, _, returns_error, output_bytes) in sorted(custom.items()):
    type_parameters = ''
    if generic:
        type_parameters = '<'+generic+'>'
    prefix = 'fn write'+type_parameters+'(writer:Writer&,value:'+name+')->blot_error::Error {'
    prefix += 'if writer.failure!=blot_error::Error.none {return writer.failure;}'
    if output_bytes:
        body = 'var bytes:u8[>..]=[];'+ns+'::jsonStringify(value,bytes);return write(writer,Raw{bytes[:]});'
    elif returns_error:
        body = 'let error='+ns+'::jsonStringify(value,writer);if error!=blot_error::Error.none {return fail(writer,error);}return writer.failure;'
    else:
        body = ns+'::jsonStringify(value,writer);return writer.failure;'
    out.append(prefix+body+'}')
seen = set()
for inner, width, _ in sorted(arrays):
    key = (inner,width)
    if key in seen:
        continue
    seen.add(key)
    # Fixed arrays are JSON arrays, including u8; only byte slices are strings.
    out.append('fn write(writer:Writer&,values:'+inner+'['+str(width)+'])->blot_error::Error {let opened=beginArray(writer);if opened!=blot_error::Error.none {return opened;}for value in values {let error=element(writer,value);if error!=blot_error::Error.none {return error;}}return endArray(writer);}')
(ROOT/'support/json_adapters.goose').write_text('\n'.join(out)+'\n')
