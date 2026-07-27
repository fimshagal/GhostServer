const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "GhostServer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(exe);
    b.getInstallStep().dependOn(
        &b.addInstallFile(b.path("config-rest.json"), "bin/config-rest.json").step,
    );
    b.getInstallStep().dependOn(
        &b.addInstallFile(b.path("config-ws.json"), "bin/config-ws.json").step,
    );

    const run_step = b.step("run", "Run the mock server (REST + WS)");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    // Default: both configs from the project root. Override with:
    //   zig build run -- --rest path --ws path
    if (b.args) |args| {
        run_cmd.addArgs(args);
    } else {
        run_cmd.addArgs(&.{
            "--rest",
            "config-rest.json",
            "--ws",
            "config-ws.json",
        });
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_tests.step);
}
