// Pure bounded readers return generated Blot source or an owned diagnostic.
namespace blot_backend_native_asset_readers;
import dictionary;
import .native_asset_numbers;
import .optimizer_buffers;
import support.error;
import support.option;
import support.native;
import support.pooled_buffer;
import support.pooled_map;
type Error = blot_error::Error;
type Text = blot_backend_optimizer_buffers::Bytes;
let limit: i64 = 16777216;
enum Kind {json,catalog,text,tunables}
struct Issue {start: u32 = 0,end: u32 = 0,code: const u8[:],message: const u8[:]}
enum Result {source {bytes: u8[:]},issue {value: Issue}}
reusable[] var output_bytes: u8[>..] = [];
fn copyOutput(bytes: const u8[:]) -> u8[:] {if bytes.len == 0 {return default<u8[:]>();}let result = output_bytes.alloc_slice(bytes.len);for index in 0..bytes.len {result[index] = bytes[index];}return result;}
fn rootedText(text:const u8[:])->const u8[:] {if text.len==0 {return default<const u8[:]>();}return text_pool.realloc_slice(text,text.len);}
fn freeOutput(bytes: const u8[:]) {if bytes.len != 0 {output_bytes.free_slice(bytes);}}
fn deinit(result: Result&) {match result {source value=>{freeOutput(value.bytes);},issue value=>{freeOutput(value.value.code);freeOutput(value.value.message);},}result = Result.source {bytes: default<u8[:]>()};}
enum Tag {null_value,boolean,number,string,array,object}
struct Member {name: const u8[:] = default<const u8[:]>(),value: u32}
struct Node {tag: Tag,start: u32,end: u32 = 0,text: const u8[:] = default<const u8[:]>(),number: f64 = 0.0,boolean: bool = false,wellformed: bool = true,members: Member[:] = default<Member[:]>(),shape: u32 = 0}
enum ShapeTag {unit,boolean,u32_value,f32_value,array,tuple,record,utf8}
struct Field {name: const u8[:],shape: u32}
struct Shape {tag: ShapeTag,name: const u8[:] = default<const u8[:]>(),fields: Field[:] = default<Field[:]>(),elements: u32[:] = default<u32[:]>(),emitted: bool = false}
struct Nodes {storage: Node[:] = default<Node[:]>(),items: Node[:] = default<Node[:]>()}
struct Shapes {storage: Shape[:] = default<Shape[:]>(),items: Shape[:] = default<Shape[:]>()}
struct Members {storage: Member[:] = default<Member[:]>(),items: Member[:] = default<Member[:]>()}
struct TextRun {bytes: u8[:]}
struct TextRuns {storage: TextRun[:] = default<TextRun[:]>(),items: TextRun[:] = default<TextRun[:]>()}
reusable[] var node_pool: Node[>..] = [];
reusable[] var shape_pool: Shape[>..] = [];
reusable[] var member_pool: Member[>..] = [];
reusable[] var member_key_pool: dictionary_slot<const u8[:],i64>[>..] = [];
reusable[] var field_pool: Field[>..] = [];
reusable[] var element_pool: u32[>..] = [];
reusable[] var text_pool: u8[>..] = [];
reusable[] var text_runs_pool: TextRun[>..] = [];
fn push(self_: Nodes&,node: Node) -> Error {return blot_support_pooled_buffer::push(self_,node,node_pool);}
fn push(self_: Shapes&,shape: Shape) -> Error {return blot_support_pooled_buffer::push(self_,shape,shape_pool);}
fn push(self_: Members&,member: Member) -> Error {return blot_support_pooled_buffer::push(self_,Member{name:rootedText(member.name),value:member.value},member_pool);}
fn deinit(self_: Members&) {blot_support_pooled_buffer::deinit(self_,member_pool);}
struct Reader {input: const u8[:],at: i64 = 0,nodes: Nodes = Nodes {..},shapes: Shapes = Shapes {..},interned: dictionary<const u8[:],u32>&,texts: TextRuns = TextRuns {..},serial: i64 = 0,visits: i64 = 0,header: Text = Text {..},body: Text = Text {..},issue: blot_support::Option<Issue> = blot_support::none<Issue>(),string_wellformed: bool = true}
fn own(self_: Reader&,bytes: const u8[:]) -> const u8[:],Error {if bytes.len == 0 {return default<const u8[:]>(),blot_error::Error.none;}let result = text_pool.alloc_slice(bytes.len);for index in 0..bytes.len {result[index] = bytes[index];}let error = blot_support_pooled_buffer::push(self_.texts,TextRun {bytes: result},text_runs_pool);if error != blot_error::Error.none {text_pool.free_slice(result);return default<const u8[:]>(),error;}return result,blot_error::Error.none;}
fn deinit(self_: Reader&) {for node in self_.nodes.items {if node.members.len != 0 {member_pool.free_slice(node.members);}}for shape in self_.shapes.items {if shape.fields.len != 0 {field_pool.free_slice(shape.fields);}if shape.elements.len != 0 {element_pool.free_slice(shape.elements);}}for text in self_.texts.items {text_pool.free_slice(text.bytes);}blot_support_pooled_buffer::deinit(self_.texts,text_runs_pool);blot_support_pooled_buffer::deinit(self_.nodes,node_pool);blot_support_pooled_buffer::deinit(self_.shapes,shape_pool);self_.header.deinit();self_.body.deinit();self_.interned.clear();}
fn fail(self_: Reader&,start: i64,end: i64,code: const u8[:],message: const u8[:]) -> Error {self_.issue = blot_support::some(Issue {start: min(start,self_.input.len) as u32,end: min(max(start,end),self_.input.len) as u32,code: code,message: message});return blot_error::Error.invalid_asset;}
fn problem(self_: Reader&,id: u32,code: const u8[:],message: const u8[:]) -> Error {let node = self_.nodes.items[id];return self_.fail(node.start,node.end,code,message);}
fn budget(self_: Reader&,depth: i64) -> Error {self_.visits++;if depth > 128 || self_.visits > 1000000 {return self_.fail(self_.at,self_.at,"asset_limit","Asset exceeds the structural budget");}return blot_error::Error.none;}
fn put(self_: Reader&,out: Text&,text: const u8[:]) -> Error {if text.len > limit || out.len > limit - text.len {return self_.fail(0,self_.input.len,"asset_limit","Generated asset module exceeds 16 MiB");}return out.append(text);}
fn integer<T>(self_: Reader&,out: Text&,value: T) -> Error {var text: u8[>..] = [];format(text,value);return self_.put(out,text);}
fn float32(self_: Reader&,out: Text&,value: f64) -> Error {var text: u8[>..<] = [];blot_backend_native_asset_numbers::float32(text,value);return self_.put(out,text);}
fn skip(self_: Reader&) {while self_.at < self_.input.len {let byte = self_.input[self_.at];if byte != ' ' && byte != '\t' && byte != '\r' && byte != '\n' {break;}self_.at++;}}
fn take(self_: Reader&,byte: u8) -> bool {self_.skip();if self_.at == self_.input.len || self_.input[self_.at] != byte {return false;}self_.at++;return true;}
fn syntax(self_: Reader&) -> Error {return self_.fail(self_.at,self_.at + 1,"asset_json","Malformed JSON asset");}
fn hex(byte: u8) -> u32,bool {if byte >= '0' && byte <= '9' {return (byte - '0') as u32,true;}if byte >= 'a' && byte <= 'f' {return (byte - 'a' + 10) as u32,true;}if byte >= 'A' && byte <= 'F' {return (byte - 'A' + 10) as u32,true;}return 0,false;}
fn half(bytes: const u8[:],at: i64) -> u32,bool {if at + 4 > bytes.len {return 0,false;}var value: u32 = 0;for index in at..at + 4 {let digit,valid = hex(bytes[index]);if !valid {return 0,false;}value = value * 16 + digit;}return value,true;}
fn encode(out: Text&,point: u32) -> Error {if point < 128 {return out.push(point as u8);}if point < 2048 {let first = out.push((192 | (point >> 6)) as u8);if first != blot_error::Error.none {return first;}return out.push((128 | (point & 63)) as u8);}if point < 65536 {let first = out.push((224 | (point >> 12)) as u8);if first != blot_error::Error.none {return first;}let second = out.push((128 | ((point >> 6) & 63)) as u8);if second != blot_error::Error.none {return second;}return out.push((128 | (point & 63)) as u8);}let first = out.push((240 | (point >> 18)) as u8);if first != blot_error::Error.none {return first;}let second = out.push((128 | ((point >> 12) & 63)) as u8);if second != blot_error::Error.none {return second;}let third = out.push((128 | ((point >> 6) & 63)) as u8);if third != blot_error::Error.none {return third;}return out.push((128 | (point & 63)) as u8);}
fn decodePoint(bytes: const u8[:],at: i64) -> u32,i64,bool {
    if at >= bytes.len {return 0,0,false;}let first = bytes[at];if first < 128 {return first as u32,1,true;}var length: i64 = 0;var point: u32 = 0;var least: u32 = 0;if first >= 194 && first <= 223 {length = 2;point = (first as u32) & 31;least = 128;}else if first >= 224 && first <= 239 {length = 3;point = (first as u32) & 15;least = 2048;}else if first >= 240 && first <= 244 {length = 4;point = (first as u32) & 7;least = 65536;}else {return 0,0,false;}if length > bytes.len - at {return 0,0,false;}for index in at + 1..at + length {let byte = bytes[index];if (byte & 192) != 128 {return 0,0,false;}point = (point << 6) | ((byte as u32) & 63);}if point < least || point > 1114111 || (point >= 55296 && point <= 57343) {return 0,0,false;}return point,length,true;
}
fn string(self_: Reader&) -> const u8[:],Error {
    let start = self_.at;self_.string_wellformed = true;if !self_.take('"') {return default<const u8[:]>(),self_.syntax();}let content = self_.at;var finish: i64 = -1;
    while self_.at < self_.input.len {let byte = self_.input[self_.at];self_.at++;if byte == '"' {finish = self_.at;break;}if byte == '\\' {if self_.at == self_.input.len {return default<const u8[:]>(),self_.syntax();}self_.at++;}else if byte < 32 {return default<const u8[:]>(),self_.syntax();}}
    if finish < 0 {return default<const u8[:]>(),self_.syntax();}var decoded = Text {..};
    fn scan() -> const u8[:],Error {
        var at = content;
        while at < finish - 1 {let byte = self_.input[at];at++;if byte != '\\' {let error = decoded.push(byte);if error != blot_error::Error.none {return default<const u8[:]>(),error;}continue;}if at >= finish - 1 {return default<const u8[:]>(),self_.fail(start,finish,"asset_json","Malformed JSON string");}let escape = self_.input[at];at++;
            if escape == 'u' {if at + 4 > finish - 1 {return default<const u8[:]>(),self_.fail(start,finish,"asset_json","Malformed JSON string");}let first,valid = half(self_.input,at);if !valid {return default<const u8[:]>(),self_.fail(start,finish,"asset_json","Malformed JSON string");}at += 4;var point = first;
                if first >= 55296 && first <= 57343 {var pair = false;if first < 56320 && at + 6 <= finish - 1 && self_.input[at] == '\\' && self_.input[at + 1] == 'u' {let low,low_valid = half(self_.input,at + 2);if low_valid && low >= 56320 && low <= 57343 {point = 65536 + ((first - 55296) << 10) + low - 56320;at += 6;pair = true;}}if !pair {point = 65533;self_.string_wellformed = false;}}let error = encode(decoded,point);if error != blot_error::Error.none {return default<const u8[:]>(),error;}
            }else {var value: u8 = 0;match escape {'"'=>{value = '"';},'\\'=>{value = '\\';},'/'=>{value = '/';},'b'=>{value = 8;},'f'=>{value = 12;},'n'=>{value = 10;},'r'=>{value = 13;},'t'=>{value = 9;},_=>{return default<const u8[:]>(),self_.fail(start,finish,"asset_json","Malformed JSON string");},}let error = decoded.push(value);if error != blot_error::Error.none {return default<const u8[:]>(),error;}}
        }return self_.own(decoded.items);
    }
    let value,error = scan();decoded.deinit();return value,error;
}

