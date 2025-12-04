//! Hue Bridge discovery via mDNS and cloud fallback
//! Primary: mDNS query for _hue._tcp.local
//! Fallback: HTTPS GET to discovery.meethue.com
const std = @import("std");
const v2rest = @import("v2rest.zig");

pub const DiscoveryError = error{
    NetworkError,
    NoResponseReceived,
    InvalidResponse,
    OutOfMemory,
    Timeout,
};

pub const DiscoveredBridge = struct {
    id: []const u8,
    ip: []const u8,
    source: Source,

    pub const Source = enum {
        mdns,
        cloud,
        manual,
    };

    pub fn deinit(self: *DiscoveredBridge, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.ip);
    }
};

/// Discover Hue bridges on the network
/// Tries mDNS first, then falls back to cloud discovery
pub fn discoverBridges(allocator: std.mem.Allocator, timeout_ms: u32) ![]DiscoveredBridge {
    var bridges: std.ArrayListUnmanaged(DiscoveredBridge) = .empty;
    errdefer {
        for (bridges.items) |*bridge| {
            bridge.deinit(allocator);
        }
        bridges.deinit(allocator);
    }

    // Try mDNS first
    const mdns_bridges = discoverViaMdns(allocator, timeout_ms) catch |err| blk: {
        std.log.warn("mDNS discovery failed: {}", .{err});
        break :blk &[_]DiscoveredBridge{};
    };
    defer {
        for (mdns_bridges) |*bridge| {
            var b = bridge.*;
            b.deinit(allocator);
        }
        allocator.free(mdns_bridges);
    }

    for (mdns_bridges) |bridge| {
        try bridges.append(allocator, .{
            .id = try allocator.dupe(u8, bridge.id),
            .ip = try allocator.dupe(u8, bridge.ip),
            .source = .mdns,
        });
    }

    // If no bridges found via mDNS, try cloud discovery
    if (bridges.items.len == 0) {
        const cloud_bridges = discoverViaCloud(allocator) catch |err| blk: {
            std.log.warn("Cloud discovery failed: {}", .{err});
            break :blk &[_]DiscoveredBridge{};
        };
        defer {
            for (cloud_bridges) |*bridge| {
                var b = bridge.*;
                b.deinit(allocator);
            }
            allocator.free(cloud_bridges);
        }

        for (cloud_bridges) |bridge| {
            try bridges.append(allocator, .{
                .id = try allocator.dupe(u8, bridge.id),
                .ip = try allocator.dupe(u8, bridge.ip),
                .source = .cloud,
            });
        }
    }

    return bridges.toOwnedSlice(allocator);
}

/// Discover bridges via mDNS (multicast DNS)
/// Queries for _hue._tcp.local service
pub fn discoverViaMdns(allocator: std.mem.Allocator, timeout_ms: u32) ![]DiscoveredBridge {
    _ = timeout_ms;

    const sock = std.posix.socket(std.posix.AF.INET, std.posix.SOCK.DGRAM, 0) catch return DiscoveryError.NetworkError;
    defer std.posix.close(sock);

    // Set socket options for multicast
    const enable: u32 = 1;
    std.posix.setsockopt(sock, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, std.mem.asBytes(&enable)) catch {};

    // mDNS multicast address: 224.0.0.251:5353
    const mdns_addr = std.net.Address.initIp4(.{ 224, 0, 0, 251 }, 5353);

    // Build mDNS query for _hue._tcp.local
    var query_buf: [512]u8 = undefined;
    const query_len = buildMdnsQuery(&query_buf, "_hue._tcp.local");

    // Send query
    _ = std.posix.sendto(sock, query_buf[0..query_len], 0, &mdns_addr.any, mdns_addr.getOsSockLen()) catch return DiscoveryError.NetworkError;

    // Wait for responses
    var bridges: std.ArrayListUnmanaged(DiscoveredBridge) = .empty;
    errdefer {
        for (bridges.items) |*bridge| {
            bridge.deinit(allocator);
        }
        bridges.deinit(allocator);
    }

    // Set receive timeout
    const timeout = std.posix.timeval{
        .sec = @intCast(3),
        .usec = 0,
    };
    std.posix.setsockopt(sock, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, std.mem.asBytes(&timeout)) catch {};

    // Receive responses (collect for a few seconds)
    var response_buf: [4096]u8 = undefined;
    var seen_ips = std.StringHashMap(void).init(allocator);
    defer seen_ips.deinit();

    for (0..10) |_| {
        var src_addr: std.posix.sockaddr.in = undefined;
        var addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in);

        const recv_len = std.posix.recvfrom(sock, &response_buf, 0, @ptrCast(&src_addr), &addr_len) catch |err| {
            if (err == error.WouldBlock) break;
            continue;
        };

        if (recv_len > 0) {
            // Parse mDNS response to extract IP and bridge ID
            if (parseMdnsResponse(allocator, response_buf[0..recv_len])) |bridge_info| {
                if (!seen_ips.contains(bridge_info.ip)) {
                    try seen_ips.put(bridge_info.ip, {});
                    try bridges.append(allocator, bridge_info);
                } else {
                    var b = bridge_info;
                    b.deinit(allocator);
                }
            } else |_| {
                // Extract IP from source address as fallback
                const ip_bytes = @as(*const [4]u8, @ptrCast(&src_addr.addr));
                const ip_str = try std.fmt.allocPrint(allocator, "{d}.{d}.{d}.{d}", .{
                    ip_bytes[0],
                    ip_bytes[1],
                    ip_bytes[2],
                    ip_bytes[3],
                });

                if (!seen_ips.contains(ip_str)) {
                    try seen_ips.put(ip_str, {});
                    try bridges.append(allocator, .{
                        .id = try std.fmt.allocPrint(allocator, "mdns-{s}", .{ip_str}),
                        .ip = ip_str,
                        .source = .mdns,
                    });
                } else {
                    allocator.free(ip_str);
                }
            }
        }
    }

    return bridges.toOwnedSlice(allocator);
}

