import std;
struct Item { value:u32 }
var values:Item[>..]=[];
var refs:Item&[>..<]=[];
fn populate() {let value .=values.push(Item{1});refs.push(value);}
struct Holder {ref_:Item?=null}
struct Pair {a:Holder,b:Holder}
var pair=Pair{Holder{},Holder{}};
fn reset() {let value .=values.push(Item{2});pair.a=Holder{value};pair.b=Holder{value};refs=[];pair.a=Holder{};pair.b=Holder{};values=[];}
fn main() {populate();reset();}
