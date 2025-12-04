//! zig-hue-lightsync library root
//! Wayland-only Philips Hue screen sync
//!
//! This module exports the core functionality for:
//! - Hue Bridge discovery and pairing
//! - Configuration management
//! - (Future) Screen capture and color processing
//! - (Future) Entertainment streaming

const std = @import("std");

// Core modules
pub const config = @import("config.zig");
pub const cli = @import("cli.zig");

// Hue API modules
pub const hue = struct {
    pub const v2rest = @import("hue/v2rest.zig");
    pub const discovery = @import("hue/discovery.zig");
};

// Re-export commonly used types
pub const Config = config.Config;
pub const ConfigManager = config.ConfigManager;
pub const HueClient = hue.v2rest.HueClient;
pub const DiscoveredBridge = hue.discovery.DiscoveredBridge;

/// Application version
pub const VERSION = "0.1.0";

/// Application name
pub const NAME = "zig-hue-lightsync";

test {
    // Run all tests from submodules
    std.testing.refAllDecls(@This());
}
