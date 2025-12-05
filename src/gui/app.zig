//! GTK4 GUI Application
//! Minimal control panel for zig-hue-lightsync
const std = @import("std");
const builtin = @import("builtin");
const gtk = @import("gtk.zig");
const root = @import("../root.zig");

pub const GuiError = error{
    InitFailed,
    NotSupported,
    WindowCreationFailed,
};

/// GUI Application state
pub const App = struct {
    allocator: std.mem.Allocator,
    gtk_app: ?gtk.GtkApplication = null,
    window: ?gtk.GtkWidget = null,

    // Widget references
    sync_switch: ?gtk.GtkWidget = null,
    brightness_slider: ?gtk.GtkWidget = null,
    area_dropdown: ?gtk.GtkWidget = null,
    fps_dropdown: ?gtk.GtkWidget = null,
    status_label: ?gtk.GtkWidget = null,

    // State
    is_syncing: bool = false,
    brightness: u8 = 75,
    selected_area: usize = 0,
    fps_tier: root.config.Config.FpsTier = .high,

    // Config
    config: ?root.Config = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.config) |*cfg| {
            cfg.deinit(self.allocator);
        }
        if (self.gtk_app) |app| {
            gtk.objectUnref(app);
        }
    }

    /// Launch the GUI application
    pub fn run(self: *Self) GuiError!void {
        if (!gtk.isAvailable()) {
            return GuiError.NotSupported;
        }

        // Load configuration
        var cfg_manager = root.ConfigManager.init(self.allocator) catch return GuiError.InitFailed;
        defer cfg_manager.deinit();

        self.config = cfg_manager.load() catch null;
        if (self.config) |cfg| {
            self.brightness = cfg.brightness;
            self.fps_tier = cfg.fps_tier;
        }

        // Create GTK application
        self.gtk_app = gtk.applicationNew("io.github.zighue.lightsync", 0);
        if (self.gtk_app == null) {
            return GuiError.InitFailed;
        }

        // Connect activate signal
        _ = gtk.signalConnect(
            self.gtk_app.?,
            "activate",
            @ptrCast(&onActivate),
            @ptrCast(self),
        );

        // Run the application
        _ = gtk.applicationRun(self.gtk_app.?, 0, null);
    }

    fn onActivate(app: gtk.GtkApplication, user_data: ?*anyopaque) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(user_data orelse return));
        self.buildUI(app);
    }

    fn buildUI(self: *Self, app: gtk.GtkApplication) void {
        // Create main window
        self.window = gtk.applicationWindowNew(app);
        if (self.window == null) return;

        gtk.windowSetTitle(self.window.?, "Hue Light Sync");
        gtk.windowSetDefaultSize(self.window.?, 400, 300);

        // Create main container
        const main_box = gtk.boxNew(.vertical, 12) orelse return;
        gtk.widgetSetMarginAll(main_box, 16);

        // Header with status
        const header = self.buildHeader();
        if (header) |h| gtk.boxAppend(main_box, h);

        // Sync toggle
        const sync_row = self.buildSyncToggle();
        if (sync_row) |s| gtk.boxAppend(main_box, s);

        // Brightness slider
        const brightness_row = self.buildBrightnessSlider();
        if (brightness_row) |b| gtk.boxAppend(main_box, b);

        // FPS tier dropdown
        const fps_row = self.buildFpsDropdown();
        if (fps_row) |f| gtk.boxAppend(main_box, f);

        // Scene buttons
        const scene_row = self.buildSceneButtons();
        if (scene_row) |sr| gtk.boxAppend(main_box, sr);

        // Status bar
        self.status_label = gtk.labelNew("Ready");
        if (self.status_label) |label| {
            gtk.boxAppend(main_box, label);
        }

        gtk.windowSetChild(self.window.?, main_box);
        gtk.widgetSetVisible(self.window.?, true);
    }

    fn buildHeader(self: *Self) ?gtk.GtkWidget {
        const box = gtk.boxNew(.horizontal, 8) orelse return null;

        const title = gtk.labelNew("Hue Light Sync") orelse return box;
        gtk.widgetSetHexpand(title, true);
        gtk.boxAppend(box, title);

        // Connection status
        const status_text = if (self.config != null and self.config.?.isPaired())
            "● Connected"
        else
            "○ Not paired";

        const status = gtk.labelNew(status_text) orelse return box;
        gtk.boxAppend(box, status);

        return box;
    }

    fn buildSyncToggle(self: *Self) ?gtk.GtkWidget {
        const box = gtk.boxNew(.horizontal, 8) orelse return null;

        const label = gtk.labelNew("Screen Sync") orelse return box;
        gtk.widgetSetHexpand(label, true);
        gtk.boxAppend(box, label);

        self.sync_switch = gtk.switchNew();
        if (self.sync_switch) |sw| {
            gtk.switchSetActive(sw, self.is_syncing);
            _ = gtk.signalConnect(sw, "state-set", @ptrCast(&onSyncToggled), @ptrCast(self));
            gtk.boxAppend(box, sw);
        }

        return box;
    }

    fn buildBrightnessSlider(self: *Self) ?gtk.GtkWidget {
        const box = gtk.boxNew(.horizontal, 8) orelse return null;

        const label = gtk.labelNew("Brightness") orelse return box;
        gtk.boxAppend(box, label);

        self.brightness_slider = gtk.scaleNewWithRange(.horizontal, 0, 100, 5);
        if (self.brightness_slider) |slider| {
            gtk.rangeSetValue(slider, @floatFromInt(self.brightness));
            gtk.widgetSetHexpand(slider, true);
            _ = gtk.signalConnect(slider, "value-changed", @ptrCast(&onBrightnessChanged), @ptrCast(self));
            gtk.boxAppend(box, slider);
        }

        return box;
    }

    fn buildFpsDropdown(self: *Self) ?gtk.GtkWidget {
        _ = self;
        const box = gtk.boxNew(.horizontal, 8) orelse return null;

        const label = gtk.labelNew("Sync Speed") orelse return box;
        gtk.widgetSetHexpand(label, true);
        gtk.boxAppend(box, label);

        // FPS tier buttons instead of dropdown (simpler, no C array issues)
        const fps_labels = [_][]const u8{ "Low", "Med", "High", "Max" };
        for (fps_labels) |fps_label| {
            const btn = gtk.buttonNewWithLabel(fps_label.ptr);
            if (btn) |b| {
                gtk.boxAppend(box, b);
            }
        }

        return box;
    }

    fn buildSceneButtons(self: *Self) ?gtk.GtkWidget {
        _ = self;
        const box = gtk.boxNew(.horizontal, 8) orelse return null;

        const scenes = [_][]const u8{ "Cozy", "Bright", "Reading", "Night" };
        for (scenes) |scene_name| {
            const btn = gtk.buttonNewWithLabel(scene_name.ptr);
            if (btn) |b| {
                gtk.boxAppend(box, b);
            }
        }

        return box;
    }

    fn onSyncToggled(_: gtk.GtkWidget, state: c_int, user_data: ?*anyopaque) callconv(.c) c_int {
        const self: *Self = @ptrCast(@alignCast(user_data orelse return 0));
        self.is_syncing = state != 0;

        if (self.status_label) |label| {
            const text = if (self.is_syncing) "Syncing..." else "Stopped";
            gtk.labelSetText(label, text);
        }

        return 0; // Don't prevent the state change
    }

    fn onBrightnessChanged(range: gtk.GtkWidget, user_data: ?*anyopaque) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(user_data orelse return));
        const value = gtk.rangeGetValue(range);
        self.brightness = @intFromFloat(value);
    }
};

/// Check if GUI is supported on this platform
pub fn isSupported() bool {
    return gtk.isAvailable();
}

/// Launch the GUI application
pub fn launch(allocator: std.mem.Allocator) GuiError!void {
    var app = App.init(allocator);
    defer app.deinit();
    try app.run();
}

test "app initialization" {
    const allocator = std.testing.allocator;
    var app = App.init(allocator);
    defer app.deinit();
    // Can't test run() without GTK
}
