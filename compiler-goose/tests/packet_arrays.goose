import support.project_packet;
import support.error;
import reuse.principal_interface;

type Binding = squid_reuse_principal_interface::Binding;
reusable[] var packet_bytes: u8[>..];

fn decode(data: const u8[:], expected: const Binding[:], budget: i64) -> squid_error::Error {
    var owner, error = squid_project_packet::initOwner();
    assert(error == squid_error::Error.none);
    var reader = squid_project_packet::Reader {data, owner};
    reader.remaining = budget;
    var bindings: Binding[:] = default<Binding[:]>();
    squid_project_packet::get(reader, bindings);
    if reader.failure == squid_error::Error.none {
        assert(reader.at == data.len && bindings == expected);
        assert(reader.remaining == budget - expected.len);
    } else {
        assert(bindings.len == 0);
    }
    owner.deinit();
    return reader.failure;
}

fn main() {
    var values: Binding[2] = default<Binding[2]>();
    values[0].kind = squid_reuse_principal_interface::Kind.local;
    values[0].private = true;
    values[1].kind = squid_reuse_principal_interface::Kind.external;
    values[1].name = 0x87654321;
    values[1].scheme.root = 41;
    values[1].scheme.variables.start = 9;
    values[1].external.present = true;
    values[1].external.value.unit = 17;

    var output: u8[>..<] = [];
    var writer = squid_project_packet::Writer {output};
    squid_project_packet::put(writer, values[..]);
    assert(writer.failure == squid_error::Error.none);
    let packet = packet_bytes.alloc_slice(output.len);
    for byte, i in output { packet[i] = byte; }
    let ok = squid_error::Error.none;
    assert(decode(packet, values[..], 2) == ok);
    assert(decode(packet, values[..], 1) == squid_error::Error.artifact_limit);
    for end in 0..packet.len { assert(decode(packet[..end], values[..], 2) != ok); }

    packet[0] = 1;
    assert(decode(packet, values[..], 2) == squid_error::Error.invalid_artifact);
    packet[0] = 2;
    // Keep the byte count intact and give every enum an invalid discriminant.
    var first: i64 = 16;
    while (packet[first] & 0x80) != 0 { first++; }
    for i in first + 1..packet.len { packet[i] = 0xff; }
    assert(decode(packet, values[..], 2) == squid_error::Error.invalid_artifact);
    packet_bytes.free_slice(packet);

    output.resize(0);
    squid_project_packet::put(writer, values[..0]);
    assert(writer.failure == ok && output.len == 8);
    let empty: u8[8] = [0; 8];
    assert(output[..] == empty[..] && decode(empty[..], values[..0], 0) == ok);
}
