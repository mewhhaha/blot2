import std;
struct R {a:i64[:],b:i64[:]}
struct Box<T> {value:T}
fn box<T>(value:T)->Box<T> {return Box<T>{value};}
fn nested<T>(value:T)->Box<Box<T>> {return box(box(value));}
var a:i64[>..]=[];
var b:i64[>..]=[];
var other:i64[>..]=[];
fn fill() {a.push(1);b.push(2);other.push(3);}
fn alter<T>(value:T,replacement:i64[:])->Box<T>{var changed=value;changed.a=replacement;return box(changed);}fn main(){fill();let result=alter(R{a[..],b[..]},other[..]);other=[];assert(result.value.a[0]==3);}
