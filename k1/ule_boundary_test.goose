import std;
import unified_frontend;
import unified_check;
struct Observation { value:bool=false, overflow:bool=false }
fn combine(a:Observation,b:Observation,is_and:bool)->Observation {
    if is_and {return Observation {value:a.value && b.value,overflow:a.overflow || (a.value && b.overflow)};}
    return Observation {value:a.value || b.value,overflow:a.overflow || (!a.value && b.overflow)};
}
fn main(){
    let expr=["#True","#False","x < 4294967295","x <= 4294967294","4294967294 < x","4294967295 <= x","x <= 4294967295","x < 1","x + 1 < 5","x + 1 <= 5"];
    let observed=[Observation {value:true},Observation {},Observation {},Observation {},Observation {value:true},Observation {value:true},Observation {value:true},Observation {},Observation {overflow:true},Observation {overflow:true}];
    var cases:i64=0;var admitted:i64=0;
    for i in 10 { for j in 10 { for k in 10 { for mode in 4 {
        let op1=mode/2==0;let op2=mode%2==0;
        let result=combine(combine(observed[i],observed[j],op1),observed[k],op2);
        let source=str("let f: U32 -> U32 = fn x => do:\n  if ((",expr[i],if op1 {" && "} else {" || "},expr[j],")",if op2 {" && "} else {" || "},expr[k],"):\n    return x + 1\n  else:\n    return x\n");
        var p=unified_frontend::parse(source);
        if p.status==0 {admitted+=1;assert(!result.overflow && !result.value && unified_check::verify(source,p.program));}
        cases+=1;
    } } } }
    assert(cases==4000 && admitted>0);print(str("<= boundary oracle passed ",cases," admitted ",admitted));
}
