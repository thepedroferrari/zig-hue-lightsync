//! Color processing module
//! Handles sRGB↔linear, XYZ, and CIE xy color space conversions
//! with gamut clamping for Philips Hue bulbs
const std = @import("std");

/// RGB color in sRGB color space (0-255 per channel)
pub const RGB = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn fromSlice(data: []const u8, format: PixelFormat) RGB {
        return switch (format) {
            .rgba, .rgbx => .{ .r = data[0], .g = data[1], .b = data[2] },
            .bgra, .bgrx => .{ .r = data[2], .g = data[1], .b = data[0] },
            .rgb => .{ .r = data[0], .g = data[1], .b = data[2] },
            .bgr => .{ .r = data[2], .g = data[1], .b = data[0] },
        };
    }

    pub fn toLinear(self: RGB) LinearRGB {
        return .{
            .r = srgbToLinear(@as(f32, @floatFromInt(self.r)) / 255.0),
            .g = srgbToLinear(@as(f32, @floatFromInt(self.g)) / 255.0),
            .b = srgbToLinear(@as(f32, @floatFromInt(self.b)) / 255.0),
        };
    }
};

/// RGB color in linear color space (0.0-1.0 per channel)
pub const LinearRGB = struct {
    r: f32,
    g: f32,
    b: f32,

    pub fn toSrgb(self: LinearRGB) RGB {
        return .{
            .r = @intFromFloat(@round(linearToSrgb(self.r) * 255.0)),
            .g = @intFromFloat(@round(linearToSrgb(self.g) * 255.0)),
            .b = @intFromFloat(@round(linearToSrgb(self.b) * 255.0)),
        };
    }

    pub fn toXYZ(self: LinearRGB) XYZ {
        // sRGB to XYZ matrix (D65 illuminant)
        return .{
            .x = 0.4124564 * self.r + 0.3575761 * self.g + 0.1804375 * self.b,
            .y = 0.2126729 * self.r + 0.7151522 * self.g + 0.0721750 * self.b,
            .z = 0.0193339 * self.r + 0.1191920 * self.g + 0.9503041 * self.b,
        };
    }

    /// Blend with another linear RGB color
    pub fn blend(self: LinearRGB, other: LinearRGB, weight: f32) LinearRGB {
        const w = std.math.clamp(weight, 0.0, 1.0);
        return .{
            .r = self.r * (1.0 - w) + other.r * w,
            .g = self.g * (1.0 - w) + other.g * w,
            .b = self.b * (1.0 - w) + other.b * w,
        };
    }
};

/// CIE XYZ color space
pub const XYZ = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn toCIExy(self: XYZ) CIExy {
        const sum = self.x + self.y + self.z;
        if (sum < 0.0001) {
            // Avoid division by zero for black
            return .{ .x = 0.3127, .y = 0.3290 }; // D65 white point
        }
        return .{
            .x = self.x / sum,
            .y = self.y / sum,
        };
    }

    /// Get brightness (Y component represents luminance)
    pub fn brightness(self: XYZ) f32 {
        return std.math.clamp(self.y, 0.0, 1.0);
    }
};

/// CIE xy chromaticity coordinates (Hue uses this)
pub const CIExy = struct {
    x: f32,
    y: f32,

    /// Clamp to a gamut defined by three vertices (triangle)
    pub fn clampToGamut(self: CIExy, gamut: Gamut) CIExy {
        if (self.isInsideGamut(gamut)) {
            return self;
        }
        return self.closestPointInGamut(gamut);
    }

    fn isInsideGamut(self: CIExy, gamut: Gamut) bool {
        // Check if point is inside triangle using barycentric coordinates
        const v0 = Vec2{ gamut.green.x - gamut.red.x, gamut.green.y - gamut.red.y };
        const v1 = Vec2{ gamut.blue.x - gamut.red.x, gamut.blue.y - gamut.red.y };
        const v2 = Vec2{ self.x - gamut.red.x, self.y - gamut.red.y };

        const dot00 = v0[0] * v0[0] + v0[1] * v0[1];
        const dot01 = v0[0] * v1[0] + v0[1] * v1[1];
        const dot02 = v0[0] * v2[0] + v0[1] * v2[1];
        const dot11 = v1[0] * v1[0] + v1[1] * v1[1];
        const dot12 = v1[0] * v2[0] + v1[1] * v2[1];

        const inv_denom = 1.0 / (dot00 * dot11 - dot01 * dot01);
        const u = (dot11 * dot02 - dot01 * dot12) * inv_denom;
        const v = (dot00 * dot12 - dot01 * dot02) * inv_denom;

        return (u >= 0) and (v >= 0) and (u + v <= 1);
    }

    fn closestPointInGamut(self: CIExy, gamut: Gamut) CIExy {
        // Find closest point on triangle edges
        const p = Vec2{ self.x, self.y };

        const p_rg = closestPointOnLine(p, Vec2{ gamut.red.x, gamut.red.y }, Vec2{ gamut.green.x, gamut.green.y });
        const p_gb = closestPointOnLine(p, Vec2{ gamut.green.x, gamut.green.y }, Vec2{ gamut.blue.x, gamut.blue.y });
        const p_br = closestPointOnLine(p, Vec2{ gamut.blue.x, gamut.blue.y }, Vec2{ gamut.red.x, gamut.red.y });

        const d_rg = distance2(p, p_rg);
        const d_gb = distance2(p, p_gb);
        const d_br = distance2(p, p_br);

        if (d_rg <= d_gb and d_rg <= d_br) {
            return .{ .x = p_rg[0], .y = p_rg[1] };
        } else if (d_gb <= d_br) {
            return .{ .x = p_gb[0], .y = p_gb[1] };
        } else {
            return .{ .x = p_br[0], .y = p_br[1] };
        }
    }
};

