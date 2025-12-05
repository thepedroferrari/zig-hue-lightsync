const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build option to enable Wayland capture (requires Linux + system libs)
    const enable_capture = b.option(bool, "enable-capture", "Enable Wayland screen capture (requires libdbus-1, libpipewire-0.3)") orelse false;

    // Library module - exports core functionality
    const lib_mod = b.addModule("zig_hue", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Main executable
    const exe = b.addExecutable(.{
        .name = "zig-hue-lightsync",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_hue", .module = lib_mod },
            },
        }),
    });

    // Link system libraries for capture module (Linux only)
    if (enable_capture) {
        // DBus for portal communication
        exe.root_module.linkSystemLibrary("dbus-1", .{});
        exe.root_module.addIncludePath(.{ .cwd_relative = "/usr/include/dbus-1.0" });
        exe.root_module.addIncludePath(.{ .cwd_relative = "/usr/lib/x86_64-linux-gnu/dbus-1.0/include" });
        exe.root_module.addIncludePath(.{ .cwd_relative = "/usr/lib/dbus-1.0/include" });

        // PipeWire for frame capture
        exe.root_module.linkSystemLibrary("pipewire-0.3", .{});
        exe.root_module.addIncludePath(.{ .cwd_relative = "/usr/include/pipewire-0.3" });
        exe.root_module.addIncludePath(.{ .cwd_relative = "/usr/include/spa-0.2" });

        // Link libc
        exe.root_module.link_libc = true;
    }

    b.installArtifact(exe);

    // Run step
    const run_step = b.step("run", "Run zig-hue-lightsync");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Test step - tests both library and executable modules
    const lib_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_lib_tests = b.addRunArtifact(lib_tests);
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Format check step
    const fmt_step = b.step("fmt", "Check source formatting");
    const fmt = b.addFmt(.{
        .paths = &.{"src"},
        .check = true,
    });
    fmt_step.dependOn(&fmt.step);
}
