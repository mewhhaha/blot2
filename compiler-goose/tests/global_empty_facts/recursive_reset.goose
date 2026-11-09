import std;
struct Item { value:u32 }
var values:Item[>..]=[];
var refs:Item&[>..<]=[];
fn populate() {let value .=values.push(Item{1});refs.push(value);}
recursive fn reset(n:u32) {if n>0 {reset(n-1);}refs=[];values=[];}
fn main() {populate();reset(2);}
