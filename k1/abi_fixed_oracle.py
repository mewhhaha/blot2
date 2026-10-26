# Independent literal transcription of ABI_PROFILE_SCHEMA.md, using bytearray
# and int.to_bytes rather than the component encoder or its generator.
import re
from pathlib import Path
rows = [
(1,1,'4 1 4 0'),(1,2,'0 1 0 0'),(1,3,'4 4 32 1'),(1,4,'4 4 2 0 1'),(1,5,'4 4 32 1'),(1,6,'4 4 1 1'),(1,7,'1 1 1'),(1,8,'4 4 4 1 1'),(1,9,'1 0 1 0 0'),(1,10,'4 1 0 0'),(1,11,'1 0 0'),(1,12,'64 32 64 32 256 256'),
(2,1,'2 1 2'),(2,2,'2 1 3'),(2,3,'2 1 4'),(2,4,'3 1 2 3'),(2,5,'2 5 6'),(2,6,'2 5 6'),(2,7,'2 5 6'),(2,8,'2 5 6'),(2,9,'2 7 8'),(2,10,'4 9 10 11 12'),
(3,1,'65536 4096 32 256 1073741824 4096 16777216 128 16777216 256 1048576 65536 65536'),(3,2,'8 1 2 3 4 5 6 7 8'),(3,3,'5 0 1 2 3 4'),(3,4,'4 1 2 3 4 0 0 0 0'),
(4,1,'4 1 2 4 4294967288'),(4,2,'5 1 2 3 4 5'),(4,3,'1 0 1 0'),(4,4,'1 2 1'),(4,5,'1 128 1'),
(6,1,'1261502465 32 8 1 2 3 4 5 6 7 8'),(6,2,'7 0 1 2 3 4 5 6'),(6,3,'2 1 2')]
write=lambda n: int(n).to_bytes(4,'little')
out=bytearray(b'K1FIX001'); out+=write(1)+write(len(rows))
for section,number,line in rows:
    fields=line.split()
    for n in (section,number,1,len(fields)*4): out+=write(n)
    for n in fields: out+=write(n)
source=Path(__file__).with_name('abi_fixed_test.goose').read_text()
hexes=re.findall(r'hex.append\("([0-9a-f]+)"\)',source)
assert bytes(out)==bytes.fromhex(''.join(hexes)), 'vector mismatch'
print('independent 34-record golden matches',len(out),'bytes')
