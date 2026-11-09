// Decoded immutable checked fields retain their concrete typed packet journal.
namespace blot_check_check;
import support.error;
import support.pooled_map;
import support.project_packet_contexts;

import .check;
import support.project_packet;
import dictionary;
struct CheckedPacketKey {lease:u32,generation:u64}
var checked_packets:blot_support_pooled_map::Map<CheckedPacketKey,blot_project_packet::Owner> =blot_support_pooled_map::Map<CheckedPacketKey,blot_project_packet::Owner>{..};
reusable[] var checked_packet_slots:dictionary_slot<CheckedPacketKey,blot_project_packet::Owner>[>..]=[];
fn attachCheckedPacket(owner:CheckedOwner,packet:blot_project_packet::Owner)->blot_error::Error {
 if !owner.valid() {return blot_error::Error.invalid_artifact;}let key=CheckedPacketKey{owner.lease,owner.generation};if blot_support_pooled_map::contains(checked_packets,key) {return blot_error::Error.invalid_artifact;}
 let held,error=packet.retain();if error!=blot_error::Error.none {return error;}let inserted=blot_support_pooled_map::insert(checked_packets,key,held,checked_packet_slots);assert(inserted);return blot_error::Error.none;
}
fn releaseCheckedPacket(owner:CheckedOwner) {let key=CheckedPacketKey{owner.lease,owner.generation};let found .= blot_support_pooled_map::get(checked_packets,key);if !found {return;}var held=found;blot_support_pooled_map::remove(checked_packets,key);held.deinit();}

fn hash(key:CheckedPacketKey)->u64 {return ::hash_combine(::hash(key.lease),::hash(key.generation));}

fn checkedPacket(owner:CheckedOwner)->blot_project_packet::Owner {assert(owner.valid());let key=CheckedPacketKey{owner.lease,owner.generation};let found .= blot_support_pooled_map::get(checked_packets,key);if !found {return blot_project_packet::Owner{};}let packet:blot_project_packet::Owner=found;assert(packet.valid());return packet;}
