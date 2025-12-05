//! Hue Entertainment Protocol
//! Encodes light state frames for DTLS streaming
const std = @import("std");

/// Entertainment protocol color space
pub const ColorSpace = enum(u8) {
    rgb = 0x00,
    xyb = 0x01, // CIE xy + brightness
};

/// Light channel state
pub const LightState = struct {
    /// Channel ID (0-based index in entertainment area)
    channel_id: u8,
    /// CIE x coordinate (0-65535 mapped to 0-1)
    x: u16,
    /// CIE y coordinate (0-65535 mapped to 0-1)
    y: u16,
    /// Brightness (0-65535 mapped to 0-1)
    brightness: u16,

    pub fn fromXYB(x: f32, y: f32, brightness: f32) LightState {
        return .{
            .channel_id = 0,
            .x = @intFromFloat(std.math.clamp(x, 0, 1) * 65535),
            .y = @intFromFloat(std.math.clamp(y, 0, 1) * 65535),
            .brightness = @intFromFloat(std.math.clamp(brightness, 0, 1) * 65535),
        };
    }

    pub fn withChannel(self: LightState, channel: u8) LightState {
        return .{
            .channel_id = channel,
            .x = self.x,
            .y = self.y,
            .brightness = self.brightness,
        };
    }
};

/// Entertainment protocol frame
pub const Frame = struct {
    /// Protocol identifier
    protocol: [9]u8 = "HueStream".*,
    /// Protocol version (major, minor)
    version: [2]u8 = .{ 0x02, 0x00 },
    /// Sequence number (for ordering)
    sequence: u8 = 0,
    /// Reserved bytes
    reserved: [2]u8 = .{ 0x00, 0x00 },
    /// Color space (0x00 = RGB, 0x01 = xyB)
    color_space: ColorSpace = .xyb,
    /// Reserved byte
    reserved2: u8 = 0x00,
    /// Entertainment area ID (first 16 chars)
    area_id: [16]u8 = .{0} ** 16,

    const HEADER_SIZE = 52;
    const LIGHT_SIZE = 7;

    /// Encode frame header
    pub fn encodeHeader(self: *Frame, buffer: []u8) !usize {
        if (buffer.len < HEADER_SIZE) return error.BufferTooSmall;

        var pos: usize = 0;

        // Protocol identifier "HueStream"
        @memcpy(buffer[pos .. pos + 9], &self.protocol);
        pos += 9;

        // Version
        buffer[pos] = self.version[0];
        buffer[pos + 1] = self.version[1];
        pos += 2;

        // Sequence number
        buffer[pos] = self.sequence;
        pos += 1;

        // Reserved
        buffer[pos] = self.reserved[0];
        buffer[pos + 1] = self.reserved[1];
        pos += 2;

        // Color space
        buffer[pos] = @intFromEnum(self.color_space);
        pos += 1;

        // Reserved
        buffer[pos] = self.reserved2;
        pos += 1;

        // Area ID (padded to 16 bytes, null-padded handled by struct init)
        @memcpy(buffer[pos .. pos + 16], &self.area_id);
        pos += 16;

        // Padding to 52 bytes
        @memset(buffer[pos..HEADER_SIZE], 0);

        return HEADER_SIZE;
    }

    /// Set area ID from string
    pub fn setAreaId(self: *Frame, id: []const u8) void {
        const copy_len = @min(id.len, 16);
        @memcpy(self.area_id[0..copy_len], id[0..copy_len]);
        if (copy_len < 16) {
            @memset(self.area_id[copy_len..], 0);
        }
    }

    /// Increment sequence number (wraps at 255)
    pub fn nextSequence(self: *Frame) void {
        self.sequence +%= 1;
    }
};

/// Encode a complete entertainment frame with light states
pub fn encodeFrame(
    frame: *Frame,
    lights: []const LightState,
    buffer: []u8,
) !usize {
    var pos = try frame.encodeHeader(buffer);

    for (lights) |light| {
        if (pos + Frame.LIGHT_SIZE > buffer.len) return error.BufferTooSmall;

        // Device type (0x00 = light)
        buffer[pos] = 0x00;
        pos += 1;

        // Device ID (channel)
        buffer[pos] = 0x00;
        buffer[pos + 1] = light.channel_id;
        pos += 2;

        // Color data (xyB format, big-endian)
        buffer[pos] = @intCast((light.x >> 8) & 0xFF);
        buffer[pos + 1] = @intCast(light.x & 0xFF);
        pos += 2;

        buffer[pos] = @intCast((light.y >> 8) & 0xFF);
        buffer[pos + 1] = @intCast(light.y & 0xFF);
        pos += 2;

        buffer[pos] = @intCast((light.brightness >> 8) & 0xFF);
        buffer[pos + 1] = @intCast(light.brightness & 0xFF);
        pos += 2;
    }

    return pos;
}

/// Maximum frame size for N lights
pub fn maxFrameSize(n_lights: usize) usize {
    return Frame.HEADER_SIZE + n_lights * Frame.LIGHT_SIZE;
}

test "frame encoding" {
    var frame = Frame{};
    frame.setAreaId("test-area");
    frame.sequence = 42;

    var buffer: [256]u8 = undefined;
    const header_size = try frame.encodeHeader(&buffer);

    try std.testing.expectEqual(@as(usize, 52), header_size);
    try std.testing.expectEqualStrings("HueStream", buffer[0..9]);
    try std.testing.expectEqual(@as(u8, 42), buffer[11]);
}

test "light state encoding" {
    var frame = Frame{};
    frame.setAreaId("test");

    const lights = [_]LightState{
        LightState.fromXYB(0.5, 0.4, 1.0).withChannel(0),
        LightState.fromXYB(0.3, 0.3, 0.5).withChannel(1),
    };

    var buffer: [256]u8 = undefined;
    const size = try encodeFrame(&frame, &lights, &buffer);

    try std.testing.expectEqual(@as(usize, 52 + 2 * 9), size);
}
