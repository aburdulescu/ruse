const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    comptime {
        const needed = "0.15.2";
        const current = builtin.zig_version;
        const needed_vers = std.SemanticVersion.parse(needed) catch unreachable;
        if (current.order(needed_vers) != .eq) {
            @compileError(std.fmt.comptimePrint("Your zig version is not supported, need version {s}", .{needed}));
        }
    }

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const strip = b.option(bool, "strip", "Omit debug information") orelse switch (optimize) {
        .Debug, .ReleaseSafe => false,
        .ReleaseFast, .ReleaseSmall => true,
    };

    const exe = b.addExecutable(.{
        .name = "ruse",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .single_threaded = true,
            .strip = strip,
        }),
    });
    b.installArtifact(exe);
}
