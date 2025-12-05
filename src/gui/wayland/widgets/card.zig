//! Card widget
//!
//! A card component for displaying entertainment areas,
//! bridges, or other selectable items.

const std = @import("std");
const base = @import("base.zig");

const Renderer = base.Renderer;
const Color = base.Color;
const Rect = base.Rect;
const WidgetState = base.WidgetState;

/// Card configuration
pub const CardConfig = struct {
    title: []const u8,
    subtitle: ?[]const u8 = null,
    icon: ?[]const u8 = null, // Unicode emoji or icon
    badge: ?[]const u8 = null, // Small badge text (e.g., "3 lights")
    selected: bool = false,
    disabled: bool = false,
};

/// Draw a card
pub fn draw(
    r: *Renderer,
    rect: Rect,
    config: CardConfig,
    state: WidgetState,
) void {
    const theme = base.theme;

    // Background
    var bg_color = theme.bg_secondary;
    if (config.selected) {
        bg_color = theme.accent.blend(theme.bg_secondary, 0.8);
    } else if (state.hovered and !config.disabled) {
        bg_color = theme.bg_hover;
    }

    // Shadow for selected state
    if (config.selected) {
        base.drawShadow(r, rect, theme.border_radius, theme.accent, 8);
    }

    r.fillRoundedRect(rect, theme.border_radius, bg_color);

    // Border
    const border_color = if (config.selected) theme.accent else theme.bg_hover;
    r.strokeRoundedRect(rect, theme.border_radius, border_color, if (config.selected) 2 else 1);

    // Content layout
    const padding = theme.padding;
    var content_x = rect.x + padding;
    const content_y = rect.y + padding;

    // Icon
    if (config.icon) |icon| {
        r.drawText(icon, content_x, content_y, 24, theme.text_primary);
        content_x += 32;
    }

    // Title
    const title_color = if (config.disabled) theme.text_secondary else theme.text_primary;
    r.drawTextBold(config.title, content_x, content_y, theme.font_size_normal, title_color);

    // Subtitle
    if (config.subtitle) |subtitle| {
        r.drawText(subtitle, content_x, content_y + 20, theme.font_size_small, theme.text_secondary);
    }

    // Badge
    if (config.badge) |badge| {
        const badge_x = rect.x + rect.width - padding - 60;
        const badge_y = rect.y + (rect.height - 20) / 2;
        const badge_rect = Rect{
            .x = badge_x,
            .y = badge_y,
            .width = 55,
            .height = 20,
        };
        r.fillRoundedRect(badge_rect, 10, theme.bg_hover);
        r.drawTextCentered(badge, badge_rect, theme.font_size_small, theme.text_secondary);
    }

    // Selection indicator
    if (config.selected) {
        const indicator_size: f32 = 20;
        const indicator_x = rect.x + rect.width - padding - indicator_size / 2;
        const indicator_y = rect.y + padding + indicator_size / 2;
        r.fillCircle(indicator_x, indicator_y, indicator_size / 2, theme.accent);

        // Checkmark in indicator
        r.drawLine(indicator_x - 5, indicator_y, indicator_x - 1, indicator_y + 4, Color.white, 2);
        r.drawLine(indicator_x - 1, indicator_y + 4, indicator_x + 6, indicator_y - 4, Color.white, 2);
    }
}

/// Check if point is in card area
pub fn hitTest(rect: Rect, x: f32, y: f32) bool {
    return rect.contains(x, y);
}

/// Draw a list of cards with spacing
pub fn drawList(
    r: *Renderer,
    start_rect: Rect,
    items: []const CardConfig,
    selected_index: ?usize,
    hovered_index: ?usize,
    card_height: f32,
    spacing: f32,
) void {
    var y = start_rect.y;
    for (items, 0..) |item, i| {
        var config = item;
        config.selected = selected_index != null and selected_index.? == i;

        const state = WidgetState{
            .hovered = hovered_index != null and hovered_index.? == i,
        };

        const card_rect = Rect{
            .x = start_rect.x,
            .y = y,
            .width = start_rect.width,
            .height = card_height,
        };

        draw(r, card_rect, config, state);
        y += card_height + spacing;
    }
}

