# Source-writing migration for the earlier unsupported Goose defer spelling.
# Named continuations return normally; explicit cleanup then runs in the owner.
# Loop/branch-scoped cleanup remains a separate manual writing task.
from pathlib import Path
import re

def tokens(source):
    pattern = re.compile(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|[A-Za-z_][A-Za-z_0-9]*|::|->|[^\s]')
    return [(m.group(), m.start(), m.end()) for m in pattern.finditer(source) if not m.group().startswith(('//','/*'))]

def lower(source):
    serial = 0
    while True:
        ts = tokens(source)
        pairs = {}
        parents = {}
        stack = []
        for i,(value,_,_) in enumerate(ts):
            parents[i] = stack[-1] if stack else -1
            if value in ('{','(','['): stack.append(i)
            elif value in ('}',')',']'):
                if stack:
                    opening = stack.pop()
                    pairs[opening] = i
        functions = []
        for i,(value,_,_) in enumerate(ts):
            if value != 'fn' or i+1 == len(ts) or not re.fullmatch(r'[A-Za-z_][A-Za-z_0-9]*',ts[i+1][0]): continue
            j=i+2
            while j+1 < len(ts) and ts[j][0]=='::': j+=2
            if j < len(ts) and ts[j][0]=='<':
                depth=1; j+=1
                while j<len(ts) and depth:
                    if ts[j][0]=='<': depth+=1
                    elif ts[j][0]=='>': depth-=1
                    j+=1
            if j>=len(ts) or ts[j][0]!='(' or j not in pairs: continue
            end_params=pairs[j]; j=end_params+1
            arrow=None
            if j<len(ts) and ts[j][0]=='->': arrow=j; j+=1
            angle=0
            while j<len(ts):
                value=ts[j][0]
                if value=='<': angle+=1
                elif value=='>': angle-=1
                if value=='{' and angle==0: break
                if value==';' and angle==0: break
                j+=1
            if j>=len(ts) or ts[j][0]!='{' or j not in pairs: continue
            result=''
            if arrow is not None: result=source[ts[arrow][2]:ts[j][1]].strip()
            functions.append((j,pairs[j],result))
        selected=None
        for opening,closing,result in reversed(functions):
            candidates=[i for i in range(opening+1,closing) if ts[i][0]=='defer' and parents[i]==opening and i+1<closing and ts[i+1][0]=='{']
            if candidates:
                selected=(opening,closing,result,candidates[-1]); break
        if selected is None: return source
        opening,closing,result,d=selected
        cleanup_open=d+1; cleanup_close=pairs[cleanup_open]
        after=ts[cleanup_close][2]
        if cleanup_close+1<len(ts) and ts[cleanup_close+1][0]==';': after=ts[cleanup_close+1][2]
        cleanup=source[ts[cleanup_open][2]:ts[cleanup_close][1]]
        suffix=source[after:ts[closing][1]]
        serial+=1
        name=f'cleanup_continuation_{serial}'
        signature=''
        if result: signature=' -> '+result
        count=0
        if result:
            count=1; depth=0
            for value,_,_ in tokens(result):
                if value in ('<','(','['): depth+=1
                elif value in ('>',')',']'): depth-=1
                elif value==',' and depth==0: count+=1
        names=[f'cleanup_result_{serial}_{i}' for i in range(count)]
        invocation=f'{name}();'
        returned='return;'
        if names:
            invocation='let '+','.join(names)+' = '+invocation
            returned='return '+','.join(names)+';'
        replacement='\n    recursive fn '+name+'()'+signature+' {\n'+suffix+'\n    }\n    '+invocation+'\n    '+cleanup+'\n    '+returned+'\n'
        source=source[:ts[d][1]]+replacement+source[ts[closing][1]:]

owned='''runtime_ir byte_encoder wasm_simd_ops wasm_control_flow runtime_flags runtime_code simd_intrinsics collection_ops scalar_ops runtime_identity discarded_bindings bottom_result wasm_local_order runtime_function_key runtime_body_relocation collector_contract machine_code_sharing known_call simd_call scalar_consumer storage_span_dominance opaque_storage packed_layout numeric_rows provider_chain runtime_operations layout backend_timing allocation_emission storage_input_alias acyclic_layout storage_type_key empty_root_scopes host_cleanup_shapes backend_plan backend_representations layout_bridge host_entry resolved_body resolved_call resolved_flow unit_index core_backend wasm scoped_backend backend_emission private_cursor safe_local_sinking inline_body function_facts collection_edit_call collection_iteration exact_builder ragged_builder list_traversal substitution_buffers'''.split()
paths=[Path('compiler-goose/src/backend')/(name+'.goose') for name in owned]
paths += [Path('compiler-goose/src/eval/specialization.goose'),Path('compiler-goose/src/support/json.goose'),Path('compiler-goose/src/support/path.goose')]
for path in paths:
    if not path.exists(): continue
    old=path.read_text(); new=lower(old)
    if new!=old:
        path.write_text(new)
        print('Explicit cleanup written:',path)