/// Discover bridges via Philips Hue cloud discovery endpoint
pub fn discoverViaCloud(allocator: std.mem.Allocator) ![]DiscoveredBridge {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const uri = std.Uri.parse("https://discovery.meethue.com") catch return DiscoveryError.InvalidResponse;

    var req = client.request(.GET, uri, .{}) catch return DiscoveryError.NetworkError;
    defer req.deinit();

    req.sendBodiless() catch return DiscoveryError.NetworkError;

    var redirect_buffer: [8192]u8 = undefined;
    var response = req.receiveHead(&redirect_buffer) catch return DiscoveryError.NetworkError;

    if (response.head.status != .ok) return DiscoveryError.InvalidResponse;

    // Read response body into a buffer
    var transfer_buffer: [4096]u8 = undefined;
    var reader = response.reader(&transfer_buffer);

    const body = reader.allocRemaining(allocator, std.Io.Limit.limited(1024 * 64)) catch return DiscoveryError.InvalidResponse;
    defer allocator.free(body);

    return parseCloudDiscoveryResponse(allocator, body);
}

fn parseCloudDiscoveryResponse(allocator: std.mem.Allocator, response: []const u8) ![]DiscoveredBridge {
    // Response format: [{"id":"...","internalipaddress":"...","port":443}]
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, response, .{}) catch return DiscoveryError.InvalidResponse;
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .array) return DiscoveryError.InvalidResponse;

    var bridges: std.ArrayListUnmanaged(DiscoveredBridge) = .empty;
    errdefer {
        for (bridges.items) |*bridge| {
            bridge.deinit(allocator);
        }
        bridges.deinit(allocator);
    }

    for (root.array.items) |item| {
        if (item != .object) continue;

        const id = item.object.get("id") orelse continue;
        const ip = item.object.get("internalipaddress") orelse continue;

        if (id != .string or ip != .string) continue;

        try bridges.append(allocator, .{
            .id = try allocator.dupe(u8, id.string),
            .ip = try allocator.dupe(u8, ip.string),
            .source = .cloud,
        });
    }

    return bridges.toOwnedSlice(allocator);
}

