import std;
struct Item { value:u32 }
var values:Item[>..]=[];
var refs:Item&[>..<]=[];
fn populate() {let value .=values.push(Item{1});refs.push(value);}
fn safe() {refs=[];values=[];}
fn unsafe() {values=[];}
fn main() {populate();safe();populate();unsafe();}
