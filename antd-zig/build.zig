const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- Library module ---
    const antd_mod = b.addModule("antd", .{
        .root_source_file = b.path("src/antd.zig"),
        .target = target,
        .optimize = optimize,
    });

    // --- Tests ---
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tests = b.addTest(.{
        .root_module = test_mod,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    // --- Examples ---
    const example_names = [_][]const u8{
        "01-connect",
        "02-data",
        "03-chunks",
        "04-files",
        "06-private-data",
    };

    for (example_names) |name| {
        const exe_mod = b.createModule(.{
            .root_source_file = b.path(b.fmt("examples/{s}.zig", .{name})),
            .target = target,
            .optimize = optimize,
        });
        exe_mod.addImport("antd", antd_mod);

        const example = b.addExecutable(.{
            .name = name,
            .root_module = exe_mod,
        });

        const run_cmd = b.addRunArtifact(example);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step(
            b.fmt("run-{s}", .{name}),
            b.fmt("Run the {s} example", .{name}),
        );
        run_step.dependOn(&run_cmd.step);
    }
}
