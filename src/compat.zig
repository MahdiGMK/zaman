const std = @import("std");
pub fn zigVersionCompare(comptime op: std.math.CompareOperator, comptime other: [:0]const u8) bool {
    return @import("builtin").zig_version
        .order(std.SemanticVersion.parse(other) catch comptime unreachable).compare(op);
}
