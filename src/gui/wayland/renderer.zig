//! Software renderer using Cairo
//!
//! This provides a simple 2D rendering abstraction for drawing
//! widgets to Wayland surfaces. Cairo handles anti-aliasing,
//! text rendering, and vector graphics.

const std = @import("std");
const client = @import("client.zig");

/// Cairo C bindings
pub const cairo = @cImport({
    @cInclude("cairo/cairo.h");
});

/// RGBA color
pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32 = 1.0,

    pub const transparent: Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
    pub const black: Color = .{ .r = 0, .g = 0, .b = 0, .a = 1 };
    pub const white: Color = .{ .r = 1, .g = 1, .b = 1, .a = 1 };
    pub const red: Color = .{ .r = 1, .g = 0, .b = 0, .a = 1 };
    pub const green: Color = .{ .r = 0, .g = 1, .b = 0, .a = 1 };
    pub const blue: Color = .{ .r = 0, .g = 0, .b = 1, .a = 1 };

    // Hue brand colors
    pub const hue_orange: Color = .{ .r = 1.0, .g = 0.6, .b = 0.2, .a = 1 };
    pub const hue_blue: Color = .{ .r = 0.2, .g = 0.5, .b = 0.9, .a = 1 };

    // UI colors (dark theme)
    pub const bg_dark: Color = .{ .r = 0.12, .g = 0.12, .b = 0.14, .a = 1 };
    pub const bg_surface: Color = .{ .r = 0.18, .g = 0.18, .b = 0.20, .a = 1 };
    pub const bg_hover: Color = .{ .r = 0.24, .g = 0.24, .b = 0.26, .a = 1 };
    pub const text_primary: Color = .{ .r = 0.95, .g = 0.95, .b = 0.95, .a = 1 };
    pub const text_secondary: Color = .{ .r = 0.7, .g = 0.7, .b = 0.7, .a = 1 };
    pub const accent: Color = .{ .r = 0.4, .g = 0.7, .b = 1.0, .a = 1 };
    pub const success: Color = .{ .r = 0.3, .g = 0.85, .b = 0.4, .a = 1 };
    pub const warning: Color = .{ .r = 1.0, .g = 0.75, .b = 0.2, .a = 1 };
    pub const error_color: Color = .{ .r = 1.0, .g = 0.3, .b = 0.3, .a = 1 };

    /// Create from HSL values
    pub fn fromHsl(h: f32, s: f32, l: f32) Color {
        if (s == 0) {
            return .{ .r = l, .g = l, .b = l };
        }

        const q = if (l < 0.5) l * (1 + s) else l + s - l * s;
        const p = 2 * l - q;

        return .{
            .r = hueToRgb(p, q, h + 1.0 / 3.0),
            .g = hueToRgb(p, q, h),
            .b = hueToRgb(p, q, h - 1.0 / 3.0),
        };
    }

    fn hueToRgb(p: f32, q: f32, t_in: f32) f32 {
        var t = t_in;
        if (t < 0) t += 1;
        if (t > 1) t -= 1;
        if (t < 1.0 / 6.0) return p + (q - p) * 6 * t;
        if (t < 1.0 / 2.0) return q;
        if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6;
        return p;
    }

    /// Create from hex value (0xRRGGBB or 0xAARRGGBB)
    pub fn fromHex(hex: u32) Color {
        const has_alpha = hex > 0xFFFFFF;
        if (has_alpha) {
            return .{
                .a = @as(f32, @floatFromInt((hex >> 24) & 0xFF)) / 255.0,
                .r = @as(f32, @floatFromInt((hex >> 16) & 0xFF)) / 255.0,
                .g = @as(f32, @floatFromInt((hex >> 8) & 0xFF)) / 255.0,
                .b = @as(f32, @floatFromInt(hex & 0xFF)) / 255.0,
            };
        }
        return .{
            .r = @as(f32, @floatFromInt((hex >> 16) & 0xFF)) / 255.0,
            .g = @as(f32, @floatFromInt((hex >> 8) & 0xFF)) / 255.0,
            .b = @as(f32, @floatFromInt(hex & 0xFF)) / 255.0,
        };
    }

    /// Blend with another color
    pub fn blend(self: Color, other: Color, t: f32) Color {
        return .{
            .r = self.r + (other.r - self.r) * t,
            .g = self.g + (other.g - self.g) * t,
            .b = self.b + (other.b - self.b) * t,
            .a = self.a + (other.a - self.a) * t,
        };
    }

    /// Convert to ARGB8888 for Wayland buffer
    pub fn toArgb8888(self: Color) u32 {
        const a: u32 = @intFromFloat(self.a * 255);
        const r: u32 = @intFromFloat(self.r * 255);
        const g: u32 = @intFromFloat(self.g * 255);
        const b: u32 = @intFromFloat(self.b * 255);
        return (a << 24) | (r << 16) | (g << 8) | b;
    }
};

