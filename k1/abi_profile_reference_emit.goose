import os;
import abi_profile_build;
fn main(){let source=abi_profile_build::canonical();let hash=abi_profile_build::digest();assert(write_file("profile.bin",source) && write_file("digest.bin",hash));}
