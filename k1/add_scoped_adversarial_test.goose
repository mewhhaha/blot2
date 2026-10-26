import std;
import add_scoped;
import add_frontend;
fn main() {
 let source = "let f: U32 -> U32 = fn x => return x + 0";
 let parsed = add_frontend::parse(source); assert(parsed.status == 0);
 for index in 4 { for field in 7 {
   var j = add_scoped::Job {}; var c = add_scoped::build(parsed.core, j);
   if field == 0 { c.checked.evidence.terms[index].kind += 1; }
   else if field == 1 { c.checked.evidence.terms[index].owner += 1; }
   else if field == 2 { c.checked.evidence.terms[index].scope += 1; }
   else if field == 3 { c.checked.evidence.terms[index].value += 1; }
   else if field == 4 { c.checked.evidence.terms[index].version += 1; }
   else if field == 5 { c.checked.evidence.terms[index].base += 1; }
   else { c.checked.evidence.terms[index].literal = if c.checked.evidence.terms[index].literal == 0 { 1 } else { 0 }; }
   assert(add_scoped::validate_core(source,c,j,5).status == 1 && j.graph.failed);
 }}
 for index in 3 { for field in 9 {
   var j = add_scoped::Job {}; var c = add_scoped::build(parsed.core, j);
   if field == 0 { c.checked.evidence.nodes[index].rule += 1; }
   else if field == 1 { c.checked.evidence.nodes[index].owner += 1; }
   else if field == 2 { c.checked.evidence.nodes[index].scope += 1; }
   else if field == 3 { c.checked.evidence.nodes[index].left += 1; }
   else if field == 4 { c.checked.evidence.nodes[index].right += 1; }
   else if field == 5 { c.checked.evidence.nodes[index].prior1 += 1; }
   else if field == 6 { c.checked.evidence.nodes[index].prior2 += 1; }
   else if field == 7 { c.checked.evidence.nodes[index].operation_version += 1; }
   else { c.checked.evidence.nodes[index].operation_result += 1; }
   assert(add_scoped::validate_core(source,c,j,5).status == 1 && j.graph.failed);
 }}
 print("independent per-field proof mutation controls passed");
}
