//! Color dot widget
//!
//! A colored circle for displaying light colors
//! in the overlay widget.

const std = @import("std");
const base = @import("base.zig");

const Renderer = base.Renderer;
const Color = base.Color;
const Rect = base.Rect;

/// Color dot configuration
pub const ColorDotConfig = struct {
    color: Color,
    label: ?[]const u8 = null,
    size: f32 = 32,
    show_border: bool = true,
    pulsing: bool = false, // For active sync indication
    pulse_phase: f32 = 0, // 0-1 for animation
};

/// Draw a single color dot
pub fn draw(r: *Renderer, cx: f32, cy: f32, config: ColorDotConfig) void {
    const theme = base.theme;
    const radius = config.size / 2;

    // Glow effect
    if (config.pulsing) {
        const glow_alpha = 0.3 + 0.2 * @sin(config.pulse_phase * std.math.pi * 2);
        const glow_size = radius * (1.2 + 0.1 * @sin(config.pulse_phase * std.math.pi * 2));
        r.fillCircle(cx, cy, glow_size, Color{
            .r = config.color.r,
            .g = config.color.g,
            .b = config.color.b,
            .a = glow_alpha,
        });
    }

    // Main circle
    r.fillCircle(cx, cy, radius, config.color);

    // Border
    if (config.show_border) {
        r.strokeCircle(cx, cy, radius, Color.white.blend(Color.transparent, 0.7), 1.5);
    }

    // Label below
    if (config.label) |label| {
        const label_rect = Rect{
            .x = cx - 40,
            .y = cy + radius + 4,
            .width = 80,
            .height = 16,
        };
        r.drawTextCentered(label, label_rect, theme.font_size_small, theme.text_secondary);
    }
}

/// Draw a grid of color dots (for overlay showing all lights)
pub fn drawGrid(
    r: *Renderer,
    rect: Rect,
    colors: []const Color,
    labels: ?[]const []const u8,
    cols: u32,
    dot_size: f32,
    spacing: f32,
) void {
    const total_spacing = spacing * @as(f32, @floatFromInt(cols - 1));
    const available_width = rect.width - total_spacing;
    const actual_dot_size = @min(dot_size, available_width / @as(f32, @floatFromInt(cols)));

    var i: usize = 0;
    for (colors) |color| {
        const col = i % cols;
        const row = i / cols;

        const cx = rect.x + @as(f32, @floatFromInt(col)) * (actual_dot_size + spacing) + actual_dot_size / 2;
        const cy = rect.y + @as(f32, @floatFromInt(row)) * (actual_dot_size + spacing + 20) + actual_dot_size / 2;

        const label = if (labels) |l| (if (i < l.len) l[i] else null) else null;

        draw(r, cx, cy, .{
            .color = color,
            .label = label,
            .size = actual_dot_size,
        });

        i += 1;
    }
}

/// Create a color from Hue CIE xy coordinates
pub fn colorFromXy(x: f32, y: f32, brightness: f32) Color {
    // Convert CIE xy to RGB (simplified)
    // Using standard sRGB conversion
    const z = 1.0 - x - y;

    const Y = brightness;
    const X = (Y / y) * x;
    const Z = (Y / y) * z;

    // XYZ to linear RGB
    var r_lin = X * 3.2406 - Y * 1.5372 - Z * 0.4986;
    var g_lin = -X * 0.9689 + Y * 1.8758 + Z * 0.0415;
    var b_lin = X * 0.0557 - Y * 0.2040 + Z * 1.0570;

    // Clamp
    r_lin = base.clamp(r_lin, 0, 1);
    g_lin = base.clamp(g_lin, 0, 1);
    b_lin = base.clamp(b_lin, 0, 1);

    // Linear to sRGB gamma
    const gamma = 1.0 / 2.2;
    return Color{
        .r = std.math.pow(r_lin, gamma),
        .g = std.math.pow(g_lin, gamma),
        .b = std.math.pow(b_lin, gamma),
    };
}

