import {compileAndRun, compileExpectedFailure, equal} from './compile_helpers.ts';
Deno.test('fixed built-in operators work without prelude and reject custom operators',async()=>{
  await compileExpectedFailure('entry const answer = 20 >< 22\n','unknown_operator',undefined,{prelude:'none'});
  await compileExpectedFailure('infixl 60 (+) = add\nentry const answer = 20 + 22\n','GPU_FRONTEND_SYNTAX_ERROR',undefined,{prelude:'none'});
  await compileAndRun('entry const answer = func () => return 20 + 22\n',guest=>equal(guest.call('answer',null),42),{prelude:'none'});
  await compileAndRun('func inc x => return x + 2\nentry const answer = func () => return 40 |> inc\n',guest=>equal(guest.call('answer',null),42),{prelude:'none'});
});
Deno.test('built-in operators ignore local and top-level function shadowing',async()=>{
  await compileAndRun('func add (a: U32) -> (b: U32) => return a + b\nentry const answer = func () => return do:\n  let add = func left => return func right => return @u32.sub left right\n  break 20 + 22\n',guest=>equal(guest.call('answer',null),42));
});
