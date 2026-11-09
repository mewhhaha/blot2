import std;
struct Item { value:u32 }
var values:Item[>..]=[];
var refs:Item&[>..<]=[];
fn populate() {let value .=values.push(Item{1});refs.push(value);}
var extra:Item&[>..<]=[];
fn reset() {let value .=values.push(Item{2});extra.push(value);refs=[];extra=[];values=[];}
fn main() {populate();reset();}
