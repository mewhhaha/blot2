import {compileAndRun, compileExpectedFailure, equal} from './compile_helpers.ts';

Deno.test('use bindings retain bare typed and nested function annotations',async()=>{
 for(const source of [
  'entry const run=func()=> return do:\n  use value<-42\n  break value\n',
  'entry const run=func()=> return do:\n  use value:U32<-20\n  break @u32.add value 22\n',
  'entry const run=func()=> return do:\n  use next:(U32->U32)<-func value=> return @u32.add value 1\n  break next 41\n',
 ])await compileAndRun(source,guest=>{equal(guest.call('run',null),42);},{prelude:'none'});
});

Deno.test('use witnesses preserve source name checking and stop before the next binding',async()=>{
 for(const source of [
  'const bad=func()=> return do:\n  use value:U32\n  break 42\n',
  'const bad=func()=> return do:\n  use Value:U32\n  break 42\n',
  'entry const run=func(value:U32)=> return do:\n  use value:U32\n  use next:U32<-42\n  break next\n',
 ])await compileExpectedFailure(source,'unknown_value',undefined,{prelude:'none'});
});
