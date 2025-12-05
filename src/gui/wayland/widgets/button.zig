//! Button widget
//!
//! A clickable button with hover and press states,
//! supporting both text and icon content.

const std = @import("std");
const base = @import("base.zig");

const Renderer = base.Renderer;
const Color = base.Color;
const Rect = base.Rect;
const WidgetState = base.WidgetState;
const Theme = base.Theme;

/// Button style variants
pub const ButtonStyle = enum {
    primary, // Accent colored, prominent
    secondary, // Subtle background
    ghost, // Transparent until hover
    danger, // Red for destructive actions
};

/// Button configuration
pub const ButtonConfig = struct {
    label: []const u8,
    style: ButtonStyle = .primary,
    icon: ?[]const u8 = null, // Optional icon (Unicode or icon font)
    min_width: f32 = 80,
    disabled: bool = false,
};

/// Draw a button
pub fn draw(
    r: *Renderer,
    rect: Rect,
    config: ButtonConfig,
    state: WidgetState,
) void {
    const theme = base.theme;
    const actual_state = if (config.disabled) WidgetState{ .disabled = true } else state;

    // Determine colors based on style and state
    const bg_color = getBackgroundColor(config.style, actual_state, theme);
    const text_color = getTextColor(config.style, actual_state, theme);

    // Draw background
    base.drawShadow(r, rect, theme.border_radius, Color.black, 4);
    r.fillRoundedRect(rect, theme.border_radius, bg_color);

    // Draw border for secondary/ghost
    if (config.style == .secondary or config.style == .ghost) {
        if (state.hovered or state.pressed) {
            r.strokeRoundedRect(rect, theme.border_radius, theme.accent.blend(Color.transparent, 0.5), 1);
        }
    }

    // Draw label
    r.drawTextCentered(config.label, rect, theme.font_size_normal, text_color);
}

fn getBackgroundColor(style: ButtonStyle, state: WidgetState, theme: Theme) Color {
    if (state.disabled) {
        return theme.bg_secondary.blend(Color.black, 0.3);
    }

    return switch (style) {
        .primary => blk: {
            var color = theme.accent;
            if (state.pressed) {
                break :blk color.blend(Color.black, 0.2);
            } else if (state.hovered) {
                break :blk color.blend(Color.white, 0.1);
            }
            break :blk color;
        },
        .secondary => blk: {
            if (state.pressed) {
                break :blk theme.bg_hover.blend(Color.black, 0.1);
            } else if (state.hovered) {
                break :blk theme.bg_hover;
            }
            break :blk theme.bg_secondary;
        },
        .ghost => blk: {
            if (state.pressed) {
                break :blk theme.bg_hover.blend(Color.black, 0.1);
            } else if (state.hovered) {
                break :blk theme.bg_hover;
            }
            break :blk Color.transparent;
        },
        .danger => blk: {
            var color = theme.err;
            if (state.pressed) {
                break :blk color.blend(Color.black, 0.2);
            } else if (state.hovered) {
                break :blk color.blend(Color.white, 0.1);
            }
            break :blk color;
        },
    };
}

fn getTextColor(style: ButtonStyle, state: WidgetState, theme: Theme) Color {
    if (state.disabled) {
        return theme.text_secondary.blend(Color.black, 0.3);
    }

    return switch (style) {
        .primary, .danger => Color.white,
        .secondary, .ghost => blk: {
            if (state.hovered or state.pressed) {
                break :blk theme.text_primary;
            }
            break :blk theme.text_secondary;
        },
    };
}

/// Handle button click - returns true if button was clicked
pub fn handleClick(rect: Rect, state: WidgetState, x: f32, y: f32) bool {
    if (state.disabled) return false;
    return rect.contains(x, y);
}

