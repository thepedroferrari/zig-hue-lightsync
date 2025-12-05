//! Slider widget
//!
//! A horizontal slider for adjusting numeric values,
//! perfect for brightness and volume controls.

const std = @import("std");
const base = @import("base.zig");

const Renderer = base.Renderer;
const Color = base.Color;
const Rect = base.Rect;
const WidgetState = base.WidgetState;

/// Slider configuration
pub const SliderConfig = struct {
    min: f32 = 0,
    max: f32 = 100,
    step: f32 = 1,
    show_value: bool = true,
    label: ?[]const u8 = null,
    suffix: []const u8 = "%",
};

/// Draw a slider
pub fn draw(
    r: *Renderer,
    rect: Rect,
    value: f32,
    config: SliderConfig,
    state: WidgetState,
) void {
    const theme = base.theme;
    const dims = base.dims;

    // Calculate positions
    const track_y = rect.y + (rect.height - dims.slider_track_height) / 2;
    const normalized = (value - config.min) / (config.max - config.min);
    const fill_width = rect.width * normalized;

    // Draw track background
    const track_rect = Rect{
        .x = rect.x,
        .y = track_y,
        .width = rect.width,
        .height = dims.slider_track_height,
    };
    r.fillRoundedRect(track_rect, dims.slider_track_height / 2, theme.bg_hover);

    // Draw filled portion
    if (fill_width > 0) {
        const fill_rect = Rect{
            .x = rect.x,
            .y = track_y,
            .width = fill_width,
            .height = dims.slider_track_height,
        };
        const fill_color = if (state.disabled) theme.text_secondary else theme.accent;
        r.fillRoundedRect(fill_rect, dims.slider_track_height / 2, fill_color);
    }

    // Draw thumb
    const thumb_radius: f32 = 10;
    const thumb_x = rect.x + fill_width;
    const thumb_y = rect.y + rect.height / 2;

    // Thumb glow on hover/press
    if (state.hovered or state.pressed) {
        r.fillCircle(thumb_x, thumb_y, thumb_radius + 6, theme.accent.blend(Color.transparent, 0.7));
    }

    // Thumb circle
    const thumb_color = if (state.disabled) theme.text_secondary else Color.white;
    r.fillCircle(thumb_x, thumb_y, thumb_radius, thumb_color);

    // Draw value text
    if (config.show_value) {
        var buf: [32]u8 = undefined;
        const val_int: i32 = @intFromFloat(value);
        const text = std.fmt.bufPrint(&buf, "{d}{s}", .{ val_int, config.suffix }) catch "?";
        r.drawText(text, rect.x + rect.width + 8, rect.y + 2, theme.font_size_normal, theme.text_primary);
    }
}

/// Calculate value from x position
pub fn valueFromPosition(rect: Rect, x: f32, config: SliderConfig) f32 {
    const clamped_x = base.clamp(x, rect.x, rect.x + rect.width);
    const normalized = (clamped_x - rect.x) / rect.width;
    const raw_value = config.min + normalized * (config.max - config.min);

    // Snap to step
    if (config.step > 0) {
        const steps = @round((raw_value - config.min) / config.step);
        return config.min + steps * config.step;
    }
    return raw_value;
}

/// Check if point is in slider interaction area
pub fn hitTest(rect: Rect, x: f32, y: f32) bool {
    // Expand hit area vertically for easier interaction
    const expanded = Rect{
        .x = rect.x - 10,
        .y = rect.y - 10,
        .width = rect.width + 20,
        .height = rect.height + 20,
    };
    return expanded.contains(x, y);
}

