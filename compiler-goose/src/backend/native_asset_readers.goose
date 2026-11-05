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
fn copyOutput(bytes: const u8[:]) -> u8[:] {if bytes.len == 0 {return [];}let result = output_bytes.alloc_slice(bytes.len);for index in 0..bytes.len {result[index] = bytes[index];}return result;}
fn freeOutput(bytes: const u8[:]) {if bytes.len != 0 {let first: const u8& = bytes[0];let at = output_bytes.index_of(first);output_bytes.free_slice(output_bytes[at..at + bytes.len]);}}
fn deinit(result: Result&) {match result {source value=>{freeOutput(value.bytes);},issue value=>{freeOutput(value.value.message);},}result = Result.source {bytes: []};}
enum Tag {null_value,boolean,number,string,array,object}
struct Member {name: const u8[:] = [],value: u32}
struct Node {tag: Tag,start: u32,end: u32 = 0,text: const u8[:] = [],number: f64 = 0.0,boolean: bool = false,wellformed: bool = true,members: Member[:] = [],shape: u32 = 0}
enum ShapeTag {unit,boolean,u32_value,f32_value,array,tuple,record,utf8}
struct Field {name: const u8[:],shape: u32}
struct Shape {tag: ShapeTag,name: const u8[:] = [],fields: Field[:] = [],elements: u32[:] = [],emitted: bool = false}
struct Nodes {storage: Node[:] = [],items: Node[:] = []}
struct Shapes {storage: Shape[:] = [],items: Shape[:] = []}
struct Members {storage: Member[:] = [],items: Member[:] = []}
struct TextRun {bytes: u8[:]}
struct TextRuns {storage: TextRun[:] = [],items: TextRun[:] = []}
reusable[] var node_pool: Node[>..] = [];
reusable[] var shape_pool: Shape[>..] = [];
reusable[] var member_pool: Member[>..] = [];
reusable[] var member_key_pool: dictionary_slot<const u8[:],i64>[>..] = [];
reusable[] var field_pool: Field[>..] = [];
reusable[] var element_pool: u32[>..] = [];
reusable[] var text_pool: u8[>..] = [];
reusable[] var text_runs_pool: TextRun[>..] = [];
fn push(self: Nodes&,node: Node) -> Error {return blot_support_pooled_buffer::push(self,node,node_pool);}
fn push(self: Shapes&,shape: Shape) -> Error {return blot_support_pooled_buffer::push(self,shape,shape_pool);}
fn push(self: Members&,member: Member) -> Error {return blot_support_pooled_buffer::push(self,member,member_pool);}
fn deinit(self: Members&) {blot_support_pooled_buffer::deinit(self,member_pool);}
struct Reader {input: const u8[:],at: i64 = 0,nodes: Nodes = Nodes {..},shapes: Shapes = Shapes {..},interned: dictionary<const u8[:],u32>&,texts: TextRuns = TextRuns {..},serial: i64 = 0,visits: i64 = 0,header: Text = Text {..},body: Text = Text {..},issue: blot_support::Option<Issue> = blot_support::none<Issue>(),string_wellformed: bool = true}
fn own(self: Reader&,bytes: const u8[:]) -> const u8[:],Error {if bytes.len == 0 {return [],Error.none;}let result = text_pool.alloc_slice(bytes.len);for index in 0..bytes.len {result[index] = bytes[index];}let error = blot_support_pooled_buffer::push(self.texts,TextRun {bytes: result},text_runs_pool);if error != Error.none {text_pool.free_slice(result);return [],error;}return result,Error.none;}
fn deinit(self: Reader&) {for node in self.nodes.items {if node.members.len != 0 {member_pool.free_slice(node.members);}}for shape in self.shapes.items {if shape.fields.len != 0 {field_pool.free_slice(shape.fields);}if shape.elements.len != 0 {element_pool.free_slice(shape.elements);}}for text in self.texts.items {text_pool.free_slice(text.bytes);}blot_support_pooled_buffer::deinit(self.texts,text_runs_pool);blot_support_pooled_buffer::deinit(self.nodes,node_pool);blot_support_pooled_buffer::deinit(self.shapes,shape_pool);self.header.deinit();self.body.deinit();self.interned.clear();}
fn fail(self: Reader&,start: i64,end: i64,code: const u8[:],message: const u8[:]) -> Error {self.issue = blot_support::some(Issue {start: min(start,self.input.len) as u32,end: min(max(start,end),self.input.len) as u32,code,message});return Error.invalid_asset;}
fn problem(self: Reader&,id: u32,code: const u8[:],message: const u8[:]) -> Error {let node = self.nodes.items[id];return self.fail(node.start,node.end,code,message);}
fn budget(self: Reader&,depth: i64) -> Error {self.visits++;if depth > 128 || self.visits > 1000000 {return self.fail(self.at,self.at,"asset_limit","Asset exceeds the structural budget");}return Error.none;}
fn put(self: Reader&,out: Text&,text: const u8[:]) -> Error {if text.len > limit || out.len > limit - text.len {return self.fail(0,self.input.len,"asset_limit","Generated asset module exceeds 16 MiB");}return out.append(text);}
fn integer<T>(self: Reader&,out: Text&,value: T) -> Error {var text: u8[>..] = [];format(text,value);return self.put(out,text);}
fn float32(self: Reader&,out: Text&,value: f64) -> Error {var text: u8[>..<] = [];blot_backend_native_asset_numbers::float32(text,value);return self.put(out,text);}
fn skip(self: Reader&) {while self.at < self.input.len {let byte = self.input[self.at];if byte != ' ' && byte != '\t' && byte != '\r' && byte != '\n' {break;}self.at++;}}
fn take(self: Reader&,byte: u8) -> bool {self.skip();if self.at == self.input.len || self.input[self.at] != byte {return false;}self.at++;return true;}
fn syntax(self: Reader&) -> Error {return self.fail(self.at,self.at + 1,"asset_json","Malformed JSON asset");}
fn hex(byte: u8) -> u32,bool {if byte >= '0' && byte <= '9' {return (byte - '0') as u32,true;}if byte >= 'a' && byte <= 'f' {return (byte - 'a' + 10) as u32,true;}if byte >= 'A' && byte <= 'F' {return (byte - 'A' + 10) as u32,true;}return 0,false;}
fn half(bytes: const u8[:],at: i64) -> u32,bool {if at + 4 > bytes.len {return 0,false;}var value: u32 = 0;for index in at..at + 4 {let digit,valid = hex(bytes[index]);if !valid {return 0,false;}value = value * 16 + digit;}return value,true;}
fn encode(out: Text&,point: u32) -> Error {if point < 128 {return out.push(point as u8);}if point < 2048 {let first = out.push((192 | (point >> 6)) as u8);if first != Error.none {return first;}return out.push((128 | (point & 63)) as u8);}if point < 65536 {let first = out.push((224 | (point >> 12)) as u8);if first != Error.none {return first;}let second = out.push((128 | ((point >> 6) & 63)) as u8);if second != Error.none {return second;}return out.push((128 | (point & 63)) as u8);}let first = out.push((240 | (point >> 18)) as u8);if first != Error.none {return first;}let second = out.push((128 | ((point >> 12) & 63)) as u8);if second != Error.none {return second;}let third = out.push((128 | ((point >> 6) & 63)) as u8);if third != Error.none {return third;}return out.push((128 | (point & 63)) as u8);}
fn decodePoint(bytes: const u8[:],at: i64) -> u32,i64,bool {
    if at >= bytes.len {return 0,0,false;}let first = bytes[at];if first < 128 {return first as u32,1,true;}var length: i64 = 0;var point: u32 = 0;var least: u32 = 0;if first >= 194 && first <= 223 {length = 2;point = first as u32 & 31;least = 128;}else if first >= 224 && first <= 239 {length = 3;point = first as u32 & 15;least = 2048;}else if first >= 240 && first <= 244 {length = 4;point = first as u32 & 7;least = 65536;}else {return 0,0,false;}if length > bytes.len - at {return 0,0,false;}for index in at + 1..at + length {let byte = bytes[index];if (byte & 192) != 128 {return 0,0,false;}point = (point << 6) | (byte as u32 & 63);}if point < least || point > 1114111 || (point >= 55296 && point <= 57343) {return 0,0,false;}return point,length,true;
}
fn string(self: Reader&) -> const u8[:],Error {
    let start = self.at;self.string_wellformed = true;if !self.take('"') {return [],self.syntax();}let content = self.at;var finish: i64 = -1;
    while self.at < self.input.len {let byte = self.input[self.at];self.at++;if byte == '"' {finish = self.at;break;}if byte == '\\' {if self.at == self.input.len {return [],self.syntax();}self.at++;}else if byte < 32 {return [],self.syntax();}}
    if finish < 0 {return [],self.syntax();}var decoded = Text {..};
    fn scan() -> const u8[:],Error {
        var at = content;
        while at < finish - 1 {let byte = self.input[at];at++;if byte != '\\' {let error = decoded.push(byte);if error != Error.none {return [],error;}continue;}if at >= finish - 1 {return [],self.fail(start,finish,"asset_json","Malformed JSON string");}let escape = self.input[at];at++;
            if escape == 'u' {if at + 4 > finish - 1 {return [],self.fail(start,finish,"asset_json","Malformed JSON string");}let first,valid = half(self.input,at);if !valid {return [],self.fail(start,finish,"asset_json","Malformed JSON string");}at += 4;var point = first;
                if first >= 55296 && first <= 57343 {var pair = false;if first < 56320 && at + 6 <= finish - 1 && self.input[at] == '\\' && self.input[at + 1] == 'u' {let low,low_valid = half(self.input,at + 2);if low_valid && low >= 56320 && low <= 57343 {point = 65536 + ((first - 55296) << 10) + low - 56320;at += 6;pair = true;}}if !pair {point = 65533;self.string_wellformed = false;}}let error = encode(decoded,point);if error != Error.none {return [],error;}
            }else {var value: u8 = 0;match escape {'"'=>{value = '"';},'\\'=>{value = '\\';},'/'=>{value = '/';},'b'=>{value = 8;},'f'=>{value = 12;},'n'=>{value = 10;},'r'=>{value = 13;},'t'=>{value = 9;},_=>{return [],self.fail(start,finish,"asset_json","Malformed JSON string");},}let error = decoded.push(value);if error != Error.none {return [],error;}}
        }return self.own(decoded.items);
    }
    let value,error = scan();decoded.deinit();return value,error;
}

