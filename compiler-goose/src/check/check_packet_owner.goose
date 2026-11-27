// Decoded immutable checked fields retain their concrete typed packet journal.
namespace squid_check_check;
import support.error;
import support.pooled_map;
import support.project_packet_contexts;

import .check;
import support.project_packet;
import dictionary;
struct CheckedPacketKey {lease:u32,generation:u64}
var checked_packets:squid_support_pooled_map::Map<CheckedPacketKey,squid_project_packet::Owner> =squid_support_pooled_map::Map<CheckedPacketKey,squid_project_packet::Owner>{..};
reusable[] var checked_packet_slots:dictionary_slot<CheckedPacketKey,squid_project_packet::Owner>[>..]=[];
fn attachCheckedPacket(owner:CheckedOwner,packet:squid_project_packet::Owner)->squid_error::Error {
 if !owner.valid() {return squid_error::Error.invalid_artifact;}let key=CheckedPacketKey{owner.lease,owner.generation};if squid_support_pooled_map::contains(checked_packets,key) {return squid_error::Error.invalid_artifact;}
 let held,error=packet.retain();if error!=squid_error::Error.none {return error;}let inserted=squid_support_pooled_map::insert(checked_packets,key,held,checked_packet_slots);assert(inserted);return squid_error::Error.none;
}
fn releaseCheckedPacket(owner:CheckedOwner) {let key=CheckedPacketKey{owner.lease,owner.generation};let found .= squid_support_pooled_map::get(checked_packets,key);if !found {return;}var held=found;squid_support_pooled_map::remove(checked_packets,key,checked_packet_slots);held.deinit();
 // The table goes with its last entry, so a finished command holds nothing.
 if checked_packets.count==0 {squid_support_pooled_map::deinit(checked_packets,checked_packet_slots);}}

fn hash(key:CheckedPacketKey)->u64 {return ::hash_combine(::hash(key.lease),::hash(key.generation));}

fn checkedPacket(owner:CheckedOwner)->squid_project_packet::Owner {assert(owner.valid());let key=CheckedPacketKey{owner.lease,owner.generation};let found .= squid_support_pooled_map::get(checked_packets,key);if !found {return squid_project_packet::Owner{};}let packet:squid_project_packet::Owner=found;assert(packet.valid());return packet;}
