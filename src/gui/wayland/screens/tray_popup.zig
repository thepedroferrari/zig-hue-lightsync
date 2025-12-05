//! Tray popup screen
//!
//! A compact popup that appears when clicking the system tray icon,
//! providing quick access to start/stop, brightness, and area selection.

const std = @import("std");
const base = @import("../widgets/base.zig");
const button = @import("../widgets/button.zig");
const slider = @import("../widgets/slider.zig");
const toggle = @import("../widgets/toggle.zig");
const dropdown = @import("../widgets/dropdown.zig");

const Renderer = base.Renderer;
const Color = base.Color;
const Rect = base.Rect;
const WidgetState = base.WidgetState;

/// Tray popup data
pub const TrayPopupData = struct {
    // State
    is_syncing: bool = false,
    brightness: f32 = 75,
    selected_area_index: ?usize = null,
    areas: []const dropdown.Option = &.{},
    bridge_connected: bool = false,
    bridge_name: ?[]const u8 = null,

    // Animation
    sync_toggle_anim: f32 = 0,

    // Interaction state
    toggle_hovered: bool = false,
    brightness_dragging: bool = false,
    dropdown_open: bool = false,
    dropdown_hovered_index: ?usize = null,
    settings_hovered: bool = false,
    quit_hovered: bool = false,
};

/// Standard popup dimensions
pub const popup_width: f32 = 300;
pub const popup_height: f32 = 340;

/// Draw the tray popup
pub fn draw(r: *Renderer, rect: Rect, data: *TrayPopupData) void {
    const theme = base.theme;
    const padding: f32 = 16;

    // Background with rounded corners
    r.fillRoundedRect(rect, 12, theme.bg_surface);

    var y = rect.y + padding;

    // Header with app name and connection status
    r.drawTextBold("Hue Lightsync", rect.x + padding, y, theme.font_size_large, theme.text_primary);

    // Connection indicator
    const status_color = if (data.bridge_connected) theme.success else theme.text_secondary;
    const status_text = if (data.bridge_connected)
        (data.bridge_name orelse "Connected")
    else
        "Not connected";

    r.fillCircle(rect.x + rect.width - padding - 60, y + 8, 4, status_color);
    r.drawText(status_text, rect.x + rect.width - padding - 52, y + 2, theme.font_size_small, theme.text_secondary);
    y += 40;

    // Divider
    r.drawLine(rect.x + padding, y, rect.x + rect.width - padding, y, theme.bg_hover, 1);
    y += 16;

    // Sync toggle
    const toggle_rect = Rect{
        .x = rect.x + padding,
        .y = y,
        .width = rect.width - padding * 2,
        .height = 24,
    };
    toggle.draw(r, toggle_rect, data.is_syncing, data.sync_toggle_anim, .{
        .label = if (data.is_syncing) "Syncing" else "Sync Off",
        .disabled = !data.bridge_connected,
    }, .{ .hovered = data.toggle_hovered });
    y += 44;

    // Brightness slider
    r.drawText("Brightness", rect.x + padding, y, theme.font_size_small, theme.text_secondary);
    y += 20;

    const slider_rect = Rect{
        .x = rect.x + padding,
        .y = y,
        .width = rect.width - padding * 2 - 50, // Leave room for value
        .height = 24,
    };
    slider.draw(r, slider_rect, data.brightness, .{
        .min = 0,
        .max = 100,
        .show_value = true,
        .suffix = "%",
    }, .{
        .pressed = data.brightness_dragging,
        .disabled = !data.bridge_connected or !data.is_syncing,
    });
    y += 44;

    // Entertainment Area dropdown
    r.drawText("Entertainment Area", rect.x + padding, y, theme.font_size_small, theme.text_secondary);
    y += 20;

    const dropdown_rect = Rect{
        .x = rect.x + padding,
        .y = y,
        .width = rect.width - padding * 2,
        .height = 40,
    };
    dropdown.draw(r, dropdown_rect, data.selected_area_index, .{
        .options = data.areas,
        .placeholder = "Select area...",
        .disabled = !data.bridge_connected,
    }, .{}, data.dropdown_open);

    // Draw dropdown menu if open
    if (data.dropdown_open) {
        dropdown.drawMenu(r, dropdown_rect, .{
            .options = data.areas,
        }, data.selected_area_index, data.dropdown_hovered_index);
    }
    y += 60;

    // Divider
    r.drawLine(rect.x + padding, y, rect.x + rect.width - padding, y, theme.bg_hover, 1);
    y += 16;

    // Quick actions
    const action_width = (rect.width - padding * 3) / 2;
    const action_height: f32 = 36;

    // Settings button
    const settings_rect = Rect{
        .x = rect.x + padding,
        .y = y,
        .width = action_width,
        .height = action_height,
    };
    button.draw(r, settings_rect, .{ .label = "Settings", .style = .ghost }, .{ .hovered = data.settings_hovered });

    // Quit button
    const quit_rect = Rect{
        .x = rect.x + padding * 2 + action_width,
        .y = y,
        .width = action_width,
        .height = action_height,
    };
    button.draw(r, quit_rect, .{ .label = "Quit", .style = .ghost }, .{ .hovered = data.quit_hovered });
}

/// Update toggle animation
pub fn updateAnimation(data: *TrayPopupData, dt: f32) bool {
    const target: f32 = if (data.is_syncing) 1.0 else 0.0;
    if (data.sync_toggle_anim == target) return false;

    const diff = target - data.sync_toggle_anim;
    const step = dt * 6.0;

    if (@abs(diff) < step) {
        data.sync_toggle_anim = target;
    } else if (diff > 0) {
        data.sync_toggle_anim += step;
    } else {
        data.sync_toggle_anim -= step;
    }
    return true;
}

/// Hit test regions
pub fn getToggleRect(rect: Rect) Rect {
    const padding: f32 = 16;
    return Rect{
        .x = rect.x + rect.width - padding - 48,
        .y = rect.y + 56 + 16,
        .width = 48,
        .height = 24,
    };
}

pub fn getSliderRect(rect: Rect) Rect {
    const padding: f32 = 16;
    return Rect{
        .x = rect.x + padding,
        .y = rect.y + 56 + 16 + 44 + 20,
        .width = rect.width - padding * 2 - 50,
        .height = 24,
    };
}

pub fn getDropdownRect(rect: Rect) Rect {
    const padding: f32 = 16;
    return Rect{
        .x = rect.x + padding,
        .y = rect.y + 56 + 16 + 44 + 20 + 44 + 20,
        .width = rect.width - padding * 2,
        .height = 40,
    };
}

pub fn getSettingsRect(rect: Rect) Rect {
    const padding: f32 = 16;
    const action_width = (rect.width - padding * 3) / 2;
    return Rect{
        .x = rect.x + padding,
        .y = rect.y + rect.height - padding - 36,
        .width = action_width,
        .height = 36,
    };
}

pub fn getQuitRect(rect: Rect) Rect {
    const padding: f32 = 16;
    const action_width = (rect.width - padding * 3) / 2;
    return Rect{
        .x = rect.x + padding * 2 + action_width,
        .y = rect.y + rect.height - padding - 36,
        .width = action_width,
        .height = 36,
    };
}

