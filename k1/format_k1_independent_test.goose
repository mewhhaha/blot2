import format_k1_formatter;
import format_k1_check;
import compiler_frontend;
fn main() {
    let first="let f: U32 -> U32 = fn x => do:\n  if x < 1:\n    if x < 2:\n      return 1\n    else:\n      return 2\n  return 3\n";
    let second="let f: U32 -> U32 = fn x => do:\n  if x < 1:\n    if x < 2:\n      return 1\n  else:\n    return 2\n  return 3\n";
    var a=compiler_frontend::parse(first);var b=compiler_frontend::parse(second);
    assert(a.status==0 && b.status==0 && format_k1_check::tokens(first,second));
    assert(!format_k1_check::equivalent(a.program,b.program));
    for src in [
      "// UTF-8: λ  // comment   \r\nlet f: U32 -> U32 = fn x => do: \r\n  return x // α  \r\n// EOF tail ",
      "// adjacent // markers  \nlet f: U32 -> U32 = fn x => do:\n  // indented comment  \n  return x  \n",
      "let f: U32 -> U32 = fn x => do:\r\n  return x\r\n// trailing comment without newline  "
    ] {let x=format_k1_formatter::format(src);assert(x.status==0);let y=format_k1_formatter::format(x.source);assert(y.status==0 && y.source[..]==x.source[..]);}
    let unicode="// UTF-8: λ  // comment   \r\nlet f: U32 -> U32 = fn x => do: \r\n  return x // α  \r\n// EOF tail ";
    let want="// UTF-8: λ  // comment   \nlet f: U32 -> U32 = fn x => do:\n  return x // α  \n// EOF tail ";
    let u=format_k1_formatter::format(unicode);assert(u.status==0 && u.source[..]==want);
    let blank="let f: U32 -> U32 = fn x => do:\n   \n  return x\n";
    let formatted=format_k1_formatter::format(blank);
    assert(formatted.status==0 && formatted.source[..]=="let f: U32 -> U32 = fn x => do:\n   \n  return x\n");
    print("independent formatter audit passed, blank-line preservation verified");
}
