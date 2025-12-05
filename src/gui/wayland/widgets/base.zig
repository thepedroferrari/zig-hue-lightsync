//! Base widget interface and common types
//!
//! All widgets follow a stateless rendering pattern:
//! - Widgets receive state and render to a renderer
//! - State is managed by screens, not widgets
//! - Input events bubble from screen to focused widget

const std = @import("std");
const renderer = @import("../renderer.zig");

pub const Renderer = renderer.Renderer;
pub const Color = renderer.Color;
pub const Rect = renderer.Rect;

/// Input event types
pub const Event = union(enum) {
    pointer_enter: struct { x: f32, y: f32 },
    pointer_leave: void,
    pointer_motion: struct { x: f32, y: f32 },
    pointer_button: struct {
        button: u32,
        pressed: bool,
        x: f32,
        y: f32,
    },
    key: struct {
        keycode: u32,
        pressed: bool,
        modifiers: Modifiers,
    },
    scroll: struct {
        dx: f32,
        dy: f32,
    },
};

/// Keyboard modifiers
pub const Modifiers = packed struct {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    super: bool = false,
    _padding: u28 = 0,
};

/// Event handler result
pub const EventResult = enum {
    consumed,
    ignored,
};

/// Widget state flags
pub const WidgetState = struct {
    hovered: bool = false,
    pressed: bool = false,
    focused: bool = false,
    disabled: bool = false,

    pub fn isInteractive(self: WidgetState) bool {
        return !self.disabled;
    }
};

/// Animation state for widgets that animate
pub const AnimationState = struct {
    progress: f32 = 0,
    target: f32 = 0,
    speed: f32 = 8.0, // Units per second

    pub fn update(self: *AnimationState, dt: f32) bool {
        if (self.progress == self.target) return false;

        const diff = self.target - self.progress;
        const step = self.speed * dt;

        if (@abs(diff) < step) {
            self.progress = self.target;
        } else if (diff > 0) {
            self.progress += step;
        } else {
            self.progress -= step;
        }
        return true;
    }

    pub fn setTarget(self: *AnimationState, target: f32) void {
        self.target = target;
    }

    pub fn isAnimating(self: *const AnimationState) bool {
        return self.progress != self.target;
    }
};

/// Theme colors for consistent styling
pub const Theme = struct {
    bg_primary: Color = Color.bg_dark,
    bg_secondary: Color = Color.bg_surface,
    bg_hover: Color = Color.bg_hover,
    text_primary: Color = Color.text_primary,
    text_secondary: Color = Color.text_secondary,
    accent: Color = Color.accent,
    success: Color = Color.success,
    warning: Color = Color.warning,
    err: Color = Color.error_color,
    border_radius: f32 = 8,
    padding: f32 = 12,
    spacing: f32 = 8,
    font_size_small: f32 = 12,
    font_size_normal: f32 = 14,
    font_size_large: f32 = 18,
    font_size_title: f32 = 24,

    pub const default: Theme = .{};
};

/// Common widget dimensions
pub const Dimensions = struct {
    button_height: f32 = 40,
    slider_height: f32 = 24,
    slider_track_height: f32 = 6,
    toggle_width: f32 = 48,
    toggle_height: f32 = 24,
    card_padding: f32 = 16,
    progress_ring_size: f32 = 80,
    progress_ring_stroke: f32 = 6,

    pub const default: Dimensions = .{};
};

/// Global theme instance
pub var theme: Theme = Theme.default;

/// Global dimensions
pub var dims: Dimensions = Dimensions.default;

/// Helper to draw a shadow/glow effect
pub fn drawShadow(r: *Renderer, rect: Rect, radius: f32, color: Color, blur: f32) void {
    const steps: u32 = 4;
    var i: u32 = 0;
    while (i < steps) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
        const alpha = color.a * (1.0 - t) * 0.3;
        const expand = blur * t;
        const shadow_rect = Rect{
            .x = rect.x - expand,
            .y = rect.y - expand,
            .width = rect.width + expand * 2,
            .height = rect.height + expand * 2,
        };
        r.fillRoundedRect(shadow_rect, radius + expand, .{
            .r = color.r,
            .g = color.g,
            .b = color.b,
            .a = alpha,
        });
    }
}

/// Ease-out cubic function for smooth animations
pub fn easeOutCubic(t: f32) f32 {
    const t1 = t - 1;
    return t1 * t1 * t1 + 1;
}

/// Ease-in-out cubic
pub fn easeInOutCubic(t: f32) f32 {
    if (t < 0.5) {
        return 4 * t * t * t;
    } else {
        const t1 = -2 * t + 2;
        return 1 - t1 * t1 * t1 / 2;
    }
}

/// Linear interpolation
pub fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

/// Clamp value to range
pub fn clamp(value: f32, min_val: f32, max_val: f32) f32 {
    return @max(min_val, @min(max_val, value));
}

test "animation state" {
    var anim = AnimationState{};
    anim.setTarget(1.0);
    try std.testing.expect(anim.isAnimating());

    // Simulate animation
    _ = anim.update(0.5);
    try std.testing.expect(anim.progress > 0);
    try std.testing.expect(anim.progress < 1);
}

test "easing functions" {
    try std.testing.expectApproxEqAbs(@as(f32, 0), easeOutCubic(0), 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 1), easeOutCubic(1), 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), easeInOutCubic(0.5), 0.01);
}

