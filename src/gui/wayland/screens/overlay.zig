//! Color preview overlay
//!
//! A floating widget that shows the colors being sent to each light,
//! useful for debugging and monitoring sync activity.

const std = @import("std");
const base = @import("../widgets/base.zig");
const color_dot = @import("../widgets/color_dot.zig");

const Renderer = base.Renderer;
const Color = base.Color;
const Rect = base.Rect;

/// Overlay data
pub const OverlayData = struct {
    /// Colors for each light
    colors: []const Color = &.{},
    /// Light labels
    labels: []const []const u8 = &.{},
    /// Whether sync is active
    is_active: bool = false,
    /// Animation phase for pulsing effect
    pulse_phase: f32 = 0,
    /// Compact mode (just dots, no labels)
    compact: bool = false,
};

/// Overlay dimensions
pub fn getOverlaySize(light_count: usize, compact: bool) struct { width: f32, height: f32 } {
    const cols: u32 = if (light_count <= 4) @intCast(light_count) else 4;
    const rows = (light_count + cols - 1) / cols;

    const dot_size: f32 = if (compact) 24 else 40;
    const spacing: f32 = if (compact) 8 else 12;
    const padding: f32 = if (compact) 8 else 16;
    const label_height: f32 = if (compact) 0 else 20;

    const width = @as(f32, @floatFromInt(cols)) * dot_size +
        @as(f32, @floatFromInt(cols - 1)) * spacing + padding * 2;
    const height = @as(f32, @floatFromInt(rows)) * (dot_size + label_height) +
        @as(f32, @floatFromInt(@max(1, rows) - 1)) * spacing + padding * 2;

    return .{ .width = width, .height = height };
}

/// Draw the overlay
pub fn draw(r: *Renderer, rect: Rect, data: *OverlayData) void {
    const theme = base.theme;

    // Semi-transparent background
    r.fillRoundedRect(rect, 12, Color{
        .r = theme.bg_surface.r,
        .g = theme.bg_surface.g,
        .b = theme.bg_surface.b,
        .a = 0.9,
    });

    // Border
    r.strokeRoundedRect(rect, 12, theme.bg_hover, 1);

    if (data.colors.len == 0) {
        // No lights message
        const msg_rect = Rect{
            .x = rect.x,
            .y = rect.y + rect.height / 2 - 10,
            .width = rect.width,
            .height = 20,
        };
        r.drawTextCentered("No lights", msg_rect, theme.font_size_small, theme.text_secondary);
        return;
    }

    // Calculate layout
    const cols: u32 = if (data.colors.len <= 4) @intCast(data.colors.len) else 4;
    const dot_size: f32 = if (data.compact) 24 else 40;
    const spacing: f32 = if (data.compact) 8 else 12;
    const padding: f32 = if (data.compact) 8 else 16;
    const label_height: f32 = if (data.compact) 0 else 20;

    // Draw color dots
    for (data.colors, 0..) |color, i| {
        const col = i % cols;
        const row = i / cols;

        const cx = rect.x + padding + @as(f32, @floatFromInt(col)) * (dot_size + spacing) + dot_size / 2;
        const cy = rect.y + padding + @as(f32, @floatFromInt(row)) * (dot_size + label_height + spacing) + dot_size / 2;

        const label = if (!data.compact and i < data.labels.len) data.labels[i] else null;

        color_dot.draw(r, cx, cy, .{
            .color = color,
            .label = label,
            .size = dot_size,
            .pulsing = data.is_active,
            .pulse_phase = data.pulse_phase,
        });
    }

    // Active indicator
    if (data.is_active) {
        // Small sync indicator in corner
        r.fillCircle(rect.x + rect.width - 12, rect.y + 12, 4, theme.success);
    }
}

/// Draw minimized overlay (single row, no background)
pub fn drawMinimized(r: *Renderer, x: f32, y: f32, data: *OverlayData) void {
    if (data.colors.len == 0) return;

    const dot_size: f32 = 16;
    const spacing: f32 = 4;

    var cx = x;
    for (data.colors) |color| {
        color_dot.draw(r, cx + dot_size / 2, y + dot_size / 2, .{
            .color = color,
            .size = dot_size,
            .show_border = true,
            .pulsing = data.is_active,
            .pulse_phase = data.pulse_phase,
        });
        cx += dot_size + spacing;
    }
}

/// Update animations
pub fn updateAnimation(data: *OverlayData, dt: f32) bool {
    if (!data.is_active) {
        if (data.pulse_phase != 0) {
            data.pulse_phase = 0;
            return true;
        }
        return false;
    }

    data.pulse_phase += dt * 2.0; // 2 Hz
    if (data.pulse_phase > 1.0) {
        data.pulse_phase -= 1.0;
    }
    return true;
}

/// Create sample colors for testing
pub fn createSampleColors(allocator: std.mem.Allocator, count: usize) ![]Color {
    var colors = try allocator.alloc(Color, count);

    for (colors, 0..) |*c, i| {
        const hue = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(count));
        c.* = Color.fromHsl(hue, 0.8, 0.5);
    }

    return colors;
}

