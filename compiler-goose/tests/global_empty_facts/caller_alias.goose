import std;
struct Item { value:u32 }
var values:Item[>..]=[];
var refs:Item&[>..<]=[];
fn populate() {let value .=values.push(Item{1});refs.push(value);}
fn reset() {refs=[];values=[];}
fn main() {populate();let held .=values[0];reset();print(held.value);}
