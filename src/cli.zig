//! CLI argument parsing and command handling for zig-hue-lightsync
const std = @import("std");
const config = @import("config.zig");
const discovery = @import("hue/discovery.zig");
const v2rest = @import("hue/v2rest.zig");

pub const Command = union(enum) {
    discover: DiscoverOptions,
    pair: PairOptions,
    status: void,
    areas: void,
    start: StartOptions,
    stop: void,
    scene: SceneOptions,
    gui: void,
    help: void,
    version: void,

    pub const DiscoverOptions = struct {
        timeout_ms: u32 = 5000,
    };

    pub const PairOptions = struct {
        ip: []const u8,
    };

    pub const StartOptions = struct {
        area_id: ?[]const u8 = null,
        fps_tier: config.Config.FpsTier = .high,
        brightness: ?u8 = null,
    };

    pub const SceneOptions = struct {
        name: ?[]const u8 = null,
        list: bool = false,
    };
};

pub const CliError = error{
    MissingArgument,
    InvalidArgument,
    UnknownCommand,
    HelpRequested,
};

pub const APP_NAME = "zig-hue-lightsync";
pub const APP_VERSION = "0.1.0";

pub fn parseArgs(allocator: std.mem.Allocator) !Command {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name
    _ = args.next();

    const cmd_str = args.next() orelse {
        return .help;
    };

    if (std.mem.eql(u8, cmd_str, "discover")) {
        var opts = Command.DiscoverOptions{};

        while (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "--timeout") or std.mem.eql(u8, arg, "-t")) {
                const timeout_str = args.next() orelse return CliError.MissingArgument;
                opts.timeout_ms = std.fmt.parseInt(u32, timeout_str, 10) catch return CliError.InvalidArgument;
            }
        }

        return .{ .discover = opts };
    }

    if (std.mem.eql(u8, cmd_str, "pair")) {
        const ip = args.next() orelse return CliError.MissingArgument;
        // Duplicate the string since args will be freed when this function returns
        const ip_owned = try allocator.dupe(u8, ip);
        return .{ .pair = .{ .ip = ip_owned } };
    }

    if (std.mem.eql(u8, cmd_str, "status")) {
        return .status;
    }

    if (std.mem.eql(u8, cmd_str, "areas")) {
        return .areas;
    }

    if (std.mem.eql(u8, cmd_str, "start")) {
        var opts = Command.StartOptions{};

        while (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "--area") or std.mem.eql(u8, arg, "-a")) {
                const area_str = args.next() orelse return CliError.MissingArgument;
                // Duplicate the string since args will be freed when this function returns
                opts.area_id = try allocator.dupe(u8, area_str);
            } else if (std.mem.eql(u8, arg, "--fps-tier") or std.mem.eql(u8, arg, "-f")) {
                const tier_str = args.next() orelse return CliError.MissingArgument;
                opts.fps_tier = config.Config.FpsTier.fromString(tier_str) orelse return CliError.InvalidArgument;
            } else if (std.mem.eql(u8, arg, "--brightness") or std.mem.eql(u8, arg, "-b")) {
                const brightness_str = args.next() orelse return CliError.MissingArgument;
                const brightness = std.fmt.parseInt(u8, brightness_str, 10) catch return CliError.InvalidArgument;
                if (brightness > 100) return CliError.InvalidArgument;
                opts.brightness = brightness;
            }
        }

        return .{ .start = opts };
    }

    if (std.mem.eql(u8, cmd_str, "stop")) {
        return .stop;
    }

    if (std.mem.eql(u8, cmd_str, "scene")) {
        var opts = Command.SceneOptions{};

        while (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "--list") or std.mem.eql(u8, arg, "-l")) {
                opts.list = true;
            } else if (!std.mem.startsWith(u8, arg, "-")) {
                // Duplicate the string since args will be freed when this function returns
                opts.name = try allocator.dupe(u8, arg);
            }
        }

        return .{ .scene = opts };
    }

    if (std.mem.eql(u8, cmd_str, "gui")) {
        return .gui;
    }

    if (std.mem.eql(u8, cmd_str, "help") or std.mem.eql(u8, cmd_str, "--help") or std.mem.eql(u8, cmd_str, "-h")) {
        return .help;
    }

    if (std.mem.eql(u8, cmd_str, "version") or std.mem.eql(u8, cmd_str, "--version") or std.mem.eql(u8, cmd_str, "-v")) {
        return .version;
    }

    return CliError.UnknownCommand;
}

