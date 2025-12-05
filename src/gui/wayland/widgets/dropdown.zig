//! Dropdown selector widget
//!
//! A dropdown for selecting from a list of options,
//! used for entertainment areas, FPS tiers, etc.

const std = @import("std");
const base = @import("base.zig");

const Renderer = base.Renderer;
const Color = base.Color;
const Rect = base.Rect;
const WidgetState = base.WidgetState;

/// Dropdown option
pub const Option = struct {
    label: []const u8,
    value: []const u8,
    icon: ?[]const u8 = null,
};

/// Dropdown configuration
pub const DropdownConfig = struct {
    label: ?[]const u8 = null,
    placeholder: []const u8 = "Select...",
    options: []const Option = &.{},
    disabled: bool = false,
};

/// Draw the dropdown button (closed state)
pub fn draw(
    r: *Renderer,
    rect: Rect,
    selected_index: ?usize,
    config: DropdownConfig,
    state: WidgetState,
    is_open: bool,
) void {
    const theme = base.theme;

    // Background
    var bg_color = theme.bg_secondary;
    if (is_open) {
        bg_color = theme.bg_hover;
    } else if (state.hovered and !config.disabled) {
        bg_color = theme.bg_hover;
    }

    r.fillRoundedRect(rect, theme.border_radius, bg_color);

    // Border
    const border_color = if (is_open) theme.accent else theme.bg_hover;
    r.strokeRoundedRect(rect, theme.border_radius, border_color, 1);

    // Label
    const padding = theme.padding;
    if (config.label) |label| {
        r.drawText(label, rect.x + padding, rect.y - 20, theme.font_size_small, theme.text_secondary);
    }

    // Selected value or placeholder
    const display_text = if (selected_index) |idx|
        (if (idx < config.options.len) config.options[idx].label else config.placeholder)
    else
        config.placeholder;

    const text_color = if (selected_index != null) theme.text_primary else theme.text_secondary;
    r.drawText(display_text, rect.x + padding, rect.y + 10, theme.font_size_normal, text_color);

    // Dropdown arrow
    const arrow_x = rect.x + rect.width - padding - 8;
    const arrow_y = rect.y + rect.height / 2;

    if (is_open) {
        // Up arrow
        r.drawLine(arrow_x - 4, arrow_y + 2, arrow_x, arrow_y - 2, theme.text_secondary, 2);
        r.drawLine(arrow_x, arrow_y - 2, arrow_x + 4, arrow_y + 2, theme.text_secondary, 2);
    } else {
        // Down arrow
        r.drawLine(arrow_x - 4, arrow_y - 2, arrow_x, arrow_y + 2, theme.text_secondary, 2);
        r.drawLine(arrow_x, arrow_y + 2, arrow_x + 4, arrow_y - 2, theme.text_secondary, 2);
    }
}

/// Draw the dropdown menu (open state)
pub fn drawMenu(
    r: *Renderer,
    anchor_rect: Rect,
    config: DropdownConfig,
    selected_index: ?usize,
    hovered_index: ?usize,
) void {
    const theme = base.theme;
    const padding = theme.padding;
    const item_height: f32 = 36;
    const menu_height = @as(f32, @floatFromInt(config.options.len)) * item_height + padding * 2;

    // Menu background
    const menu_rect = Rect{
        .x = anchor_rect.x,
        .y = anchor_rect.y + anchor_rect.height + 4,
        .width = anchor_rect.width,
        .height = menu_height,
    };

    // Shadow
    base.drawShadow(r, menu_rect, theme.border_radius, Color.black, 8);

    r.fillRoundedRect(menu_rect, theme.border_radius, theme.bg_surface);
    r.strokeRoundedRect(menu_rect, theme.border_radius, theme.bg_hover, 1);

    // Options
    var y = menu_rect.y + padding;
    for (config.options, 0..) |option, i| {
        const item_rect = Rect{
            .x = menu_rect.x + padding / 2,
            .y = y,
            .width = menu_rect.width - padding,
            .height = item_height,
        };

        const is_selected = selected_index != null and selected_index.? == i;
        const is_hovered = hovered_index != null and hovered_index.? == i;

        // Item background
        if (is_selected or is_hovered) {
            const item_bg = if (is_selected) theme.accent.blend(theme.bg_surface, 0.8) else theme.bg_hover;
            r.fillRoundedRect(item_rect, 4, item_bg);
        }

        // Icon
        var text_x = item_rect.x + padding / 2;
        if (option.icon) |icon| {
            r.drawText(icon, text_x, y + 8, theme.font_size_normal, theme.text_primary);
            text_x += 24;
        }

        // Label
        const text_color = if (is_selected) theme.accent else theme.text_primary;
        r.drawText(option.label, text_x, y + 8, theme.font_size_normal, text_color);

        // Checkmark for selected
        if (is_selected) {
            const check_x = item_rect.x + item_rect.width - 20;
            const check_y = y + item_height / 2;
            r.drawLine(check_x - 4, check_y, check_x - 1, check_y + 3, theme.accent, 2);
            r.drawLine(check_x - 1, check_y + 3, check_x + 5, check_y - 4, theme.accent, 2);
        }

        y += item_height;
    }
}

/// Get the index of the option at the given y position in the menu
pub fn getOptionAtPosition(
    anchor_rect: Rect,
    config: DropdownConfig,
    x: f32,
    y: f32,
) ?usize {
    const theme = base.theme;
    const padding = theme.padding;
    const item_height: f32 = 36;

    const menu_y = anchor_rect.y + anchor_rect.height + 4 + padding;
    const menu_x = anchor_rect.x;
    const menu_width = anchor_rect.width;

    if (x < menu_x or x > menu_x + menu_width) return null;
    if (y < menu_y) return null;

    const relative_y = y - menu_y;
    const index = @as(usize, @intFromFloat(relative_y / item_height));

    if (index >= config.options.len) return null;
    return index;
}

/// Check if point is in dropdown button
pub fn hitTest(rect: Rect, x: f32, y: f32) bool {
    return rect.contains(x, y);
}

/// Check if point is in dropdown menu
pub fn hitTestMenu(anchor_rect: Rect, options_count: usize, x: f32, y: f32) bool {
    const theme = base.theme;
    const padding = theme.padding;
    const item_height: f32 = 36;
    const menu_height = @as(f32, @floatFromInt(options_count)) * item_height + padding * 2;

    const menu_rect = Rect{
        .x = anchor_rect.x,
        .y = anchor_rect.y + anchor_rect.height + 4,
        .width = anchor_rect.width,
        .height = menu_height,
    };

    return menu_rect.contains(x, y);
}

