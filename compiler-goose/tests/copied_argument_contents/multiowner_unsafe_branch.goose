import std;
struct R {a:i64[:],b:i64[:]}
struct Box<T> {value:T}
fn box<T>(value:T)->Box<T> {return Box<T>{value};}
fn nested<T>(value:T)->Box<Box<T>> {return box(box(value));}
var a:i64[>..]=[];
var b:i64[>..]=[];
var other:i64[>..]=[];
fn fill() {a.push(1);b.push(2);other.push(3);}
fn choose<T>(first:T,second:T,flag:bool)->Box<T>{if flag{return box(first);}return box(second);}fn main(){fill();let result=choose(R{a[..],b[..]},R{other[..],b[..]},false);other=[];assert(result.value.a[0]==3);}
