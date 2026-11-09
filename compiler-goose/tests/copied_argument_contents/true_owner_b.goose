import std;
struct R {a:i64[:],b:i64[:]}
struct Box<T> {value:T}
fn box<T>(value:T)->Box<T> {return Box<T>{value};}
fn nested<T>(value:T)->Box<Box<T>> {return box(box(value));}
var a:i64[>..]=[];
var b:i64[>..]=[];
var other:i64[>..]=[];
fn fill() {a.push(1);b.push(2);other.push(3);}
fn main(){fill();let result=box(R{a[..],b[..]});b=[];assert(result.value.b[0]==2);}
