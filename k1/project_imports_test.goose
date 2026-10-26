import project_imports;
import project_imports_check;
fn main() {
 let good="// hi\nimport \"./a.blot\" as a\nimport \"../b.blot\" as b\nlet x: U32 = 1\n";
 var p=project_imports::parse(good);assert(p.status==0 && p.imports.len==2 && project_imports_check::verify(good,p.imports));
 for i in p.imports.len {
  let old=p.imports[i];p.imports[i].path_start+=1;assert(!project_imports_check::verify(good,p.imports));p.imports[i]=old;
  p.imports[i].alias_end+=1;assert(!project_imports_check::verify(good,p.imports));p.imports[i]=old;
 }
 assert(project_imports::parse("import \"./a\" as a\nimport \"./b\" as a\n").status==3);
 for bad in ["import \"\" as a\n", "import \"./a\" as a let x\n", "let x: U32 = 1\nimport \"./a\" as a\n", "import \"a\\b\" as a\n", "import \"./a\" a\n"] {
  let r=project_imports::parse(bad);assert(r.status!=0 && r.imports.len==0);
 }
 let mismatch="// hi\nimport \"./a.blot\" as a\nimport \"../c.blot\" as b\nlet x: U32 = 1\n";
 // Offsets are not source authority; a complete project snapshot binds bytes.
 // The graph layer re-reads path/content and compares exact source separately.
 assert(project_imports_check::verify(mismatch,p.imports));
 print("private import preamble laws passed");
}
