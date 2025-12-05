//! wlr-layer-shell protocol bindings
//!
//! This protocol allows creating surfaces that exist in layers
//! above or below normal application windows - perfect for
//! panels, overlays, and system tray popups.
//!
//! Supported by: Sway, Hyprland, River, wayfire (wlroots-based)

const std = @import("std");
const client = @import("client.zig");
const c = client.c;

/// Layer shell layer types
pub const Layer = enum(u32) {
    background = 0,
    bottom = 1,
    top = 2,
    overlay = 3,
};

/// Anchor edges for positioning
pub const Anchor = packed struct(u32) {
    top: bool = false,
    bottom: bool = false,
    left: bool = false,
    right: bool = false,
    _padding: u28 = 0,

    pub const none: Anchor = .{};
    pub const top_left: Anchor = .{ .top = true, .left = true };
    pub const top_right: Anchor = .{ .top = true, .right = true };
    pub const bottom_left: Anchor = .{ .bottom = true, .left = true };
    pub const bottom_right: Anchor = .{ .bottom = true, .right = true };
    pub const center: Anchor = .{};
    pub const fill: Anchor = .{ .top = true, .bottom = true, .left = true, .right = true };
    pub const top_edge: Anchor = .{ .top = true, .left = true, .right = true };
    pub const bottom_edge: Anchor = .{ .bottom = true, .left = true, .right = true };
    pub const left_edge: Anchor = .{ .left = true, .top = true, .bottom = true };
    pub const right_edge: Anchor = .{ .right = true, .top = true, .bottom = true };

    pub fn toU32(self: Anchor) u32 {
        return @bitCast(self);
    }
};

/// Keyboard interactivity modes
pub const KeyboardInteractivity = enum(u32) {
    none = 0,
    exclusive = 1,
    on_demand = 2,
};

/// Layer shell interface name for registry binding
pub const interface_name = "zwlr_layer_shell_v1";

/// Layer shell global object
/// This is the entry point for creating layer surfaces
pub const LayerShell = struct {
    /// Raw pointer - will be set when bound from registry
    /// Using opaque pointer since we define protocol manually
    ptr: ?*anyopaque = null,
    version: u32 = 0,

    const Self = @This();

    /// Check if layer shell is available
    pub fn isAvailable(self: *const Self) bool {
        return self.ptr != null;
    }

    /// Get the layer surface from a wl_surface
    pub fn getLayerSurface(
        self: *Self,
        surface: *c.wl_surface,
        output: ?*c.wl_output,
        layer: Layer,
        namespace: [:0]const u8,
    ) !LayerSurface {
        if (self.ptr == null) return error.LayerShellNotAvailable;

        // Call the protocol function via C interop
        // zwlr_layer_shell_v1_get_layer_surface(layer_shell, surface, output, layer, namespace)
        const layer_surface = layerShellGetSurface(
            self.ptr.?,
            surface,
            output,
            @intFromEnum(layer),
            namespace.ptr,
        ) orelse return error.LayerSurfaceCreationFailed;

        return .{ .ptr = layer_surface };
    }
};

/// Layer surface - a surface that lives in a specific layer
pub const LayerSurface = struct {
    ptr: *anyopaque,
    configured: bool = false,
    width: u32 = 0,
    height: u32 = 0,
    closed: bool = false,

    const Self = @This();

    /// Set the size of the surface
    /// A size of 0 means the compositor should decide
    pub fn setSize(self: *Self, width: u32, height: u32) void {
        layerSurfaceSetSize(self.ptr, width, height);
    }

    /// Set the anchor edges
    pub fn setAnchor(self: *Self, anchor: Anchor) void {
        layerSurfaceSetAnchor(self.ptr, anchor.toU32());
    }

    /// Set exclusive zone (area reserved from other surfaces)
    /// -1 means extend to screen edge
    pub fn setExclusiveZone(self: *Self, zone: i32) void {
        layerSurfaceSetExclusiveZone(self.ptr, zone);
    }

    /// Set margin from anchor edges
    pub fn setMargin(self: *Self, top: i32, right: i32, bottom: i32, left: i32) void {
        layerSurfaceSetMargin(self.ptr, top, right, bottom, left);
    }

    /// Set keyboard interactivity
    pub fn setKeyboardInteractivity(self: *Self, mode: KeyboardInteractivity) void {
        layerSurfaceSetKeyboardInteractivity(self.ptr, @intFromEnum(mode));
    }

    /// Acknowledge a configure event
    pub fn ackConfigure(self: *Self, serial: u32) void {
        layerSurfaceAckConfigure(self.ptr, serial);
    }

    /// Destroy the layer surface
    pub fn destroy(self: *Self) void {
        layerSurfaceDestroy(self.ptr);
    }

    /// Add listener for layer surface events
    pub fn addListener(self: *Self, listener: *const LayerSurfaceListener, data: ?*anyopaque) void {
        layerSurfaceAddListener(self.ptr, listener, data);
    }
};