pub fn printHelp(writer: anytype) !void {
    try writer.print(
        \\{s} v{s}
        \\Wayland-only Philips Hue screen sync
        \\
        \\USAGE:
        \\    {s} <COMMAND> [OPTIONS]
        \\
        \\COMMANDS:
        \\    discover              Discover Hue Bridges on the network
        \\        -t, --timeout <MS>    Discovery timeout in milliseconds (default: 5000)
        \\
        \\    pair <IP>             Pair with a Hue Bridge at the given IP
        \\                          Press the link button on the bridge when prompted
        \\
        \\    status                Show current pairing and configuration status
        \\
        \\    areas                 List available Entertainment Areas on the paired bridge
        \\
        \\    start                 Start screen sync to lights
        \\        -a, --area <ID>       Entertainment Area ID to sync
        \\        -f, --fps-tier <TIER> Sync intensity: Low(12)/Medium(24)/High(30)/Max(60)
        \\        -b, --brightness <N>  Brightness 0-100 (default: from config)
        \\
        \\    stop                  Stop screen sync and restore previous light state
        \\
        \\    scene [NAME]          Apply a preset scene or list available scenes
        \\        -l, --list            List all available preset scenes
        \\        NAME                  Scene name: cozy, bright, reading, warm_amber, cool_focus, night
        \\
        \\    gui                   Launch the graphical interface (Linux + GTK4 only)
        \\
        \\    help                  Show this help message
        \\    version               Show version information
        \\
        \\EXAMPLES:
        \\    {s} discover
        \\    {s} pair 192.168.1.100
        \\    {s} start --area abc123 --fps-tier High --brightness 75
        \\
    , .{ APP_NAME, APP_VERSION, APP_NAME, APP_NAME, APP_NAME, APP_NAME });
}

pub fn printVersion(writer: anytype) !void {
    try writer.print("{s} v{s}\n", .{ APP_NAME, APP_VERSION });
}

/// Execute the discover command
pub fn executeDiscover(allocator: std.mem.Allocator, opts: Command.DiscoverOptions, writer: anytype) !void {
    try writer.print("Discovering Hue Bridges (timeout: {d}ms)...\n\n", .{opts.timeout_ms});

    const bridges = discovery.discoverBridges(allocator, opts.timeout_ms) catch |err| {
        try writer.print("Discovery failed: {}\n", .{err});
        return;
    };
    defer {
        for (bridges) |*bridge| {
            bridge.deinit(allocator);
        }
        allocator.free(bridges);
    }

    if (bridges.len == 0) {
        try writer.writeAll("No bridges found.\n");
        try writer.writeAll("\nTips:\n");
        try writer.writeAll("  - Ensure your Hue Bridge is powered on and connected to the network\n");
        try writer.writeAll("  - Try specifying the IP directly with: pair <IP>\n");
        return;
    }

    try writer.print("Found {d} bridge(s):\n\n", .{bridges.len});
    try writer.writeAll("  ID                   IP               Source\n");
    try writer.writeAll("  ─────────────────────────────────────────────────\n");

    for (bridges) |bridge| {
        const source_str = switch (bridge.source) {
            .mdns => "mDNS",
            .cloud => "Cloud",
            .manual => "Manual",
        };
        try writer.print("  {s:<18}   {s:<15}  {s}\n", .{ bridge.id, bridge.ip, source_str });
    }

    try writer.writeAll("\nTo pair with a bridge, run:\n");
    try writer.print("  {s} pair <IP>\n", .{APP_NAME});
}

