from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parent/'cases';root.mkdir(exist_ok=True)
h=lambda a,r:f'pub let f: {a} -> {r} ! {{}} resources {{depth: 1, frame: 0}} = fn x => '
cases={
 'u32_identity':h('U32','U32')+'return x\n',
 'u32_less':h('U32','Bool')+'return x < 7\n',
 'bool_identity':h('Bool','Bool')+'return x\n',
 'bool_branch':h('Bool','U32')+'do:\n  if x:\n    return 7\n  return 3\n',
 'u32_loop':h('U32','U32')+'do:\n  let out = for i in 0..x carry (a=17) do:\n    next (i)\n  return out\n',
 'u32_wrapping':h('U32','U32')+'do:\n  return U32.wrapping_add(x,1)\n',
 'invalid_unbound':h('U32','U32')+'return missing\n',
 'invalid_type':h('Bool','U32')+'return x\n',
 'invalid_unproved':h('U32','U32')+'return x + 1\n',
 'invalid_effect':'pub let f: U32 -> U32 ! {reserve} resources {depth: 1, frame: 0} = fn x => return x\n',
 'invalid_missing_return':h('Bool','U32')+'do:\n  if x:\n    return 1\n',
}
for n,s in cases.items():(root/(n+'.blot')).write_text(s)
manifest={n:hashlib.sha256((root/(n+'.blot')).read_bytes()).hexdigest() for n in cases}
(root/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
