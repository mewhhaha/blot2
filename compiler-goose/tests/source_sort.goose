import std;
import check.source_sort;
struct Entry {key:u32,index:u32,text:const u8[:]}
struct Order {entries:Entry[:],comparisons:i64&,swaps:i64&}
fn lessThan(order:Order,left:i64,right:i64)->bool {
    order.comparisons++;
    let a=order.entries[left];let b=order.entries[right];
    if a.key!=b.key {return a.key<b.key;}
    return a.index<b.index;
}
fn swap(order:Order,left:i64,right:i64) {
    order.swaps++;
    let old=order.entries[left];order.entries[left]=order.entries[right];order.entries[right]=old;
}
fn run(size:i64,mode:i64) {
    var bytes:u8[>..]=[];for index in 0..size {bytes.push(index as! u8);}
    var entries:Entry[>..]=[];
    for index in 0..size {
        var key=index as u32;
        if mode==1 {key=(size-index) as u32;}
        if mode==2 {key=((index*37+11)%17) as u32;}
        entries.push(Entry{key:key,index:index as u32,text:bytes[index..index+1]});
    }
    var comparisons:i64=0;var swaps:i64=0;
    {
        let order=Order{entries:entries[..],comparisons:comparisons,swaps:swaps};
        blot_check_source_sort::pdqContext(0,size,order);
    }
    for value,index in entries {
        assert(value.index<size && value.text.len==1 && value.text[0]==value.index as! u8);
        if index!=0 {
            let before=entries[index-1];
            assert(before.key<value.key || (before.key==value.key && before.index<value.index));
        }
    }
    if size>1 {assert(comparisons>0);}
    if size>1 && mode==1 {assert(swaps>0);}
}
fn main() {
    for size in [0 as i64,1,23,24,25,64,65,127,128,257] {
        for mode in 0..3 {run(size,mode);}
    }
    print("source sort passed: borrowed payloads, permutation, ordering and shared counters");
}