/// Execute the pair command
pub fn executePair(allocator: std.mem.Allocator, opts: Command.PairOptions, writer: anytype) !void {
    try writer.print("Pairing with bridge at {s}...\n\n", .{opts.ip});

    var client = v2rest.HueClient.init(allocator, opts.ip);

    // Check if bridge is reachable
    try writer.writeAll("Checking bridge connectivity... ");
    if (!try client.ping()) {
        try writer.writeAll("FAILED\n");
        try writer.writeAll("\nCould not connect to the bridge. Please check:\n");
        try writer.writeAll("  - The IP address is correct\n");
        try writer.writeAll("  - The bridge is powered on and connected to the network\n");
        return;
    }
    try writer.writeAll("OK\n\n");

    try writer.writeAll("╔════════════════════════════════════════════════════════════╗\n");
    try writer.writeAll("║  Press the LINK BUTTON on your Hue Bridge now!             ║\n");
    try writer.writeAll("║  You have 30 seconds...                                    ║\n");
    try writer.writeAll("╚════════════════════════════════════════════════════════════╝\n\n");

    // Poll for 30 seconds
    const max_attempts = 30;
    var attempt: u32 = 0;

    while (attempt < max_attempts) : (attempt += 1) {
        const result = client.pair("zig-hue-lightsync") catch |err| {
            if (err == v2rest.ApiError.LinkButtonNotPressed) {
                try writer.print("\rWaiting for link button... {d}s remaining  ", .{max_attempts - attempt});
                std.Thread.sleep(std.time.ns_per_s);
                continue;
            }
            try writer.print("\nPairing failed: {}\n", .{err});
            return;
        };
        defer {
            var r = result;
            r.deinit(allocator);
        }

        try writer.writeAll("\n\n✓ Pairing successful!\n\n");

        // Save credentials
        var cfg_manager = try config.ConfigManager.init(allocator);
        defer cfg_manager.deinit();

        cfg_manager.saveCredentials(opts.ip, result.app_key, result.client_key) catch |err| {
            try writer.print("Warning: Could not save credentials: {}\n", .{err});
            try writer.print("\nApp Key: {s}\n", .{result.app_key});
            try writer.print("Client Key: {s}\n", .{result.client_key});
            try writer.writeAll("\nPlease save these manually.\n");
            return;
        };

        try writer.print("Credentials saved to: {s}\n", .{cfg_manager.getConfigPath()});
        try writer.writeAll("\nYou can now use the 'areas' command to list Entertainment Areas,\n");
        try writer.writeAll("then 'start' to begin syncing.\n");
        return;
    }

    try writer.writeAll("\n\nTimeout: Link button was not pressed within 30 seconds.\n");
    try writer.writeAll("Please try again.\n");
}

/// Execute the status command
pub fn executeStatus(allocator: std.mem.Allocator, writer: anytype) !void {
    var cfg_manager = try config.ConfigManager.init(allocator);
    defer cfg_manager.deinit();

    var cfg = cfg_manager.load() catch |err| {
        try writer.print("Could not load configuration: {}\n", .{err});
        return;
    };
    defer cfg.deinit(allocator);

    try writer.print("{s} Status\n", .{APP_NAME});
    try writer.writeAll("═══════════════════════════════════════\n\n");

    try writer.print("Config file: {s}\n\n", .{cfg_manager.getConfigPath()});

    if (cfg.isPaired()) {
        try writer.writeAll("Bridge: PAIRED ✓\n");
        try writer.print("  IP: {s}\n", .{cfg.bridge_ip.?});
        try writer.print("  App Key: {s}...{s}\n", .{ cfg.app_key.?[0..8], cfg.app_key.?[cfg.app_key.?.len - 4 ..] });
    } else {
        try writer.writeAll("Bridge: NOT PAIRED\n");
        try writer.writeAll("  Run 'discover' to find bridges, then 'pair <IP>' to connect.\n");
    }

    try writer.writeAll("\nSync Settings:\n");
    try writer.print("  FPS Tier: {s} ({d} fps)\n", .{ cfg.fps_tier.toString(), cfg.fps_tier.toFps() });
    try writer.print("  Brightness: {d}%\n", .{cfg.brightness});
    try writer.print("  Smoothing: {d:.2}\n", .{cfg.smoothing});
    try writer.print("  Only Send Dirty: {}\n", .{cfg.only_send_dirty});

    if (cfg.entertainment_area_id) |area_id| {
        try writer.print("\nEntertainment Area: {s}\n", .{area_id});
    }
}