fn digit(byte: u8) -> bool {return byte >= '0' && byte <= '9';}
recursive fn parse(self: Reader&,depth: i64) -> u32,Error {
    let bounded = self.budget(depth);if bounded != Error.none {return 0,bounded;}self.skip();let start = self.at;if start == self.input.len {return 0,self.syntax();}var node = Node {tag: Tag.null_value,start: start as u32,..};let byte = self.input[self.at];
    if byte == '"' {let text,error = self.string();if error != Error.none {return 0,error;}node.tag = Tag.string;node.text = text;node.wellformed = self.string_wellformed;}
    else if byte == '[' || byte == '{' {
        self.at++;node.tag = Tag.array;var close: u8 = ']';if byte == '{' {node.tag = Tag.object;close = '}';}var members = Members {..};var keys = blot_support_pooled_map::Map<const u8[:],i64> {..};
        recursive fn container() -> Error {
            if !self.take(close) {while true {var name: const u8[:] = [];if node.tag == Tag.object {self.skip();let parsed,error = self.string();if error != Error.none {return error;}name = parsed;if !self.take(':') {return self.syntax();}}let child,error = self.parse(depth + 1);if error != Error.none {return error;}
                var existing: i64 = -1;if node.tag == Tag.object {let found .= blot_support_pooled_map::get(keys,name);if found {existing = found;}}if existing >= 0 {members.items[existing].value = child;}else {if node.tag == Tag.object {blot_support_pooled_map::insert(keys,name,members.items.len,member_key_pool);}let added = members.push(Member {name,value: child});if added != Error.none {return added;}}if self.take(close) {break;}if !self.take(',') {return self.syntax();}
            }}return Error.none;
        }
        let parsed = container();blot_support_pooled_map::deinit(keys,member_key_pool);if parsed != Error.none {members.deinit();return 0,parsed;}if members.items.len != 0 {let owned = member_pool.alloc_slice(members.items.len);for index in 0..owned.len {owned[index] = members.items[index];}node.members = owned;}members.deinit();
    }
    else if byte == 't' || byte == 'f' || byte == 'n' {var token: const u8[:] = "null";if byte == 't' {token = "true";node.tag = Tag.boolean;node.boolean = true;}if byte == 'f' {token = "false";node.tag = Tag.boolean;}if token.len > self.input.len - self.at || self.input[self.at..self.at + token.len] != token {return 0,self.syntax();}self.at += token.len;}
    else {
        node.tag = Tag.number;if self.input[self.at] == '-' {self.at++;}if self.at == self.input.len {return 0,self.syntax();}if self.input[self.at] == '0' {self.at++;}else {if self.input[self.at] < '1' || self.input[self.at] > '9' {return 0,self.syntax();}while self.at < self.input.len && digit(self.input[self.at]) {self.at++;}}
        if self.at < self.input.len && self.input[self.at] == '.' {self.at++;let first = self.at;while self.at < self.input.len && digit(self.input[self.at]) {self.at++;}if first == self.at {return 0,self.syntax();}}
        if self.at < self.input.len && (self.input[self.at] == 'e' || self.input[self.at] == 'E') {self.at++;if self.at < self.input.len && (self.input[self.at] == '+' || self.input[self.at] == '-') {self.at++;}let first = self.at;while self.at < self.input.len && digit(self.input[self.at]) {self.at++;}if first == self.at {return 0,self.syntax();}}
        let value,valid = blot_backend_native_asset_numbers::decimal(self.input[start..self.at]);if !valid {return 0,self.syntax();}node.number = value;
    }
    node.end = self.at as u32;let id = self.nodes.items.len as u32;let error = self.nodes.push(node);if error != Error.none && node.members.len != 0 {member_pool.free_slice(node.members);}return id,error;
}
fn parts(self: Reader&,out: Text&,values: const const u8[:][:]) -> Error {for value in values {let error = self.put(out,value);if error != Error.none {return error;}}return Error.none;}
fn text(self: Reader&,values: const const u8[:][:]) -> const u8[:],Error {var bytes: u8[>..] = [];for value in values {bytes.append(value);}return self.own(bytes);}
fn boundedUtf8Prefix(bytes: const u8[:],maximum: i64) -> const u8[:] {var end = min(bytes.len,maximum);while end > 0 && end < bytes.len && (bytes[end] & 192) == 128 {end--;}return bytes[..end];}
fn identifier(self: Reader&,id: u32,name: const u8[:]) -> Error {var valid = name.len > 0 && name != "_";if valid {valid = (name[0] >= 'a' && name[0] <= 'z') || name[0] == '_';}for byte in name {if !((byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') || digit(byte) || byte == '_') {valid = false;break;}}for keyword in ["const","let","type","data","effect","is","func","do","use","return","yield","break","for","ever","continue","in","case","of","if","then","else","as","import","infix","infixl","infixr","self","where","and","or","true","false"] {if name == keyword {valid = false;break;}}if !valid {let message,error = self.text(["Invalid Blot value/field name: ",boundedUtf8Prefix(name,256)]);if error != Error.none {return error;}return self.problem(id,"asset_identifier",message);}return Error.none;}
fn member(self: const Reader&,id: u32,name: const u8[:]) -> blot_support::Option<u32> {for item in self.nodes.items[id].members {if item.name == name {return blot_support::some(item.value);}}return blot_support::none<u32>();}
fn object(self: Reader&,id: u32) -> Error {if self.nodes.items[id].tag != Tag.object {return self.problem(id,"asset_shape","Expected a JSON object");}return Error.none;}
fn less(left: const u8[:],right: const u8[:]) -> bool {for index in 0..min(left.len,right.len) {if left[index] != right[index] {return left[index] < right[index];}}return left.len < right.len;}
fn shapeName(tag: ShapeTag) -> const u8[:] {match tag {unit=>"unit",boolean=>"boolean",u32_value=>"u32_value",f32_value=>"f32_value",array=>"array",tuple=>"tuple",record=>"record",utf8=>"utf8",}}
fn freeShape(shape: Shape) {if shape.fields.len != 0 {field_pool.free_slice(shape.fields);}if shape.elements.len != 0 {element_pool.free_slice(shape.elements);}}
fn intern(self: Reader&,shape: Shape) -> u32,Error {
    var key = Text {..};
    fn identify() -> u32,Error {
        let tag = self.put(key,shapeName(shape.tag));if tag != Error.none {return 0,tag;}for item in shape.elements {let separator = self.put(key,":");if separator != Error.none {return 0,separator;}let value = self.integer(key,item);if value != Error.none {return 0,value;}}
        for field in shape.fields {let named = self.parts(key,[":",field.name,"="]);if named != Error.none {return 0,named;}let value = self.integer(key,field.shape);if value != Error.none {return 0,value;}}
        {let known .= self.interned.get(key.items);if known {freeShape(shape);return known,Error.none;}}
        var named = shape;if shape.tag == ShapeTag.record {self.serial++;var name: u8[>..] = [];format(name,"JsonRecord",self.serial);let copied,error = self.own(name);if error != Error.none {return 0,error;}named.name = copied;}let id = self.shapes.items.len as u32;let owned_key,error = self.own(key.items);if error != Error.none {return 0,error;}let inserted = self.shapes.push(named);if inserted != Error.none {return 0,inserted;}self.interned.insert(owned_key,id);return id,Error.none;
    }
    let id,error = identify();key.deinit();if error != Error.none {freeShape(shape);}return id,error;
}
recursive fn infer(self: Reader&,id: u32,depth: i64) -> u32,Error {
    let bounded = self.budget(depth);if bounded != Error.none {return 0,bounded;}let node = self.nodes.items[id];var shape_id: u32 = 0;
    match node.tag {
        null_value=>{shape_id = 0;},boolean=>{shape_id = 1;},
        number=>{let value = node.number;var magnitude = value;if magnitude < 0.0 {magnitude = -magnitude;}if blot_backend_native_asset_numbers::finite(value) && blot_backend_native_asset_numbers::integral(value) && magnitude > 9007199254740991.0 {return 0,self.problem(id,"asset_number","JSON integer exceeds exact host representation");}shape_id = 3;if blot_backend_native_asset_numbers::integral(value) && value >= 0.0 && value <= 4294967295.0 && !(value == 0.0 && blot_backend_native_asset_numbers::negative(value)) {shape_id = 2;}let single = value as! f32;if !blot_backend_native_asset_numbers::finite(single as f64) {return 0,self.problem(id,"asset_number","Asset number does not fit finite F32");}},
        string=>{if !node.wellformed {return 0,self.problem(id,"asset_unicode","JSON strings must be well-formed Unicode");}shape_id = 4;},
        array=>{var elements: u32[:] = [];if node.members.len != 0 {elements = element_pool.alloc_slice(node.members.len);}var homogeneous = elements.len > 0;for item,index in node.members {let element,error = self.infer(item.value,depth + 1);if error != Error.none {if elements.len != 0 {element_pool.free_slice(elements);}return 0,error;}elements[index] = element;if element != elements[0] {homogeneous = false;}}var shape = Shape {tag: ShapeTag.tuple,elements,..};if homogeneous {let first = element_pool.alloc_slice(1);first[0] = elements[0];element_pool.free_slice(elements);shape.tag = ShapeTag.array;shape.elements = first;}let interned,error = self.intern(shape);if error != Error.none {return 0,error;}shape_id = interned;},
        object=>{for index in 1..node.members.len {let item = node.members[index];var position = index;while position > 0 && less(item.name,node.members[position - 1].name) {node.members[position] = node.members[position - 1];position--;}node.members[position] = item;}var fields: Field[:] = [];if node.members.len != 0 {fields = field_pool.alloc_slice(node.members.len);}
            for item,index in node.members {let named = self.identifier(item.value,item.name);if named != Error.none {if fields.len != 0 {field_pool.free_slice(fields);}return 0,named;}let shape,error = self.infer(item.value,depth + 1);if error != Error.none {if fields.len != 0 {field_pool.free_slice(fields);}return 0,error;}fields[index] = Field {name: item.name,shape};}
            var shape = Shape {tag: ShapeTag.record,fields,..};if depth == 0 {shape.name = "Data";shape_id = self.shapes.items.len as u32;let inserted = self.shapes.push(shape);if inserted != Error.none {freeShape(shape);return 0,inserted;}}else {let interned,error = self.intern(shape);if error != Error.none {return 0,error;}shape_id = interned;}
        },
    }
    self.nodes.items[id].shape = shape_id;return shape_id,Error.none;
}
recursive fn shapeType(self: Reader&,out: Text&,id: u32,depth: i64) -> Error {
    let bounded = self.budget(depth);if bounded != Error.none {return bounded;}let shape = self.shapes.items[id];
    match shape.tag {
        unit=>{return self.put(out,"Unit");},boolean=>{return self.put(out,"Bool");},u32_value=>{return self.put(out,"U32");},f32_value=>{return self.put(out,"F32");},
        utf8=>{if !shape.emitted {let declaration = self.put(self.header,"type Utf8 is data = $Utf8 { bytes: (Array U32) }\n");if declaration != Error.none {return declaration;}self.shapes.items[id].emitted = true;}return self.put(out,"Utf8");},
        array=>{let opened = self.put(out,"(Array ");if opened != Error.none {return opened;}let element = self.shapeType(out,shape.elements[0],depth + 1);if element != Error.none {return element;}return self.put(out,")");},
        tuple=>{let opened = self.put(out,"(");if opened != Error.none {return opened;}for element,index in shape.elements {if index > 0 {let separator = self.put(out,", ");if separator != Error.none {return separator;}}let value = self.shapeType(out,element,depth + 1);if value != Error.none {return value;}}if shape.elements.len == 1 {let comma = self.put(out,",");if comma != Error.none {return comma;}}return self.put(out,")");},
        record=>{if !shape.emitted {var declaration = Text {..};
            recursive fn build() -> Error {let header = self.parts(declaration,["type ",shape.name," is data = $",shape.name," { "]);if header != Error.none {return header;}for field,index in shape.fields {if index > 0 {let separator = self.put(declaration,", ");if separator != Error.none {return separator;}}let named = self.parts(declaration,[field.name,": "]);if named != Error.none {return named;}let ty = self.shapeType(declaration,field.shape,depth + 1);if ty != Error.none {return ty;}}let closed = self.put(declaration," }\n");if closed != Error.none {return closed;}let published = self.put(self.header,declaration.items);if published != Error.none {return published;}self.shapes.items[id].emitted = true;return Error.none;}
            let generated = build();declaration.deinit();if generated != Error.none {return generated;}
        }return self.put(out,shape.name);},
    }
}
recursive fn jsonValue(self: Reader&,out: Text&,id: u32,depth: i64) -> Error {
    let bounded = self.budget(depth);if bounded != Error.none {return bounded;}let node = self.nodes.items[id];let shape = self.shapes.items[node.shape];
    match node.tag {
        null_value=>{return self.put(out,"()");},boolean=>{if node.boolean {return self.put(out,"true");}return self.put(out,"false");},number=>{if node.shape == 2 {return self.integer(out,node.number as u32);}return self.float32(out,node.number);},
        string=>{let opened = self.put(out,"($Utf8 { bytes: #[");if opened != Error.none {return opened;}for byte,index in node.text {let bounded = self.budget(depth + 2);if bounded != Error.none {return bounded;}if index > 0 {let comma = self.put(out,", ");if comma != Error.none {return comma;}}let value = self.integer(out,byte);if value != Error.none {return value;}}return self.put(out,"] })");},
        array=>{var opened: const u8[:] = "(";if shape.tag == ShapeTag.array {opened = "#[";}let start = self.put(out,opened);if start != Error.none {return start;}for item,index in node.members {if index > 0 {let comma = self.put(out,", ");if comma != Error.none {return comma;}}let value = self.jsonValue(out,item.value,depth + 1);if value != Error.none {return value;}}if shape.tag == ShapeTag.array {return self.put(out,"]");}if node.members.len == 1 {let comma = self.put(out,",");if comma != Error.none {return comma;}}return self.put(out,")");},
        object=>{let opened = self.parts(out,["($",shape.name," { "]);if opened != Error.none {return opened;}for item,index in node.members {if index > 0 {let comma = self.put(out,", ");if comma != Error.none {return comma;}}let named = self.parts(out,[item.name,": "]);if named != Error.none {return named;}let value = self.jsonValue(out,item.value,depth + 1);if value != Error.none {return value;}}return self.put(out," })");},
    }
}
fn json(self: Reader&,root: u32) -> Error {
    for tag in [ShapeTag.unit,ShapeTag.boolean,ShapeTag.u32_value,ShapeTag.f32_value,ShapeTag.utf8] {let inserted = self.shapes.push(Shape {tag,..});if inserted != Error.none {return inserted;}}let shape,error = self.infer(root,0);if error != Error.none {return error;}self.visits = 0;var annotation = Text {..};
    fn build() -> Error {let ty = self.shapeType(annotation,shape,0);if ty != Error.none {return ty;}if self.nodes.items[root].tag != Tag.object {let declaration = self.parts(self.header,["type Data = ",annotation.items,"\n"]);if declaration != Error.none {return declaration;}}let opened = self.parts(self.body,["const value: ",annotation.items," = "]);if opened != Error.none {return opened;}let value = self.jsonValue(self.body,root,0);if value != Error.none {return value;}return self.put(self.body,"\n");}
    let result = build();annotation.deinit();return result;
}
fn recordStart(self: Reader&,name: const u8[:],value: const u8[:]) -> Error {let header = self.parts(self.header,["type ",name," is data = $",name," { "]);if header != Error.none {return header;}return self.parts(self.body,["const ",value,": ",name," = ($",name," { "]);}
fn recordEnd(self: Reader&) -> Error {let header = self.put(self.header," }\n");if header != Error.none {return header;}return self.put(self.body," })\n");}
fn emitField(self: Reader&,name: const u8[:],shape: const u8[:],index: i64) -> Error {if index > 0 {let header = self.put(self.header,", ");if header != Error.none {return header;}let body = self.put(self.body,", ");if body != Error.none {return body;}}let header = self.parts(self.header,[name,": ",shape]);if header != Error.none {return header;}return self.parts(self.body,[name,": "]);}
fn ends(bytes: const u8[:],suffix: const u8[:]) -> bool {return suffix.len <= bytes.len && bytes[bytes.len - suffix.len..] == suffix;}
fn catalog(self: Reader&,root: u32) -> Error {
    let object = self.object(root);if object != Error.none {return object;}let categories: const u8[:][3] = ["meshes","materials","sounds"];let names: const u8[:][3] = ["Meshes","Materials","Sounds"];
    for category,ordinal in categories {let opened = self.recordStart(names[ordinal],category);if opened != Error.none {return opened;}let selected = self.member(root,category);if selected.present {let list = self.nodes.items[selected.value];if list.tag != Tag.null_value {if list.tag != Tag.array {return self.problem(selected.value,"asset_catalog","Catalog category must be a list of filenames");}var used: dictionary<const u8[:],bool> = {};
        for item,index in list.members {let file = self.nodes.items[item.value];if file.tag != Tag.string {return self.problem(item.value,"asset_catalog","Catalog filename must be text");}var basename = file.text;for suffix in [".mesh.json",".material.json"] {if ends(basename,suffix) {basename = basename[..basename.len - suffix.len];break;}}for suffix in [".wav",".ogg",".json"] {if ends(basename,suffix) {basename = basename[..basename.len - suffix.len];break;}}
            var field_name = Text {..};var at: i64 = 0;
            while at < basename.len {let point,length,valid = decodePoint(basename,at);assert(valid);at += length;var byte: u8 = '_';if point < 128 {let ascii = point as u8;if (ascii >= 'a' && ascii <= 'z') || (ascii >= 'A' && ascii <= 'Z') || digit(ascii) || ascii == '_' {byte = ascii;}}let first = field_name.push(byte);if first != Error.none {field_name.deinit();return first;}if point > 65535 {let second = field_name.push('_');if second != Error.none {field_name.deinit();return second;}}}
            let named = self.identifier(item.value,field_name.items);if named != Error.none {field_name.deinit();return named;}if used.get(field_name.items) {field_name.deinit();let message,error = self.text(["catalog ",category,": two files share a name"]);if error != Error.none {return error;}return self.problem(item.value,"asset_catalog",message);}let owned,error = self.own(field_name.items);if error != Error.none {field_name.deinit();return error;}used.insert(owned,true);let emitted = self.emitField(field_name.items,"U32",index);field_name.deinit();if emitted != Error.none {return emitted;}let value = self.integer(self.body,index);if value != Error.none {return value;}
        }
    }}let closed = self.recordEnd();if closed != Error.none {return closed;}}
    return Error.none;
}
fn inFont(point: u32) -> bool {if point >= 32 && point <= 126 {return true;}let extras = "åäöÅÄÖéüÉ‹›•…×–—";var at: i64 = 0;while at < extras.len {let extra,length,valid = decodePoint(extras,at);assert(valid);if extra == point {return true;}at += length;}return false;}
fn points(self: Reader&,out: Text&,id: u32,name: const u8[:],shown: bool) -> Error {
    let node = self.nodes.items[id];if node.tag != Tag.string {return self.problem(id,"asset_text","Text must be a string or a list of strings");}
    if !shown {var missing = Text {..};var seen: dictionary<u32,bool> = {};var at: i64 = 0;while at < node.text.len {let point,length,valid = decodePoint(node.text,at);assert(valid);if !inFont(point) && missing.len < 512 && !seen.get(point) {seen.insert(point,true);let appended = missing.append(node.text[at..at + length]);if appended != Error.none {missing.deinit();return appended;}}at += length;}if missing.len > 0 {let message,error = self.text(["text ",boundedUtf8Prefix(name,256),": the font has no ",missing.items]);missing.deinit();if error != Error.none {return error;}return self.problem(id,"asset_font",message);}missing.deinit();}
    let opened = self.put(out,"#[");if opened != Error.none {return opened;}var at: i64 = 0;var index: i64 = 0;while at < node.text.len {let point,length,valid = decodePoint(node.text,at);assert(valid);at += length;let bounded = self.budget(1);if bounded != Error.none {return bounded;}var value = point;if shown && !inFont(point) {value = 63;}if index > 0 {let separator = self.put(out,", ");if separator != Error.none {return separator;}}let emitted = self.integer(out,value);if emitted != Error.none {return emitted;}index++;}return self.put(out,"]");
}
fn textModule(self: Reader&,root: u32) -> Error {
    let object = self.object(root);if object != Error.none {return object;}let opened = self.recordStart("Text","text");if opened != Error.none {return opened;}
    for item,index in self.nodes.items[root].members {let named = self.identifier(item.value,item.name);if named != Error.none {return named;}let node = self.nodes.items[item.value];if node.tag == Tag.string {let field = self.emitField(item.name,"(Array U32)",index);if field != Error.none {return field;}let values = self.points(self.body,item.value,item.name,false);if values != Error.none {return values;}}
        else {if node.tag != Tag.array {return self.problem(item.value,"asset_text","Text must be a string or a list of strings");}let field = self.emitField(item.name,"(Array (Array U32))",index);if field != Error.none {return field;}let opened = self.put(self.body,"#[");if opened != Error.none {return opened;}for line,line_index in node.members {if line_index > 0 {let separator = self.put(self.body,", ");if separator != Error.none {return separator;}}let value = self.points(self.body,line.value,item.name,false);if value != Error.none {return value;}}let closed = self.put(self.body,"]");if closed != Error.none {return closed;}}
    }return self.recordEnd();
}
fn tunableNumber(self: Reader&,id: u32,key: const u8[:]) -> f64,Error {let selected = self.member(id,key);if !selected.present {let message,error = self.text([key," must be a finite number"]);if error != Error.none {return 0.0,error;}return 0.0,self.problem(id,"asset_tunables",message);}let node = self.nodes.items[selected.value];let single = node.number as! f32;if node.tag != Tag.number || !blot_backend_native_asset_numbers::finite(single as f64) {let message,error = self.text([key," must be a finite number"]);if error != Error.none {return 0.0,error;}return 0.0,self.problem(selected.value,"asset_tunables",message);}return node.number,Error.none;}
fn shownSpan(self: Reader&,out: Text&,count: u32&,id: blot_support::Option<u32>) -> u32[2],Error {let start = count;if id.present {let text = self.nodes.items[id.value].text;var at: i64 = 0;while at < text.len {let point,length,valid = decodePoint(text,at);assert(valid);at += length;let bounded = self.budget(1);if bounded != Error.none {return [0,0],bounded;}if count != 0 {let comma = self.put(out,", ");if comma != Error.none {return [0,0],comma;}}var value = point;if !inFont(point) {value = 63;}let emitted = self.integer(out,value);if emitted != Error.none {return [0,0],emitted;}count++;}}return [start,count - start],Error.none;}
fn tunableName(name: const u8[:]) -> bool {var first = true;if name.len == 0 {return false;}for byte in name {if first {if byte < 'a' || byte > 'z' {return false;}first = false;}else if byte == '.' {first = true;}else if (byte < 'a' || byte > 'z') && !digit(byte) && byte != '_' {return false;}}return !first;}
fn tunableId(name: const u8[:]) -> u32 {var hash: u32 = 2166136261;for byte in name {hash = ((hash ^ byte) as u64 * 16777619) as! u32;}return ((hash >> 24) ^ hash) & 16777215;}
fn tunables(self: Reader&,root: u32) -> Error {
    let selected = self.member(root,"tunables");if !selected.present {return self.problem(root,"asset_tunables","tunables.json: expected { \"tunables\": [...] }");}let list = self.nodes.items[selected.value];if self.nodes.items[root].tag != Tag.object || list.tag != Tag.array {return self.problem(root,"asset_tunables","tunables.json: expected { \"tunables\": [...] }");}
    var fields: dictionary<const u8[:],bool> = {};var ids: dictionary<u32,bool> = {};var declarations = Text {..};var text = Text {..};var text_count: u32 = 0;
    fn build() -> Error {
        let text_opened = self.put(text,"const declaration_text: Array U32 = #[");if text_opened != Error.none {return text_opened;}let declarations_opened = self.put(declarations,"const declarations: (Array Declaration) = #[");if declarations_opened != Error.none {return declarations_opened;}let opened = self.recordStart("Tunables","tunables");if opened != Error.none {return opened;}
        for item,index in list.members {
            let id = item.value;let object = self.object(id);if object != Error.none {return object;}let name_id = self.member(id,"name");if !name_id.present {return self.problem(id,"asset_tunables","Tunable needs a name of lowercase words joined by dots");}let name = self.nodes.items[name_id.value];if name.tag != Tag.string || !tunableName(name.text) {return self.problem(name_id.value,"asset_tunables","Tunable needs a name of lowercase words joined by dots");}
            for entry in self.nodes.items[id].members {var known = false;for key in ["name","default","min","max","step","doc"] {if key == entry.name {known = true;break;}}if !known {let message,error = self.text(["Unknown tunable field: ",boundedUtf8Prefix(entry.name,256)]);if error != Error.none {return error;}return self.problem(entry.value,"asset_tunables",message);}}
            let initial,initial_error = self.tunableNumber(id,"default");if initial_error != Error.none {return initial_error;}let least,least_error = self.tunableNumber(id,"min");if least_error != Error.none {return least_error;}let most,most_error = self.tunableNumber(id,"max");if most_error != Error.none {return most_error;}if !((least as! f32) < (most as! f32)) {return self.problem(id,"asset_tunables","min must be below max");}if (initial as! f32) < (least as! f32) || (initial as! f32) > (most as! f32) {return self.problem(id,"asset_tunables","Tunable default is outside min..max");}
            let step = self.member(id,"step");if step.present {let value,error = self.tunableNumber(id,"step");if error != Error.none {return error;}if !(value > 0.0) {return self.problem(step.value,"asset_tunables","step must be positive");}}let doc_id = self.member(id,"doc");if doc_id.present && self.nodes.items[doc_id.value].tag != Tag.string {return self.problem(doc_id.value,"asset_tunables","doc must be text");}
            var renamed = Text {..};for byte in name.text {var value = byte;if value == '.' {value = '_';}let added = renamed.push(value);if added != Error.none {renamed.deinit();return added;}}let field_name,field_error = self.own(renamed.items);renamed.deinit();if field_error != Error.none {return field_error;}let named = self.identifier(name_id.value,field_name);if named != Error.none {return named;}if fields.get(field_name) {return self.problem(name_id.value,"asset_tunables","Two tunables share a field; rename one");}fields.insert(field_name,true);let stable_id = tunableId(name.text);if ids.get(stable_id) {return self.problem(name_id.value,"asset_tunables","Two tunables share an id; rename one");}ids.insert(stable_id,true);
            let field = self.emitField(field_name,"(U32, F32, F32, F32)",index);if field != Error.none {return field;}let value_opened = self.put(self.body,"(");if value_opened != Error.none {return value_opened;}let identifier = self.integer(self.body,stable_id);if identifier != Error.none {return identifier;}for value in [initial,least,most] {let comma = self.put(self.body,", ");if comma != Error.none {return comma;}let emitted = self.float32(self.body,value);if emitted != Error.none {return emitted;}}let closed = self.put(self.body,")");if closed != Error.none {return closed;}if index > 0 {let comma = self.put(declarations,", ");if comma != Error.none {return comma;}}
            let name_span,name_error = self.shownSpan(text,text_count,name_id);if name_error != Error.none {return name_error;}let doc_span,doc_error = self.shownSpan(text,text_count,doc_id);if doc_error != Error.none {return doc_error;}
            let declaration_opened = self.put(declarations,"($Declaration { name_start: ");if declaration_opened != Error.none {return declaration_opened;}let name_start = self.integer(declarations,name_span[0]);if name_start != Error.none {return name_start;}let name_count_text = self.put(declarations,", name_count: ");if name_count_text != Error.none {return name_count_text;}let name_count = self.integer(declarations,name_span[1]);if name_count != Error.none {return name_count;}let id_text = self.put(declarations,", id: ");if id_text != Error.none {return id_text;}let id_value = self.integer(declarations,stable_id);if id_value != Error.none {return id_value;}
            let labels: const u8[:][3] = [", initial: ",", least: ",", most: "];let values: f64[3] = [initial,least,most];for value,position in values {let label = self.put(declarations,labels[position]);if label != Error.none {return label;}let emitted = self.float32(declarations,value);if emitted != Error.none {return emitted;}}
            let doc_start_text = self.put(declarations,", doc_start: ");if doc_start_text != Error.none {return doc_start_text;}let doc_start = self.integer(declarations,doc_span[0]);if doc_start != Error.none {return doc_start;}let doc_count_text = self.put(declarations,", doc_count: ");if doc_count_text != Error.none {return doc_count_text;}let doc_count = self.integer(declarations,doc_span[1]);if doc_count != Error.none {return doc_count;}let declaration_closed = self.put(declarations," })");if declaration_closed != Error.none {return declaration_closed;}
        }
        let closed = self.recordEnd();if closed != Error.none {return closed;}let declaration_type = self.put(self.header,"type Declaration is data = $Declaration { name_start: U32, name_count: U32, id: U32, initial: F32, least: F32, most: F32, doc_start: U32, doc_count: U32 }\n");if declaration_type != Error.none {return declaration_type;}let text_closed = self.put(text,"]\n");if text_closed != Error.none {return text_closed;}let declarations_closed = self.put(declarations,"]\n");if declarations_closed != Error.none {return declarations_closed;}
        return self.parts(self.body,[text.items,declarations.items,"const name = func (row: Declaration) => return &declaration_text[row.name_start..row.name_start + row.name_count]\n","const doc = func (row: Declaration) => return &declaration_text[row.doc_start..row.doc_start + row.doc_count]\n"]);
    }
    let error = build();text.deinit();declarations.deinit();return error;
}
fn run(self: Reader&,kind: Kind) -> Error {
    if self.input.len > limit {return self.fail(0,self.input.len,"asset_limit","Asset input exceeds 16 MiB");}var at: i64 = 0;while at < self.input.len {let point,length,valid = decodePoint(self.input,at);if !valid {return self.fail(at,at + 1,"asset_unicode","Asset input must be UTF-8");}at += length;}if self.input.len >= 3 && self.input[0] == 239 && self.input[1] == 187 && self.input[2] == 191 {self.at = 3;}
    let root,error = self.parse(0);if error != Error.none {return error;}self.skip();if self.at != self.input.len {return self.syntax();}self.visits = 0;var generated = Error.none;match kind {json=>{generated = self.json(root);},catalog=>{generated = self.catalog(root);},text=>{generated = self.textModule(root);},tunables=>{generated = self.tunables(root);},}if generated != Error.none {return generated;}if self.header.len > limit - self.body.len {return self.problem(root,"asset_limit","Generated asset module exceeds 16 MiB");}return Error.none;
}
fn generate(kind: Kind,bytes: const u8[:]) -> Result,Error {
    var interned: dictionary<const u8[:],u32> = {};var reader = Reader {input: bytes,interned,..};let error = reader.run(kind);
    if error != Error.none {if error == Error.out_of_memory {reader.deinit();return Result.source {bytes: []},error;}assert(error == Error.invalid_asset && reader.issue.present);var issue = reader.issue.value;issue.message = copyOutput(issue.message);reader.deinit();return Result.issue {value: issue},Error.none;}
    let length = reader.header.len + reader.body.len;var source: u8[:] = [];if length != 0 {source = output_bytes.alloc_slice(length);for index in 0..reader.header.len {source[index] = reader.header.items[index];}for index in 0..reader.body.len {source[reader.header.len + index] = reader.body.items[index];}}reader.deinit();return Result.source {bytes: source},Error.none;
}
