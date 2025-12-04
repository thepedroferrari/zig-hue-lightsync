//! Hue CLIP v2 REST API client
//! Handles communication with Philips Hue Bridge via HTTPS
const std = @import("std");
const config = @import("../config.zig");

pub const ApiError = error{
    ConnectionFailed,
    TlsError,
    InvalidResponse,
    BridgeError,
    LinkButtonNotPressed,
    Timeout,
    InvalidJson,
};

pub const Bridge = struct {
    id: []const u8,
    ip: []const u8,
    name: ?[]const u8 = null,

    pub fn deinit(self: *Bridge, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.ip);
        if (self.name) |name| allocator.free(name);
    }
};

pub const PairingResult = struct {
    app_key: []const u8,
    client_key: []const u8,

    pub fn deinit(self: *PairingResult, allocator: std.mem.Allocator) void {
        allocator.free(self.app_key);
        allocator.free(self.client_key);
    }
};

pub const EntertainmentArea = struct {
    id: []const u8,
    name: []const u8,
    lights: []Light,

    pub const Light = struct {
        id: []const u8,
        name: []const u8,
        x: f32,
        y: f32,
        z: f32,
    };

    pub fn deinit(self: *EntertainmentArea, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        for (self.lights) |*light| {
            allocator.free(light.id);
            allocator.free(light.name);
        }
        allocator.free(self.lights);
    }
};

