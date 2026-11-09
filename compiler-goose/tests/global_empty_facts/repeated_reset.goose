import std;
struct Item { value:u32 }
var values:Item[>..]=[];
var refs:Item&[>..<]=[];
fn populate() {let value .=values.push(Item{1});refs.push(value);}
fn reset() {refs=[];values=[];}
fn wrapped() {reset();}
fn main() {for i in 0..4 {populate();wrapped();}}