/// Execute the areas command
pub fn executeAreas(allocator: std.mem.Allocator, writer: anytype) !void {
    var cfg_manager = try config.ConfigManager.init(allocator);
    defer cfg_manager.deinit();

    var cfg = cfg_manager.load() catch |err| {
        try writer.print("Could not load configuration: {}\n", .{err});
        return;
    };
    defer cfg.deinit(allocator);

    if (!cfg.isPaired()) {
        try writer.writeAll("Not paired with a bridge. Run 'pair <IP>' first.\n");
        return;
    }

    try writer.print("Fetching Entertainment Areas from {s}...\n\n", .{cfg.bridge_ip.?});

    var client = v2rest.HueClient.initWithCredentials(allocator, cfg.bridge_ip.?, cfg.app_key.?);

    const areas = client.listEntertainmentAreas() catch |err| {
        try writer.print("Failed to fetch areas: {}\n", .{err});
        return;
    };
    defer {
        for (areas) |*area| {
            area.deinit(allocator);
        }
        allocator.free(areas);
    }

    if (areas.len == 0) {
        try writer.writeAll("No Entertainment Areas found.\n");
        try writer.writeAll("\nCreate an Entertainment Area in the Philips Hue app first.\n");
        return;
    }

    try writer.print("Found {d} Entertainment Area(s):\n\n", .{areas.len});

    for (areas) |area| {
        try writer.print("  {s}\n", .{area.name});
        try writer.print("  ID: {s}\n", .{area.id});
        try writer.print("  Lights: {d}\n", .{area.lights.len});

        if (area.lights.len > 0) {
            try writer.writeAll("    Position (x, y, z):\n");
            for (area.lights) |light| {
                try writer.print("    - {s}: ({d:.2}, {d:.2}, {d:.2})\n", .{ light.name, light.x, light.y, light.z });
            }
        }
        try writer.writeAll("\n");
    }

    try writer.writeAll("To start syncing, run:\n");
    try writer.print("  {s} start --area <ID>\n", .{APP_NAME});
}

/// Execute the start command
pub fn executeStart(allocator: std.mem.Allocator, opts: Command.StartOptions, writer: anytype) !void {
    const root = @import("root.zig");

    var cfg_manager = try config.ConfigManager.init(allocator);
    defer cfg_manager.deinit();

    var cfg = cfg_manager.load() catch |err| {
        try writer.print("Could not load configuration: {}\n", .{err});
        return;
    };
    defer cfg.deinit(allocator);

    if (!cfg.isPaired()) {
        try writer.writeAll("Not paired with a bridge. Run 'pair <IP>' first.\n");
        return;
    }

    // Check for entertainment area
    const area_id = opts.area_id orelse cfg.entertainment_area_id orelse {
        try writer.writeAll("No entertainment area specified.\n");
        try writer.writeAll("Use --area <ID> or set a default in the config.\n");
        try writer.print("Run '{s} areas' to list available areas.\n", .{APP_NAME});
        return;
    };

    // Check platform support
    if (!root.isCaptureAvailable()) {
        try writer.writeAll("Screen capture is only supported on Linux with Wayland.\n");
        try writer.writeAll("This feature requires:\n");
        try writer.writeAll("  - Linux operating system\n");
        try writer.writeAll("  - Wayland compositor (KDE Plasma, GNOME, Sway, etc.)\n");
        try writer.writeAll("  - PipeWire\n");
        try writer.writeAll("  - Build with: zig build -Denable-capture=true\n");
        return;
    }

    const fps = opts.fps_tier.toFps();
    const brightness = opts.brightness orelse cfg.brightness;

    try writer.print("Starting screen sync...\n", .{});
    try writer.print("  Bridge: {s}\n", .{cfg.bridge_ip.?});
    try writer.print("  Entertainment Area: {s}\n", .{area_id});
    try writer.print("  FPS Tier: {s} ({d} fps)\n", .{ opts.fps_tier.toString(), fps });
    try writer.print("  Brightness: {d}%\n", .{brightness});
    try writer.writeAll("\n");

    // Initialize capture
    var screen_capture = root.capture.ScreenCapture.init(allocator);
    defer screen_capture.deinit();

    try writer.writeAll("Requesting screen capture permission...\n");
    try writer.writeAll("(A system dialog should appear to select your screen)\n\n");

    screen_capture.requestPermission(.{
        .target_fps = fps,
    }) catch |err| {
        try writer.print("Failed to get screen capture permission: {}\n", .{err});
        if (err == error.NotSupported) {
            try writer.writeAll("Build with -Denable-capture=true on Linux.\n");
        }
        return;
    };

    try writer.writeAll("Permission granted! Starting capture...\n");

    // Start capture loop
    screen_capture.start() catch |err| {
        try writer.print("Failed to start capture: {}\n", .{err});
        return;
    };

    try writer.writeAll("Screen sync is now running.\n");
    try writer.print("Press Ctrl+C to stop, or run '{s} stop'.\n", .{APP_NAME});
}

