//! Hue Entertainment streaming coordinator
//! Manages DTLS connection and frame transmission
const std = @import("std");
const dtls = @import("dtls.zig");
const protocol = @import("protocol.zig");

pub const StreamingError = error{
    NotConfigured,
    ConnectionFailed,
    StreamingFailed,
    AreaNotActive,
    NotSupported,
};

/// FPS tier for streaming rate limiting
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

    pub fn frameIntervalNs(self: FpsTier) u64 {
        const fps = self.toFps();
        return std.time.ns_per_s / @as(u64, fps);
    }
};

/// Light channel for streaming
pub const LightChannel = struct {
    channel_id: u8,
    light_id: []const u8,
    x: f32,
    y: f32,
    brightness: f32,
};

/// Entertainment streaming session
pub const EntertainmentStreamer = struct {
    allocator: std.mem.Allocator,
    connection: ?dtls.DtlsConnection = null,
    frame: protocol.Frame,
    fps_tier: FpsTier,
    area_id: []const u8,
    is_streaming: bool,

    // Rate limiting
    last_frame_time: i128,
    frame_count: u64,
    dropped_frames: u64,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .frame = protocol.Frame{},
            .fps_tier = .high,
            .area_id = "",
            .is_streaming = false,
            .last_frame_time = 0,
            .frame_count = 0,
            .dropped_frames = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();
        if (self.connection) |*conn| {
            conn.deinit();
        }
    }

    /// Configure streaming for an entertainment area
    pub fn configure(
        self: *Self,
        bridge_ip: []const u8,
        app_key: []const u8,
        client_key: []const u8,
        area_id: []const u8,
    ) !void {
        // Set up DTLS connection
        self.connection = dtls.DtlsConnection.init(
            self.allocator,
            bridge_ip,
            app_key,
            client_key,
        );

        self.area_id = area_id;
        self.frame.setAreaId(area_id);
    }

    /// Set FPS tier
    pub fn setFpsTier(self: *Self, tier: FpsTier) void {
        self.fps_tier = tier;
    }

    /// Start streaming
    pub fn start(self: *Self) StreamingError!void {
        if (self.connection == null) return StreamingError.NotConfigured;

        // Connect DTLS
        self.connection.?.connect() catch |err| {
            return switch (err) {
                dtls.DtlsError.NotSupported => StreamingError.NotSupported,
                else => StreamingError.ConnectionFailed,
            };
        };

        self.is_streaming = true;
        self.last_frame_time = std.time.nanoTimestamp();
        self.frame_count = 0;
        self.dropped_frames = 0;
    }

    /// Stop streaming
    pub fn stop(self: *Self) void {
        self.is_streaming = false;
        if (self.connection) |*conn| {
            conn.disconnect();
        }
    }

    /// Send a frame with light states
    /// Returns true if frame was sent, false if rate-limited
    pub fn sendFrame(self: *Self, lights: []const LightChannel) !bool {
        if (!self.is_streaming) return StreamingError.NotConfigured;

        const conn = &(self.connection orelse return StreamingError.NotConfigured);
        if (!conn.isConnected()) return StreamingError.ConnectionFailed;

        // Rate limiting
        const now = std.time.nanoTimestamp();
        const elapsed: u64 = @intCast(now - self.last_frame_time);
        const min_interval = self.fps_tier.frameIntervalNs();

        if (elapsed < min_interval) {
            self.dropped_frames += 1;
            return false;
        }

        // Build light states
        var states = try self.allocator.alloc(protocol.LightState, lights.len);
        defer self.allocator.free(states);

        for (lights, 0..) |light, i| {
            states[i] = protocol.LightState.fromXYB(
                light.x,
                light.y,
                light.brightness,
            ).withChannel(light.channel_id);
        }

        // Encode and send frame
        var buffer: [1024]u8 = undefined;
        const frame_size = try protocol.encodeFrame(&self.frame, states, &buffer);

        conn.send(buffer[0..frame_size]) catch |err| {
            return switch (err) {
                dtls.DtlsError.NotSupported => StreamingError.NotSupported,
                else => StreamingError.StreamingFailed,
            };
        };

        self.frame.nextSequence();
        self.last_frame_time = now;
        self.frame_count += 1;

        return true;
    }

    /// Get streaming statistics
    pub fn getStats(self: *const Self) Stats {
        return .{
            .frame_count = self.frame_count,
            .dropped_frames = self.dropped_frames,
            .is_streaming = self.is_streaming,
            .fps_tier = self.fps_tier,
        };
    }

    pub const Stats = struct {
        frame_count: u64,
        dropped_frames: u64,
        is_streaming: bool,
        fps_tier: FpsTier,
    };
};

/// Check if entertainment streaming is supported on this platform
pub fn isSupported() bool {
    // Full support requires DTLS (mbedTLS)
    // Return false for now since we only have stubs
    return false;
}

test "entertainment streamer init" {
    const allocator = std.testing.allocator;
    var streamer = EntertainmentStreamer.init(allocator);
    defer streamer.deinit();

    try std.testing.expect(!streamer.is_streaming);
}

test "fps tier intervals" {
    try std.testing.expectEqual(@as(u64, std.time.ns_per_s / 12), FpsTier.low.frameIntervalNs());
    try std.testing.expectEqual(@as(u64, std.time.ns_per_s / 30), FpsTier.high.frameIntervalNs());
}
