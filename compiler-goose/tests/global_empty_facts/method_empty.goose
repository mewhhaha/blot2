import std;
struct Item { value:u32 }
var values:Item[>..]=[];
var refs:Item&[>..<]=[];
fn populate() {let value .=values.push(Item{1});refs.push(value);}
struct Reset { count:u32 }
fn reset(self_:Reset&) {refs=[];values=[];self_.count++;}
fn main() {var resetter=Reset{0};populate();resetter.reset();assert(resetter.count==1);}
