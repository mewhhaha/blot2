// Concrete U32-MAX boundary oracle for short-circuit proof acceptance. At MAX,
// executing `x + 1` overflows; all other U32 x values make that successor fit.
import std;
import unified_frontend;
import unified_check;
struct Observation { value:bool=false, overflow:bool=false }
fn combine(a:Observation,b:Observation,is_and:bool)->Observation {
    if is_and { return Observation { value:a.value && b.value, overflow:a.overflow || (a.value && b.overflow) }; }
    return Observation { value:a.value || b.value, overflow:a.overflow || (!a.value && b.overflow) };
}
fn main() {
    let expr=["#True","#False","x < 4294967295","x < 1","x < 0","x + 1 < 5"];
    let observed=[Observation {value:true},Observation {},Observation {},Observation {},Observation {},Observation {overflow:true}];
    var cases:i64=0;var admitted:i64=0;
    for i in 6 { for j in 6 { for k in 6 { for mode in 4 {
        let op1=mode/2==0;let op2=mode%2==0;
        let mid=combine(observed[i],observed[j],op1);let result=combine(mid,observed[k],op2);
        let unsafe=result.overflow || result.value;
        let source=str("let f: U32 -> U32 = fn x => do:\n  if ((",expr[i],if op1 {" && "} else {" || "},expr[j],")",if op2 {" && "} else {" || "},expr[k],"):\n    return x + 1\n  else:\n    return x\n");
        var candidate=unified_frontend::parse(source);
        if candidate.status==0 {admitted+=1;assert(!unsafe && unified_check::verify(source,candidate.program));}
        cases+=1;
    } } } }
    assert(cases==864 && admitted>0);
    print("unified short-circuit U32-MAX boundary oracle passed");
}
