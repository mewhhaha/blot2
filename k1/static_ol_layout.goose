// Private metadata/layout pass. Each listed check expression is charged
// before execution; this fixture does not define the C09 cost table.
namespace static_ol_layout;
import work;
import static_product_eval;
fn visit(w:work::ScheduledWork&,phase:u32)->i64 {
 let r=work::scheduled_charge(w,phase,10);return if r.status==0 {0} else if r.status==1 {4} else {5};
}
fn check(rows:i64,width:i64,value:static_product_eval::Result&,w:work::ScheduledWork&)->i64 {
 let a=visit(w,5);if a!=0{return a;}if rows<1{return 1;}
 let b=visit(w,5);if b!=0{return b;}if width<2 || width>16{return 1;}
 let c=visit(w,5);if c!=0{return c;}if rows>100000/width{return 1;}
 let d=visit(w,5);if d!=0{return d;}if value.data.len!=value.bytes{return 1;}
 let e=visit(w,5);if e!=0{return e;}if (rows as u64)*(width as u64)*4!=value.bytes as u64{return 1;}
 return 0;
}
