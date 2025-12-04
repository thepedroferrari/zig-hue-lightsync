//! Configuration management for zig-hue-lightsync
//! Handles credential storage in ~/.config/zig-hue-lightsync/
//! All sensitive files are stored with 0600 permissions
const std = @import("std");

pub const ConfigError = error{
    ConfigDirCreationFailed,
    ConfigReadFailed,
    ConfigWriteFailed,
    InvalidConfig,
    PermissionDenied,
    OutOfMemory,
};

pub const Config = struct {
    bridge_ip: ?[]const u8 = null,
    app_key: ?[]const u8 = null,
    client_key: ?[]const u8 = null,
    entertainment_area_id: ?[]const u8 = null,
    fps_tier: FpsTier = .high,
    brightness: u8 = 75,
    smoothing: f32 = 0.5,
    only_send_dirty: bool = true,

    pub const FpsTier = enum {
        low, // 12 fps
        medium, // 24 fps
        high, // 30 fps
        max, // 60 fps

        pub fn toFps(self: FpsTier) u8 {
            return switch (self) {
                .low => 12,
                .medium => 24,
                .high => 30,
                .max => 60,
            };
        }

        pub fn fromString(s: []const u8) ?FpsTier {
            if (std.mem.eql(u8, s, "Low") or std.mem.eql(u8, s, "low")) return .low;
            if (std.mem.eql(u8, s, "Medium") or std.mem.eql(u8, s, "medium")) return .medium;
            if (std.mem.eql(u8, s, "High") or std.mem.eql(u8, s, "high")) return .high;
            if (std.mem.eql(u8, s, "Max") or std.mem.eql(u8, s, "max")) return .max;
            return null;
        }

        pub fn toString(self: FpsTier) []const u8 {
            return switch (self) {
                .low => "Low",
                .medium => "Medium",
                .high => "High",
                .max => "Max",
            };
        }
    };

    const Self = @This();

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        if (self.bridge_ip) |ip| allocator.free(ip);
        if (self.app_key) |key| allocator.free(key);
        if (self.client_key) |key| allocator.free(key);
        if (self.entertainment_area_id) |id| allocator.free(id);
        self.* = .{};
    }

    pub fn isPaired(self: *const Self) bool {
        return self.bridge_ip != null and self.app_key != null and self.client_key != null;
    }
};

