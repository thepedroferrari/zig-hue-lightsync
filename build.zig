const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build options for optional features (require Linux + system libs)
    const enable_capture = b.option(bool, "enable-capture", "Enable Wayland screen capture (requires libdbus-1, libpipewire-0.3)") orelse false;
    const enable_gui = b.option(bool, "enable-gui", "Enable GTK4 GUI (requires libgtk-4)") orelse false;

    // Library module - exports core functionality
    const lib_mod = b.addModule("zig_hue", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Pass build options as compile-time constants
    const options = b.addOptions();
    const capture_enabled = enable_capture and target.result.os.tag == .linux;
    const gui_enabled = enable_gui and target.result.os.tag == .linux;
    options.addOption(bool, "enable_capture", capture_enabled);
    options.addOption(bool, "enable_gui", gui_enabled);
    lib_mod.addOptions("build_options", options);

    // Conditionally add capture module (only on Linux with capture enabled)
    if (capture_enabled) {
        lib_mod.addImport("capture_impl", b.addModule("capture_impl", .{
            .root_source_file = b.path("src/capture/capture.zig"),
            .target = target,
            .optimize = optimize,
        }));
    }

    // Conditionally add GUI modules (only on Linux with GUI enabled)
    if (gui_enabled) {
        const gui_mod = b.addModule("gui_impl", .{
            .root_source_file = b.path("src/gui/app.zig"),
            .target = target,
            .optimize = optimize,
        });
        lib_mod.addImport("gui_impl", gui_mod);
    }

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

    // Add build options to exe module as well
    exe.root_module.addOptions("build_options", options);

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

    // Link GTK4 for GUI (Linux only)
    if (enable_gui) {
        exe.root_module.linkSystemLibrary("gtk4", .{});
        exe.root_module.addIncludePath(.{ .cwd_relative = "/usr/include/gtk-4.0" });
        exe.root_module.addIncludePath(.{ .cwd_relative = "/usr/include/glib-2.0" });
        exe.root_module.addIncludePath(.{ .cwd_relative = "/usr/lib/x86_64-linux-gnu/glib-2.0/include" });
        exe.root_module.addIncludePath(.{ .cwd_relative = "/usr/include/pango-1.0" });
        exe.root_module.addIncludePath(.{ .cwd_relative = "/usr/include/harfbuzz" });
        exe.root_module.addIncludePath(.{ .cwd_relative = "/usr/include/cairo" });
        exe.root_module.addIncludePath(.{ .cwd_relative = "/usr/include/gdk-pixbuf-2.0" });
        exe.root_module.addIncludePath(.{ .cwd_relative = "/usr/include/graphene-1.0" });
        exe.root_module.addIncludePath(.{ .cwd_relative = "/usr/lib/x86_64-linux-gnu/graphene-1.0/include" });

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