/// Rectangle
pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    pub fn contains(self: Rect, px: f32, py: f32) bool {
        return px >= self.x and px < self.x + self.width and
            py >= self.y and py < self.y + self.height;
    }

    pub fn inset(self: Rect, amount: f32) Rect {
        return .{
            .x = self.x + amount,
            .y = self.y + amount,
            .width = @max(0, self.width - amount * 2),
            .height = @max(0, self.height - amount * 2),
        };
    }

    pub fn center(self: Rect) struct { x: f32, y: f32 } {
        return .{
            .x = self.x + self.width / 2,
            .y = self.y + self.height / 2,
        };
    }
};

/// Software renderer using Cairo
pub const Renderer = struct {
    surface: ?*cairo.cairo_surface_t = null,
    cr: ?*cairo.cairo_t = null,
    width: u32 = 0,
    height: u32 = 0,
    data: ?[*]u8 = null,
    stride: i32 = 0,

    const Self = @This();

    /// Initialize renderer with a buffer
    pub fn init(data: [*]u8, width: u32, height: u32, stride: i32) Self {
        const surface = cairo.cairo_image_surface_create_for_data(
            data,
            cairo.CAIRO_FORMAT_ARGB32,
            @intCast(width),
            @intCast(height),
            stride,
        );

        const cr = cairo.cairo_create(surface);

        return .{
            .surface = surface,
            .cr = cr,
            .width = width,
            .height = height,
            .data = data,
            .stride = stride,
        };
    }

    /// Cleanup
    pub fn deinit(self: *Self) void {
        if (self.cr) |cr| cairo.cairo_destroy(cr);
        if (self.surface) |surface| cairo.cairo_surface_destroy(surface);
    }

    /// Clear the entire surface
    pub fn clear(self: *Self, color: Color) void {
        const cr = self.cr orelse return;
        cairo.cairo_set_source_rgba(cr, color.r, color.g, color.b, color.a);
        cairo.cairo_paint(cr);
    }

    /// Set the current color
    pub fn setColor(self: *Self, color: Color) void {
        const cr = self.cr orelse return;
        cairo.cairo_set_source_rgba(cr, color.r, color.g, color.b, color.a);
    }

    /// Draw a filled rectangle
    pub fn fillRect(self: *Self, rect: Rect, color: Color) void {
        const cr = self.cr orelse return;
        cairo.cairo_set_source_rgba(cr, color.r, color.g, color.b, color.a);
        cairo.cairo_rectangle(cr, rect.x, rect.y, rect.width, rect.height);
        cairo.cairo_fill(cr);
    }

    /// Draw a rounded rectangle
    pub fn fillRoundedRect(self: *Self, rect: Rect, radius: f32, color: Color) void {
        const cr = self.cr orelse return;
        cairo.cairo_set_source_rgba(cr, color.r, color.g, color.b, color.a);

        const x = rect.x;
        const y = rect.y;
        const w = rect.width;
        const h = rect.height;
        const r = @min(radius, @min(w, h) / 2);

        cairo.cairo_new_path(cr);
        cairo.cairo_arc(cr, x + w - r, y + r, r, -std.math.pi / 2.0, 0);
        cairo.cairo_arc(cr, x + w - r, y + h - r, r, 0, std.math.pi / 2.0);
        cairo.cairo_arc(cr, x + r, y + h - r, r, std.math.pi / 2.0, std.math.pi);
        cairo.cairo_arc(cr, x + r, y + r, r, std.math.pi, 3.0 * std.math.pi / 2.0);
        cairo.cairo_close_path(cr);
        cairo.cairo_fill(cr);
    }

    /// Draw a stroked rounded rectangle
    pub fn strokeRoundedRect(self: *Self, rect: Rect, radius: f32, color: Color, line_width: f32) void {
        const cr = self.cr orelse return;
        cairo.cairo_set_source_rgba(cr, color.r, color.g, color.b, color.a);
        cairo.cairo_set_line_width(cr, line_width);

        const x = rect.x;
        const y = rect.y;
        const w = rect.width;
        const h = rect.height;
        const r = @min(radius, @min(w, h) / 2);

        cairo.cairo_new_path(cr);
        cairo.cairo_arc(cr, x + w - r, y + r, r, -std.math.pi / 2.0, 0);
        cairo.cairo_arc(cr, x + w - r, y + h - r, r, 0, std.math.pi / 2.0);
        cairo.cairo_arc(cr, x + r, y + h - r, r, std.math.pi / 2.0, std.math.pi);
        cairo.cairo_arc(cr, x + r, y + r, r, std.math.pi, 3.0 * std.math.pi / 2.0);
        cairo.cairo_close_path(cr);
        cairo.cairo_stroke(cr);
    }

    /// Draw a filled circle
    pub fn fillCircle(self: *Self, cx: f32, cy: f32, radius: f32, color: Color) void {
        const cr = self.cr orelse return;
        cairo.cairo_set_source_rgba(cr, color.r, color.g, color.b, color.a);
        cairo.cairo_arc(cr, cx, cy, radius, 0, 2 * std.math.pi);
        cairo.cairo_fill(cr);
    }

    /// Draw a stroked circle
    pub fn strokeCircle(self: *Self, cx: f32, cy: f32, radius: f32, color: Color, line_width: f32) void {
        const cr = self.cr orelse return;
        cairo.cairo_set_source_rgba(cr, color.r, color.g, color.b, color.a);
        cairo.cairo_set_line_width(cr, line_width);
        cairo.cairo_arc(cr, cx, cy, radius, 0, 2 * std.math.pi);
        cairo.cairo_stroke(cr);
    }

    /// Draw an arc (for progress rings)
    pub fn strokeArc(self: *Self, cx: f32, cy: f32, radius: f32, start_angle: f32, end_angle: f32, color: Color, line_width: f32) void {
        const cr = self.cr orelse return;
        cairo.cairo_set_source_rgba(cr, color.r, color.g, color.b, color.a);
        cairo.cairo_set_line_width(cr, line_width);
        cairo.cairo_set_line_cap(cr, cairo.CAIRO_LINE_CAP_ROUND);
        cairo.cairo_arc(cr, cx, cy, radius, start_angle, end_angle);
        cairo.cairo_stroke(cr);
    }

    /// Draw text
    pub fn drawText(self: *Self, text: []const u8, x: f32, y: f32, size: f32, color: Color) void {
        const cr = self.cr orelse return;

        // Create null-terminated string
        var buf: [256]u8 = undefined;
        const len = @min(text.len, buf.len - 1);
        @memcpy(buf[0..len], text[0..len]);
        buf[len] = 0;

        cairo.cairo_set_source_rgba(cr, color.r, color.g, color.b, color.a);
        cairo.cairo_select_font_face(cr, "Sans", cairo.CAIRO_FONT_SLANT_NORMAL, cairo.CAIRO_FONT_WEIGHT_NORMAL);
        cairo.cairo_set_font_size(cr, size);
        cairo.cairo_move_to(cr, x, y + size);
        cairo.cairo_show_text(cr, &buf);
    }

    /// Draw centered text
    pub fn drawTextCentered(self: *Self, text: []const u8, rect: Rect, size: f32, color: Color) void {
        const cr = self.cr orelse return;

        // Create null-terminated string
        var buf: [256]u8 = undefined;
        const len = @min(text.len, buf.len - 1);
        @memcpy(buf[0..len], text[0..len]);
        buf[len] = 0;

        cairo.cairo_select_font_face(cr, "Sans", cairo.CAIRO_FONT_SLANT_NORMAL, cairo.CAIRO_FONT_WEIGHT_NORMAL);
        cairo.cairo_set_font_size(cr, size);

        var extents: cairo.cairo_text_extents_t = undefined;
        cairo.cairo_text_extents(cr, &buf, &extents);

        const cx = rect.center();
        const x = cx.x - extents.width / 2 - extents.x_bearing;
        const y = cx.y - extents.height / 2 - extents.y_bearing;

        cairo.cairo_set_source_rgba(cr, color.r, color.g, color.b, color.a);
        cairo.cairo_move_to(cr, x, y);
        cairo.cairo_show_text(cr, &buf);
    }

    /// Draw bold text
    pub fn drawTextBold(self: *Self, text: []const u8, x: f32, y: f32, size: f32, color: Color) void {
        const cr = self.cr orelse return;

        var buf: [256]u8 = undefined;
        const len = @min(text.len, buf.len - 1);
        @memcpy(buf[0..len], text[0..len]);
        buf[len] = 0;

        cairo.cairo_set_source_rgba(cr, color.r, color.g, color.b, color.a);
        cairo.cairo_select_font_face(cr, "Sans", cairo.CAIRO_FONT_SLANT_NORMAL, cairo.CAIRO_FONT_WEIGHT_BOLD);
        cairo.cairo_set_font_size(cr, size);
        cairo.cairo_move_to(cr, x, y + size);
        cairo.cairo_show_text(cr, &buf);
    }

    /// Draw a line
    pub fn drawLine(self: *Self, x1: f32, y1: f32, x2: f32, y2: f32, color: Color, line_width: f32) void {
        const cr = self.cr orelse return;
        cairo.cairo_set_source_rgba(cr, color.r, color.g, color.b, color.a);
        cairo.cairo_set_line_width(cr, line_width);
        cairo.cairo_move_to(cr, x1, y1);
        cairo.cairo_line_to(cr, x2, y2);
        cairo.cairo_stroke(cr);
    }

    /// Save current state
    pub fn save(self: *Self) void {
        if (self.cr) |cr| cairo.cairo_save(cr);
    }

    /// Restore saved state
    pub fn restore(self: *Self) void {
        if (self.cr) |cr| cairo.cairo_restore(cr);
    }

    /// Clip to rectangle
    pub fn clipRect(self: *Self, rect: Rect) void {
        const cr = self.cr orelse return;
        cairo.cairo_rectangle(cr, rect.x, rect.y, rect.width, rect.height);
        cairo.cairo_clip(cr);
    }

    /// Translate coordinate system
    pub fn translate(self: *Self, tx: f32, ty: f32) void {
        if (self.cr) |cr| cairo.cairo_translate(cr, tx, ty);
    }

    /// Scale coordinate system
    pub fn scale(self: *Self, sx: f32, sy: f32) void {
        if (self.cr) |cr| cairo.cairo_scale(cr, sx, sy);
    }

    /// Rotate coordinate system
    pub fn rotate(self: *Self, angle: f32) void {
        if (self.cr) |cr| cairo.cairo_rotate(cr, angle);
    }

    /// Flush to surface
    pub fn flush(self: *Self) void {
        if (self.surface) |surface| cairo.cairo_surface_flush(surface);
    }
};

test "color operations" {
    const c1 = Color.fromHex(0xFF5500);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), c1.r, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.333), c1.g, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), c1.b, 0.01);

    const blend = Color.white.blend(Color.black, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), blend.r, 0.01);
}

test "rect operations" {
    const rect = Rect{ .x = 10, .y = 10, .width = 100, .height = 50 };
    try std.testing.expect(rect.contains(50, 30));
    try std.testing.expect(!rect.contains(5, 30));

    const inset = rect.inset(5);
    try std.testing.expectApproxEqAbs(@as(f32, 15), inset.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 90), inset.width, 0.01);
}

