//! Toggle switch widget
//!
//! An on/off toggle switch with smooth animation.

const std = @import("std");
const base = @import("base.zig");

const Renderer = base.Renderer;
const Color = base.Color;
const Rect = base.Rect;
const WidgetState = base.WidgetState;
const AnimationState = base.AnimationState;

/// Toggle configuration
pub const ToggleConfig = struct {
    label: ?[]const u8 = null,
    disabled: bool = false,
};

/// Draw a toggle switch
pub fn draw(
    r: *Renderer,
    rect: Rect,
    is_on: bool,
    anim_progress: f32, // 0 = off, 1 = on (for smooth animation)
    config: ToggleConfig,
    state: WidgetState,
) void {
    const theme = base.theme;
    const dims = base.dims;

    // Draw label if present
    var toggle_x = rect.x;
    if (config.label) |label| {
        const label_color = if (config.disabled) theme.text_secondary.blend(Color.black, 0.3) else theme.text_primary;
        r.drawText(label, rect.x, rect.y + 4, theme.font_size_normal, label_color);
        toggle_x = rect.x + rect.width - dims.toggle_width;
    }

    // Toggle track
    const track_rect = Rect{
        .x = toggle_x,
        .y = rect.y,
        .width = dims.toggle_width,
        .height = dims.toggle_height,
    };

    // Background color transitions with animation
    const off_color = theme.bg_hover;
    const on_color = if (config.disabled) theme.accent.blend(Color.black, 0.5) else theme.accent;
    const bg_color = off_color.blend(on_color, anim_progress);

    r.fillRoundedRect(track_rect, dims.toggle_height / 2, bg_color);

    // Thumb
    const thumb_radius = (dims.toggle_height - 4) / 2;
    const thumb_travel = dims.toggle_width - dims.toggle_height;
    const thumb_x = toggle_x + dims.toggle_height / 2 + thumb_travel * anim_progress;
    const thumb_y = rect.y + dims.toggle_height / 2;

    // Thumb shadow
    r.fillCircle(thumb_x, thumb_y + 1, thumb_radius, Color{ .r = 0, .g = 0, .b = 0, .a = 0.2 });

    // Thumb circle
    const thumb_color = if (config.disabled) theme.text_secondary else Color.white;
    r.fillCircle(thumb_x, thumb_y, thumb_radius, thumb_color);

    // Hover highlight
    if (state.hovered and !config.disabled) {
        r.strokeRoundedRect(track_rect, dims.toggle_height / 2, theme.accent.blend(Color.transparent, 0.5), 2);
    }

    _ = is_on;
}

/// Check if point is in toggle area
pub fn hitTest(rect: Rect, x: f32, y: f32) bool {
    const dims = base.dims;
    const toggle_rect = Rect{
        .x = rect.x + rect.width - dims.toggle_width,
        .y = rect.y,
        .width = dims.toggle_width,
        .height = dims.toggle_height,
    };
    return toggle_rect.contains(x, y);
}

/// Create animation state for toggle
pub fn createAnimation(is_on: bool) AnimationState {
    return .{
        .progress = if (is_on) 1.0 else 0.0,
        .target = if (is_on) 1.0 else 0.0,
        .speed = 6.0,
    };
}

