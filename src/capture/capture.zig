//! Screen capture module
//! Coordinates portal permissions and PipeWire frame capture
const std = @import("std");
const portal = @import("portal.zig");
const pipewire = @import("pipewire.zig");

pub const CaptureError = error{
    PortalConnectionFailed,
    PermissionDenied,
    NoStreamsAvailable,
    PipeWireConnectionFailed,
    CaptureNotStarted,
    OutOfMemory,
};

pub const CaptureOptions = struct {
    capture_type: portal.CaptureType = .monitor,
    cursor_mode: portal.CursorMode = .embedded,
    multiple: bool = false,
    target_fps: u8 = 30,
};

pub const Frame = pipewire.Frame;

/// Screen capture session manager
pub const ScreenCapture = struct {
    allocator: std.mem.Allocator,
    portal_client: portal.PortalClient,
    session: ?portal.ScreenCastSession = null,
    stream: ?pipewire.CaptureStream = null,
    is_capturing: bool = false,
    target_fps: u8 = 30,
    frame_callback: ?*const fn (Frame) void = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .portal_client = portal.PortalClient.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();
        if (self.session) |*session| {
            session.deinit();
        }
        self.portal_client.deinit();
    }

    /// Request screen capture permission via portal
    /// This will show the system's screen selection dialog
    pub fn requestPermission(self: *Self, options: CaptureOptions) !void {
        self.target_fps = options.target_fps;

        // Connect to DBus
        self.portal_client.connect() catch return CaptureError.PortalConnectionFailed;

        // Start portal flow - this shows the system dialog
        self.session = self.portal_client.startScreenCast(.{
            .capture_type = options.capture_type,
            .cursor_mode = options.cursor_mode,
            .multiple = options.multiple,
        }) catch |err| {
            return switch (err) {
                portal.PortalError.Cancelled => CaptureError.PermissionDenied,
                portal.PortalError.PermissionDenied => CaptureError.PermissionDenied,
                portal.PortalError.NoStreams => CaptureError.NoStreamsAvailable,
                else => CaptureError.PortalConnectionFailed,
            };
        };
    }

    /// Start capturing frames
    pub fn start(self: *Self) !void {
        const session = self.session orelse return CaptureError.CaptureNotStarted;

        if (session.streams.len == 0) return CaptureError.NoStreamsAvailable;

        // Initialize PipeWire capture
        var stream = pipewire.CaptureStream.init(self.allocator);
        errdefer stream.deinit();

        // Connect to the first stream's node
        const node_id = session.streams[0].node_id;
        stream.connectToNode(node_id) catch return CaptureError.PipeWireConnectionFailed;

        if (self.frame_callback) |callback| {
            stream.setFrameCallback(callback);
        }

        self.stream = stream;
        self.is_capturing = true;

        // Start the capture loop (this runs in the PipeWire main loop)
        stream.start();
    }

    /// Stop capturing
    pub fn stop(self: *Self) void {
        self.is_capturing = false;
        if (self.stream) |*stream| {
            stream.stop();
            stream.deinit();
            self.stream = null;
        }
    }

    /// Set callback for receiving frames
    pub fn setFrameCallback(self: *Self, callback: *const fn (Frame) void) void {
        self.frame_callback = callback;
        if (self.stream) |*stream| {
            stream.setFrameCallback(callback);
        }
    }

    /// Check if capture is active
    pub fn isCapturing(self: *const Self) bool {
        return self.is_capturing;
    }

    /// Get stream information
    pub fn getStreamInfo(self: *const Self) ?struct { node_id: u32, source_type: ?portal.CaptureType } {
        const session = self.session orelse return null;
        if (session.streams.len == 0) return null;

        return .{
            .node_id = session.streams[0].node_id,
            .source_type = session.streams[0].source_type,
        };
    }
};

test "screen capture initialization" {
    const allocator = std.testing.allocator;
    var capture = ScreenCapture.init(allocator);
    defer capture.deinit();
    try std.testing.expect(!capture.isCapturing());
}
