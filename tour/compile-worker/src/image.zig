//! The worker's part of a LIR image: the 512-byte ROCS prefix that Roc's CLI
//! puts before an image in shared memory, and the runtime contract check.

const std = @import("std");

/// The interpreter shim counts the image's array offsets from the start of
/// this prefix.
pub const prefix_size: usize = 512;

const magic: u32 = 0x53434f52; // "ROCS"
const version: u32 = 1;

/// The Tour host runs only specialized LIR. A boxy image would load and then
/// fail inside the interpreter.
pub fn requireSpecialized(contract: anytype) error{NotSpecialized}!void {
    if (contract != .specialized) return error.NotSpecialized;
}

/// `len` counts the prefix and the image after it.
pub fn writePrefix(buf: []u8, len: usize) void {
    std.mem.writeInt(u32, buf[0..4], magic, .little);
    std.mem.writeInt(u32, buf[4..8], version, .little);
    std.mem.writeInt(u64, buf[8..16], len, .little);
    std.mem.writeInt(u64, buf[16..24], len, .little);
    std.mem.writeInt(u64, buf[24..32], prefix_size, .little);
}

const TestContract = enum { specialized, boxy };

test "a specialized lower passes" {
    try requireSpecialized(TestContract.specialized);
}

test "a boxy lower fails" {
    try std.testing.expectError(error.NotSpecialized, requireSpecialized(TestContract.boxy));
}

test "the prefix starts with ROCS and records the image length and its own size" {
    var buf: [prefix_size]u8 = @splat(0xaa);
    writePrefix(&buf, 4096);
    try std.testing.expectEqualStrings("ROCS", buf[0..4]);
    try std.testing.expectEqualSlices(u8, &.{ 1, 0, 0, 0 }, buf[4..8]);
    try std.testing.expectEqual(@as(u64, 4096), std.mem.readInt(u64, buf[8..16], .little));
    try std.testing.expectEqual(@as(u64, 4096), std.mem.readInt(u64, buf[16..24], .little));
    try std.testing.expectEqual(@as(u64, 512), std.mem.readInt(u64, buf[24..32], .little));
}
