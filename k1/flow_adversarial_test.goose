import flow_parse;
import flow_verify;
import flow_completion;
fn main() {
 let src = "do:\n  return do:\n    if x:\n      break do:\n        if y:\n          break 1\n        else:\n          return 2\n    else:\n      break 3\n";
 var t, status = flow_parse::parse(src); assert(status==0 && flow_verify::verify(t) && flow_completion::check(t)==0);
 for i in t.nodes.len { let orig=t.nodes[i];
  for choice in 8 { let mutation = if choice==0 { -1 } else if choice==1 { 0 } else if choice==2 { 1 } else if choice==3 { 2 } else if choice==4 { 2048 } else if choice==5 { 99999999 } else if choice==6 { i+1 } else { i+2 };
    for field in 6 { t.nodes[i]=orig;
      if field==0 {t.nodes[i].tag=mutation;} else if field==1 {t.nodes[i].start=mutation;} else if field==2 {t.nodes[i].end=mutation;} else if field==3 {t.nodes[i].a=mutation;} else if field==4 {t.nodes[i].b=mutation;} else {t.nodes[i].c=mutation;}
      let original = if field==0 {orig.tag} else if field==1 {orig.start} else if field==2 {orig.end} else if field==3 {orig.a} else if field==4 {orig.b} else {orig.c};
      if original != mutation { assert(!flow_verify::verify(t) && flow_completion::check(t)==1); }
    }
  }
  t.nodes[i]=orig;
 }
 for mutation in [-1, 0, 9999999] { t.root=mutation; assert(!flow_verify::verify(t) && flow_completion::check(t)==1); }
 print("independent nested control node and target mutation tests passed");
}
