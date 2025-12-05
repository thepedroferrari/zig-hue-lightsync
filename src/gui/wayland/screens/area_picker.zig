//! Entertainment Area picker screen
//!
//! Displays available entertainment areas as visual cards,
//! allowing the user to select one for syncing.

const std = @import("std");
const base = @import("../widgets/base.zig");
const button = @import("../widgets/button.zig");
const card = @import("../widgets/card.zig");

const Renderer = base.Renderer;
const Color = base.Color;
const Rect = base.Rect;
const WidgetState = base.WidgetState;

/// Entertainment area info
pub const AreaInfo = struct {
    id: []const u8,
    name: []const u8,
    light_count: u32,
    room_name: ?[]const u8 = null,
    icon: []const u8 = "💡",
};

/// Area picker data
pub const AreaPickerData = struct {
    areas: []const AreaInfo = &.{},
    selected_index: ?usize = null,
    hovered_index: ?usize = null,
    scroll_offset: f32 = 0,
    loading: bool = false,
    error_message: ?[]const u8 = null,

    // Button states
    start_hovered: bool = false,
    test_hovered: bool = false,
    refresh_hovered: bool = false,
};

/// Draw the area picker screen
pub fn draw(r: *Renderer, rect: Rect, data: *AreaPickerData) void {
    const theme = base.theme;

    // Background
    r.clear(theme.bg_primary);

    const padding: f32 = 24;
    const content_width = rect.width - padding * 2;
    var y = rect.y + padding;

    // Header
    r.drawTextBold("Select Entertainment Area", rect.x + padding, y, theme.font_size_title, theme.text_primary);
    y += 40;

    r.drawText("Choose an area to sync with your screen colors", rect.x + padding, y, theme.font_size_normal, theme.text_secondary);
    y += 40;

    // Refresh button (top right)
    const refresh_rect = Rect{
        .x = rect.x + rect.width - padding - 100,
        .y = rect.y + padding,
        .width = 90,
        .height = 36,
    };
    button.draw(r, refresh_rect, .{ .label = "Refresh", .style = .ghost }, .{ .hovered = data.refresh_hovered });

    // Loading state
    if (data.loading) {
        const loading_rect = Rect{
            .x = rect.x + padding,
            .y = y + 100,
            .width = content_width,
            .height = 40,
        };
        r.drawTextCentered("Loading entertainment areas...", loading_rect, theme.font_size_normal, theme.text_secondary);
        return;
    }

    // Error state
    if (data.error_message) |err| {
        const error_rect = Rect{
            .x = rect.x + padding,
            .y = y + 100,
            .width = content_width,
            .height = 40,
        };
        r.drawTextCentered(err, error_rect, theme.font_size_normal, theme.err);
        return;
    }

    // No areas
    if (data.areas.len == 0) {
        const empty_rect = Rect{
            .x = rect.x + padding,
            .y = y + 80,
            .width = content_width,
            .height = 100,
        };

        r.drawTextCentered("No Entertainment Areas Found", empty_rect, theme.font_size_large, theme.text_primary);

        const hint_rect = Rect{
            .x = rect.x + padding,
            .y = y + 130,
            .width = content_width,
            .height = 40,
        };
        r.drawTextCentered("Create one in the Philips Hue app under Entertainment settings", hint_rect, theme.font_size_normal, theme.text_secondary);
        return;
    }

    // Area cards
    const card_height: f32 = 72;
    const card_spacing: f32 = 12;
    const max_visible: f32 = @floatFromInt(@min(data.areas.len, 5));
    const list_height = max_visible * (card_height + card_spacing);

    // Scroll area
    r.save();
    r.clipRect(.{
        .x = rect.x + padding,
        .y = y,
        .width = content_width,
        .height = list_height,
    });

    var card_y = y - data.scroll_offset;
    for (data.areas, 0..) |area, i| {
        const card_rect = Rect{
            .x = rect.x + padding,
            .y = card_y,
            .width = content_width,
            .height = card_height,
        };

        // Format badge text
        var badge_buf: [16]u8 = undefined;
        const badge = std.fmt.bufPrint(&badge_buf, "{d} lights", .{area.light_count}) catch "? lights";

        const config = card.CardConfig{
            .title = area.name,
            .subtitle = area.room_name,
            .icon = area.icon,
            .badge = badge,
            .selected = data.selected_index != null and data.selected_index.? == i,
        };

        const state = WidgetState{
            .hovered = data.hovered_index != null and data.hovered_index.? == i,
        };

        card.draw(r, card_rect, config, state);
        card_y += card_height + card_spacing;
    }

    r.restore();
    y += list_height + 20;

    // Selected area details
    if (data.selected_index) |idx| {
        if (idx < data.areas.len) {
            const area = data.areas[idx];

            // Divider
            r.drawLine(rect.x + padding, y, rect.x + rect.width - padding, y, theme.bg_hover, 1);
            y += 20;

            // Area name
            r.drawTextBold(area.name, rect.x + padding, y, theme.font_size_large, theme.text_primary);
            y += 30;

            // Light info
            var info_buf: [64]u8 = undefined;
            const info = std.fmt.bufPrint(&info_buf, "Contains {d} color-capable lights", .{area.light_count}) catch "Contains lights";
            r.drawText(info, rect.x + padding, y, theme.font_size_normal, theme.text_secondary);
            y += 40;

            // Action buttons
            const button_width: f32 = 140;
            const button_height: f32 = 44;
            const button_spacing: f32 = 16;

            // Test lights button
            const test_rect = Rect{
                .x = rect.x + padding,
                .y = y,
                .width = button_width,
                .height = button_height,
            };
            button.draw(r, test_rect, .{ .label = "Test Lights", .style = .secondary }, .{ .hovered = data.test_hovered });

            // Start sync button
            const start_rect = Rect{
                .x = rect.x + padding + button_width + button_spacing,
                .y = y,
                .width = button_width + 20,
                .height = button_height,
            };
            button.draw(r, start_rect, .{ .label = "Start Sync", .style = .primary }, .{ .hovered = data.start_hovered });
        }
    }
}

