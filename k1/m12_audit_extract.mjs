import {readFileSync,writeFileSync} from 'node:fs';
import {inspect} from './i08_machine_inspect.mjs';
import {decode} from './i08_machine_decode.mjs';
const bytes=readFileSync(process.argv[2]);if(!inspect(bytes).ok)throw Error('source-checked guarded target required');
const g=decode(bytes);let bodies={};for(const f of [1,4,5,6,8,11,12,13])bodies[f]=g.bodies[f].ops.map(({op,imm})=>({op,imm}));
writeFileSync(process.argv[3],JSON.stringify(bodies));
