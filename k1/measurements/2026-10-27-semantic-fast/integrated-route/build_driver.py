#!/usr/bin/env python3
import hashlib,json,os,pathlib,platform,shutil,subprocess
import benchmark
p=pathlib.Path(__file__).resolve().parent
sha=lambda f:hashlib.sha256(pathlib.Path(f).read_bytes()).hexdigest()
goose=pathlib.Path(os.environ.get('GOOSE','/tmp/k1-goose/build/goose')).resolve()
node=pathlib.Path(shutil.which('node')).resolve()
cc=pathlib.Path(shutil.which(os.environ.get('CC','cc'))).resolve()
before,ext=benchmark.dependencies()
cmd=[str(goose),'build','-O2','-o',str(benchmark.DRIVER),str(benchmark.K/'semantic_job_bench.goose')]
x=subprocess.run(cmd,capture_output=True,text=True,check=True)
after,ext_after=benchmark.dependencies()
if before!=after or ext!=ext_after:raise RuntimeError('input changed during build')
log=p/'build.log';log.write_text(x.stdout+x.stderr)
record={'command':cmd,'goose_home':os.environ.get('GOOSE_HOME'),'goose_sha256':sha(goose),'node_sha256':sha(node),'cc_path':str(cc),'cc_sha256':sha(cc),'cc_version':subprocess.check_output([str(cc),'--version'],text=True).splitlines()[0],'platform':platform.platform(),'dependencies':before,'external_imports':ext,'binary_sha256':sha(benchmark.DRIVER),'build_log_sha256':sha(log)}
(p/'build-record.json').write_text(json.dumps(record,indent=2)+'\n')
print('built baseline and candidate in one binary; source and tool hashes recorded')
