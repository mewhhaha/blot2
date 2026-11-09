import std;
struct Item { value:u32 }
var values:Item[>..]=[];
var refs:Item&[>..<]=[];
fn populate() {let value .=values.push(Item{1});refs.push(value);}
struct Reset {count:u32}
fn noop(self_:Reset&) {self_.count++;}
fn reset(self_:Reset&) {refs=[];self_.noop();values=[];}
fn main() {var resetter=Reset{0};populate();resetter.reset();}
