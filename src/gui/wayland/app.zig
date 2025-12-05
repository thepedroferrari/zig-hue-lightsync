//! Main Wayland GUI application
//!
//! Coordinates all GUI components: tray, settings window, and overlay.

const std = @import("std");
const client = @import("client.zig");
const layer_shell = @import("layer_shell.zig");
const renderer = @import("renderer.zig");
const input = @import("input.zig");
const widgets = @import("widgets.zig");
const screens = @import("screens.zig");

const c = client.c;
const Color = widgets.Color;
const Rect = widgets.Rect;

/// Application state
pub const AppState = enum {
    initializing,
    pairing,
    area_selection,
    ready,
    syncing,
    error_state,
};

/// Main application
pub const App = struct {
    allocator: std.mem.Allocator,

    // Wayland state
    display: ?client.Display = null,
    registry: ?client.Registry = null,
    compositor: ?*c.wl_compositor = null,
    shm: ?*c.wl_shm = null,
    seat: ?*c.wl_seat = null,
    layer_shell_global: layer_shell.LayerShell = .{},

    // Input
    input_manager: input.InputManager = .{},

    // Application state
    state: AppState = .initializing,
    running: bool = false,

    // Screen data
    pairing_data: screens.PairingData = .{},
    area_picker_data: screens.AreaPickerData = .{},
    tray_popup_data: screens.TrayPopupData = .{},
    overlay_data: screens.OverlayData = .{},

    // Window state
    settings_visible: bool = false,
    overlay_visible: bool = false,
    tray_popup_visible: bool = false,

    const Self = @This();

    /// Initialize the application
    pub fn init(allocator: std.mem.Allocator) !Self {
        var app = Self{
            .allocator = allocator,
        };

        // Connect to Wayland
        app.display = try client.Display.connect();
        errdefer if (app.display) |*d| d.disconnect();

        // Get registry
        app.registry = try app.display.?.getRegistry();

        // Set up registry listener
        const registry_listener = c.wl_registry_listener{
            .global = globalHandler,
            .global_remove = globalRemoveHandler,
        };
        app.registry.?.addListener(&registry_listener, &app);

        // Roundtrip to get globals
        try app.display.?.roundtrip();
        try app.display.?.roundtrip();

        app.running = true;
        app.state = .pairing;

        return app;
    }

    /// Cleanup
    pub fn deinit(self: *Self) void {
        self.input_manager.deinit();
        if (self.registry) |*reg| reg.destroy();
        if (self.display) |*disp| disp.disconnect();
    }

    /// Run the main event loop
    pub fn run(self: *Self) !void {
        var last_time = std.time.milliTimestamp();

        while (self.running) {
            // Calculate delta time
            const current_time = std.time.milliTimestamp();
            const dt = @as(f32, @floatFromInt(current_time - last_time)) / 1000.0;
            last_time = current_time;

            // Update animations
            self.updateAnimations(dt);

            // Dispatch Wayland events
            try self.display.?.dispatchPending();
            try self.display.?.flush();

            // Small sleep to not burn CPU
            std.time.sleep(16 * std.time.ns_per_ms); // ~60fps
        }
    }

    /// Update all animations
    fn updateAnimations(self: *Self, dt: f32) void {
        switch (self.state) {
            .pairing => screens.pairing.updateAnimations(&self.pairing_data, dt),
            else => {},
        }

        if (self.tray_popup_visible) {
            _ = screens.tray_popup.updateAnimation(&self.tray_popup_data, dt);
        }

        if (self.overlay_visible) {
            _ = screens.overlay.updateAnimation(&self.overlay_data, dt);
        }
    }

    /// Show the settings window
    pub fn showSettings(self: *Self) void {
        self.settings_visible = true;
        // Create layer surface, etc.
    }

    /// Hide the settings window
    pub fn hideSettings(self: *Self) void {
        self.settings_visible = false;
    }

    /// Toggle overlay visibility
    pub fn toggleOverlay(self: *Self) void {
        self.overlay_visible = !self.overlay_visible;
    }

    /// Show tray popup
    pub fn showTrayPopup(self: *Self) void {
        self.tray_popup_visible = true;
    }

    /// Hide tray popup
    pub fn hideTrayPopup(self: *Self) void {
        self.tray_popup_visible = false;
    }

    /// Quit the application
    pub fn quit(self: *Self) void {
        self.running = false;
    }

    // Registry global handler
    fn globalHandler(
        data: ?*anyopaque,
        registry: ?*c.wl_registry,
        name: u32,
        interface_ptr: [*:0]const u8,
        version: u32,
    ) callconv(.C) void {
        const self: *Self = @ptrCast(@alignCast(data));
        const interface = std.mem.span(interface_ptr);

        if (std.mem.eql(u8, interface, "wl_compositor")) {
            self.compositor = @ptrCast(@alignCast(c.wl_registry_bind(
                registry,
                name,
                &c.wl_compositor_interface,
                @min(version, 4),
            )));
        } else if (std.mem.eql(u8, interface, "wl_shm")) {
            self.shm = @ptrCast(@alignCast(c.wl_registry_bind(
                registry,
                name,
                &c.wl_shm_interface,
                @min(version, 1),
            )));
        } else if (std.mem.eql(u8, interface, "wl_seat")) {
            self.seat = @ptrCast(@alignCast(c.wl_registry_bind(
                registry,
                name,
                &c.wl_seat_interface,
                @min(version, 5),
            )));

            // Set up seat listener for input
            const seat_listener = c.wl_seat_listener{
                .capabilities = seatCapabilities,
                .name = null,
            };
            _ = c.wl_seat_add_listener(self.seat, &seat_listener, self);
        } else if (std.mem.eql(u8, interface, layer_shell.interface_name)) {
            self.layer_shell_global.ptr = c.wl_registry_bind(
                registry,
                name,
                // We'd need the actual interface here
                &c.wl_compositor_interface, // Placeholder
                @min(version, 4),
            );
            self.layer_shell_global.version = version;
        }
    }

    fn globalRemoveHandler(
        _: ?*anyopaque,
        _: ?*c.wl_registry,
        _: u32,
    ) callconv(.C) void {
        // Handle global removal if needed
    }

    fn seatCapabilities(
        data: ?*anyopaque,
        _: ?*c.wl_seat,
        capabilities: u32,
    ) callconv(.C) void {
        const self: *Self = @ptrCast(@alignCast(data));
        var seat = client.Seat{ .ptr = self.seat.? };
        self.input_manager.initFromSeat(&seat, capabilities);
    }
};

/// Check if Wayland GUI is supported
pub fn isSupported() bool {
    return client.isWaylandSession();
}

/// Launch the GUI application
pub fn launch(allocator: std.mem.Allocator) !void {
    var app = try App.init(allocator);
    defer app.deinit();

    try app.run();
}

/// GUI error types
pub const GuiError = error{
    NotSupported,
    InitFailed,
    ConnectionFailed,
    DispatchFailed,
    FlushFailed,
    RoundtripFailed,
    OutOfMemory,
};

test "wayland gui support check" {
    // Just verify the function compiles
    _ = isSupported();
}

