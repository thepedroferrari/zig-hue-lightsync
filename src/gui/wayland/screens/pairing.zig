//! Pairing wizard screen
//!
//! A visually engaging pairing flow that guides the user
//! through pressing the link button on their Hue Bridge.

const std = @import("std");
const base = @import("../widgets/base.zig");
const button = @import("../widgets/button.zig");
const progress = @import("../widgets/progress.zig");

const Renderer = base.Renderer;
const Color = base.Color;
const Rect = base.Rect;
const WidgetState = base.WidgetState;

/// Pairing wizard state
pub const PairingState = enum {
    searching, // Looking for bridges
    waiting_for_button, // Waiting for user to press link button
    connecting, // Connecting to bridge
    success, // Pairing successful
    failed, // Pairing failed
    timeout, // Timed out waiting for button press
};

/// Pairing wizard data
pub const PairingData = struct {
    state: PairingState = .searching,
    bridge_ip: ?[]const u8 = null,
    bridge_name: ?[]const u8 = null,
    countdown_seconds: u32 = 30,
    total_seconds: u32 = 30,
    error_message: ?[]const u8 = null,
    spin_offset: f32 = 0, // For spinner animation
    pulse_phase: f32 = 0, // For button pulse animation

    // Interaction state
    retry_hovered: bool = false,
    cancel_hovered: bool = false,
};

/// Draw the pairing wizard screen
pub fn draw(r: *Renderer, rect: Rect, data: *PairingData) void {
    const theme = base.theme;

    // Background
    r.clear(theme.bg_primary);

    // Center content
    const content_width: f32 = 400;
    const content_x = rect.x + (rect.width - content_width) / 2;
    var y = rect.y + 40;

    // Title
    const title = switch (data.state) {
        .searching => "Searching for Bridges...",
        .waiting_for_button => "Press the Link Button",
        .connecting => "Connecting...",
        .success => "Pairing Complete!",
        .failed => "Pairing Failed",
        .timeout => "Time's Up",
    };

    const title_rect = Rect{ .x = content_x, .y = y, .width = content_width, .height = 40 };
    r.drawTextCentered(title, title_rect, theme.font_size_title, theme.text_primary);
    y += 60;

    // Main visual based on state
    const visual_rect = Rect{
        .x = content_x + (content_width - 160) / 2,
        .y = y,
        .width = 160,
        .height = 160,
    };

    switch (data.state) {
        .searching => {
            // Spinning progress indicator
            progress.draw(r, visual_rect, .{
                .progress = 0,
                .indeterminate = true,
                .spin_offset = data.spin_offset,
                .size = 120,
                .stroke_width = 6,
            });
        },
        .waiting_for_button => {
            // Countdown timer
            progress.drawCountdown(r, visual_rect, data.countdown_seconds, data.total_seconds);

            // Draw bridge icon with pulsing button
            drawBridgeIcon(r, visual_rect, data.pulse_phase);
        },
        .connecting => {
            progress.draw(r, visual_rect, .{
                .progress = 0,
                .indeterminate = true,
                .spin_offset = data.spin_offset,
                .center_text = "...",
                .size = 120,
            });
        },
        .success => {
            progress.drawSuccess(r, visual_rect);
        },
        .failed, .timeout => {
            progress.drawFailure(r, visual_rect);
        },
    }
    y += 180;

    // Subtitle/instructions
    const subtitle = switch (data.state) {
        .searching => "Looking for Hue Bridges on your network",
        .waiting_for_button => "Press the large round button on top of your Hue Bridge",
        .connecting => "Establishing secure connection...",
        .success => if (data.bridge_name) |name| name else "Connected to Hue Bridge",
        .failed => data.error_message orelse "Could not connect to bridge",
        .timeout => "The link button was not pressed in time",
    };

    const subtitle_rect = Rect{ .x = content_x, .y = y, .width = content_width, .height = 40 };
    r.drawTextCentered(subtitle, subtitle_rect, theme.font_size_normal, theme.text_secondary);
    y += 50;

    // Show bridge IP if available
    if (data.bridge_ip) |ip| {
        if (data.state == .waiting_for_button or data.state == .success) {
            var buf: [64]u8 = undefined;
            const ip_text = std.fmt.bufPrint(&buf, "Bridge: {s}", .{ip}) catch ip;
            const ip_rect = Rect{ .x = content_x, .y = y, .width = content_width, .height = 20 };
            r.drawTextCentered(ip_text, ip_rect, theme.font_size_small, theme.text_secondary);
            y += 30;
        }
    }

    // Buttons based on state
    y += 20;
    const button_width: f32 = 140;
    const button_height: f32 = 44;

    switch (data.state) {
        .success => {
            // Continue button
            const continue_rect = Rect{
                .x = content_x + (content_width - button_width) / 2,
                .y = y,
                .width = button_width,
                .height = button_height,
            };
            button.draw(r, continue_rect, .{ .label = "Continue", .style = .primary }, .{});
        },
        .failed, .timeout => {
            // Retry and Cancel buttons
            const spacing: f32 = 16;
            const total_width = button_width * 2 + spacing;
            const start_x = content_x + (content_width - total_width) / 2;

            const retry_rect = Rect{
                .x = start_x,
                .y = y,
                .width = button_width,
                .height = button_height,
            };
            button.draw(r, retry_rect, .{ .label = "Try Again", .style = .primary }, .{ .hovered = data.retry_hovered });

            const cancel_rect = Rect{
                .x = start_x + button_width + spacing,
                .y = y,
                .width = button_width,
                .height = button_height,
            };
            button.draw(r, cancel_rect, .{ .label = "Cancel", .style = .secondary }, .{ .hovered = data.cancel_hovered });
        },
        .searching, .connecting => {
            // Cancel button only
            const cancel_rect = Rect{
                .x = content_x + (content_width - button_width) / 2,
                .y = y,
                .width = button_width,
                .height = button_height,
            };
            button.draw(r, cancel_rect, .{ .label = "Cancel", .style = .ghost }, .{ .hovered = data.cancel_hovered });
        },
        .waiting_for_button => {
            // Cancel button
            const cancel_rect = Rect{
                .x = content_x + (content_width - button_width) / 2,
                .y = y,
                .width = button_width,
                .height = button_height,
            };
            button.draw(r, cancel_rect, .{ .label = "Cancel", .style = .ghost }, .{ .hovered = data.cancel_hovered });
        },
    }
}

