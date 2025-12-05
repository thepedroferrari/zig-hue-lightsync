//! StatusNotifierItem (SNI) system tray integration
//!
//! Implements the org.kde.StatusNotifierItem DBus interface
//! for system tray icon support on modern Linux desktops.

const std = @import("std");

// DBus bindings (reusing from capture module)
pub const dbus = @cImport({
    @cInclude("dbus/dbus.h");
});

/// SNI item status
pub const Status = enum {
    passive, // Not active, may be hidden
    active, // Active, should be visible
    needs_attention, // Needs user attention (e.g., notification)
};

/// SNI item category
pub const Category = enum {
    application_status,
    communications,
    system_services,
    hardware,
};

/// Tray icon data
pub const IconData = struct {
    /// Icon name (from icon theme) or path to icon file
    name: []const u8 = "hue-sync",
    /// Fallback icon as pixel data (ARGB32)
    pixmap: ?[]const u8 = null,
    pixmap_width: u32 = 0,
    pixmap_height: u32 = 0,
};

/// StatusNotifierItem configuration
pub const SniConfig = struct {
    /// Unique identifier
    id: []const u8 = "zig-hue-lightsync",
    /// Category
    category: Category = .application_status,
    /// Window ID (0 if not associated with a window)
    window_id: u32 = 0,
    /// Title shown in tooltip
    title: []const u8 = "Hue Lightsync",
    /// Icon
    icon: IconData = .{},
    /// Overlay icon (optional)
    overlay_icon: ?IconData = null,
    /// Attention icon (for needs_attention status)
    attention_icon: ?IconData = null,
    /// Tooltip
    tooltip_title: []const u8 = "Hue Lightsync",
    tooltip_body: []const u8 = "Click to open controls",
};

/// Callback function types
pub const ActivateCallback = *const fn (x: i32, y: i32) void;
pub const SecondaryActivateCallback = *const fn (x: i32, y: i32) void;
pub const ScrollCallback = *const fn (delta: i32, orientation: ScrollOrientation) void;
pub const ContextMenuCallback = *const fn (x: i32, y: i32) void;

pub const ScrollOrientation = enum { horizontal, vertical };

