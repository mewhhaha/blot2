import std;
struct Item { value:u32 }
var values:Item[>..]=[];
var refs:Item&[>..<]=[];
fn populate() {let value .=values.push(Item{1});refs.push(value);}
fn reset() {refs=[];for i in 2 {values=[];refs.push(values.push(Item{1}));}}
fn main() {populate();reset();}
