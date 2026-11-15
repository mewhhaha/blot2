//! Immutable test inputs. Only native test modules import this catalog.
pub fn source(comptime path: []const u8) @TypeOf(@embedFile(path)) {
    return @embedFile(path);
}
