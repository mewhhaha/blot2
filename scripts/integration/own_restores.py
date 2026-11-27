"""Rewrite calls of Ink's persist restore helpers for their owned form.

Usage: python3 scripts/integration/own_restores.py FILE...   (paths under ../gdev)

Each restore helper now takes what it restores with `own` and returns it
(ink/lib/persist.sq). A call that stood as a statement on fields of the
world becomes a call whose results are put back:

  persist.restore_resource C I access.x S V O
    -> access.x := persist.restore_resource C I access.x S V O
  persist.restore_alive S V access.a access.b O
    -> let (restored_a, restored_b) = ...; access.a := ...; access.b := ...
  persist.restore_component / restore_snapshotted_resource /
  restore_snapshotted_component: the same with two or four parts
  persist.restore_into C D R access S V O
    -> access := persist.restore_into C D R access S V O
"""
import re,sys,os
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
import ownify
ROOT=ownify.ROOT
# helper -> positions (in the argument atoms) of the parts it returns
PARTS={'restore_resource':[2],'restore_alive':[2,3],'restore_component':[3,4],
       'restore_snapshotted_resource':[2,3],'restore_snapshotted_component':[4,5,6,7]}
def rewrite(lines):
    changed=0; out=[]; n=0
    for l in lines:
        m=re.match(r'^(\s*)persist\.(restore_\w+) (.*)$',l)
        if not m: out.append(l); continue
        ind,helper,rest=m.group(1),m.group(2),m.group(3)
        if helper=='restore_into':
            a=ownify.atoms(rest)
            # one that goes on below (its callbacks written in place) is left to the reader
            if len(a)<7: out.append(l); print(f'  left: {l.strip()[:90]}'); continue
            out.append(f'{ind}{a[3]} := persist.restore_into {rest}'); changed+=1; continue
        if helper not in PARTS: out.append(l); continue
        if re.match(r'^\s*(let|\w+ :=)',l): out.append(l); continue
        a=ownify.atoms(rest); places=[a[i] for i in PARTS[helper]]
        if len(places)==1:
            out.append(f'{ind}{places[0]} := persist.{helper} {rest}'); changed+=1; continue
        n+=1
        names=[f'restored_{n}_{k}' for k in range(len(places))]
        out.append(f'{ind}let ({", ".join(names)}) = persist.{helper} {rest}')
        for place,name in zip(places,names): out.append(f'{ind}{place} := {name}')
        changed+=1
    return out,changed
if __name__=='__main__':
    for rel in sys.argv[1:]:
        path=os.path.join(ROOT,rel); lines=open(path).read().split('\n')
        out,changed=rewrite(lines)
        if changed: open(path,'w').write('\n'.join(out)); print(f'{rel}: {changed} calls')
