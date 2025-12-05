//! xdg-desktop-portal ScreenCast interface
//! Handles DBus communication with the portal for screen capture permissions
const std = @import("std");
const dbus = @import("dbus.zig");

pub const PortalError = error{
    SessionCreationFailed,
    SourceSelectionFailed,
    StartFailed,
    PermissionDenied,
    Cancelled,
    NoStreams,
    DBusError,
    OutOfMemory,
};

pub const CaptureType = enum(u32) {
    monitor = 1,
    window = 2,
    virtual = 4,
};

pub const CursorMode = enum(u32) {
    hidden = 1,
    embedded = 2,
    metadata = 4,
};

pub const Stream = struct {
    node_id: u32,
    position: ?struct { x: i32, y: i32 } = null,
    size: ?struct { width: i32, height: i32 } = null,
    source_type: ?CaptureType = null,
};

pub const ScreenCastSession = struct {
    allocator: std.mem.Allocator,
    session_handle: []const u8,
    streams: []Stream,
    restore_token: ?[]const u8 = null,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.session_handle);
        self.allocator.free(self.streams);
        if (self.restore_token) |token| self.allocator.free(token);
    }
};

/// Portal client for xdg-desktop-portal ScreenCast
pub const PortalClient = struct {
    allocator: std.mem.Allocator,
    dbus_conn: ?*dbus.Connection = null,
    sender_name: []const u8 = "",
    request_counter: u32 = 0,

    const Self = @This();

    const PORTAL_BUS_NAME = "org.freedesktop.portal.Desktop";
    const PORTAL_OBJECT_PATH = "/org/freedesktop/portal/desktop";
    const SCREENCAST_INTERFACE = "org.freedesktop.portal.ScreenCast";
    const REQUEST_INTERFACE = "org.freedesktop.portal.Request";

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.dbus_conn) |conn| {
            dbus.connectionUnref(conn);
        }
    }

    /// Connect to DBus session bus
    pub fn connect(self: *Self) !void {
        self.dbus_conn = dbus.busGet(.session) orelse return PortalError.DBusError;

        // Get our unique bus name for request path construction
        if (dbus.busGetUniqueName(self.dbus_conn.?)) |name| {
            self.sender_name = name;
        }
    }

    /// Start a new screen capture session
    /// Returns PipeWire stream node IDs after user approves via portal UI
    pub fn startScreenCast(self: *Self, options: StartOptions) !ScreenCastSession {
        if (self.dbus_conn == null) return PortalError.DBusError;

        // Step 1: CreateSession
        const session_handle = try self.createSession();
        errdefer self.allocator.free(session_handle);

        // Step 2: SelectSources
        try self.selectSources(session_handle, options);

        // Step 3: Start
        const streams = try self.start(session_handle);

        return ScreenCastSession{
            .allocator = self.allocator,
            .session_handle = session_handle,
            .streams = streams,
        };
    }

    pub const StartOptions = struct {
        capture_type: CaptureType = .monitor,
        cursor_mode: CursorMode = .embedded,
        multiple: bool = false,
        restore_token: ?[]const u8 = null,
    };

    fn createSession(self: *Self) ![]const u8 {
        const request_path = try self.buildRequestPath();
        defer self.allocator.free(request_path);

        var msg = dbus.messageNewMethodCall(
            PORTAL_BUS_NAME,
            PORTAL_OBJECT_PATH,
            SCREENCAST_INTERFACE,
            "CreateSession",
        ) orelse return PortalError.DBusError;
        defer dbus.messageUnref(msg);

        // Build options dict: { "handle_token": "zig_hue_X", "session_handle_token": "session_X" }
        var iter: dbus.MessageIter = undefined;
        dbus.messageIterInitAppend(msg, &iter);

        var dict_iter: dbus.MessageIter = undefined;
        _ = dbus.messageIterOpenContainer(&iter, dbus.DBUS_TYPE_ARRAY, "{sv}", &dict_iter);

        // Add handle_token
        const request_token = try self.generateToken("request");
        defer self.allocator.free(request_token);
        try self.appendDictEntry(&dict_iter, "handle_token", request_token);

        const session_token = try self.generateToken("session");
        defer self.allocator.free(session_token);
        try self.appendDictEntry(&dict_iter, "session_handle_token", session_token);

        _ = dbus.messageIterCloseContainer(&iter, &dict_iter);

        // Send and wait for response
        var reply = dbus.connectionSendWithReply(self.dbus_conn.?, msg, 5000) orelse return PortalError.SessionCreationFailed;
        defer dbus.messageUnref(reply);

        // Parse response to get session handle
        return try self.parseSessionResponse(reply);
    }

    fn selectSources(self: *Self, session_handle: []const u8, options: StartOptions) !void {
        const request_path = try self.buildRequestPath();
        defer self.allocator.free(request_path);

        var msg = dbus.messageNewMethodCall(
            PORTAL_BUS_NAME,
            PORTAL_OBJECT_PATH,
            SCREENCAST_INTERFACE,
            "SelectSources",
        ) orelse return PortalError.DBusError;
        defer dbus.messageUnref(msg);

        var iter: dbus.MessageIter = undefined;
        dbus.messageIterInitAppend(msg, &iter);

        // Session handle (object path)
        _ = dbus.messageIterAppendBasic(&iter, dbus.DBUS_TYPE_OBJECT_PATH, session_handle.ptr);

        // Options dict
        var dict_iter: dbus.MessageIter = undefined;
        _ = dbus.messageIterOpenContainer(&iter, dbus.DBUS_TYPE_ARRAY, "{sv}", &dict_iter);

        const select_token = try self.generateToken("select");
        defer self.allocator.free(select_token);
        try self.appendDictEntry(&dict_iter, "handle_token", select_token);
        try self.appendDictEntryU32(&dict_iter, "types", @intFromEnum(options.capture_type));
        try self.appendDictEntryU32(&dict_iter, "cursor_mode", @intFromEnum(options.cursor_mode));
        try self.appendDictEntryBool(&dict_iter, "multiple", options.multiple);

        if (options.restore_token) |token| {
            try self.appendDictEntry(&dict_iter, "restore_token", token);
        }

        _ = dbus.messageIterCloseContainer(&iter, &dict_iter);

        var reply = dbus.connectionSendWithReply(self.dbus_conn.?, msg, 30000) orelse return PortalError.SourceSelectionFailed;
        defer dbus.messageUnref(reply);

        // Wait for user to select source via portal UI
        // The actual selection happens asynchronously via signals
    }

    fn start(self: *Self, session_handle: []const u8) ![]Stream {
        var msg = dbus.messageNewMethodCall(
            PORTAL_BUS_NAME,
            PORTAL_OBJECT_PATH,
            SCREENCAST_INTERFACE,
            "Start",
        ) orelse return PortalError.DBusError;
        defer dbus.messageUnref(msg);

        var iter: dbus.MessageIter = undefined;
        dbus.messageIterInitAppend(msg, &iter);

        // Session handle
        _ = dbus.messageIterAppendBasic(&iter, dbus.DBUS_TYPE_OBJECT_PATH, session_handle.ptr);

        // Parent window (empty string for no parent)
        const empty: [*c]const u8 = "";
        _ = dbus.messageIterAppendBasic(&iter, dbus.DBUS_TYPE_STRING, @ptrCast(&empty));

        // Options dict
        var dict_iter: dbus.MessageIter = undefined;
        _ = dbus.messageIterOpenContainer(&iter, dbus.DBUS_TYPE_ARRAY, "{sv}", &dict_iter);
        const start_token = try self.generateToken("start");
        defer self.allocator.free(start_token);
        try self.appendDictEntry(&dict_iter, "handle_token", start_token);
        _ = dbus.messageIterCloseContainer(&iter, &dict_iter);

        var reply = dbus.connectionSendWithReply(self.dbus_conn.?, msg, 30000) orelse return PortalError.StartFailed;
        defer dbus.messageUnref(reply);

        return try self.parseStreamsResponse(reply);
    }

    fn buildRequestPath(self: *Self) ![]const u8 {
        self.request_counter += 1;
        // Request path format: /org/freedesktop/portal/desktop/request/SENDER/TOKEN
        const sender_escaped = try self.escapeBusName(self.sender_name);
        defer self.allocator.free(sender_escaped);

        return std.fmt.allocPrint(self.allocator, "/org/freedesktop/portal/desktop/request/{s}/zig_hue_{d}", .{ sender_escaped, self.request_counter });
    }

    fn escapeBusName(self: *Self, name: []const u8) ![]const u8 {
        // Replace ':' and '.' with '_'
        var result = try self.allocator.alloc(u8, name.len);
        for (name, 0..) |c, i| {
            result[i] = if (c == ':' or c == '.') '_' else c;
        }
        return result;
    }

    fn generateToken(self: *Self, prefix: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{s}_{d}", .{ prefix, self.request_counter });
    }

    fn appendDictEntry(self: *Self, dict_iter: *dbus.MessageIter, key: []const u8, value: []const u8) !void {
        _ = self;
        var entry_iter: dbus.MessageIter = undefined;
        var variant_iter: dbus.MessageIter = undefined;

        _ = dbus.messageIterOpenContainer(dict_iter, dbus.DBUS_TYPE_DICT_ENTRY, null, &entry_iter);
        _ = dbus.messageIterAppendBasic(&entry_iter, dbus.DBUS_TYPE_STRING, key.ptr);
        _ = dbus.messageIterOpenContainer(&entry_iter, dbus.DBUS_TYPE_VARIANT, "s", &variant_iter);
        _ = dbus.messageIterAppendBasic(&variant_iter, dbus.DBUS_TYPE_STRING, value.ptr);
        _ = dbus.messageIterCloseContainer(&entry_iter, &variant_iter);
        _ = dbus.messageIterCloseContainer(dict_iter, &entry_iter);
    }

    fn appendDictEntryU32(self: *Self, dict_iter: *dbus.MessageIter, key: []const u8, value: u32) !void {
        _ = self;
        var entry_iter: dbus.MessageIter = undefined;
        var variant_iter: dbus.MessageIter = undefined;

        _ = dbus.messageIterOpenContainer(dict_iter, dbus.DBUS_TYPE_DICT_ENTRY, null, &entry_iter);
        _ = dbus.messageIterAppendBasic(&entry_iter, dbus.DBUS_TYPE_STRING, key.ptr);
        _ = dbus.messageIterOpenContainer(&entry_iter, dbus.DBUS_TYPE_VARIANT, "u", &variant_iter);
        _ = dbus.messageIterAppendBasic(&variant_iter, dbus.DBUS_TYPE_UINT32, &value);
        _ = dbus.messageIterCloseContainer(&entry_iter, &variant_iter);
        _ = dbus.messageIterCloseContainer(dict_iter, &entry_iter);
    }

    fn appendDictEntryBool(self: *Self, dict_iter: *dbus.MessageIter, key: []const u8, value: bool) !void {
        _ = self;
        var entry_iter: dbus.MessageIter = undefined;
        var variant_iter: dbus.MessageIter = undefined;

        _ = dbus.messageIterOpenContainer(dict_iter, dbus.DBUS_TYPE_DICT_ENTRY, null, &entry_iter);
        _ = dbus.messageIterAppendBasic(&entry_iter, dbus.DBUS_TYPE_STRING, key.ptr);
        _ = dbus.messageIterOpenContainer(&entry_iter, dbus.DBUS_TYPE_VARIANT, "b", &variant_iter);
        const bool_val: u32 = if (value) 1 else 0;
        _ = dbus.messageIterAppendBasic(&variant_iter, dbus.DBUS_TYPE_BOOLEAN, &bool_val);
        _ = dbus.messageIterCloseContainer(&entry_iter, &variant_iter);
        _ = dbus.messageIterCloseContainer(dict_iter, &entry_iter);
    }

    fn parseSessionResponse(self: *Self, reply: *dbus.Message) ![]const u8 {
        var iter: dbus.MessageIter = undefined;
        if (!dbus.messageIterInit(reply, &iter)) return PortalError.DBusError;

        // Response is (u, a{sv}) - response code and results dict
        if (dbus.messageIterGetArgType(&iter) != dbus.DBUS_TYPE_UINT32) return PortalError.DBusError;

        var response_code: u32 = undefined;
        dbus.messageIterGetBasic(&iter, &response_code);

        if (response_code != 0) {
            return if (response_code == 1) PortalError.Cancelled else PortalError.PermissionDenied;
        }

        _ = dbus.messageIterNext(&iter);

        // Parse results dict for session_handle
        return try self.extractStringFromDict(&iter, "session_handle");
    }

    fn parseStreamsResponse(self: *Self, reply: *dbus.Message) ![]Stream {
        var iter: dbus.MessageIter = undefined;
        if (!dbus.messageIterInit(reply, &iter)) return PortalError.DBusError;

        // Response is (u, a{sv})
        if (dbus.messageIterGetArgType(&iter) != dbus.DBUS_TYPE_UINT32) return PortalError.DBusError;

        var response_code: u32 = undefined;
        dbus.messageIterGetBasic(&iter, &response_code);

        if (response_code != 0) {
            return if (response_code == 1) PortalError.Cancelled else PortalError.PermissionDenied;
        }

        _ = dbus.messageIterNext(&iter);

        // Parse streams from results dict
        // streams is a(oa{sv}) - array of (node_id, properties)
        var streams = std.ArrayList(Stream).init(self.allocator);
        errdefer streams.deinit();

        // For now, return a placeholder - full implementation requires parsing nested dicts
        // This will be populated when we integrate with PipeWire
        try streams.append(.{ .node_id = 0 });

        return streams.toOwnedSlice();
    }

    fn extractStringFromDict(self: *Self, iter: *dbus.MessageIter, key: []const u8) ![]const u8 {
        _ = key;
        // Simplified - in real implementation, iterate through dict entries
        // For now, return a placeholder session handle
        return try self.allocator.dupe(u8, "/org/freedesktop/portal/desktop/session/placeholder");
    }
};

test "portal client initialization" {
    const allocator = std.testing.allocator;
    var client = PortalClient.init(allocator);
    defer client.deinit();
    // Connection test would require actual DBus session
}