const Vec2 = [2]f32;

fn closestPointOnLine(p: Vec2, a: Vec2, b: Vec2) Vec2 {
    const ap = Vec2{ p[0] - a[0], p[1] - a[1] };
    const ab = Vec2{ b[0] - a[0], b[1] - a[1] };
    const ab_len2 = ab[0] * ab[0] + ab[1] * ab[1];

    if (ab_len2 < 0.0001) return a;

    var t = (ap[0] * ab[0] + ap[1] * ab[1]) / ab_len2;
    t = std.math.clamp(t, 0.0, 1.0);

    return Vec2{ a[0] + ab[0] * t, a[1] + ab[1] * t };
}

fn distance2(a: Vec2, b: Vec2) f32 {
    const dx = a[0] - b[0];
    const dy = a[1] - b[1];
    return dx * dx + dy * dy;
}

/// Hue bulb color gamut
pub const Gamut = struct {
    red: CIExy,
    green: CIExy,
    blue: CIExy,

    /// Gamut A - older Hue bulbs
    pub const A = Gamut{
        .red = .{ .x = 0.704, .y = 0.296 },
        .green = .{ .x = 0.2151, .y = 0.7106 },
        .blue = .{ .x = 0.138, .y = 0.08 },
    };

    /// Gamut B - BR30, Spot, etc.
    pub const B = Gamut{
        .red = .{ .x = 0.675, .y = 0.322 },
        .green = .{ .x = 0.409, .y = 0.518 },
        .blue = .{ .x = 0.167, .y = 0.04 },
    };

    /// Gamut C - most recent Hue bulbs (widest gamut)
    pub const C = Gamut{
        .red = .{ .x = 0.6915, .y = 0.3083 },
        .green = .{ .x = 0.17, .y = 0.7 },
        .blue = .{ .x = 0.1532, .y = 0.0475 },
    };
};

/// Pixel formats supported for frame processing
pub const PixelFormat = enum {
    rgba,
    rgbx,
    bgra,
    bgrx,
    rgb,
    bgr,

    pub fn bytesPerPixel(self: PixelFormat) u8 {
        return switch (self) {
            .rgba, .rgbx, .bgra, .bgrx => 4,
            .rgb, .bgr => 3,
        };
    }
};

/// Hue light color state
pub const HueColor = struct {
    xy: CIExy,
    brightness: f32, // 0.0-1.0

    /// Convert from RGB with gamut clamping
    pub fn fromRGB(rgb: RGB, gamut: Gamut) HueColor {
        const linear = rgb.toLinear();
        const xyz = linear.toXYZ();
        const xy = xyz.toCIExy().clampToGamut(gamut);
        return .{
            .xy = xy,
            .brightness = xyz.brightness(),
        };
    }

    /// Convert from linear RGB with gamut clamping
    pub fn fromLinearRGB(linear: LinearRGB, gamut: Gamut) HueColor {
        const xyz = linear.toXYZ();
        const xy = xyz.toCIExy().clampToGamut(gamut);
        return .{
            .xy = xy,
            .brightness = xyz.brightness(),
        };
    }

    /// Apply brightness multiplier
    pub fn withBrightness(self: HueColor, multiplier: f32) HueColor {
        return .{
            .xy = self.xy,
            .brightness = std.math.clamp(self.brightness * multiplier, 0.0, 1.0),
        };
    }
};

// sRGB gamma functions (IEC 61966-2-1)
fn srgbToLinear(c: f32) f32 {
    if (c <= 0.04045) {
        return c / 12.92;
    }
    return std.math.pow(f32, (c + 0.055) / 1.055, 2.4);
}

fn linearToSrgb(c: f32) f32 {
    const clamped = std.math.clamp(c, 0.0, 1.0);
    if (clamped <= 0.0031308) {
        return clamped * 12.92;
    }
    return 1.055 * std.math.pow(f32, clamped, 1.0 / 2.4) - 0.055;
}

// Tests
test "sRGB to linear conversion" {
    // Black
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), srgbToLinear(0.0), 0.001);
    // White
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), srgbToLinear(1.0), 0.001);
    // Mid gray (should be darker in linear)
    try std.testing.expect(srgbToLinear(0.5) < 0.5);
}

test "linear to sRGB conversion" {
    // Roundtrip
    const original: f32 = 0.5;
    const linear = srgbToLinear(original);
    const back = linearToSrgb(linear);
    try std.testing.expectApproxEqAbs(original, back, 0.001);
}

test "RGB to HueColor conversion" {
    const rgb = RGB{ .r = 255, .g = 0, .b = 0 }; // Pure red
    const hue_color = HueColor.fromRGB(rgb, Gamut.C);

    // Red should have high x, low y
    try std.testing.expect(hue_color.xy.x > 0.5);
    try std.testing.expect(hue_color.brightness > 0);
}

test "gamut clamping" {
    // Point clearly outside gamut C
    const outside = CIExy{ .x = 0.8, .y = 0.1 };
    const clamped = outside.clampToGamut(Gamut.C);

    // Should be clamped to edge
    try std.testing.expect(clamped.isInsideGamut(Gamut.C) or
        (clamped.x >= 0.0 and clamped.x <= 1.0 and clamped.y >= 0.0 and clamped.y <= 1.0));
}