pub const HueClient = struct {
    allocator: std.mem.Allocator,
    bridge_ip: []const u8,
    app_key: ?[]const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, bridge_ip: []const u8) Self {
        return .{
            .allocator = allocator,
            .bridge_ip = bridge_ip,
            .app_key = null,
        };
    }

    pub fn initWithCredentials(allocator: std.mem.Allocator, bridge_ip: []const u8, app_key: []const u8) Self {
        return .{
            .allocator = allocator,
            .bridge_ip = bridge_ip,
            .app_key = app_key,
        };
    }

    /// Pair with the bridge using the link button flow
    /// Returns app_key and client_key for DTLS streaming
    pub fn pair(self: *Self, device_name: []const u8) !PairingResult {
        const payload = try std.fmt.allocPrint(self.allocator, "{{\"devicetype\":\"{s}#linux\",\"generateclientkey\":true}}", .{device_name});
        defer self.allocator.free(payload);

        const url = try std.fmt.allocPrint(self.allocator, "https://{s}/api", .{self.bridge_ip});
        defer self.allocator.free(url);

        const response = try self.httpPost(url, payload, null);
        defer self.allocator.free(response);

        return self.parsePairingResponse(response);
    }

    /// List entertainment areas from the bridge
    pub fn listEntertainmentAreas(self: *Self) ![]EntertainmentArea {
        if (self.app_key == null) return error.NotAuthenticated;

        const url = try std.fmt.allocPrint(self.allocator, "https://{s}/clip/v2/resource/entertainment_configuration", .{self.bridge_ip});
        defer self.allocator.free(url);

        const response = try self.httpGet(url, self.app_key);
        defer self.allocator.free(response);

        return self.parseEntertainmentAreas(response);
    }

    /// Check if bridge is reachable
    pub fn ping(self: *Self) !bool {
        const url = try std.fmt.allocPrint(self.allocator, "https://{s}/api/0/config", .{self.bridge_ip});
        defer self.allocator.free(url);

        const response = self.httpGet(url, null) catch return false;
        defer self.allocator.free(response);
        return true;
    }

    fn httpGet(self: *Self, url: []const u8, auth_key: ?[]const u8) ![]u8 {
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const uri = std.Uri.parse(url) catch return ApiError.InvalidResponse;

        var extra_headers_buf: [1]std.http.Header = undefined;
        var extra_headers: []const std.http.Header = &.{};

        if (auth_key) |key| {
            extra_headers_buf[0] = .{ .name = "hue-application-key", .value = key };
            extra_headers = &extra_headers_buf;
        }

        var req = client.request(.GET, uri, .{
            .extra_headers = extra_headers,
        }) catch return ApiError.ConnectionFailed;
        defer req.deinit();

        req.sendBodiless() catch return ApiError.ConnectionFailed;

        var redirect_buffer: [8192]u8 = undefined;
        var response = req.receiveHead(&redirect_buffer) catch return ApiError.ConnectionFailed;

        // Read response body
        var transfer_buffer: [4096]u8 = undefined;
        var reader = response.reader(&transfer_buffer);

        const body = reader.allocRemaining(self.allocator, std.Io.Limit.limited(1024 * 1024)) catch return ApiError.InvalidResponse;
        return body;
    }

    fn httpPost(self: *Self, url: []const u8, payload: []const u8, auth_key: ?[]const u8) ![]u8 {
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const uri = std.Uri.parse(url) catch return ApiError.InvalidResponse;

        var extra_headers_buf: [1]std.http.Header = undefined;
        var extra_headers: []const std.http.Header = &.{};

        if (auth_key) |key| {
            extra_headers_buf[0] = .{ .name = "hue-application-key", .value = key };
            extra_headers = &extra_headers_buf;
        }

        var req = client.request(.POST, uri, .{
            .extra_headers = extra_headers,
        }) catch return ApiError.ConnectionFailed;
        defer req.deinit();

        req.transfer_encoding = .{ .content_length = payload.len };
        var body_writer = req.sendBody(&.{}) catch return ApiError.ConnectionFailed;
        body_writer.writer.writeAll(payload) catch return ApiError.ConnectionFailed;
        body_writer.end() catch return ApiError.ConnectionFailed;
        if (req.connection) |conn| conn.flush() catch return ApiError.ConnectionFailed;

        var redirect_buffer: [8192]u8 = undefined;
        var response = req.receiveHead(&redirect_buffer) catch return ApiError.ConnectionFailed;

        // Read response body
        var transfer_buffer: [4096]u8 = undefined;
        var reader = response.reader(&transfer_buffer);

        const body = reader.allocRemaining(self.allocator, std.Io.Limit.limited(1024 * 1024)) catch return ApiError.InvalidResponse;
        return body;
    }

    fn parsePairingResponse(self: *Self, response: []const u8) !PairingResult {
        // Hue API returns array: [{"success":{"username":"...","clientkey":"..."}}]
        // or [{"error":{"type":101,"description":"link button not pressed"}}]
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response, .{}) catch return ApiError.InvalidJson;
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .array or root.array.items.len == 0) return ApiError.InvalidResponse;

        const first = root.array.items[0];
        if (first != .object) return ApiError.InvalidResponse;

        if (first.object.get("error")) |err| {
            if (err == .object) {
                if (err.object.get("type")) |err_type| {
                    if (err_type == .integer and err_type.integer == 101) {
                        return ApiError.LinkButtonNotPressed;
                    }
                }
            }
            return ApiError.BridgeError;
        }

        if (first.object.get("success")) |success| {
            if (success != .object) return ApiError.InvalidResponse;

            const username = success.object.get("username") orelse return ApiError.InvalidResponse;
            const clientkey = success.object.get("clientkey") orelse return ApiError.InvalidResponse;

            if (username != .string or clientkey != .string) return ApiError.InvalidResponse;

            return PairingResult{
                .app_key = try self.allocator.dupe(u8, username.string),
                .client_key = try self.allocator.dupe(u8, clientkey.string),
            };
        }

        return ApiError.InvalidResponse;
    }

    fn parseEntertainmentAreas(self: *Self, response: []const u8) ![]EntertainmentArea {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response, .{}) catch return ApiError.InvalidJson;
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return ApiError.InvalidResponse;

        const data = root.object.get("data") orelse return ApiError.InvalidResponse;
        if (data != .array) return ApiError.InvalidResponse;

        var areas: std.ArrayListUnmanaged(EntertainmentArea) = .empty;

        for (data.array.items) |item| {
            if (item != .object) continue;

            const id = item.object.get("id") orelse continue;
            const metadata = item.object.get("metadata") orelse continue;

            if (id != .string or metadata != .object) continue;

            const name = metadata.object.get("name") orelse continue;
            if (name != .string) continue;

            var lights: std.ArrayListUnmanaged(EntertainmentArea.Light) = .empty;

            if (item.object.get("channels")) |channels| {
                if (channels == .array) {
                    for (channels.array.items) |channel| {
                        if (channel != .object) continue;

                        const channel_id_val = channel.object.get("channel_id") orelse continue;
                        const position = channel.object.get("position") orelse continue;

                        if (channel_id_val != .integer or position != .object) continue;

                        const x = position.object.get("x") orelse continue;
                        const y = position.object.get("y") orelse continue;
                        const z = position.object.get("z") orelse continue;

                        const light = EntertainmentArea.Light{
                            .id = try std.fmt.allocPrint(self.allocator, "{d}", .{channel_id_val.integer}),
                            .name = try self.allocator.dupe(u8, "Light"),
                            .x = @floatCast(if (x == .float) x.float else 0.0),
                            .y = @floatCast(if (y == .float) y.float else 0.0),
                            .z = @floatCast(if (z == .float) z.float else 0.0),
                        };
                        try lights.append(self.allocator, light);
                    }
                }
            }

            const area = EntertainmentArea{
                .id = try self.allocator.dupe(u8, id.string),
                .name = try self.allocator.dupe(u8, name.string),
                .lights = try lights.toOwnedSlice(self.allocator),
            };
            try areas.append(self.allocator, area);
        }

        return areas.toOwnedSlice(self.allocator);
    }
};

test "pairing response parsing" {
    const allocator = std.testing.allocator;
    var client = HueClient.init(allocator, "192.168.1.100");

    // Test successful pairing response
    const success_response = "[{\"success\":{\"username\":\"test-app-key\",\"clientkey\":\"test-client-key\"}}]";
    var result = try client.parsePairingResponse(success_response);
    defer result.deinit(allocator);

    try std.testing.expectEqualStrings("test-app-key", result.app_key);
    try std.testing.expectEqualStrings("test-client-key", result.client_key);
}
