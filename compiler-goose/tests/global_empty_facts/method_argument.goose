import std;
struct Item { value:u32 }
var values:Item[>..]=[];
var refs:Item&[>..<]=[];
fn populate() {let value .=values.push(Item{1});refs.push(value);}
struct Writer {count:u32}
fn refill(self_:Writer&,ignored:u32) {let value .=values.push(Item{2});refs.push(value);}
fn reset() {var writer=Writer{0};writer.refill(block {refs=[];0});values=[];}
fn main() {populate();reset();}