/// Build a simple mDNS query packet
fn buildMdnsQuery(buf: []u8, name: []const u8) usize {
    var pos: usize = 0;

    // Transaction ID (random)
    buf[pos] = 0x00;
    buf[pos + 1] = 0x00;
    pos += 2;

    // Flags: Standard query
    buf[pos] = 0x00;
    buf[pos + 1] = 0x00;
    pos += 2;

    // Questions: 1
    buf[pos] = 0x00;
    buf[pos + 1] = 0x01;
    pos += 2;

    // Answer RRs: 0
    buf[pos] = 0x00;
    buf[pos + 1] = 0x00;
    pos += 2;

    // Authority RRs: 0
    buf[pos] = 0x00;
    buf[pos + 1] = 0x00;
    pos += 2;

    // Additional RRs: 0
    buf[pos] = 0x00;
    buf[pos + 1] = 0x00;
    pos += 2;

    // Encode domain name (e.g., "_hue._tcp.local" -> \x04_hue\x04_tcp\x05local\x00)
    var start: usize = 0;
    for (name, 0..) |c, i| {
        if (c == '.') {
            const label_len = i - start;
            buf[pos] = @intCast(label_len);
            pos += 1;
            @memcpy(buf[pos .. pos + label_len], name[start..i]);
            pos += label_len;
            start = i + 1;
        }
    }
    // Last label
    const label_len = name.len - start;
    buf[pos] = @intCast(label_len);
    pos += 1;
    @memcpy(buf[pos .. pos + label_len], name[start..]);
    pos += label_len;

    // Null terminator
    buf[pos] = 0x00;
    pos += 1;

    // Query type: PTR (12)
    buf[pos] = 0x00;
    buf[pos + 1] = 0x0C;
    pos += 2;

    // Query class: IN (1) with unicast response bit
    buf[pos] = 0x00;
    buf[pos + 1] = 0x01;
    pos += 2;

    return pos;
}

/// Parse mDNS response to extract bridge information
fn parseMdnsResponse(allocator: std.mem.Allocator, response: []const u8) !DiscoveredBridge {
    if (response.len < 12) return DiscoveryError.InvalidResponse;

    // Skip header, look for A record (type 1) containing IP address
    var pos: usize = 12;

    // Skip questions section
    const qdcount = (@as(u16, response[4]) << 8) | response[5];
    for (0..qdcount) |_| {
        while (pos < response.len and response[pos] != 0) {
            if ((response[pos] & 0xC0) == 0xC0) {
                pos += 2;
                break;
            }
            pos += @as(usize, response[pos]) + 1;
        }
        if (pos < response.len and response[pos] == 0) pos += 1;
        pos += 4; // Skip type and class
    }

    // Parse answer section looking for A records
    const ancount = (@as(u16, response[6]) << 8) | response[7];
    for (0..ancount) |_| {
        if (pos >= response.len) break;

        // Skip name (handle compression)
        while (pos < response.len) {
            if ((response[pos] & 0xC0) == 0xC0) {
                pos += 2;
                break;
            }
            if (response[pos] == 0) {
                pos += 1;
                break;
            }
            pos += @as(usize, response[pos]) + 1;
        }

        if (pos + 10 > response.len) break;

        const rtype = (@as(u16, response[pos]) << 8) | response[pos + 1];
        pos += 2;
        pos += 2; // Skip class
        pos += 4; // Skip TTL
        const rdlength = (@as(u16, response[pos]) << 8) | response[pos + 1];
        pos += 2;

        if (rtype == 1 and rdlength == 4 and pos + 4 <= response.len) {
            // A record - extract IP
            const ip_str = try std.fmt.allocPrint(allocator, "{d}.{d}.{d}.{d}", .{
                response[pos],
                response[pos + 1],
                response[pos + 2],
                response[pos + 3],
            });

            return DiscoveredBridge{
                .id = try std.fmt.allocPrint(allocator, "mdns-{s}", .{ip_str}),
                .ip = ip_str,
                .source = .mdns,
            };
        }

        pos += rdlength;
    }

    return DiscoveryError.InvalidResponse;
}

/// Create a manual bridge entry for direct IP input
pub fn createManualBridge(allocator: std.mem.Allocator, ip: []const u8) !DiscoveredBridge {
    return .{
        .id = try std.fmt.allocPrint(allocator, "manual-{s}", .{ip}),
        .ip = try allocator.dupe(u8, ip),
        .source = .manual,
    };
}

test "cloud discovery response parsing" {
    const allocator = std.testing.allocator;
    const response = "[{\"id\":\"001788fffe123456\",\"internalipaddress\":\"192.168.1.100\",\"port\":443}]";

    const bridges = try parseCloudDiscoveryResponse(allocator, response);
    defer {
        for (bridges) |*b| {
            var bridge = b.*;
            bridge.deinit(allocator);
        }
        allocator.free(bridges);
    }

    try std.testing.expectEqual(@as(usize, 1), bridges.len);
    try std.testing.expectEqualStrings("001788fffe123456", bridges[0].id);
    try std.testing.expectEqualStrings("192.168.1.100", bridges[0].ip);
}

test "mdns query building" {
    var buf: [512]u8 = undefined;
    const len = buildMdnsQuery(&buf, "_hue._tcp.local");
    try std.testing.expect(len > 12); // At least header + some data
}
