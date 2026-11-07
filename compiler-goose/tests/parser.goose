// Executed syntax laws use the production parser and pooled AST tables.
import std;
import parse.parser;
import parse.lexer;
import parse.ast;
import parse.symbols;
import support.error;
type Tree=blot_parse_ast::Tree;
type Pool=blot_parse_symbols::Pool;
fn parse_source(source:const u8[:],names:Pool&,tree:Tree&,inherited:const blot_parse_parser::InheritedFixity[:]=[]) {
 var tokens:blot_parse_token::Token[>..<]=[];
 var comments:blot_parse_token::Token[>..<]=[];
 var diagnostics:blot_parse_lexer::Diagnostic[>..<]=[];
 var lexed=blot_parse_lexer::init(tokens,comments,diagnostics);
 assert(blot_parse_lexer::lex(source,lexed)==blot_error::Error.none && diagnostics.len==0);
 assert(blot_parse_parser::parse_with_fixities(source,tokens[..],names,tree,inherited)==blot_error::Error.none);
}
fn values() {
 var names,error=blot_parse_symbols::initPooled();assert(error==blot_error::Error.none);
 var tree,error=blot_parse_ast::initPooled();assert(error==blot_error::Error.none);
 parse_source("const value = #[1, 2, 3]\nconst predicate = true and false or true\n",names,tree);
 assert(tree.diagnostics.len==0 && tree.roots.len==2);
 let value=tree.node(tree.node(tree.roots.items[0]).b);
 assert(value.tag==blot_parse_ast::tag_array && value.b==3);
 for id,index in tree.list(blot_parse_ast::List {value.a,value.b}) {
  let item=tree.node(id);assert(item.tag==blot_parse_ast::tag_integer && item.a==index+1);
 }
 let predicate=tree.node(tree.node(tree.roots.items[1]).b);
 assert(predicate.tag==blot_parse_ast::tag_binary && names.get(predicate.a)=="or");
 let conjunction=tree.node(predicate.b);
 assert(conjunction.tag==blot_parse_ast::tag_binary && names.get(conjunction.a)=="and");
 assert(tree.node(conjunction.b).a==1 && tree.node(conjunction.c).a==0 && tree.node(predicate.c).a==1);
 tree.deinit();names.deinit();
}
fn fixities() {
 var names,error=blot_parse_symbols::initPooled();assert(error==blot_error::Error.none);
 let plus,error=names.intern("+");assert(error==blot_error::Error.none);
 let times,error=names.intern("*");assert(error==blot_error::Error.none);
 var tree,error=blot_parse_ast::initPooled();assert(error==blot_error::Error.none);
 let inherited=[blot_parse_parser::InheritedFixity {plus,20,1,false},blot_parse_parser::InheritedFixity {times,60,0,false}];
 parse_source("infixl 50 (+) = add\nconst value = 1 + 2 * 3 + 4\n",names,tree,inherited);
 assert(tree.diagnostics.len==0 && tree.roots.len==2);
 let body=tree.node(tree.node(tree.roots.items[1]).b);
 assert(body.tag==blot_parse_ast::tag_binary && names.get(body.a)=="+" && tree.node(body.c).a==4);
 let left=tree.node(body.b);
 assert(left.tag==blot_parse_ast::tag_binary && names.get(left.a)=="+" && tree.node(left.b).a==1);
 let product=tree.node(left.c);
 assert(product.tag==blot_parse_ast::tag_binary && names.get(product.a)=="*" && tree.node(product.b).a==2 && tree.node(product.c).a==3);
 tree.deinit();names.deinit();
}
fn recovery() {
 var names,error=blot_parse_symbols::initPooled();assert(error==blot_error::Error.none);
 var tree,error=blot_parse_ast::initPooled();assert(error==blot_error::Error.none);
 parse_source("const x = )\nconst y = 2\n",names,tree);
 assert(tree.roots.len==1 && tree.diagnostics.len==1);
 let diagnostic=tree.diagnostics.items[0];
 assert(diagnostic.code==blot_parse_ast::code_expected_expression && diagnostic.start==10 && diagnostic.end==11);
 assert(diagnostic.has_actual_token && diagnostic.actual_token==blot_parse_token::r_paren);
 assert(diagnostic.has_declaration_origin && diagnostic.declaration_origin.start==0 && diagnostic.declaration_origin.end==5);
 assert(names.get(tree.node(tree.roots.items[0]).a)=="y");
 assert(tree.node(tree.node(tree.roots.items[0]).b).a==2);
 tree.deinit();names.deinit();
}
fn staging() {
 var names,error=blot_parse_symbols::initPooled();assert(error==blot_error::Error.none);
 var tree,error=blot_parse_ast::initPooled();assert(error==blot_error::Error.none);
 parse_source("const value = @code.quote 1\nconst proof: @proof.U32Eq 1 1 = @proof.eq 1 1\n",names,tree);
 assert(tree.diagnostics.len==0 && tree.roots.len==2 && tree.has_typed_staging && tree.has_numeric_proofs);
 tree.deinit();names.deinit();
}
fn depth_limit() {
 var names,error=blot_parse_symbols::initPooled();assert(error==blot_error::Error.none);
 var tree,error=blot_parse_ast::initPooled();assert(error==blot_error::Error.none);
 var source:u8[>..<]=[];source.append("const x = ");
 for index in 0..300 {source.push('(');}source.push('1');for index in 0..300 {source.push(')');}source.push('\n');
 parse_source(source[..],names,tree);
 assert(tree.roots.len==0 && tree.diagnostics.len==1 && tree.diagnostics.items[0].code==blot_parse_ast::code_nesting_limit);
 tree.deinit();names.deinit();
}
fn main() {
 for cycle in 0..3 {values();fixities();recovery();staging();depth_limit();}
}
