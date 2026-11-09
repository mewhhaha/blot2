import std;
struct Item { value:u32 }
var values:Item[>..]=[];
var refs:Item&[>..<]=[];
fn populate() {let value .=values.push(Item{1});refs.push(value);}
fn refill(ignored:u32=block {refs=[];0}) {let value .=values.push(Item{2});refs.push(value);}
fn reset() {refill();values=[];}
fn main() {populate();reset();}
