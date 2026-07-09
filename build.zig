const std = @import("std");

pub fn build(b: *std.Build) void {
    const targ = b.standardTargetOptions(.{});
    const optim = b.standardOptimizeOption(.{});
    _ = b.addModule("zaman", .{
        .root_source_file = b.path("src/lifetime.zig"),
        .target = targ,
        .optimize = optim,
    });
    _ = b.addModule("lockguard", .{
        .root_source_file = b.path("src/lockguard.zig"),
        .target = targ,
        .optimize = optim,
    });
    const lifetime_tests = b.addRunArtifact(b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test.zig"),
            .target = targ,
            .optimize = optim,
        }),
    }));
    const test_step = b.step("test", "test package");
    test_step.dependOn(&lifetime_tests.step);
}
