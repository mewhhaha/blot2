import std;
struct Item { value:u32 }
var values:Item[>..]=[];
var refs:Item&[>..<]=[];
fn populate() {let value .=values.push(Item{1});refs.push(value);}
fn reset(items:Item&[>..<]&) {items=[];values=[];}
fn main() {populate();reset(refs);}