fn digit(byte: u8) -> bool {return byte >= '0' && byte <= '9';}
recursive fn parse(self_: Reader&,depth: i64) -> u32,Error {
    let bounded = self_.budget(depth);if bounded != blot_error::Error.none {return 0,bounded;}self_.skip();let start = self_.at;if start == self_.input.len {return 0,self_.syntax();}var node = Node {tag: Tag.null_value,start: start as u32,..};let byte = self_.input[self_.at];
    if byte == '"' {let text,error = self_.string();if error != blot_error::Error.none {return 0,error;}node.tag = Tag.string;node.text = text;node.wellformed = self_.string_wellformed;}
    else if byte == '[' || byte == '{' {
        self_.at++;node.tag = Tag.array;var close: u8 = ']';if byte == '{' {node.tag = Tag.object;close = '}';}var members = Members {..};var keys = blot_support_pooled_map::Map<const u8[:],i64> {..};
        recursive fn container() -> Error {
            if !self_.take(close) {while true {var name: const u8[:] = default<const u8[:]>();if node.tag == Tag.object {self_.skip();let parsed,error = self_.string();if error != blot_error::Error.none {return error;}name = parsed;if !self_.take(':') {return self_.syntax();}}let child,error = self_.parse(depth + 1);if error != blot_error::Error.none {return error;}
                var existing: i64 = -1;if node.tag == Tag.object {let found .= blot_support_pooled_map::get(keys,name);if found {existing = found;}}if existing >= 0 {members.items[existing].value = child;}else {if node.tag == Tag.object {blot_support_pooled_map::insert(keys,name,members.items.len,member_key_pool);}let added = members.push(Member {name: name,value: child});if added != blot_error::Error.none {return added;}}if self_.take(close) {break;}if !self_.take(',') {return self_.syntax();}
            }}return blot_error::Error.none;
        }
        let parsed = container();blot_support_pooled_map::deinit(keys,member_key_pool);if parsed != blot_error::Error.none {members.deinit();return 0,parsed;}if members.items.len != 0 {let owned = member_pool.alloc_slice(members.items.len);for index in 0..owned.len {let member=members.items[index];owned[index]=Member{name:rootedText(member.name),value:member.value};}node.members = owned;}members.deinit();
    }
    else if byte == 't' || byte == 'f' || byte == 'n' {var token: const u8[:] = "null";if byte == 't' {token = "true";node.tag = Tag.boolean;node.boolean = true;}if byte == 'f' {token = "false";node.tag = Tag.boolean;}if token.len > self_.input.len - self_.at || self_.input[self_.at..self_.at + token.len] != token {return 0,self_.syntax();}self_.at += token.len;}
    else {
        node.tag = Tag.number;if self_.input[self_.at] == '-' {self_.at++;}if self_.at == self_.input.len {return 0,self_.syntax();}if self_.input[self_.at] == '0' {self_.at++;}else {if self_.input[self_.at] < '1' || self_.input[self_.at] > '9' {return 0,self_.syntax();}while self_.at < self_.input.len && digit(self_.input[self_.at]) {self_.at++;}}
        if self_.at < self_.input.len && self_.input[self_.at] == '.' {self_.at++;let first = self_.at;while self_.at < self_.input.len && digit(self_.input[self_.at]) {self_.at++;}if first == self_.at {return 0,self_.syntax();}}
        if self_.at < self_.input.len && (self_.input[self_.at] == 'e' || self_.input[self_.at] == 'E') {self_.at++;if self_.at < self_.input.len && (self_.input[self_.at] == '+' || self_.input[self_.at] == '-') {self_.at++;}let first = self_.at;while self_.at < self_.input.len && digit(self_.input[self_.at]) {self_.at++;}if first == self_.at {return 0,self_.syntax();}}
        let value,valid = blot_backend_native_asset_numbers::decimal(self_.input[start..self_.at]);if !valid {return 0,self_.syntax();}node.number = value;
    }
    node.end = self_.at as u32;let id = self_.nodes.items.len as u32;let error = self_.nodes.push(node);if error != blot_error::Error.none && node.members.len != 0 {member_pool.free_slice(node.members);}return id,error;
}
fn parts(self_: Reader&,out: Text&,values: const (const u8[:])[:]) -> Error {for value in values {let error = self_.put(out,value);if error != blot_error::Error.none {return error;}}return blot_error::Error.none;}
fn text(self_: Reader&,values: const (const u8[:])[:]) -> const u8[:],Error {var bytes: u8[>..] = [];for value in values {bytes.append(value);}return self_.own(bytes);}
fn boundedUtf8Prefix(bytes: const u8[:],maximum: i64) -> const u8[:] {var end = min(bytes.len,maximum);while end > 0 && end < bytes.len && (bytes[end] & 192) == 128 {end--;}return bytes[..end];}
fn identifier(self_: Reader&,id: u32,name: const u8[:]) -> Error {var valid = name.len > 0 && name != "_";if valid {valid = (name[0] >= 'a' && name[0] <= 'z') || name[0] == '_';}for byte in name {if !((byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') || digit(byte) || byte == '_') {valid = false;break;}}for keyword in ["const","let","type","data","effect","is","func","do","use","return","yield","break","for","ever","continue","in","case","of","if","then","else","as","import","infix","infixl","infixr","self","where","and","or","true","false"] {if name == keyword {valid = false;break;}}if !valid {let message,error = self_.text(["Invalid Blot value/field name: ",boundedUtf8Prefix(name,256)]);if error != blot_error::Error.none {return error;}return self_.problem(id,"asset_identifier",message);}return blot_error::Error.none;}
fn member(self_: const Reader&,id: u32,name: const u8[:]) -> blot_support::Option<u32> {for item in self_.nodes.items[id].members {if item.name == name {return blot_support::some(item.value);}}return blot_support::none<u32>();}
fn object(self_: Reader&,id: u32) -> Error {if self_.nodes.items[id].tag != Tag.object {return self_.problem(id,"asset_shape","Expected a JSON object");}return blot_error::Error.none;}
fn less(left: const u8[:],right: const u8[:]) -> bool {for index in 0..min(left.len,right.len) {if left[index] != right[index] {return left[index] < right[index];}}return left.len < right.len;}
fn shapeName(tag: ShapeTag) -> const u8[:] {match tag {unit=>"unit",boolean=>"boolean",u32_value=>"u32_value",f32_value=>"f32_value",array=>"array",tuple=>"tuple",record=>"record",utf8=>"utf8",}}
fn freeShape(shape: Shape) {if shape.fields.len != 0 {field_pool.free_slice(shape.fields);}if shape.elements.len != 0 {element_pool.free_slice(shape.elements);}}
fn intern(self_: Reader&,shape: Shape) -> u32,Error {
    var key = Text {..};
    fn identify() -> u32,Error {
        let tag = self_.put(key,shapeName(shape.tag));if tag != blot_error::Error.none {return 0,tag;}for item in shape.elements {let separator = self_.put(key,":");if separator != blot_error::Error.none {return 0,separator;}let value = self_.integer(key,item);if value != blot_error::Error.none {return 0,value;}}
        for field in shape.fields {let named = self_.parts(key,[":",field.name,"="]);if named != blot_error::Error.none {return 0,named;}let value = self_.integer(key,field.shape);if value != blot_error::Error.none {return 0,value;}}
        {let known .= self_.interned.get(key.items);if known {freeShape(shape);return known,blot_error::Error.none;}}
        var named = shape;if shape.tag == ShapeTag.record {self_.serial++;var name: u8[>..] = [];format(name,"JsonRecord",self_.serial);let copied,error = self_.own(name);if error != blot_error::Error.none {return 0,error;}named.name = copied;}let id = self_.shapes.items.len as u32;let owned_key,error = self_.own(key.items);if error != blot_error::Error.none {return 0,error;}let inserted = self_.shapes.push(named);if inserted != blot_error::Error.none {return 0,inserted;}self_.interned.insert(owned_key,id);return id,blot_error::Error.none;
    }
    let id,error = identify();key.deinit();if error != blot_error::Error.none {freeShape(shape);}return id,error;
}
recursive fn infer(self_: Reader&,id: u32,depth: i64) -> u32,Error {
    let bounded = self_.budget(depth);if bounded != blot_error::Error.none {return 0,bounded;}let node = self_.nodes.items[id];var shape_id: u32 = 0;
    match node.tag {
        null_value=>{shape_id = 0;},boolean=>{shape_id = 1;},
        number=>{let value = node.number;var magnitude = value;if magnitude < 0.0 {magnitude = -magnitude;}if blot_backend_native_asset_numbers::finite(value) && blot_backend_native_asset_numbers::integral(value) && magnitude > 9007199254740991.0 {return 0,self_.problem(id,"asset_number","JSON integer exceeds exact host representation");}shape_id = 3;if blot_backend_native_asset_numbers::integral(value) && value >= 0.0 && value <= 4294967295.0 && !(value == 0.0 && blot_backend_native_asset_numbers::negative(value)) {shape_id = 2;}let single = value as! f32;if !blot_backend_native_asset_numbers::finite(single as f64) {return 0,self_.problem(id,"asset_number","Asset number does not fit finite F32");}},
        string=>{if !node.wellformed {return 0,self_.problem(id,"asset_unicode","JSON strings must be well-formed Unicode");}shape_id = 4;},
        array=>{
            let count = node.members.len;var start:i64=0;
            if count!=0 {let allocated=element_pool.alloc_slice(count);start=element_pool.index_of(allocated[0]);}
            var homogeneous=count>0;
            for item,index in node.members {
                let element,error=self_.infer(item.value,depth+1);
                if error!=blot_error::Error.none {if count!=0 {element_pool.free_slice(element_pool[start..start+count]);}return 0,error;}
                element_pool[start+index]=element;
                if element!=element_pool[start] {homogeneous=false;}
            }
            var elements:u32[:]=default<u32[:]>();if count!=0 {elements=element_pool[start..start+count];}
            var shape=Shape{tag:ShapeTag.tuple,elements:elements,..};
            if homogeneous {let first=element_pool.alloc_slice(1);first[0]=elements[0];element_pool.free_slice(elements);shape.tag=ShapeTag.array;shape.elements=first;}
            let interned,error=self_.intern(shape);if error!=blot_error::Error.none {return 0,error;}shape_id=interned;
        },
        object=>{let sorted_members=member_pool.realloc_slice(node.members,node.members.len);for index in 1..sorted_members.len {let item = sorted_members[index];var position = index;while position > 0 && less(item.name,sorted_members[position - 1].name) {sorted_members[position] = sorted_members[position - 1];position--;}sorted_members[position] = item;}var fields: Field[:] = default<Field[:]>();if node.members.len != 0 {fields = field_pool.alloc_slice(node.members.len);}
            for item,index in node.members {let named = self_.identifier(item.value,item.name);if named != blot_error::Error.none {if fields.len != 0 {field_pool.free_slice(fields);}return 0,named;}let shape,error = self_.infer(item.value,depth + 1);if error != blot_error::Error.none {if fields.len != 0 {field_pool.free_slice(fields);}return 0,error;}fields[index] = Field {name: rootedText(item.name),shape: shape};}
            var shape = Shape {tag: ShapeTag.record,fields: fields,..};if depth == 0 {shape.name = "Data";shape_id = self_.shapes.items.len as u32;let inserted = self_.shapes.push(shape);if inserted != blot_error::Error.none {freeShape(shape);return 0,inserted;}}else {let interned,error = self_.intern(shape);if error != blot_error::Error.none {return 0,error;}shape_id = interned;}
        },
    }
    self_.nodes.items[id].shape = shape_id;return shape_id,blot_error::Error.none;
}
recursive fn shapeType(self_: Reader&,out: Text&,id: u32,depth: i64) -> Error {
    let bounded = self_.budget(depth);if bounded != blot_error::Error.none {return bounded;}let shape = self_.shapes.items[id];
    match shape.tag {
        unit=>{return self_.put(out,"Unit");},boolean=>{return self_.put(out,"Bool");},u32_value=>{return self_.put(out,"U32");},f32_value=>{return self_.put(out,"F32");},
        utf8=>{if !shape.emitted {let declaration = self_.put(self_.header,"type Utf8 is data = $Utf8 { bytes: (Array U32) }\n");if declaration != blot_error::Error.none {return declaration;}self_.shapes.items[id].emitted = true;}return self_.put(out,"Utf8");},
        array=>{let opened = self_.put(out,"(Array ");if opened != blot_error::Error.none {return opened;}let element = self_.shapeType(out,shape.elements[0],depth + 1);if element != blot_error::Error.none {return element;}return self_.put(out,")");},
        tuple=>{let opened = self_.put(out,"(");if opened != blot_error::Error.none {return opened;}for element,index in shape.elements {if index > 0 {let separator = self_.put(out,", ");if separator != blot_error::Error.none {return separator;}}let value = self_.shapeType(out,element,depth + 1);if value != blot_error::Error.none {return value;}}if shape.elements.len == 1 {let comma = self_.put(out,",");if comma != blot_error::Error.none {return comma;}}return self_.put(out,")");},
        record=>{if !shape.emitted {var declaration = Text {..};
            recursive fn build() -> Error {let header = self_.parts(declaration,["type ",shape.name," is data = $",shape.name," { "]);if header != blot_error::Error.none {return header;}for field,index in shape.fields {if index > 0 {let separator = self_.put(declaration,", ");if separator != blot_error::Error.none {return separator;}}let named = self_.parts(declaration,[field.name,": "]);if named != blot_error::Error.none {return named;}let ty = self_.shapeType(declaration,field.shape,depth + 1);if ty != blot_error::Error.none {return ty;}}let closed = self_.put(declaration," }\n");if closed != blot_error::Error.none {return closed;}let published = self_.put(self_.header,declaration.items);if published != blot_error::Error.none {return published;}self_.shapes.items[id].emitted = true;return blot_error::Error.none;}
            let generated = build();declaration.deinit();if generated != blot_error::Error.none {return generated;}
        }return self_.put(out,shape.name);},
    }
}
recursive fn jsonValue(self_: Reader&,out: Text&,id: u32,depth: i64) -> Error {
    let bounded = self_.budget(depth);if bounded != blot_error::Error.none {return bounded;}let node = self_.nodes.items[id];let shape = self_.shapes.items[node.shape];
    match node.tag {
        null_value=>{return self_.put(out,"()");},boolean=>{if node.boolean {return self_.put(out,"true");}return self_.put(out,"false");},number=>{if node.shape == 2 {return self_.integer(out,node.number as u32);}return self_.float32(out,node.number);},
        string=>{let opened = self_.put(out,"($Utf8 { bytes: #[");if opened != blot_error::Error.none {return opened;}for byte,index in node.text {let bounded = self_.budget(depth + 2);if bounded != blot_error::Error.none {return bounded;}if index > 0 {let comma = self_.put(out,", ");if comma != blot_error::Error.none {return comma;}}let value = self_.integer(out,byte);if value != blot_error::Error.none {return value;}}return self_.put(out,"] })");},
        array=>{var opened: const u8[:] = "(";if shape.tag == ShapeTag.array {opened = "#[";}let start = self_.put(out,opened);if start != blot_error::Error.none {return start;}for item,index in node.members {if index > 0 {let comma = self_.put(out,", ");if comma != blot_error::Error.none {return comma;}}let value = self_.jsonValue(out,item.value,depth + 1);if value != blot_error::Error.none {return value;}}if shape.tag == ShapeTag.array {return self_.put(out,"]");}if node.members.len == 1 {let comma = self_.put(out,",");if comma != blot_error::Error.none {return comma;}}return self_.put(out,")");},
        object=>{let opened = self_.parts(out,["($",shape.name," { "]);if opened != blot_error::Error.none {return opened;}for item,index in node.members {if index > 0 {let comma = self_.put(out,", ");if comma != blot_error::Error.none {return comma;}}let named = self_.parts(out,[item.name,": "]);if named != blot_error::Error.none {return named;}let value = self_.jsonValue(out,item.value,depth + 1);if value != blot_error::Error.none {return value;}}return self_.put(out," })");},
    }
}
fn json(self_: Reader&,root: u32) -> Error {
    for tag in [ShapeTag.unit,ShapeTag.boolean,ShapeTag.u32_value,ShapeTag.f32_value,ShapeTag.utf8] {let inserted = self_.shapes.push(Shape {tag,..});if inserted != blot_error::Error.none {return inserted;}}let shape,error = self_.infer(root,0);if error != blot_error::Error.none {return error;}self_.visits = 0;var annotation = Text {..};
    fn build() -> Error {let ty = self_.shapeType(annotation,shape,0);if ty != blot_error::Error.none {return ty;}if self_.nodes.items[root].tag != Tag.object {let declaration = self_.parts(self_.header,["type Data = ",annotation.items,"\n"]);if declaration != blot_error::Error.none {return declaration;}}let opened = self_.parts(self_.body,["const value: ",annotation.items," = "]);if opened != blot_error::Error.none {return opened;}let value = self_.jsonValue(self_.body,root,0);if value != blot_error::Error.none {return value;}return self_.put(self_.body,"\n");}
    let result = build();annotation.deinit();return result;
}
fn recordStart(self_: Reader&,name: const u8[:],value: const u8[:]) -> Error {let header = self_.parts(self_.header,["type ",name," is data = $",name," { "]);if header != blot_error::Error.none {return header;}return self_.parts(self_.body,["const ",value,": ",name," = ($",name," { "]);}
fn recordEnd(self_: Reader&) -> Error {let header = self_.put(self_.header," }\n");if header != blot_error::Error.none {return header;}return self_.put(self_.body," })\n");}
fn emitField(self_: Reader&,name: const u8[:],shape: const u8[:],index: i64) -> Error {if index > 0 {let header = self_.put(self_.header,", ");if header != blot_error::Error.none {return header;}let body = self_.put(self_.body,", ");if body != blot_error::Error.none {return body;}}let header = self_.parts(self_.header,[name,": ",shape]);if header != blot_error::Error.none {return header;}return self_.parts(self_.body,[name,": "]);}
fn ends(bytes: const u8[:],suffix: const u8[:]) -> bool {return suffix.len <= bytes.len && bytes[bytes.len - suffix.len..] == suffix;}
fn catalog(self_: Reader&,root: u32) -> Error {
    let object = self_.object(root);if object != blot_error::Error.none {return object;}let categories: const u8[:][3] = ["meshes","materials","sounds"];let names: const u8[:][3] = ["Meshes","Materials","Sounds"];
    for category,ordinal in categories {let opened = self_.recordStart(names[ordinal],category);if opened != blot_error::Error.none {return opened;}let selected = self_.member(root,category);if selected.present {let list = self_.nodes.items[selected.value];if list.tag != Tag.null_value {if list.tag != Tag.array {return self_.problem(selected.value,"asset_catalog","Catalog category must be a list of filenames");}var used: dictionary<const u8[:],bool> = dictionary<const u8[:],bool> {};
        for item,index in list.members {let file = self_.nodes.items[item.value];if file.tag != Tag.string {return self_.problem(item.value,"asset_catalog","Catalog filename must be text");}var basename = file.text;for suffix in [".mesh.json",".material.json"] {if ends(basename,suffix) {basename = basename[..basename.len - suffix.len];break;}}for suffix in [".wav",".ogg",".json"] {if ends(basename,suffix) {basename = basename[..basename.len - suffix.len];break;}}
            var field_name = Text {..};var at: i64 = 0;
            while at < basename.len {let point,length,valid = decodePoint(basename,at);assert(valid);at += length;var byte: u8 = '_';if point < 128 {let ascii = point as u8;if (ascii >= 'a' && ascii <= 'z') || (ascii >= 'A' && ascii <= 'Z') || digit(ascii) || ascii == '_' {byte = ascii;}}let first = field_name.push(byte);if first != blot_error::Error.none {field_name.deinit();return first;}if point > 65535 {let second = field_name.push('_');if second != blot_error::Error.none {field_name.deinit();return second;}}}
            let named = self_.identifier(item.value,field_name.items);if named != blot_error::Error.none {field_name.deinit();return named;}if used.get(field_name.items) {field_name.deinit();let message,error = self_.text(["catalog ",category,": two files share a name"]);if error != blot_error::Error.none {return error;}return self_.problem(item.value,"asset_catalog",message);}let owned,error = self_.own(field_name.items);if error != blot_error::Error.none {field_name.deinit();return error;}used.insert(owned,true);let emitted = self_.emitField(field_name.items,"U32",index);field_name.deinit();if emitted != blot_error::Error.none {return emitted;}let value = self_.integer(self_.body,index);if value != blot_error::Error.none {return value;}
        }
    }}let closed = self_.recordEnd();if closed != blot_error::Error.none {return closed;}}
    return blot_error::Error.none;
}
fn inFont(point: u32) -> bool {if point >= 32 && point <= 126 {return true;}let extras = "åäöÅÄÖéüÉ‹›•…×–—";var at: i64 = 0;while at < extras.len {let extra,length,valid = decodePoint(extras,at);assert(valid);if extra == point {return true;}at += length;}return false;}
fn points(self_: Reader&,out: Text&,id: u32,name: const u8[:],shown: bool) -> Error {
    let node = self_.nodes.items[id];if node.tag != Tag.string {return self_.problem(id,"asset_text","Text must be a string or a list of strings");}
    if !shown {var missing = Text {..};var seen: dictionary<u32,bool> = dictionary<u32,bool> {};var at: i64 = 0;while at < node.text.len {let point,length,valid = decodePoint(node.text,at);assert(valid);if !inFont(point) && missing.len < 512 && !seen.get(point) {seen.insert(point,true);let appended = missing.append(node.text[at..at + length]);if appended != blot_error::Error.none {missing.deinit();return appended;}}at += length;}if missing.len > 0 {let message,error = self_.text(["text ",boundedUtf8Prefix(name,256),": the font has no ",missing.items]);missing.deinit();if error != blot_error::Error.none {return error;}return self_.problem(id,"asset_font",message);}missing.deinit();}
    let opened = self_.put(out,"#[");if opened != blot_error::Error.none {return opened;}var at: i64 = 0;var index: i64 = 0;while at < node.text.len {let point,length,valid = decodePoint(node.text,at);assert(valid);at += length;let bounded = self_.budget(1);if bounded != blot_error::Error.none {return bounded;}var value = point;if shown && !inFont(point) {value = 63;}if index > 0 {let separator = self_.put(out,", ");if separator != blot_error::Error.none {return separator;}}let emitted = self_.integer(out,value);if emitted != blot_error::Error.none {return emitted;}index++;}return self_.put(out,"]");
}
fn textModule(self_: Reader&,root: u32) -> Error {
    let object = self_.object(root);if object != blot_error::Error.none {return object;}let opened = self_.recordStart("Text","text");if opened != blot_error::Error.none {return opened;}
    for item,index in self_.nodes.items[root].members {let named = self_.identifier(item.value,item.name);if named != blot_error::Error.none {return named;}let node = self_.nodes.items[item.value];if node.tag == Tag.string {let field = self_.emitField(item.name,"(Array U32)",index);if field != blot_error::Error.none {return field;}let values = self_.points(self_.body,item.value,item.name,false);if values != blot_error::Error.none {return values;}}
        else {if node.tag != Tag.array {return self_.problem(item.value,"asset_text","Text must be a string or a list of strings");}let field = self_.emitField(item.name,"(Array (Array U32))",index);if field != blot_error::Error.none {return field;}let opened = self_.put(self_.body,"#[");if opened != blot_error::Error.none {return opened;}for line,line_index in node.members {if line_index > 0 {let separator = self_.put(self_.body,", ");if separator != blot_error::Error.none {return separator;}}let value = self_.points(self_.body,line.value,item.name,false);if value != blot_error::Error.none {return value;}}let closed = self_.put(self_.body,"]");if closed != blot_error::Error.none {return closed;}}
    }return self_.recordEnd();
}
fn tunableNumber(self_: Reader&,id: u32,key: const u8[:]) -> f64,Error {let selected = self_.member(id,key);if !selected.present {let message,error = self_.text([key," must be a finite number"]);if error != blot_error::Error.none {return 0.0,error;}return 0.0,self_.problem(id,"asset_tunables",message);}let node = self_.nodes.items[selected.value];let single = node.number as! f32;if node.tag != Tag.number || !blot_backend_native_asset_numbers::finite(single as f64) {let message,error = self_.text([key," must be a finite number"]);if error != blot_error::Error.none {return 0.0,error;}return 0.0,self_.problem(selected.value,"asset_tunables",message);}return node.number,blot_error::Error.none;}
fn shownSpan(self_: Reader&,out: Text&,count: u32&,id: blot_support::Option<u32>) -> u32[2],Error {let start = count;if id.present {let text = self_.nodes.items[id.value].text;var at: i64 = 0;while at < text.len {let point,length,valid = decodePoint(text,at);assert(valid);at += length;let bounded = self_.budget(1);if bounded != blot_error::Error.none {return [0,0],bounded;}if count != 0 {let comma = self_.put(out,", ");if comma != blot_error::Error.none {return [0,0],comma;}}var value = point;if !inFont(point) {value = 63;}let emitted = self_.integer(out,value);if emitted != blot_error::Error.none {return [0,0],emitted;}count++;}}return [start,count - start],blot_error::Error.none;}
fn tunableName(name: const u8[:]) -> bool {var first = true;if name.len == 0 {return false;}for byte in name {if first {if byte < 'a' || byte > 'z' {return false;}first = false;}else if byte == '.' {first = true;}else if (byte < 'a' || byte > 'z') && !digit(byte) && byte != '_' {return false;}}return !first;}
fn tunableId(name: const u8[:]) -> u32 {var hash: u32 = 2166136261;for byte in name {hash = ((hash ^ byte) as u64 * 16777619) as! u32;}return ((hash >> 24) ^ hash) & 16777215;}
fn tunables(self_: Reader&,root: u32) -> Error {
    let selected = self_.member(root,"tunables");if !selected.present {return self_.problem(root,"asset_tunables","tunables.json: expected { \"tunables\": [...] }");}let list = self_.nodes.items[selected.value];if self_.nodes.items[root].tag != Tag.object || list.tag != Tag.array {return self_.problem(root,"asset_tunables","tunables.json: expected { \"tunables\": [...] }");}
    var fields: dictionary<const u8[:],bool> = dictionary<const u8[:],bool> {};var ids: dictionary<u32,bool> = dictionary<u32,bool> {};var declarations = Text {..};var text = Text {..};var text_count: u32 = 0;
    fn build() -> Error {
        let text_opened = self_.put(text,"const declaration_text: Array U32 = #[");if text_opened != blot_error::Error.none {return text_opened;}let declarations_opened = self_.put(declarations,"const declarations: (Array Declaration) = #[");if declarations_opened != blot_error::Error.none {return declarations_opened;}let opened = self_.recordStart("Tunables","tunables");if opened != blot_error::Error.none {return opened;}
        for item,index in list.members {
            let id = item.value;let object = self_.object(id);if object != blot_error::Error.none {return object;}let name_id = self_.member(id,"name");if !name_id.present {return self_.problem(id,"asset_tunables","Tunable needs a name of lowercase words joined by dots");}let name = self_.nodes.items[name_id.value];if name.tag != Tag.string || !tunableName(name.text) {return self_.problem(name_id.value,"asset_tunables","Tunable needs a name of lowercase words joined by dots");}
            for entry in self_.nodes.items[id].members {var known = false;for key in ["name","default","min","max","step","doc"] {if key == entry.name {known = true;break;}}if !known {let message,error = self_.text(["Unknown tunable field: ",boundedUtf8Prefix(entry.name,256)]);if error != blot_error::Error.none {return error;}return self_.problem(entry.value,"asset_tunables",message);}}
            let initial,initial_error = self_.tunableNumber(id,"default");if initial_error != blot_error::Error.none {return initial_error;}let least,least_error = self_.tunableNumber(id,"min");if least_error != blot_error::Error.none {return least_error;}let most,most_error = self_.tunableNumber(id,"max");if most_error != blot_error::Error.none {return most_error;}if !((least as! f32) < (most as! f32)) {return self_.problem(id,"asset_tunables","min must be below max");}if (initial as! f32) < (least as! f32) || (initial as! f32) > (most as! f32) {return self_.problem(id,"asset_tunables","Tunable default is outside min..max");}
            let step = self_.member(id,"step");if step.present {let value,error = self_.tunableNumber(id,"step");if error != blot_error::Error.none {return error;}if !(value > 0.0) {return self_.problem(step.value,"asset_tunables","step must be positive");}}let doc_id = self_.member(id,"doc");if doc_id.present && self_.nodes.items[doc_id.value].tag != Tag.string {return self_.problem(doc_id.value,"asset_tunables","doc must be text");}
            var renamed = Text {..};for byte in name.text {var value = byte;if value == '.' {value = '_';}let added = renamed.push(value);if added != blot_error::Error.none {renamed.deinit();return added;}}let field_name,field_error = self_.own(renamed.items);renamed.deinit();if field_error != blot_error::Error.none {return field_error;}let named = self_.identifier(name_id.value,field_name);if named != blot_error::Error.none {return named;}if fields.get(field_name) {return self_.problem(name_id.value,"asset_tunables","Two tunables share a field; rename one");}fields.insert(field_name,true);let stable_id = tunableId(name.text);if ids.get(stable_id) {return self_.problem(name_id.value,"asset_tunables","Two tunables share an id; rename one");}ids.insert(stable_id,true);
            let field = self_.emitField(field_name,"(U32, F32, F32, F32)",index);if field != blot_error::Error.none {return field;}let value_opened = self_.put(self_.body,"(");if value_opened != blot_error::Error.none {return value_opened;}let identifier = self_.integer(self_.body,stable_id);if identifier != blot_error::Error.none {return identifier;}for value in [initial,least,most] {let comma = self_.put(self_.body,", ");if comma != blot_error::Error.none {return comma;}let emitted = self_.float32(self_.body,value);if emitted != blot_error::Error.none {return emitted;}}let closed = self_.put(self_.body,")");if closed != blot_error::Error.none {return closed;}if index > 0 {let comma = self_.put(declarations,", ");if comma != blot_error::Error.none {return comma;}}
            let name_span,name_error = self_.shownSpan(text,text_count,name_id);if name_error != blot_error::Error.none {return name_error;}let doc_span,doc_error = self_.shownSpan(text,text_count,doc_id);if doc_error != blot_error::Error.none {return doc_error;}
            let declaration_opened = self_.put(declarations,"($Declaration { name_start: ");if declaration_opened != blot_error::Error.none {return declaration_opened;}let name_start = self_.integer(declarations,name_span[0]);if name_start != blot_error::Error.none {return name_start;}let name_count_text = self_.put(declarations,", name_count: ");if name_count_text != blot_error::Error.none {return name_count_text;}let name_count = self_.integer(declarations,name_span[1]);if name_count != blot_error::Error.none {return name_count;}let id_text = self_.put(declarations,", id: ");if id_text != blot_error::Error.none {return id_text;}let id_value = self_.integer(declarations,stable_id);if id_value != blot_error::Error.none {return id_value;}
            let labels: const u8[:][3] = [", initial: ",", least: ",", most: "];let values: f64[3] = [initial,least,most];for value,position in values {let label = self_.put(declarations,labels[position]);if label != blot_error::Error.none {return label;}let emitted = self_.float32(declarations,value);if emitted != blot_error::Error.none {return emitted;}}
            let doc_start_text = self_.put(declarations,", doc_start: ");if doc_start_text != blot_error::Error.none {return doc_start_text;}let doc_start = self_.integer(declarations,doc_span[0]);if doc_start != blot_error::Error.none {return doc_start;}let doc_count_text = self_.put(declarations,", doc_count: ");if doc_count_text != blot_error::Error.none {return doc_count_text;}let doc_count = self_.integer(declarations,doc_span[1]);if doc_count != blot_error::Error.none {return doc_count;}let declaration_closed = self_.put(declarations," })");if declaration_closed != blot_error::Error.none {return declaration_closed;}
        }
        let closed = self_.recordEnd();if closed != blot_error::Error.none {return closed;}let declaration_type = self_.put(self_.header,"type Declaration is data = $Declaration { name_start: U32, name_count: U32, id: U32, initial: F32, least: F32, most: F32, doc_start: U32, doc_count: U32 }\n");if declaration_type != blot_error::Error.none {return declaration_type;}let text_closed = self_.put(text,"]\n");if text_closed != blot_error::Error.none {return text_closed;}let declarations_closed = self_.put(declarations,"]\n");if declarations_closed != blot_error::Error.none {return declarations_closed;}
        let parts: (const u8[:])[4] = [text.items,declarations.items,"const name = func (row: Declaration) => return &declaration_text[row.name_start..row.name_start + row.name_count]\n","const doc = func (row: Declaration) => return &declaration_text[row.doc_start..row.doc_start + row.doc_count]\n"];return self_.parts(self_.body,parts);
    }
    let error = build();text.deinit();declarations.deinit();return error;
}
fn run(self_: Reader&,kind: Kind) -> Error {
    if self_.input.len > limit {return self_.fail(0,self_.input.len,"asset_limit","Asset input exceeds 16 MiB");}var at: i64 = 0;while at < self_.input.len {let point,length,valid = decodePoint(self_.input,at);if !valid {return self_.fail(at,at + 1,"asset_unicode","Asset input must be UTF-8");}at += length;}if self_.input.len >= 3 && self_.input[0] == 239 && self_.input[1] == 187 && self_.input[2] == 191 {self_.at = 3;}
    let root,error = self_.parse(0);if error != blot_error::Error.none {return error;}self_.skip();if self_.at != self_.input.len {return self_.syntax();}self_.visits = 0;var generated = blot_error::Error.none;match kind {json=>{generated = self_.json(root);},catalog=>{generated = self_.catalog(root);},text=>{generated = self_.textModule(root);},tunables=>{generated = self_.tunables(root);},}if generated != blot_error::Error.none {return generated;}if self_.header.len > limit - self_.body.len {return self_.problem(root,"asset_limit","Generated asset module exceeds 16 MiB");}return blot_error::Error.none;
}
fn generate(kind: Kind,bytes: const u8[:]) -> Result,Error {
    var interned: dictionary<const u8[:],u32> = dictionary<const u8[:],u32> {};var reader = Reader {input: bytes,interned: interned,..};let error = reader.run(kind);
    if error != blot_error::Error.none {if error == blot_error::Error.out_of_memory {reader.deinit();return Result.source {bytes: default<u8[:]>()},error;}assert(error == blot_error::Error.invalid_asset && reader.issue.present);let observed=reader.issue.value;let issue=Issue{start:observed.start,end:observed.end,code:copyOutput(observed.code),message:copyOutput(observed.message)};reader.deinit();return Result.issue {value: issue},blot_error::Error.none;}
    let length = reader.header.len + reader.body.len;var source: u8[:] = default<u8[:]>();if length != 0 {source = output_bytes.alloc_slice(length);for index in 0..reader.header.len {source[index] = reader.header.items[index];}for index in 0..reader.body.len {source[reader.header.len + index] = reader.body.items[index];}}reader.deinit();return Result.source {bytes: source},blot_error::Error.none;
}