/// Get the card rect for a given index (for hit testing)
pub fn getCardRect(rect: Rect, index: usize, scroll_offset: f32) Rect {
    const padding: f32 = 24;
    const card_height: f32 = 72;
    const card_spacing: f32 = 12;
    const y_base = rect.y + 24 + 40 + 40; // After header

    return Rect{
        .x = rect.x + padding,
        .y = y_base + @as(f32, @floatFromInt(index)) * (card_height + card_spacing) - scroll_offset,
        .width = rect.width - padding * 2,
        .height = card_height,
    };
}

/// Get which card index is at a given y position
pub fn getCardIndexAtPosition(rect: Rect, areas_count: usize, scroll_offset: f32, x: f32, y: f32) ?usize {
    const padding: f32 = 24;
    const content_width = rect.width - padding * 2;

    if (x < rect.x + padding or x > rect.x + padding + content_width) return null;

    const y_base = rect.y + 24 + 40 + 40;
    const card_height: f32 = 72;
    const card_spacing: f32 = 12;

    const relative_y = y - y_base + scroll_offset;
    if (relative_y < 0) return null;

    const index = @as(usize, @intFromFloat(relative_y / (card_height + card_spacing)));
    if (index >= areas_count) return null;

    // Check if actually in the card (not in spacing)
    const card_y_in_slot = @mod(relative_y, card_height + card_spacing);
    if (card_y_in_slot > card_height) return null;

    return index;
}

/// Get button rects for hit testing
pub fn getTestButtonRect(rect: Rect) Rect {
    const padding: f32 = 24;
    return Rect{
        .x = rect.x + padding,
        .y = rect.y + rect.height - 80,
        .width = 140,
        .height = 44,
    };
}

pub fn getStartButtonRect(rect: Rect) Rect {
    const padding: f32 = 24;
    return Rect{
        .x = rect.x + padding + 156,
        .y = rect.y + rect.height - 80,
        .width = 160,
        .height = 44,
    };
}

pub fn getRefreshButtonRect(rect: Rect) Rect {
    const padding: f32 = 24;
    return Rect{
        .x = rect.x + rect.width - padding - 100,
        .y = rect.y + padding,
        .width = 90,
        .height = 36,
    };
}

