import std;
struct R {a:i64[:],b:i64[:]}
struct Box<T> {value:T}
fn box<T>(value:T)->Box<T> {return Box<T>{value};}
fn nested<T>(value:T)->Box<Box<T>> {return box(box(value));}
var a:i64[>..]=[];
var b:i64[>..]=[];
var other:i64[>..]=[];
fn fill() {a.push(1);b.push(2);other.push(3);}
struct Link{data:i64[:]} struct Pair{left:Link&,right:Link&} var left:Link[>..]=[];var right:Link[>..]=[];fn deep<T>(value:T)->Box<i64[:]>{return box(value.left.data);}fn main(){fill();let l.=left.push(Link{other[..]});let r.=right.push(Link{b[..]});let result=deep(Pair{l,r});other=[];assert(result.value[0]==3);}
