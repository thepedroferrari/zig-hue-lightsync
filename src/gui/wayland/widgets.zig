//! Widget library for zig-hue-lightsync
//!
//! Reusable UI components for building the Wayland-native GUI.

pub const base = @import("widgets/base.zig");
pub const button = @import("widgets/button.zig");
pub const slider = @import("widgets/slider.zig");
pub const toggle = @import("widgets/toggle.zig");
pub const progress = @import("widgets/progress.zig");
pub const card = @import("widgets/card.zig");
pub const dropdown = @import("widgets/dropdown.zig");
pub const color_dot = @import("widgets/color_dot.zig");

// Re-export common types
pub const Color = base.Color;
pub const Rect = base.Rect;
pub const Theme = base.Theme;
pub const WidgetState = base.WidgetState;
pub const AnimationState = base.AnimationState;
pub const Event = base.Event;
pub const EventResult = base.EventResult;

// Re-export global config
pub const theme = &base.theme;
pub const dims = &base.dims;

