"""Bounded upstream-Goose acceptance with diagnostics kept out of the terminal."""
from pathlib import Path
import argparse,collections,json,math,os,re,signal,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--phase',choices=['parse','check'],default='parse');p.add_argument('--area',default='');p.add_argument('--log',default='current');p.add_argument('--timeout',type=float,default=30);p.add_argument('--entry',default='compiler-goose/src/main.goose');p.add_argument('--goose',type=Path);p.add_argument('--keep-going',action='store_true');args=p.parse_args()
if not math.isfinite(args.timeout) or args.timeout<=0:p.error('--timeout must be positive and finite')
compiler=args.goose or ROOT.parent/'goose-to-wasm/build/native/goose';stdlib=ROOT.parent/'goose-to-wasm/build/source/stdlib';log=ROOT/'build/goose-port/verification'/f'{args.log}.log';log.parent.mkdir(parents=True,exist_ok=True)
command=[str(compiler),'--'+args.phase,'--diagnostics',('text' if args.phase=='check' else 'json'),'--stdlib',str(stdlib),args.entry]
started=time.monotonic()
with log.open('w') as stream:
 child=subprocess.Popen(command,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT,start_new_session=True)
 first_error=None;stopped=False
 try:
  while child.poll() is None:
   elapsed=time.monotonic()-started
   if elapsed>=args.timeout:
    try:os.killpg(child.pid,signal.SIGKILL)
    except ProcessLookupError:pass
    child.wait();status=124;break
   if args.phase=='check' and not args.keep_going:
    current=log.read_text()
    if ': error:' in current:
     if first_error is None:first_error=time.monotonic()
     if time.monotonic()-first_error>=0.2:
      try:os.killpg(child.pid,signal.SIGKILL)
      except ProcessLookupError:pass
      child.wait();status=1;stopped=True;break
   time.sleep(0.05)
  else:status=child.returncode
 except KeyboardInterrupt:
  try:os.killpg(child.pid,signal.SIGKILL)
  except ProcessLookupError:pass
  child.wait();status=130
elapsed=time.monotonic()-started;text=log.read_text();items=[]
try:items=json.loads(text)
except json.JSONDecodeError:
 try:items=json.JSONDecoder().raw_decode(text[text.index('['):])[0]
 except (json.JSONDecodeError,ValueError):pass
errors=[i for i in items if i.get('severity')=='error']
if not errors:
 for match in re.finditer(r'^(.+?):(\d+): error: (.+)$',text,re.M):
  errors.append({'file':match[1],'line':int(match[2]),'message':match[3],'severity':'error'})
selected=[e for e in errors if args.area in e.get('file','')]
print(json.dumps({'exit':status,'seconds':round(elapsed,3),'errors':len(errors),'stopped_on_error':stopped,'selected':len(selected),'log':str(log)}))
print(json.dumps(collections.Counter(e.get('message','') for e in selected).most_common(8)))
for e in selected[:12]:print(json.dumps({k:e.get(k) for k in ['file','line','col','message']}))
if not errors:print(text[:1500])
raise SystemExit(status)
