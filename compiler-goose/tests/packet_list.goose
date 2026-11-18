import support.project_packet;
import support.error;
import check.types;

type List = blot_check_types::List;

fn checkReads(bytes: const u8[:], offset: i64, depth: i64, value: List) {
    for size in 0..9 {
        var reader = blot_project_packet::Reader { bytes[..offset + size], default<blot_project_packet::Owner>() };
        reader.at = offset;
        reader.depth = depth;
        var actual = List { 19, 23 };
        blot_project_packet::get(reader, actual);
        assert(reader.depth == depth && reader.remaining == blot_project_packet::element_limit);
        if size == 8 {
            assert(reader.failure == blot_error::Error.none && reader.at == offset + 8);
            assert(actual == value);
        } else {
            assert(reader.failure == blot_error::Error.invalid_artifact && actual.len == 23);
            if size >= 4 { assert(actual.start == value.start && reader.at == offset + 4); }
            else { assert(actual.start == 19 && reader.at == offset); }
        }
    }
    var reader = blot_project_packet::Reader { bytes, default<blot_project_packet::Owner>() };
    reader.depth = blot_project_packet::depth_limit;
    var actual = List { 19, 23 };
    blot_project_packet::get(reader, actual);
    assert(reader.failure == blot_error::Error.artifact_limit && reader.at == 0 && actual.start == 19 && actual.len == 23);
}

fn main() {
    let value = List { 0xfedcba98, 0x76543210 };
    let encoded: u8[8] = [0x98, 0xba, 0xdc, 0xfe, 0x10, 0x32, 0x54, 0x76];

    for offset in 0..8 {
        var packet: u8[>..<] = [];
        packet.resize(offset, 0xa5);
        var writer = blot_project_packet::Writer { packet };
        writer.depth = blot_project_packet::depth_limit - 1;
        blot_project_packet::put(writer, value);
        assert(writer.failure == blot_error::Error.none && writer.depth == blot_project_packet::depth_limit - 1);
        assert(packet[offset..] == encoded[..]);
        for byte in packet[..offset] { assert(byte == 0xa5); }

        var input: u8[16] = [0xa5; 16];
        for byte, index in encoded { input[offset + index] = byte; }
        checkReads(input[..offset + 8], offset, writer.depth, value);
        writer.depth++;
        blot_project_packet::put(writer, value);
        assert(writer.failure == blot_error::Error.artifact_limit && packet.len == offset + 8);
    }
}
