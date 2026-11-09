import std;
struct Item { value:u32 }
var values:Item[>..]=[];
var refs:Item&[>..<]=[];
fn populate() {let value .=values.push(Item{1});refs.push(value);}
fn reset(empty:bool) {if empty {refs=[];}else{refs=[];}values=[];}
fn main() {populate();reset(false);}
