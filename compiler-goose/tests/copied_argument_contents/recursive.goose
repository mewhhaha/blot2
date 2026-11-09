import std;
struct R {a:i64[:],b:i64[:]}
struct Box<T> {value:T}
fn box<T>(value:T)->Box<T> {return Box<T>{value};}
fn nested<T>(value:T)->Box<Box<T>> {return box(box(value));}
var a:i64[>..]=[];
var b:i64[>..]=[];
var other:i64[>..]=[];
fn fill() {a.push(1);b.push(2);other.push(3);}
recursive fn recur(value:R,n:i64)->Box<R>{if n==0{return box(value);}return recur(R{other[..],value.b},n-1);}fn main(){fill();let result=recur(R{a[..],b[..]},1);other=[];assert(result.value.a[0]==3);}
