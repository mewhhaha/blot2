import tests.frontend_lifecycle_test;
import tests.validator_test;
fn test_validator_layout_premises() {
    var source:u8[>..]=[]; assert(read_file("examples/generic_result.blot",source));
    with_core() { b =>
        var work=Work{..}; var diags:Diagnostic[>..]=[];
        assert(frontend_complete(source,"premise-forgery",b,work,diags)); assert(build_plans(b,"",diags)); assert(canonical_schemas(b,diags)); assert(seal_completion(b));
        validator_expect(b,true,0); assert(b.contracts[b.functions[1].contract].layout_premises.count>0);
        b.contracts[b.functions[1].contract].layout_premises=Span{..};
        // Recompute all hashes: rejection must derive the missing obligation,
        // rather than merely noticing a stale digest.
        assert(canonical_schemas(b,diags)); validator_expect(b,false,2024);
    };
    let hidden="let roundtrip: forall [T:Type] where [Share(T)] => T -> T ! {} resources {depth:1,frame:2048} = fn value => do:\n  let tagged: Result[T,Unit] = #Ok(value)\n  case tagged:\n    #Ok(result) => return result\n    #Err(()) => return value\n";
    var positive:u8[>..]=[]; positive.append(hidden); positive.append("pub let run: U32 -> U32 ! {} resources {depth:2,frame:4096} = fn x => return roundtrip@[U32](x)\n"); frontend_planned(positive,true,0);
    var negative:u8[>..]=[]; negative.append("type Wide = ("); for i in 64 { if i!=0 { negative.append(","); } negative.append("U32"); } negative.append(")\n"); negative.append(hidden); negative.append("pub let run: Wide -> Wide ! {} resources {depth:2,frame:4096} = fn x => return roundtrip@[Wide](x)\n");
    with_core() { b =>
        var work=Work{..}; var diags:Diagnostic[>..]=[]; let completed=frontend_complete(negative,"hidden-layout-overflow",b,work,diags); if !completed { print(diags); } assert(completed);
        assert(!build_plans(b,"",diags)); assert(diags.len>0); assert(diags[diags.len-1].code==2024 || diags[diags.len-1].code==4012);
    };
    print("GEN-A02/R02 explicit LayoutFits accepts small Result, rejects hidden tagged256-byte payload and missing premises");
}

fn test_validator_compound_plain() {
    let generic="let length: forall [r:Region,T:Type,n:Nat,d:Domain] where [Plain(T)] => View[r,(T,T),n,d] -> U32 ! {} resources {depth:1,frame:256} = fn values => return values.length\n";
    var positive:u8[>..]=[]; positive.append(generic); positive.append("pub let run: forall [r:Region,n:Nat,d:Domain] => View[r,(U32,U32),n,d] -> U32 ! {} resources {depth:2,frame:1024} = fn values => return length@[r,U32,n,d](values)\n"); frontend_planned(positive,true,0);
    var negative:u8[>..]=[]; negative.append("type Wide = ("); for i in 9 { if i!=0 {negative.append(",");} negative.append("U32"); } negative.append(")\n"); negative.append(generic); negative.append("pub let run: forall [r:Region,n:Nat,d:Domain] => View[r,(Wide,Wide),n,d] -> U32 ! {} resources {depth:2,frame:1024} = fn values => return length@[r,Wide,n,d](values)\n");
    with_core() { b => var work=Work{..}; var diags:Diagnostic[>..]=[]; assert(frontend_complete(negative,"compound-plain-overflow",b,work,diags)); assert(!build_plans(b,"",diags)); if diags.len==0 || diags[diags.len-1].code!=2024 { print(diags); } assert(diags.len>0); assert(diags[diags.len-1].code==2024); };
    print("GEN-01 generic compound Plain derives64-byte premise and rejects72-byte instantiation");
}
