// Concrete temporary owners shared by the native asset readers.
namespace blot_backend_optimizer_buffers;
import support.error;
import support.option;
import support.pooled_buffer;
type Error=blot_error::Error;
struct Words {storage:u32[:] = default<u32[:]>(),items:u32[:] = default<u32[:]>(),len:i64=0}
reusable[] var pool_Words:u32[>..]=[];
fn ensure(self_:Words&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self_,minimum,pool_Words);}
fn push(self_:Words&,value:u32)->Error {let error=blot_support_pooled_buffer::push(self_,value,pool_Words);self_.len=self_.items.len;return error;}
fn append(self_:Words&,values:const u32[:])->Error {let error=blot_support_pooled_buffer::append(self_,values,pool_Words);self_.len=self_.items.len;return error;}
fn resize(self_:Words&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Words&,length:i64,initial:u32)->Error {if length<=self_.len {self_.resize(length);return blot_error::Error.none;}let error=self_.ensure(length);if error!=blot_error::Error.none {return error;}for index in self_.len..length {self_.storage[index]=initial;}self_.items=self_.storage[..length];self_.len=length;return blot_error::Error.none;}
fn pop(self_:Words&)->u32 {assert(self_.len!=0);let value=self_.items[self_.len-1];self_.resize(self_.len-1);return value;}
fn clear(self_:Words&) {self_.resize(0);}
fn deinit(self_:Words&) {blot_support_pooled_buffer::deinit(self_,pool_Words);self_.len=0;}
struct Sizes {storage:i64[:] = default<i64[:]>(),items:i64[:] = default<i64[:]>(),len:i64=0}
reusable[] var pool_Sizes:i64[>..]=[];
fn ensure(self_:Sizes&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self_,minimum,pool_Sizes);}
fn push(self_:Sizes&,value:i64)->Error {let error=blot_support_pooled_buffer::push(self_,value,pool_Sizes);self_.len=self_.items.len;return error;}
fn append(self_:Sizes&,values:const i64[:])->Error {let error=blot_support_pooled_buffer::append(self_,values,pool_Sizes);self_.len=self_.items.len;return error;}
fn resize(self_:Sizes&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Sizes&,length:i64,initial:i64)->Error {if length<=self_.len {self_.resize(length);return blot_error::Error.none;}let error=self_.ensure(length);if error!=blot_error::Error.none {return error;}for index in self_.len..length {self_.storage[index]=initial;}self_.items=self_.storage[..length];self_.len=length;return blot_error::Error.none;}
fn pop(self_:Sizes&)->i64 {assert(self_.len!=0);let value=self_.items[self_.len-1];self_.resize(self_.len-1);return value;}
fn clear(self_:Sizes&) {self_.resize(0);}
fn deinit(self_:Sizes&) {blot_support_pooled_buffer::deinit(self_,pool_Sizes);self_.len=0;}
struct Bytes {storage:u8[:] = default<u8[:]>(),items:u8[:] = default<u8[:]>(),len:i64=0}
reusable[] var pool_Bytes:u8[>..]=[];
fn ensure(self_:Bytes&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self_,minimum,pool_Bytes);}
fn push(self_:Bytes&,value:u8)->Error {let error=blot_support_pooled_buffer::push(self_,value,pool_Bytes);self_.len=self_.items.len;return error;}
fn append(self_:Bytes&,values:const u8[:])->Error {let error=blot_support_pooled_buffer::append(self_,values,pool_Bytes);self_.len=self_.items.len;return error;}
fn resize(self_:Bytes&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Bytes&,length:i64,initial:u8)->Error {if length<=self_.len {self_.resize(length);return blot_error::Error.none;}let error=self_.ensure(length);if error!=blot_error::Error.none {return error;}for index in self_.len..length {self_.storage[index]=initial;}self_.items=self_.storage[..length];self_.len=length;return blot_error::Error.none;}
fn pop(self_:Bytes&)->u8 {assert(self_.len!=0);let value=self_.items[self_.len-1];self_.resize(self_.len-1);return value;}
fn clear(self_:Bytes&) {self_.resize(0);}
fn deinit(self_:Bytes&) {blot_support_pooled_buffer::deinit(self_,pool_Bytes);self_.len=0;}
struct Flags {storage:bool[:] = default<bool[:]>(),items:bool[:] = default<bool[:]>(),len:i64=0}
reusable[] var pool_Flags:bool[>..]=[];
fn ensure(self_:Flags&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self_,minimum,pool_Flags);}
fn push(self_:Flags&,value:bool)->Error {let error=blot_support_pooled_buffer::push(self_,value,pool_Flags);self_.len=self_.items.len;return error;}
fn append(self_:Flags&,values:const bool[:])->Error {let error=blot_support_pooled_buffer::append(self_,values,pool_Flags);self_.len=self_.items.len;return error;}
fn resize(self_:Flags&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Flags&,length:i64,initial:bool)->Error {if length<=self_.len {self_.resize(length);return blot_error::Error.none;}let error=self_.ensure(length);if error!=blot_error::Error.none {return error;}for index in self_.len..length {self_.storage[index]=initial;}self_.items=self_.storage[..length];self_.len=length;return blot_error::Error.none;}
fn pop(self_:Flags&)->bool {assert(self_.len!=0);let value=self_.items[self_.len-1];self_.resize(self_.len-1);return value;}
fn clear(self_:Flags&) {self_.resize(0);}
fn deinit(self_:Flags&) {blot_support_pooled_buffer::deinit(self_,pool_Flags);self_.len=0;}