/// Draw a stylized Hue Bridge icon
fn drawBridgeIcon(r: *Renderer, rect: Rect, pulse_phase: f32) void {
    const cx = rect.x + rect.width / 2;
    const cy = rect.y + rect.height / 2 + 30; // Below the countdown

    // Bridge body (rounded rectangle)
    const bridge_width: f32 = 80;
    const bridge_height: f32 = 30;
    const bridge_rect = Rect{
        .x = cx - bridge_width / 2,
        .y = cy - bridge_height / 2,
        .width = bridge_width,
        .height = bridge_height,
    };
    r.fillRoundedRect(bridge_rect, 8, Color.fromHex(0x3A3A3C));

    // Link button (pulsing)
    const button_radius: f32 = 14;
    const pulse_scale = 1.0 + 0.15 * @sin(pulse_phase * std.math.pi * 2);
    const pulse_alpha = 0.3 + 0.3 * @sin(pulse_phase * std.math.pi * 2);

    // Glow
    r.fillCircle(cx, cy - bridge_height / 2 - 10, button_radius * pulse_scale * 1.5, Color{
        .r = 0.4,
        .g = 0.7,
        .b = 1.0,
        .a = pulse_alpha,
    });

    // Button
    r.fillCircle(cx, cy - bridge_height / 2 - 10, button_radius, Color.accent);
    r.strokeCircle(cx, cy - bridge_height / 2 - 10, button_radius, Color.white.blend(Color.transparent, 0.5), 2);

    // LEDs on bridge
    const led_y = cy;
    const led_spacing: f32 = 15;
    var led_x = cx - led_spacing * 1.5;
    var i: u32 = 0;
    while (i < 4) : (i += 1) {
        r.fillCircle(led_x, led_y, 3, Color.fromHex(0x00FF88));
        led_x += led_spacing;
    }
}

/// Update animations (call every frame)
pub fn updateAnimations(data: *PairingData, dt: f32) void {
    // Spin animation
    data.spin_offset += dt * 2; // 2 radians per second
    if (data.spin_offset > std.math.pi * 2) {
        data.spin_offset -= std.math.pi * 2;
    }

    // Pulse animation
    data.pulse_phase += dt * 1.5; // 1.5 Hz
    if (data.pulse_phase > 1.0) {
        data.pulse_phase -= 1.0;
    }
}

/// Get the rect for the retry button (for hit testing)
pub fn getRetryButtonRect(rect: Rect) Rect {
    const content_width: f32 = 400;
    const content_x = rect.x + (rect.width - content_width) / 2;
    const button_width: f32 = 140;
    const button_height: f32 = 44;
    const spacing: f32 = 16;
    const total_width = button_width * 2 + spacing;
    const start_x = content_x + (content_width - total_width) / 2;
    const y = rect.y + 350; // Approximate button y position

    return Rect{
        .x = start_x,
        .y = y,
        .width = button_width,
        .height = button_height,
    };
}

/// Get the rect for the cancel button (for hit testing)
pub fn getCancelButtonRect(rect: Rect, state: PairingState) Rect {
    const content_width: f32 = 400;
    const content_x = rect.x + (rect.width - content_width) / 2;
    const button_width: f32 = 140;
    const button_height: f32 = 44;
    const y = rect.y + 350;

    if (state == .failed or state == .timeout) {
        // Second button position
        const spacing: f32 = 16;
        const total_width = button_width * 2 + spacing;
        const start_x = content_x + (content_width - total_width) / 2;
        return Rect{
            .x = start_x + button_width + spacing,
            .y = y,
            .width = button_width,
            .height = button_height,
        };
    } else {
        // Centered
        return Rect{
            .x = content_x + (content_width - button_width) / 2,
            .y = y,
            .width = button_width,
            .height = button_height,
        };
    }
}

