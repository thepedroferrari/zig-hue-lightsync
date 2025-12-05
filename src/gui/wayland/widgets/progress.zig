//! Progress ring widget
//!
//! A circular progress indicator, perfect for
//! the pairing countdown timer.

const std = @import("std");
const base = @import("base.zig");

const Renderer = base.Renderer;
const Color = base.Color;
const Rect = base.Rect;

/// Progress ring configuration
pub const ProgressConfig = struct {
    /// Progress value 0.0 - 1.0
    progress: f32,
    /// Text to show in center (e.g., "15s")
    center_text: ?[]const u8 = null,
    /// Secondary text below center
    sub_text: ?[]const u8 = null,
    /// Ring color
    color: Color = Color.accent,
    /// Background ring color
    bg_color: Color = Color.bg_hover,
    /// Size of the ring
    size: f32 = 80,
    /// Stroke width
    stroke_width: f32 = 6,
    /// Animate the progress (spinning effect when indeterminate)
    indeterminate: bool = false,
    /// Animation offset for spinning
    spin_offset: f32 = 0,
};

/// Draw a progress ring
pub fn draw(r: *Renderer, rect: Rect, config: ProgressConfig) void {
    const theme = base.theme;
    const cx = rect.x + rect.width / 2;
    const cy = rect.y + rect.height / 2;
    const radius = config.size / 2 - config.stroke_width / 2;

    // Background ring
    r.strokeCircle(cx, cy, radius, config.bg_color, config.stroke_width);

    // Progress arc
    const start_angle = -std.math.pi / 2.0 + config.spin_offset; // Start from top
    const progress_clamped = base.clamp(config.progress, 0, 1);

    if (config.indeterminate) {
        // Spinning arc for indeterminate state
        const arc_length = std.math.pi * 0.75; // 3/4 of a circle
        r.strokeArc(cx, cy, radius, start_angle, start_angle + arc_length, config.color, config.stroke_width);
    } else if (progress_clamped > 0) {
        const end_angle = start_angle + progress_clamped * 2 * std.math.pi;
        r.strokeArc(cx, cy, radius, start_angle, end_angle, config.color, config.stroke_width);
    }

    // Center text
    if (config.center_text) |text| {
        const text_rect = Rect{
            .x = cx - config.size / 2,
            .y = cy - 12,
            .width = config.size,
            .height = 24,
        };
        r.drawTextCentered(text, text_rect, theme.font_size_title, theme.text_primary);
    }

    // Sub text
    if (config.sub_text) |text| {
        const text_rect = Rect{
            .x = cx - config.size / 2,
            .y = cy + 8,
            .width = config.size,
            .height = 16,
        };
        r.drawTextCentered(text, text_rect, theme.font_size_small, theme.text_secondary);
    }
}

/// Draw a large countdown timer (for pairing)
pub fn drawCountdown(r: *Renderer, rect: Rect, seconds_remaining: u32, total_seconds: u32) void {
    const progress = 1.0 - @as(f32, @floatFromInt(seconds_remaining)) / @as(f32, @floatFromInt(total_seconds));

    var buf: [8]u8 = undefined;
    const time_text = std.fmt.bufPrint(&buf, "{d}s", .{seconds_remaining}) catch "?";

    draw(r, rect, .{
        .progress = progress,
        .center_text = time_text,
        .sub_text = "remaining",
        .size = 120,
        .stroke_width = 8,
        .color = if (seconds_remaining <= 5) Color.warning else Color.accent,
    });
}

/// Draw a success state (checkmark)
pub fn drawSuccess(r: *Renderer, rect: Rect) void {
    const theme = base.theme;
    const cx = rect.x + rect.width / 2;
    const cy = rect.y + rect.height / 2;
    const size: f32 = 80;
    const radius = size / 2 - 3;

    // Green circle
    r.fillCircle(cx, cy, radius, theme.success);

    // Checkmark
    const check_color = Color.white;
    const line_width: f32 = 4;

    // Draw checkmark lines
    r.drawLine(cx - 15, cy, cx - 5, cy + 12, check_color, line_width);
    r.drawLine(cx - 5, cy + 12, cx + 18, cy - 10, check_color, line_width);
}

/// Draw a failure/retry state
pub fn drawFailure(r: *Renderer, rect: Rect) void {
    const theme = base.theme;
    const cx = rect.x + rect.width / 2;
    const cy = rect.y + rect.height / 2;
    const size: f32 = 80;
    const radius = size / 2 - 3;

    // Red circle
    r.fillCircle(cx, cy, radius, theme.err);

    // X mark
    const x_color = Color.white;
    const line_width: f32 = 4;
    const offset: f32 = 12;

    r.drawLine(cx - offset, cy - offset, cx + offset, cy + offset, x_color, line_width);
    r.drawLine(cx + offset, cy - offset, cx - offset, cy + offset, x_color, line_width);
}