pub const ConfigManager = struct {
    allocator: std.mem.Allocator,
    config_dir: []const u8,
    config_path: []const u8,

    const Self = @This();

    const CONFIG_DIR_NAME = "zig-hue-lightsync";
    const CONFIG_FILE_NAME = "config.json";

    pub fn init(allocator: std.mem.Allocator) !Self {
        const config_dir = try getConfigDir(allocator);
        const config_path = try std.fs.path.join(allocator, &.{ config_dir, CONFIG_FILE_NAME });

        return .{
            .allocator = allocator,
            .config_dir = config_dir,
            .config_path = config_path,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.config_dir);
        self.allocator.free(self.config_path);
    }

    /// Load configuration from disk
    pub fn load(self: *Self) !Config {
        const file = std.fs.openFileAbsolute(self.config_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                return Config{};
            }
            return ConfigError.ConfigReadFailed;
        };
        defer file.close();

        const stat = file.stat() catch return ConfigError.ConfigReadFailed;
        const content = self.allocator.alloc(u8, stat.size) catch return ConfigError.OutOfMemory;
        defer self.allocator.free(content);

        _ = file.readAll(content) catch return ConfigError.ConfigReadFailed;

        return self.parseConfig(content);
    }

    /// Save configuration to disk with secure permissions
    pub fn save(self: *Self, config: *const Config) !void {
        // Ensure config directory exists
        std.fs.makeDirAbsolute(self.config_dir) catch |err| {
            if (err != error.PathAlreadyExists) {
                return ConfigError.ConfigDirCreationFailed;
            }
        };

        // Build JSON content
        var buffer: std.ArrayListUnmanaged(u8) = .empty;
        defer buffer.deinit(self.allocator);

        var writer = buffer.writer(self.allocator);
        try writer.writeAll("{\n");

        if (config.bridge_ip) |ip| {
            try writer.print("  \"bridge_ip\": \"{s}\",\n", .{ip});
        }
        if (config.app_key) |key| {
            try writer.print("  \"app_key\": \"{s}\",\n", .{key});
        }
        if (config.client_key) |key| {
            try writer.print("  \"client_key\": \"{s}\",\n", .{key});
        }
        if (config.entertainment_area_id) |id| {
            try writer.print("  \"entertainment_area_id\": \"{s}\",\n", .{id});
        }
        try writer.print("  \"fps_tier\": \"{s}\",\n", .{config.fps_tier.toString()});
        try writer.print("  \"brightness\": {d},\n", .{config.brightness});
        try writer.print("  \"smoothing\": {d:.2},\n", .{config.smoothing});
        try writer.print("  \"only_send_dirty\": {}\n", .{config.only_send_dirty});
        try writer.writeAll("}\n");

        // Write file with restricted permissions (0600)
        const file = std.fs.createFileAbsolute(self.config_path, .{
            .mode = 0o600,
        }) catch return ConfigError.ConfigWriteFailed;
        defer file.close();

        file.writeAll(buffer.items) catch return ConfigError.ConfigWriteFailed;
    }

    /// Update credentials after pairing
    pub fn saveCredentials(self: *Self, bridge_ip: []const u8, app_key: []const u8, client_key: []const u8) !void {
        var config = self.load() catch Config{};
        defer config.deinit(self.allocator);

        // Create new config with updated credentials
        var new_config = Config{
            .bridge_ip = try self.allocator.dupe(u8, bridge_ip),
            .app_key = try self.allocator.dupe(u8, app_key),
            .client_key = try self.allocator.dupe(u8, client_key),
            .entertainment_area_id = if (config.entertainment_area_id) |id| try self.allocator.dupe(u8, id) else null,
            .fps_tier = config.fps_tier,
            .brightness = config.brightness,
            .smoothing = config.smoothing,
            .only_send_dirty = config.only_send_dirty,
        };
        defer new_config.deinit(self.allocator);

        try self.save(&new_config);
    }

    fn parseConfig(self: *Self, content: []const u8) !Config {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, content, .{}) catch return ConfigError.InvalidConfig;
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return ConfigError.InvalidConfig;

        var config = Config{};

        if (root.object.get("bridge_ip")) |v| {
            if (v == .string) config.bridge_ip = try self.allocator.dupe(u8, v.string);
        }
        if (root.object.get("app_key")) |v| {
            if (v == .string) config.app_key = try self.allocator.dupe(u8, v.string);
        }
        if (root.object.get("client_key")) |v| {
            if (v == .string) config.client_key = try self.allocator.dupe(u8, v.string);
        }
        if (root.object.get("entertainment_area_id")) |v| {
            if (v == .string) config.entertainment_area_id = try self.allocator.dupe(u8, v.string);
        }
        if (root.object.get("fps_tier")) |v| {
            if (v == .string) {
                if (Config.FpsTier.fromString(v.string)) |tier| {
                    config.fps_tier = tier;
                }
            }
        }
        if (root.object.get("brightness")) |v| {
            if (v == .integer) config.brightness = @intCast(@min(100, @max(0, v.integer)));
        }
        if (root.object.get("smoothing")) |v| {
            if (v == .float) config.smoothing = @floatCast(@min(1.0, @max(0.0, v.float)));
        }
        if (root.object.get("only_send_dirty")) |v| {
            if (v == .bool) config.only_send_dirty = v.bool;
        }

        return config;
    }

    /// Get the config file path for display
    pub fn getConfigPath(self: *const Self) []const u8 {
        return self.config_path;
    }
};

/// Get the XDG config directory path
fn getConfigDir(allocator: std.mem.Allocator) ![]const u8 {
    // Check XDG_CONFIG_HOME first
    if (std.posix.getenv("XDG_CONFIG_HOME")) |xdg_config| {
        return std.fs.path.join(allocator, &.{ xdg_config, ConfigManager.CONFIG_DIR_NAME });
    }

    // Fall back to ~/.config
    if (std.posix.getenv("HOME")) |home| {
        return std.fs.path.join(allocator, &.{ home, ".config", ConfigManager.CONFIG_DIR_NAME });
    }

    return ConfigError.ConfigDirCreationFailed;
}

test "config fps tier conversion" {
    try std.testing.expectEqual(@as(u8, 12), Config.FpsTier.low.toFps());
    try std.testing.expectEqual(@as(u8, 24), Config.FpsTier.medium.toFps());
    try std.testing.expectEqual(@as(u8, 30), Config.FpsTier.high.toFps());
    try std.testing.expectEqual(@as(u8, 60), Config.FpsTier.max.toFps());
}

test "config fps tier from string" {
    try std.testing.expectEqual(Config.FpsTier.low, Config.FpsTier.fromString("Low").?);
    try std.testing.expectEqual(Config.FpsTier.medium, Config.FpsTier.fromString("medium").?);
    try std.testing.expectEqual(Config.FpsTier.high, Config.FpsTier.fromString("High").?);
    try std.testing.expectEqual(Config.FpsTier.max, Config.FpsTier.fromString("max").?);
    try std.testing.expect(Config.FpsTier.fromString("invalid") == null);
}

test "config isPaired" {
    var config = Config{};
    try std.testing.expect(!config.isPaired());

    config.bridge_ip = "192.168.1.100";
    try std.testing.expect(!config.isPaired());

    config.app_key = "test-key";
    try std.testing.expect(!config.isPaired());

    config.client_key = "client-key";
    try std.testing.expect(config.isPaired());
}
