import std;
import m12_internal_body;
import bridge_plan_sites;
fn main() {
 let body=m12_internal_body::body();let r=bridge_plan_sites::scan(body);assert(r.ok);
 for i in body.len {assert(!bridge_plan_sites::scan(body[..i]).ok);}
 for site in r.sites {
  assert(site>=0 && site+1<body.len && body[site]==0x10);
  var bad=copy(body);bad[site+1]^=1;assert(!bridge_plan_sites::scan(bad).ok);
 }
 var bad=copy(body);bad[0]^=1;assert(!bridge_plan_sites::scan(bad).ok);
 print("bounded bridge template scanner rejects truncations and changed calls");
}
