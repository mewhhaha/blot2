// Concrete temporary owners shared by symbolic Wasm transforms.
namespace blot_backend_optimizer_buffers;
import .runtime_ir;
import support.error;
import support.option;
import support.pooled_buffer;
type Error=blot_error::Error;
struct Code {storage:blot_backend_runtime_ir::Instruction[:]=[],items:blot_backend_runtime_ir::Instruction[:]=[],len:i64=0}
reusable[] var pool_Code:blot_backend_runtime_ir::Instruction[>..]=[];
fn ensure(self:Code&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self,minimum,pool_Code);}
fn push(self:Code&,value:blot_backend_runtime_ir::Instruction)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_Code);self.len=self.items.len;return error;}
fn append(self:Code&,values:const blot_backend_runtime_ir::Instruction[:])->Error {let error=blot_support_pooled_buffer::append(self,values,pool_Code);self.len=self.items.len;return error;}
fn resize(self:Code&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn resize(self:Code&,length:i64,initial:blot_backend_runtime_ir::Instruction)->Error {if length<=self.len {self.resize(length);return Error.none;}let error=self.ensure(length);if error!=Error.none {return error;}for index in self.len..length {self.storage[index]=initial;}self.items=self.storage[..length];self.len=length;return Error.none;}
fn pop(self:Code&)->blot_backend_runtime_ir::Instruction {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn clear(self:Code&) {self.resize(0);}
fn deinit(self:Code&) {blot_support_pooled_buffer::deinit(self,pool_Code);self.len=0;}
struct Types {storage:blot_backend_runtime_ir::ValueType[:]=[],items:blot_backend_runtime_ir::ValueType[:]=[],len:i64=0}
reusable[] var pool_Types:blot_backend_runtime_ir::ValueType[>..]=[];
fn ensure(self:Types&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self,minimum,pool_Types);}
fn push(self:Types&,value:blot_backend_runtime_ir::ValueType)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_Types);self.len=self.items.len;return error;}
fn append(self:Types&,values:const blot_backend_runtime_ir::ValueType[:])->Error {let error=blot_support_pooled_buffer::append(self,values,pool_Types);self.len=self.items.len;return error;}
fn resize(self:Types&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn resize(self:Types&,length:i64,initial:blot_backend_runtime_ir::ValueType)->Error {if length<=self.len {self.resize(length);return Error.none;}let error=self.ensure(length);if error!=Error.none {return error;}for index in self.len..length {self.storage[index]=initial;}self.items=self.storage[..length];self.len=length;return Error.none;}
fn pop(self:Types&)->blot_backend_runtime_ir::ValueType {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn clear(self:Types&) {self.resize(0);}
fn deinit(self:Types&) {blot_support_pooled_buffer::deinit(self,pool_Types);self.len=0;}
struct Words {storage:u32[:]=[],items:u32[:]=[],len:i64=0}
reusable[] var pool_Words:u32[>..]=[];
fn ensure(self:Words&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self,minimum,pool_Words);}
fn push(self:Words&,value:u32)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_Words);self.len=self.items.len;return error;}
fn append(self:Words&,values:const u32[:])->Error {let error=blot_support_pooled_buffer::append(self,values,pool_Words);self.len=self.items.len;return error;}
fn resize(self:Words&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn resize(self:Words&,length:i64,initial:u32)->Error {if length<=self.len {self.resize(length);return Error.none;}let error=self.ensure(length);if error!=Error.none {return error;}for index in self.len..length {self.storage[index]=initial;}self.items=self.storage[..length];self.len=length;return Error.none;}
fn pop(self:Words&)->u32 {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn clear(self:Words&) {self.resize(0);}
fn deinit(self:Words&) {blot_support_pooled_buffer::deinit(self,pool_Words);self.len=0;}
struct Sizes {storage:i64[:]=[],items:i64[:]=[],len:i64=0}
reusable[] var pool_Sizes:i64[>..]=[];
fn ensure(self:Sizes&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self,minimum,pool_Sizes);}
fn push(self:Sizes&,value:i64)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_Sizes);self.len=self.items.len;return error;}
fn append(self:Sizes&,values:const i64[:])->Error {let error=blot_support_pooled_buffer::append(self,values,pool_Sizes);self.len=self.items.len;return error;}
fn resize(self:Sizes&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn resize(self:Sizes&,length:i64,initial:i64)->Error {if length<=self.len {self.resize(length);return Error.none;}let error=self.ensure(length);if error!=Error.none {return error;}for index in self.len..length {self.storage[index]=initial;}self.items=self.storage[..length];self.len=length;return Error.none;}
fn pop(self:Sizes&)->i64 {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn clear(self:Sizes&) {self.resize(0);}
fn deinit(self:Sizes&) {blot_support_pooled_buffer::deinit(self,pool_Sizes);self.len=0;}
struct Bytes {storage:u8[:]=[],items:u8[:]=[],len:i64=0}
reusable[] var pool_Bytes:u8[>..]=[];
fn ensure(self:Bytes&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self,minimum,pool_Bytes);}
fn push(self:Bytes&,value:u8)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_Bytes);self.len=self.items.len;return error;}
fn append(self:Bytes&,values:const u8[:])->Error {let error=blot_support_pooled_buffer::append(self,values,pool_Bytes);self.len=self.items.len;return error;}
fn resize(self:Bytes&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn resize(self:Bytes&,length:i64,initial:u8)->Error {if length<=self.len {self.resize(length);return Error.none;}let error=self.ensure(length);if error!=Error.none {return error;}for index in self.len..length {self.storage[index]=initial;}self.items=self.storage[..length];self.len=length;return Error.none;}
fn pop(self:Bytes&)->u8 {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn clear(self:Bytes&) {self.resize(0);}
fn deinit(self:Bytes&) {blot_support_pooled_buffer::deinit(self,pool_Bytes);self.len=0;}
struct Flags {storage:bool[:]=[],items:bool[:]=[],len:i64=0}
reusable[] var pool_Flags:bool[>..]=[];
fn ensure(self:Flags&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self,minimum,pool_Flags);}
fn push(self:Flags&,value:bool)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_Flags);self.len=self.items.len;return error;}
fn append(self:Flags&,values:const bool[:])->Error {let error=blot_support_pooled_buffer::append(self,values,pool_Flags);self.len=self.items.len;return error;}
fn resize(self:Flags&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn resize(self:Flags&,length:i64,initial:bool)->Error {if length<=self.len {self.resize(length);return Error.none;}let error=self.ensure(length);if error!=Error.none {return error;}for index in self.len..length {self.storage[index]=initial;}self.items=self.storage[..length];self.len=length;return Error.none;}
fn pop(self:Flags&)->bool {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn clear(self:Flags&) {self.resize(0);}
fn deinit(self:Flags&) {blot_support_pooled_buffer::deinit(self,pool_Flags);self.len=0;}
fn finish(locals:Types&,code:Code&)->blot_backend_runtime_ir::DetachedBody,Error {let output,error=blot_backend_runtime_ir::cloneBody(locals.items,code.items);code.deinit();locals.deinit();return output,error;}
fn finishOptional(locals:Types&,code:Code&,changed:bool,error:Error)->blot_support::Option<blot_backend_runtime_ir::DetachedBody>,Error {if error!=Error.none || !changed {code.deinit();locals.deinit();return blot_support::none<blot_backend_runtime_ir::DetachedBody>(),error;}let output,error=finish(locals,code);if error!=Error.none {return blot_support::none<blot_backend_runtime_ir::DetachedBody>(),error;}return blot_support::some(output),Error.none;}
fn I(op:blot_backend_runtime_ir::Op,operand:u32=0)->blot_backend_runtime_ir::Instruction {return blot_backend_runtime_ir::Instruction{op:op,operand:operand,..};}
struct Builder {locals:Types=Types{..},code:Code=Code{..},next_local:u32}
fn temp(self:Builder&)->u32,Error {let local=self.next_local;self.next_local+=1;let error=self.locals.push(blot_backend_runtime_ir::VT_i32);return local,error;}