/// StatusNotifierItem client
pub const StatusNotifierItem = struct {
    allocator: std.mem.Allocator,
    connection: ?*dbus.DBusConnection = null,
    config: SniConfig,
    status: Status = .active,
    registered: bool = false,

    // Callbacks
    on_activate: ?ActivateCallback = null,
    on_secondary_activate: ?SecondaryActivateCallback = null,
    on_scroll: ?ScrollCallback = null,
    on_context_menu: ?ContextMenuCallback = null,

    // DBus object path
    object_path: []const u8 = "/StatusNotifierItem",

    const Self = @This();

    /// DBus interface names
    const WATCHER_BUS_NAME = "org.kde.StatusNotifierWatcher";
    const WATCHER_OBJECT_PATH = "/StatusNotifierWatcher";
    const WATCHER_INTERFACE = "org.kde.StatusNotifierWatcher";
    const ITEM_INTERFACE = "org.kde.StatusNotifierItem";

    /// Initialize SNI client
    pub fn init(allocator: std.mem.Allocator, config: SniConfig) !Self {
        var err: dbus.DBusError = undefined;
        dbus.dbus_error_init(&err);

        // Connect to session bus
        const conn = dbus.dbus_bus_get(dbus.DBUS_BUS_SESSION, &err);
        if (dbus.dbus_error_is_set(&err) != 0) {
            dbus.dbus_error_free(&err);
            return error.DBusConnectionFailed;
        }

        if (conn == null) {
            return error.DBusConnectionFailed;
        }

        return Self{
            .allocator = allocator,
            .connection = conn,
            .config = config,
        };
    }

    /// Cleanup
    pub fn deinit(self: *Self) void {
        if (self.registered) {
            self.unregister() catch {};
        }
        if (self.connection) |conn| {
            dbus.dbus_connection_unref(conn);
        }
    }

    /// Register with StatusNotifierWatcher
    pub fn register(self: *Self) !void {
        const conn = self.connection orelse return error.NotConnected;

        // Request a unique bus name for our item
        var err: dbus.DBusError = undefined;
        dbus.dbus_error_init(&err);

        // Create our service name
        var name_buf: [128]u8 = undefined;
        const service_name = std.fmt.bufPrintZ(&name_buf, "org.kde.StatusNotifierItem-{d}-1", .{std.os.linux.getpid()}) catch return error.FormatError;

        const result = dbus.dbus_bus_request_name(conn, service_name.ptr, dbus.DBUS_NAME_FLAG_DO_NOT_QUEUE, &err);
        if (dbus.dbus_error_is_set(&err) != 0) {
            dbus.dbus_error_free(&err);
            return error.NameRequestFailed;
        }

        if (result != dbus.DBUS_REQUEST_NAME_REPLY_PRIMARY_OWNER) {
            return error.NameRequestFailed;
        }

        // Register object path for method calls
        // In a full implementation, we'd register a message filter here

        // Call RegisterStatusNotifierItem on the watcher
        const msg = dbus.dbus_message_new_method_call(
            WATCHER_BUS_NAME,
            WATCHER_OBJECT_PATH,
            WATCHER_INTERFACE,
            "RegisterStatusNotifierItem",
        ) orelse return error.MessageCreationFailed;
        defer dbus.dbus_message_unref(msg);

        // Append service name argument
        var iter: dbus.DBusMessageIter = undefined;
        dbus.dbus_message_iter_init_append(msg, &iter);
        _ = dbus.dbus_message_iter_append_basic(&iter, dbus.DBUS_TYPE_STRING, &service_name.ptr);

        // Send and wait for reply
        const reply = dbus.dbus_connection_send_with_reply_and_block(conn, msg, 5000, &err);
        if (dbus.dbus_error_is_set(&err) != 0) {
            dbus.dbus_error_free(&err);
            return error.RegistrationFailed;
        }

        if (reply != null) {
            dbus.dbus_message_unref(reply);
        }

        self.registered = true;
    }

    /// Unregister from StatusNotifierWatcher
    pub fn unregister(self: *Self) !void {
        // The watcher automatically removes items when they disconnect
        // We just need to release our bus name
        self.registered = false;
    }

    /// Update status
    pub fn setStatus(self: *Self, status: Status) !void {
        self.status = status;
        try self.emitSignal("NewStatus", statusToString(status));
    }

    /// Update icon
    pub fn setIcon(self: *Self, icon: IconData) !void {
        self.config.icon = icon;
        try self.emitSignal("NewIcon", null);
    }

    /// Update tooltip
    pub fn setTooltip(self: *Self, title: []const u8, body: []const u8) !void {
        self.config.tooltip_title = title;
        self.config.tooltip_body = body;
        try self.emitSignal("NewToolTip", null);
    }

    /// Emit a DBus signal
    fn emitSignal(self: *Self, signal_name: [*:0]const u8, string_arg: ?[*:0]const u8) !void {
        const conn = self.connection orelse return error.NotConnected;

        const signal = dbus.dbus_message_new_signal(
            self.object_path.ptr,
            ITEM_INTERFACE,
            signal_name,
        ) orelse return error.SignalCreationFailed;
        defer dbus.dbus_message_unref(signal);

        if (string_arg) |arg| {
            var iter: dbus.DBusMessageIter = undefined;
            dbus.dbus_message_iter_init_append(signal, &iter);
            _ = dbus.dbus_message_iter_append_basic(&iter, dbus.DBUS_TYPE_STRING, &arg);
        }

        _ = dbus.dbus_connection_send(conn, signal, null);
        _ = dbus.dbus_connection_flush(conn);
    }

    /// Process pending DBus messages
    pub fn processEvents(self: *Self) void {
        const conn = self.connection orelse return;

        // Non-blocking dispatch
        _ = dbus.dbus_connection_read_write(conn, 0);

        while (dbus.dbus_connection_dispatch(conn) == dbus.DBUS_DISPATCH_DATA_REMAINS) {
            // Keep dispatching
        }
    }

    fn statusToString(status: Status) [*:0]const u8 {
        return switch (status) {
            .passive => "Passive",
            .active => "Active",
            .needs_attention => "NeedsAttention",
        };
    }
};

/// Check if SNI is available (StatusNotifierWatcher is running)
pub fn isAvailable() bool {
    var err: dbus.DBusError = undefined;
    dbus.dbus_error_init(&err);
    defer dbus.dbus_error_free(&err);

    const conn = dbus.dbus_bus_get(dbus.DBUS_BUS_SESSION, &err);
    if (conn == null or dbus.dbus_error_is_set(&err) != 0) {
        return false;
    }
    defer dbus.dbus_connection_unref(conn);

    // Check if the watcher service exists
    const exists = dbus.dbus_bus_name_has_owner(conn, StatusNotifierItem.WATCHER_BUS_NAME, &err);
    return exists != 0 and dbus.dbus_error_is_set(&err) == 0;
}

test "sni availability check" {
    // Just verify the function compiles
    _ = isAvailable();
}