/// Execute the scene command
pub fn executeScene(allocator: std.mem.Allocator, opts: Command.SceneOptions, writer: anytype) !void {
    const root = @import("root.zig");

    if (opts.list) {
        try writer.writeAll("Available preset scenes:\n\n");
        try writer.writeAll("  Name          Brightness  Color (xy)\n");
        try writer.writeAll("  ────────────────────────────────────────\n");

        for (root.scenes.presets.all()) |scene| {
            try writer.print("  {s:<12}  {d:>3}%        ({d:.2}, {d:.2})\n", .{
                scene.name,
                scene.brightness,
                scene.color_xy.x,
                scene.color_xy.y,
            });
        }

        try writer.writeAll("\nUsage: ");
        try writer.print("{s} scene <NAME>\n", .{APP_NAME});
        return;
    }

    const scene_name = opts.name orelse {
        try writer.writeAll("No scene specified.\n");
        try writer.print("Run '{s} scene --list' to see available scenes.\n", .{APP_NAME});
        return;
    };

    const scene = root.scenes.presets.findByName(scene_name) orelse {
        try writer.print("Unknown scene: {s}\n", .{scene_name});
        try writer.print("Run '{s} scene --list' to see available scenes.\n", .{APP_NAME});
        return;
    };

    var cfg_manager = try config.ConfigManager.init(allocator);
    defer cfg_manager.deinit();

    var cfg = cfg_manager.load() catch |err| {
        try writer.print("Could not load configuration: {}\n", .{err});
        return;
    };
    defer cfg.deinit(allocator);

    if (!cfg.isPaired()) {
        try writer.writeAll("Not paired with a bridge. Run 'pair <IP>' first.\n");
        try writer.writeAll("Note: Scene preview only - lights not changed.\n\n");
    }

    try writer.print("Scene: {s}\n", .{scene.name});
    try writer.print("  Brightness: {d}%\n", .{scene.brightness});
    try writer.print("  Color (xy): ({d:.3}, {d:.3})\n", .{ scene.color_xy.x, scene.color_xy.y });

    if (!cfg.isPaired()) {
        try writer.writeAll("\nPair with a bridge to apply this scene to your lights.\n");
    } else {
        try writer.writeAll("\nApplying scene to lights...\n");
        try writer.writeAll("(Scene application via v2 API not yet implemented)\n");
    }
}

/// Execute the GUI command
pub fn executeGui(allocator: std.mem.Allocator, writer: anytype) !void {
    const root = @import("root.zig");

    if (!root.gui.isSupported()) {
        try writer.writeAll("GUI is only supported on Linux with GTK4.\n\n");
        try writer.writeAll("Requirements:\n");
        try writer.writeAll("  - Linux operating system\n");
        try writer.writeAll("  - GTK4 libraries installed\n");
        try writer.writeAll("  - Build with: zig build -Denable-gui=true\n");
        return;
    }

    try writer.writeAll("Launching GUI...\n");

    root.gui.launch(allocator) catch |err| {
        try writer.print("GUI error: {}\n", .{err});
    };
}

test "parse discover command" {
    const allocator = std.testing.allocator;
    _ = allocator;
    // Basic parsing test would require mocking args
}

test "fps tier string conversion" {
    try std.testing.expectEqualStrings("Low", config.Config.FpsTier.low.toString());
    try std.testing.expectEqualStrings("Medium", config.Config.FpsTier.medium.toString());
    try std.testing.expectEqualStrings("High", config.Config.FpsTier.high.toString());
    try std.testing.expectEqualStrings("Max", config.Config.FpsTier.max.toString());
}
