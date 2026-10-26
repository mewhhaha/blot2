// Private single static-array image. Identifiers in this record do not confer
// a K1 Domain, artifact authentication, or caller/host authority.
namespace static_publish_core;
struct Image {source:u8[]=[],width:u32=0,rows:u32=0,steps:u32=0,bytes:u32=0,data:u8[]=[]}
struct Result {status:i64=1,image:Image=Image {}}
