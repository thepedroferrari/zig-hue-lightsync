//! Built-in scenes and Hue scene management
//! Provides local preset scenes and v2 API scene recall
const std = @import("std");
const v2rest = @import("hue/v2rest.zig");
const color = @import("color/color.zig");

/// Local preset scene (applied without bridge interaction)
pub const LocalScene = struct {
    name: []const u8,
    brightness: u8, // 0-100
    color_xy: color.CIExy,

    /// Apply to a Hue color
    pub fn toHueColor(self: LocalScene) color.HueColor {
        return .{
            .xy = self.color_xy,
            .brightness = @as(f32, @floatFromInt(self.brightness)) / 100.0,
        };
    }
};

/// Built-in preset scenes (from PRD)
pub const presets = struct {
    /// Warm, relaxed atmosphere
    pub const cozy = LocalScene{
        .name = "Cozy",
        .brightness = 40,
        .color_xy = .{ .x = 0.50, .y = 0.42 },
    };

    /// Full brightness, neutral white
    pub const bright = LocalScene{
        .name = "Bright",
        .brightness = 100,
        .color_xy = .{ .x = 0.32, .y = 0.33 },
    };

    /// Comfortable reading light
    pub const reading = LocalScene{
        .name = "Reading",
        .brightness = 80,
        .color_xy = .{ .x = 0.38, .y = 0.38 },
    };

    /// Warm amber glow
    pub const warm_amber = LocalScene{
        .name = "Warm Amber",
        .brightness = 30,
        .color_xy = .{ .x = 0.56, .y = 0.41 },
    };

    /// Cool focus light
    pub const cool_focus = LocalScene{
        .name = "Cool Focus",
        .brightness = 85,
        .color_xy = .{ .x = 0.28, .y = 0.30 },
    };

    /// Relaxing night mode
    pub const night = LocalScene{
        .name = "Night",
        .brightness = 10,
        .color_xy = .{ .x = 0.58, .y = 0.38 },
    };

    /// Get all preset scenes
    pub fn all() [6]LocalScene {
        return .{ cozy, bright, reading, warm_amber, cool_focus, night };
    }

    /// Find preset by name (case-insensitive)
    pub fn findByName(name: []const u8) ?LocalScene {
        for (all()) |scene| {
            if (std.ascii.eqlIgnoreCase(scene.name, name)) {
                return scene;
            }
        }
        return null;
    }
};

/// Hue v2 scene recall mode
pub const RecallAction = enum {
    active, // Static scene
    dynamic_palette, // Dynamic/animated scene
};

/// Hue scene (from bridge v2 API)
pub const HueScene = struct {
    id: []const u8,
    name: []const u8,
    group_id: []const u8, // Room/zone this scene belongs to
    is_dynamic: bool,

    pub fn deinit(self: *HueScene, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        allocator.free(self.group_id);
    }
};

/// Scene manager for listing and recalling scenes
pub const SceneManager = struct {
    allocator: std.mem.Allocator,
    client: *v2rest.HueClient,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, client: *v2rest.HueClient) Self {
        return .{
            .allocator = allocator,
            .client = client,
        };
    }

    /// List all scenes from the bridge
    pub fn listScenes(self: *Self) ![]HueScene {
        _ = self;
        // TODO: Implement v2 scene listing
        // GET /clip/v2/resource/scene
        return &[_]HueScene{};
    }

    /// Recall a scene by ID
    pub fn recallScene(self: *Self, scene_id: []const u8, action: RecallAction) !void {
        _ = self;
        _ = scene_id;
        _ = action;
        // TODO: Implement v2 scene recall
        // PUT /clip/v2/resource/scene/{id}
        // Body: { "recall": { "action": "active" } }
    }

    /// Recall a local preset scene (applies to all lights)
    pub fn applyLocalScene(self: *Self, scene: LocalScene) !void {
        _ = self;
        _ = scene;
        // TODO: Apply scene colors to lights via v2 API
    }
};

/// Runtime controls for brightness and sync intensity
pub const SyncControls = struct {
    /// Master brightness multiplier (0-100)
    brightness: u8 = 100,
    /// Sync intensity (affects responsiveness)
    intensity: Intensity = .high,
    /// Whether sync is active
    enabled: bool = false,

    pub const Intensity = enum {
        low, // Slower, smoother transitions
        medium,
        high,
        max, // Fastest, most responsive

        pub fn smoothingFactor(self: Intensity) f32 {
            return switch (self) {
                .low => 0.8, // High smoothing
                .medium => 0.5,
                .high => 0.3,
                .max => 0.1, // Low smoothing
            };
        }
    };

    /// Apply brightness adjustment to a color
    pub fn applyBrightness(self: *const SyncControls, hue_color: color.HueColor) color.HueColor {
        const multiplier = @as(f32, @floatFromInt(self.brightness)) / 100.0;
        return hue_color.withBrightness(multiplier);
    }

    /// Get smoothing factor based on intensity
    pub fn getSmoothingFactor(self: *const SyncControls) f32 {
        return self.intensity.smoothingFactor();
    }
};

test "local scene presets" {
    const cozy = presets.cozy;
    try std.testing.expectEqualStrings("Cozy", cozy.name);
    try std.testing.expectEqual(@as(u8, 40), cozy.brightness);
}

test "find preset by name" {
    const scene = presets.findByName("bright");
    try std.testing.expect(scene != null);
    try std.testing.expectEqual(@as(u8, 100), scene.?.brightness);

    const not_found = presets.findByName("nonexistent");
    try std.testing.expect(not_found == null);
}

test "sync controls brightness" {
    var controls = SyncControls{};
    controls.brightness = 50;

    const full_color = color.HueColor{
        .xy = .{ .x = 0.5, .y = 0.4 },
        .brightness = 1.0,
    };

    const adjusted = controls.applyBrightness(full_color);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), adjusted.brightness, 0.01);
}
