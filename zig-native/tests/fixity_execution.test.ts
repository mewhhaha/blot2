import {compileAndRun, compileExpectedFailure, equal} from './compile_helpers.ts';
Deno.test('no prelude requires a declared symbolic producer and keeps named calls lexical',async()=>{
  await compileExpectedFailure('entry const answer=20+22\n','unknown_operator',undefined,{prelude:'none'});
  for(const source of [
    'entry const answer=func()=> return do:\n  let minus=func left=> return func right=> return @u32.sub left right\n  break 50 `minus` 8\n',
    'infixl 60 (+)=combine\nconst combine=func left=> return func right=> return @u32.sub left right\nentry const answer=func()=> return do:\n  let combine=func left=> return func right=> return @u32.add left right\n  break 50+8\n',
    'infixl 60 `combine`\nconst combine=func left=> return func right=> return @u32.add left right\nentry const answer=func()=> return do:\n  let combine=func left=> return func right=> return @u32.sub left right\n  break 50 `combine` 8\n',
  ]) await compileAndRun(source,guest=>equal(guest.call('answer',null),42),{prelude:'none'});
});
Deno.test('the real prelude captures its inherited symbolic producer through local target shadowing',async()=>{
  await compileAndRun('entry const answer=func()=> return do:\n  let add=func left=> return func right=> return @u32.sub left right\n  break 20+22\n',guest=>equal(guest.call('answer',null),42));
});