/// Layer surface event listener
pub const LayerSurfaceListener = extern struct {
    configure: ?*const fn (?*anyopaque, ?*anyopaque, u32, u32, u32) callconv(.C) void = null,
    closed: ?*const fn (?*anyopaque, ?*anyopaque) callconv(.C) void = null,
};

// External C functions - these will be linked from the layer-shell protocol library
// or implemented via wayland-scanner generated code

extern fn zwlr_layer_shell_v1_get_layer_surface(
    layer_shell: *anyopaque,
    surface: *c.wl_surface,
    output: ?*c.wl_output,
    layer: u32,
    namespace: [*:0]const u8,
) ?*anyopaque;

extern fn zwlr_layer_surface_v1_set_size(layer_surface: *anyopaque, width: u32, height: u32) void;
extern fn zwlr_layer_surface_v1_set_anchor(layer_surface: *anyopaque, anchor: u32) void;
extern fn zwlr_layer_surface_v1_set_exclusive_zone(layer_surface: *anyopaque, zone: i32) void;
extern fn zwlr_layer_surface_v1_set_margin(layer_surface: *anyopaque, top: i32, right: i32, bottom: i32, left: i32) void;
extern fn zwlr_layer_surface_v1_set_keyboard_interactivity(layer_surface: *anyopaque, mode: u32) void;
extern fn zwlr_layer_surface_v1_ack_configure(layer_surface: *anyopaque, serial: u32) void;
extern fn zwlr_layer_surface_v1_destroy(layer_surface: *anyopaque) void;
extern fn zwlr_layer_surface_v1_add_listener(layer_surface: *anyopaque, listener: *const LayerSurfaceListener, data: ?*anyopaque) c_int;

// Wrapper functions to handle null checks
fn layerShellGetSurface(
    layer_shell: *anyopaque,
    surface: *c.wl_surface,
    output: ?*c.wl_output,
    layer: u32,
    namespace: [*:0]const u8,
) ?*anyopaque {
    return zwlr_layer_shell_v1_get_layer_surface(layer_shell, surface, output, layer, namespace);
}

fn layerSurfaceSetSize(layer_surface: *anyopaque, width: u32, height: u32) void {
    zwlr_layer_surface_v1_set_size(layer_surface, width, height);
}

fn layerSurfaceSetAnchor(layer_surface: *anyopaque, anchor: u32) void {
    zwlr_layer_surface_v1_set_anchor(layer_surface, anchor);
}

fn layerSurfaceSetExclusiveZone(layer_surface: *anyopaque, zone: i32) void {
    zwlr_layer_surface_v1_set_exclusive_zone(layer_surface, zone);
}

fn layerSurfaceSetMargin(layer_surface: *anyopaque, top: i32, right: i32, bottom: i32, left: i32) void {
    zwlr_layer_surface_v1_set_margin(layer_surface, top, right, bottom, left);
}

fn layerSurfaceSetKeyboardInteractivity(layer_surface: *anyopaque, mode: u32) void {
    zwlr_layer_surface_v1_set_keyboard_interactivity(layer_surface, mode);
}

fn layerSurfaceAckConfigure(layer_surface: *anyopaque, serial: u32) void {
    zwlr_layer_surface_v1_ack_configure(layer_surface, serial);
}

fn layerSurfaceDestroy(layer_surface: *anyopaque) void {
    zwlr_layer_surface_v1_destroy(layer_surface);
}

fn layerSurfaceAddListener(layer_surface: *anyopaque, listener: *const LayerSurfaceListener, data: ?*anyopaque) void {
    _ = zwlr_layer_surface_v1_add_listener(layer_surface, listener, data);
}

/// Configuration for creating a layer surface
pub const LayerSurfaceConfig = struct {
    layer: Layer = .top,
    anchor: Anchor = Anchor.center,
    width: u32 = 400,
    height: u32 = 300,
    exclusive_zone: i32 = 0,
    margin_top: i32 = 0,
    margin_right: i32 = 0,
    margin_bottom: i32 = 0,
    margin_left: i32 = 0,
    keyboard_interactivity: KeyboardInteractivity = .on_demand,
    namespace: [:0]const u8 = "zig-hue",
};

test "anchor flags" {
    const top_right = Anchor.top_right;
    try std.testing.expect(top_right.top);
    try std.testing.expect(top_right.right);
    try std.testing.expect(!top_right.bottom);
    try std.testing.expect(!top_right.left);

    // Test bit representation
    const fill = Anchor.fill;
    try std.testing.expectEqual(@as(u32, 0b1111), fill.toU32());
}

