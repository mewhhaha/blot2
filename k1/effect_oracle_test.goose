// Independent generated direct-call graph/resource oracle for the private
// effect summary. This does not qualify public K1 contracts, region effects,
// callbacks, nonzero local frames, authenticated source or full work metering.
import std;
import module_frontend;
import effect_core;
import effect_build;
import effect_verify;
fn random(s:u32&)->u32 {s^=s<<13;s^=s>>17;s^=s<<5;return s;}
fn copy_summary(s:effect_core::Summary&)->effect_core::Summary {return effect_core::Summary {source:copy(s.source),entries:copy(s.entries)};}
fn main() {
    var rng:u32=0x6b29a41d;var graphs=0;var edges=0;var backwards=0;var forwards=0;
    for trial in 180 {
        let count=(random(rng)%64+1) as i64;
        var targets:i64[64]=[-1;64];var depths:i64[64]=[0;64];
        var effects:i64[64]=[0;64];var frames:i64[64]=[0;64];
        for reverse in count {
            let i=count-1-reverse;
            if i+1<count && random(rng)%4!=0 {targets[i]=i+1+(random(rng)%(count-i-1)) as i64;}
            let child=targets[i];
            depths[i]=if child<0 {1} else {depths[child]+1};
            frames[i]=if child<0 {(random(rng)%30+1) as i64} else {frames[child]+(random(rng)%5+1) as i64};
            effects[i]=(random(rng)%8) as i64 | (if child<0 {0} else {effects[child]});
        }
        // Randomly permute declarations after independently constructing the
        // acyclic graph. Calls can now point backward or forward in source.
        var order:i64[64]=[0;64];var position:i64[64]=[0;64];
        for i in count {order[i]=i;}
        for i in count {
            let j=random(rng)%count;let saved=order[i];order[i]=order[j];order[j]=saved;
        }
        for i in count {position[order[i]]=i;}
        var source:u8[>..]=[];
        for ordinal in count {
            let id=order[ordinal];
            if targets[id]<0 {
                if random(rng)%2==0 {format(source,"let f",id,": U32 -> U32 = fn x => return x\n");}
                else {format(source,"let f",id,": U32 -> U32 = fn x => return x & 7\n");}
            } else {format(source,"let f",id,": U32 -> U32 = fn x => return f",targets[id],"(x)\n");}
        }
        var parsed,parse_status=module_frontend::parse(source);assert(parse_status==0 && parsed.declarations.len==count);
        var bounds:effect_core::Bound[>..]=[];
        for i in count {
            let declaration=parsed.declarations[i];let id=order[i];assert(declaration.depth==depths[id]);
            bounds.push(effect_core::Bound {name_start:declaration.name_start,name_end:declaration.name_end,
                effects:effects[id],depth:depths[id],frame:frames[id]});
        }
        var summary,ok=effect_build::build(source,bounds);assert(ok && effect_verify::verify(source,bounds,summary));
        graphs+=1;
        for i in count {
            let id=order[i];let target=targets[id];let expected=if target<0 {-1} else {position[target]};
            assert(summary.entries[i].callee==expected && summary.entries[i].actual_depth==depths[id]);
            assert(summary.entries[i].actual_effects==0 && summary.entries[i].actual_frame==0);
            if target>=0 {edges+=1;if expected<i {backwards+=1;} else {forwards+=1;}}
        }
        let pos=(random(rng)%count) as i64;
        var forged=copy_summary(summary);
        forged.entries[pos].callee=if targets[order[pos]]==-1 {0} else {-1};assert(!effect_verify::verify(source,bounds,forged));
        var forged_depth=copy_summary(summary);forged_depth.entries[pos].actual_depth+=1;assert(!effect_verify::verify(source,bounds,forged_depth));
        var forged_frame=copy_summary(summary);forged_frame.entries[pos].actual_frame=1;assert(!effect_verify::verify(source,bounds,forged_frame));
        var forged_effect=copy_summary(summary);forged_effect.entries[pos].actual_effects=1;assert(!effect_verify::verify(source,bounds,forged_effect));
        var changed_source=copy(source);changed_source[0]='?';assert(!effect_verify::verify(changed_source,bounds,summary));
        var broken=copy(bounds);broken[pos].name_start=-1;
        let blank,badname=effect_build::build(source,broken);assert(!badname && blank.entries.len==0 && !effect_verify::verify(source,broken,summary));
        var invalid_effect=copy(bounds);invalid_effect[pos].effects=8;
        let _,unknown=effect_build::build(source,invalid_effect);assert(!unknown);
        var invalid_depth=copy(bounds);invalid_depth[pos].depth=129;
        let _,overdepth=effect_build::build(source,invalid_depth);assert(!overdepth);
        var invalid_frame=copy(bounds);invalid_frame[pos].frame=4294967296;
        let _,overframe=effect_build::build(source,invalid_frame);assert(!overframe);
        var parent:i64=-1;for i in count {if targets[order[i]]>=0 {parent=i;break;}}
        if parent>=0 {
            let child=position[targets[order[parent]]];
            var low_depth=copy(bounds);low_depth[parent].depth=low_depth[child].depth;
            let _,depth_ok=effect_build::build(source,low_depth);assert(!depth_ok && !effect_verify::verify(source,low_depth,summary));
            var low_frame=copy(bounds);low_frame[parent].frame=low_frame[child].frame-1;
            let _,frame_ok=effect_build::build(source,low_frame);assert(!frame_ok && !effect_verify::verify(source,low_frame,summary));
            var bad_effect=copy(bounds);bad_effect[child].effects=bad_effect[child].effects | 1;bad_effect[parent].effects=bad_effect[parent].effects & 6;
            let _,effect_ok=effect_build::build(source,bad_effect);assert(!effect_ok && !effect_verify::verify(source,bad_effect,summary));
        }
    }
    assert(graphs==180 && edges>0 && backwards>0 && forwards>0);
    // Distinct malformed graph families: direct cycle, indirect cycle, and
    // a call hidden in a nested argument are never accepted by this subset.
    var dummy:effect_core::Bound[2]=[effect_core::Bound {name_start:4,name_end:5,depth:2},effect_core::Bound {name_start:44,name_end:45,depth:1}];
    let _,cycle=effect_build::build("let a: U32 -> U32 = fn x => return b(x)\nlet b: U32 -> U32 = fn x => return a(x)\n",dummy);assert(!cycle);
    let _,nested=effect_build::build("let a: U32 -> U32 = fn x => return b(b(x))\nlet b: U32 -> U32 = fn x => return x\n",dummy);assert(!nested);
    print("independent effect/resource graph oracle passed: ",graphs," DAGs, ",edges," direct edges (",backwards," backward, ",forwards," forward)");
}
