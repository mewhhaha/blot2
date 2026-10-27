import {strict as assert} from 'node:assert';
import {readFileSync} from 'node:fs';
import {inspectLinked} from './m11_linked.mjs';
const target=readFileSync('private-invoke.wasm'),resource=readFileSync('m11-source-resource.bin'),ok=inspectLinked(target,resource);
assert(ok.ok);assert.equal(ok.actualMachineDepth,6);assert.deepEqual(ok.sourceContractDepths,[2,3]);assert.equal(ok.wrapperSourceArithmeticLowerBound,4);
assert.equal(ok.declaredEnvelope,688);assert.equal(ok.physicalReservation,768);assert(ok.adapterAndShimFrameAccesses>0);
assert.equal(ok.helperFrameEffectsQualified,false);assert.equal(ok.callerWorkerDynamicAccessesQualified,false);assert.equal(ok.m11Qualified,false);
for(let i=0;i<resource.length;i++){const b=Uint8Array.from(resource);b[i]^=1;assert(!inspectLinked(target,b).ok);assert(!inspectLinked(target,resource.subarray(0,i)).ok);}
for(let i=0;i<target.length;i++){const b=Uint8Array.from(target);b[i]^=1;assert(!inspectLinked(b,resource).ok);assert(!inspectLinked(target.subarray(0,i),resource).ok);}
console.log('private source resources and adapter/shim frame access composition passed');
