import std;
struct Item { value:u32 }
var values:Item[>..]=[];
var refs:Item&[>..<]=[];
fn populate() {let value .=values.push(Item{1});refs.push(value);}
enum Choice {one,two}
fn refill(choice:Choice.one,ignored:u32) {let value .=values.push(Item{2});refs.push(value);}
fn refill(choice:Choice.two,ignored:u32) {let value .=values.push(Item{2});refs.push(value);}
fn reset() {var choice:Choice=Choice.one;refill(choice,block {refs=[];0});values=[];}
fn main() {populate();reset();}
