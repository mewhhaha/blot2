"""The existing 24 checker controls, parameterized for reproducible inputs."""
from pathlib import Path
import hashlib,json,os,subprocess,time

def run(args):
    work=args.output/'semantic';work.mkdir(parents=True,exist_ok=True)
    cases=work/'controls';cases.mkdir(exist_ok=True)
    candidate=args.goose;baseline=args.baseline
    built={'binary':str(candidate),'sha256':hashlib.sha256(candidate.read_bytes()).hexdigest()}
    stdlib=args.stdlib;upstream=args.upstream/'test'
    manifest=args.fixtures
    started=time.monotonic();results=[]
    def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
    def run(binary,mode,source,extra=(),env=None):
     command=[str(binary),mode,str(source),'--stdlib',str(stdlib),*map(str,extra)]
     p=subprocess.run(command,capture_output=True,text=True,timeout=10,env=env)
     return p

    def compare(name,source,expected,*,intentional=False,signature=False):
     row={'name':name,'source':str(source),'source_sha256':sha(source),'runs':{}}
     for label,binary in [('baseline',baseline),('closure',candidate)]:
      p=run(binary,'check',source,('--diagnostics','json'))
      (work/(name+'.'+label+'.stdout')).write_text(p.stdout)
      (work/(name+'.'+label+'.stderr')).write_text(p.stderr)
      wanted=expected
      if intentional and label=='closure':wanted=0
      assert p.returncode==wanted,(name,label,p.returncode,p.stdout,p.stderr)
      row['runs'][label]={'exit':p.returncode,'diagnostics':json.loads(p.stdout),'profile_absent':'GOOSE_CHECKER_PROFILE' not in p.stderr}
     if not intentional:
      left=row['runs']['baseline']['diagnostics'];right=row['runs']['closure']['diagnostics']
      if signature:
       primary=lambda items:[{k:v for k,v in d.items() if k not in ('text','related')} for d in items]
       assert primary(left)==primary(right),row
       row['signature_primary_unchanged']=True
       row['standalone_body_chain_omitted']=left!=right
      else:assert left==right,row
     else:row['intentional_dead_body_omission']=True
     results.append(row)

    for c in manifest['store_controls']:
     source=upstream/(c['id'].removeprefix('upstream/')+'.goose')
     expected=0
     if c['phase']=='type-error':expected=1
     compare(c['file'].removesuffix('.goose'),source,expected)
     if c['phase']=='run':
      for binary in (baseline,candidate):
       p=run(binary,'run',source);assert p.returncode==c['expect']['exit'] and p.stdout==c['expect']['stdout'],(c,p.stdout,p.stderr)
      results[-1]['runtime_unchanged']=True
    for name,path in [
     ('global_initializer','errors_tc/global_before_init_call.goose'),
     ('global_fixup','errors_tc/shrink_global_initializer.goose'),
     ('function_value','errors_tc/branch_join_arrays_function_value.goose'),
     ('live_thread','errors_tc/thread_global.goose'),
     ('nongeneric_type','errors_tc/struct_contains_itself.goose')]:compare(name,upstream/path,1)
    compare('dead_body',upstream/'errors_tc/unreached_param_hazard.goose',0)
    custom={
     'dead_param': 'fn dead(x: varint) {}\nfn main() {}\n',
     'dead_return': 'fn dead() -> varint { return 0; }\nfn main() {}\n',
     'dead_signature_names': 'let N = 2;\nfn dead(N: i64) -> i64[N] { return [1, 2]; }\nfn main() {}\n',
     'unspawned_thread': 'thread_fn worker() { let x: i64 = true; print(x); }\nfn main() {}\n',
     'uncalled_export': 'export fn exported() -> i64 { return true; }\nfn main() {}\n',
    }
    for name,text in custom.items():
     source=cases/(name+'.goose');source.write_text(text);compare(name,source,1,signature=name in ('dead_param','dead_return'))
    # Runtime function values remain roots through a real overloaded stdlib caller.
    source=upstream/'typing/overloaded_function_values.goose';compare('live_function_values',source,0)
    a=run(baseline,'run',source);b=run(candidate,'run',source)
    assert a.returncode==b.returncode==0 and a.stdout==b.stdout,(a.stdout,a.stderr,b.stdout,b.stderr)
    results[-1]['runtime_unchanged']=True

    # The upstream unused-extern adapter law requires types for uncalled externs.
    source=cases/'unused_extern.goose';source.write_text('''struct Input { values: i16[2] }
struct Result { value: i32 }
extern fn sum(values: const f32[:]) -> f32 = "native_sum";
extern fn input(value: const Input&) -> i32 = "native_input";
extern fn result() -> Result = "native_result";
extern fn missing(values: const f64[:]) = "native_missing";
fn main() { print("extern types passed"); }
''')
    header=cases/'adapter.h';header.write_text('''static float native_sum(sl_f32 values) { return (float)values.len; }
static int32_t native_input(Input_g *value) { return value->values_g.e[0]; }
static Result_g native_result(void) { Result_g result = { 42 }; return result; }
static int64_t adapter_length(sl_f64 values) { return values.len; }
''')
    for label,binary in [('baseline',baseline),('closure',candidate)]:
     cfile=cases/(label+'-extern.c');p=run(binary,'--standalone',source,('--include',header,'-o',cfile));assert p.returncode==0,(label,p.stdout,p.stderr)
     exe=cfile.with_suffix('');compile=subprocess.run([str(args.cc),'-std=c11','-O0','-Werror=implicit-function-declaration',str(cfile),'-pthread','-lm','-o',str(exe)],capture_output=True,text=True,timeout=15)
     assert compile.returncode==0,(label,compile.stdout,compile.stderr)
     p=subprocess.run([str(exe)],capture_output=True,text=True,timeout=5);assert p.returncode==0 and p.stdout=='extern types passed\n'
    results.append({'name':'unused_extern_adapter_types','both_emit_compile_link_run':True,'source_sha256':sha(source),'adapter_sha256':sha(header)})

    # Export-only library roots still get a usable C ABI wrapper.
    source=cases/'library.goose';source.write_text('export "answer" fn exported() -> i64 { return 42; }\n')
    for label,binary in [('baseline',baseline),('closure',candidate)]:
     cfile=cases/(label+'-library.c');header=cases/(label+'-library.h')
     p=run(binary,'--standalone',source,('--header',header,'-o',cfile));assert p.returncode==0,(label,p.stdout,p.stderr)
     caller=cases/(label+'-caller.c');caller.write_text('#include "'+header.name+'"\nint main(void) { goose_init(0, 0); if (answer() != 42) return 1; return 0; }\n')
     exe=cases/(label+'-library');p=subprocess.run([str(args.cc),'-std=c11','-O0',str(cfile),str(caller),'-pthread','-lm','-o',str(exe)],capture_output=True,text=True,timeout=15)
     assert p.returncode==0,(label,p.stdout,p.stderr)
     p=subprocess.run([str(exe)],capture_output=True,text=True,timeout=5);assert p.returncode==0,p.stderr
    results.append({'name':'export_library_abi','both_emit_compile_link_run':True,'source_sha256':sha(source)})

    source=cases/'partial.goose';source.write_text('fn selected() { print(1); }\nfn dead() { let bad: i64 = true; }\nfn main() {}\n')
    for binary in (baseline,candidate):
     env=dict(os.environ);env['GOOSE_DIAGNOSTIC_ROOTS']='selected'
     p=run(binary,'check',source,env=env);assert p.returncode==0 and 'PARTIAL selected-root diagnostics' in p.stderr,(p.stdout,p.stderr)
    results.append({'name':'selected_root_mode','both_partial_pass':True})

    source=cases/'profile.goose';source.write_text('var value: i64 = 1;\nexport fn exported() -> i64 { return value; }\nthread_fn worker() {}\nfn dead(x: i64) -> i64 { return x + 1; }\nfn read(xs: i64[:]) -> i64 { return xs[0]; }\nfn main() { var xs: i64[>..] = []; xs.push(1); print(read(xs)); print(read(xs)); print(exported()); }\n')
    env=dict(os.environ);env.pop('GOOSE_DIAGNOSTIC_ROOTS',None);env.pop('GOOSE_CHECKER_PROFILE',None)
    off=run(candidate,'check',source,env=env);env['GOOSE_CHECKER_PROFILE']='1';on=run(candidate,'check',source,env=env)
    assert off.returncode==on.returncode==0 and off.stdout==on.stdout,(off.stdout,off.stderr,on.stdout,on.stderr)
    lines=on.stderr.splitlines();stripped='\n'.join(line for line in lines if not line.startswith('GOOSE_CHECKER_PROFILE'))+'\n'
    assert off.stderr==stripped,(off.stderr,stripped)
    phases=[line.split('phase=')[1].split()[0] for line in lines if line.startswith('GOOSE_CHECKER_PROFILE') and ' phase=' in line]
    assert phases==['parse','resolve','roots.globals','roots.declarations','roots.main','roots.threads','roots.export_bodies','roots.dead','roots.exports','roots.fixups','typecheck','optimize','bce'],phases
    (work/'profile.log').write_text(on.stderr)
    cache_rows={}
    for line in lines:
     if line.startswith('GOOSE_CHECKER_PROFILE cache='):
      fields=dict(item.split('=',1) for item in line.split()[1:])
      name=fields.pop('cache');cache_rows[name]={key:int(value) for key,value in fields.items()}
    expected_caches={'stable.type','stable.contain','stable.identity','stable.reaches','array.elements'}
    if 'struct ReferenceClosures {' in (args.source/'src/typecheck.h').read_text():expected_caches.add('reach.closure')
    assert set(cache_rows)==expected_caches,cache_rows
    assert sum(row['hits'] for row in cache_rows.values())>0,cache_rows
    assert cache_rows['array.elements']['rejected']==cache_rows['array.elements']['building']+cache_rows['array.elements']['unstable']
    (work/'cache-profile.json').write_text(json.dumps(cache_rows,indent=2)+'\n')
    # Profiling cannot change generated C, using the exact same emission pathname.
    cfile=cases/'same-profile.c';offenv=dict(env);offenv.pop('GOOSE_CHECKER_PROFILE')
    a=run(candidate,'--standalone',source,('-o',cfile),offenv);before=sha(cfile)
    b=run(candidate,'--standalone',source,('-o',cfile),env);after=sha(cfile)
    assert a.returncode==b.returncode==0 and before==after
    results.append({'name':'observational_profile','phases':phases,'stdout_stderr_unchanged_except_profile':True,'same_path_C_unchanged':before==after,'C_sha256':after})
    report={'binary':built,'baseline':str(baseline),'baseline_sha256':sha(baseline),'seconds':round(time.monotonic()-started,3),'controls':results,'default_source_pin':'652b36d0039864a5a2bc9f6220f86bf08da77624f53a650ff15fe61e6914eded','mode':'both builds reachable-program; only stable successful closure publication and query counters differ','whole_port_qualification':False}
    (work/'control-results.json').write_text(json.dumps(report,indent=2)+'\n')
    return report
