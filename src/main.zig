//! zig-hue-lightsync CLI entry point
//! Wayland-only Philips Hue screen sync for Linux
const std = @import("std");
const root = @import("root.zig");
const cli = root.cli;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stdout_buffer: [4096]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;

    const command = cli.parseArgs(allocator) catch |err| {
        switch (err) {
            cli.CliError.MissingArgument => {
                try stderr.writeAll("Error: Missing required argument\n\n");
                try cli.printHelp(stderr);
            },
            cli.CliError.InvalidArgument => {
                try stderr.writeAll("Error: Invalid argument value\n\n");
                try cli.printHelp(stderr);
            },
            cli.CliError.UnknownCommand => {
                try stderr.writeAll("Error: Unknown command\n\n");
                try cli.printHelp(stderr);
            },
            else => {
                try stderr.print("Error: {}\n", .{err});
            },
        }
        std.process.exit(1);
    };

    switch (command) {
        .discover => |opts| {
            try cli.executeDiscover(allocator, opts, stdout);
        },
        .pair => |opts| {
            try cli.executePair(allocator, opts, stdout);
        },
        .status => {
            try cli.executeStatus(allocator, stdout);
        },
        .areas => {
            try cli.executeAreas(allocator, stdout);
        },
        .start => |opts| {
            try cli.executeStart(allocator, opts, stdout);
        },
        .stop => {
            try stdout.writeAll("Stop not yet implemented (M4).\n");
        },
        .scene => |opts| {
            try cli.executeScene(allocator, opts, stdout);
        },
        .gui => {
            try cli.executeGui(allocator, stdout);
        },
        .help => {
            try cli.printHelp(stdout);
        },
        .version => {
            try cli.printVersion(stdout);
        },
    }

    // Flush output buffers
    try stdout.flush();
}

test "main module" {
    // Import root to run all tests
    _ = root;
}
