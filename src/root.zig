//! zig-hue-lightsync library root
//! Wayland-only Philips Hue screen sync
//!
//! This module exports the core functionality for:
//! - Hue Bridge discovery and pairing
//! - Configuration management
//! - Screen capture (Wayland/PipeWire) - requires Linux + system libs
//! - (Future) Entertainment streaming

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

// Core modules
pub const config = @import("config.zig");
pub const cli = @import("cli.zig");
pub const scenes = @import("scenes.zig");

// Hue API modules
pub const hue = struct {
    pub const v2rest = @import("hue/v2rest.zig");
    pub const discovery = @import("hue/discovery.zig");
};

// Color processing modules
pub const color = struct {
    const color_mod = @import("color/color.zig");
    const mapper_mod = @import("color/mapper.zig");

    pub const RGB = color_mod.RGB;
    pub const LinearRGB = color_mod.LinearRGB;
    pub const XYZ = color_mod.XYZ;
    pub const CIExy = color_mod.CIExy;
    pub const HueColor = color_mod.HueColor;
    pub const Gamut = color_mod.Gamut;
    pub const PixelFormat = color_mod.PixelFormat;

    pub const FrameProcessor = mapper_mod.FrameProcessor;
    pub const Region = mapper_mod.Region;
    pub const LightPosition = mapper_mod.LightPosition;
};

// GUI module (optional, Linux with GTK4 only)
// Compile with -Denable-gui=true to enable
pub const gui = if (build_options.enable_gui)
    @import("gui_impl")
else
    struct {
        // Stub types when GUI is disabled
        pub const App = void;
        pub const GuiError = error{NotSupported};

        pub fn isSupported() bool {
            return false;
        }

        pub fn launch(_: std.mem.Allocator) GuiError!void {
            return GuiError.NotSupported;
        }
    };

// Entertainment streaming module
pub const streaming = struct {
    const protocol_mod = @import("streaming/protocol.zig");
    const dtls_mod = @import("streaming/dtls.zig");
    const entertainment_mod = @import("streaming/entertainment.zig");

    pub const Frame = protocol_mod.Frame;
    pub const LightState = protocol_mod.LightState;
    pub const encodeFrame = protocol_mod.encodeFrame;

    pub const DtlsConnection = dtls_mod.DtlsConnection;
    pub const ConnectionState = dtls_mod.ConnectionState;

    pub const EntertainmentStreamer = entertainment_mod.EntertainmentStreamer;
    pub const FpsTier = entertainment_mod.FpsTier;
    pub const LightChannel = entertainment_mod.LightChannel;

    pub const isSupported = entertainment_mod.isSupported;
};

// Capture module (Linux only, requires system libraries)
// Compile with -Denable-capture=true to enable
// On non-Linux platforms or without -Denable-capture, these are stub types
pub const capture = if (build_options.enable_capture)
    @import("capture_impl")
else
    struct {
        // Stub types for non-Linux platforms or when capture is disabled
        pub const ScreenCapture = struct {
            allocator: std.mem.Allocator,

            pub fn init(allocator: std.mem.Allocator) @This() {
                return .{ .allocator = allocator };
            }

            pub fn deinit(_: *@This()) void {}

            pub fn requestPermission(_: *@This(), _: CaptureOptions) !void {
                return error.NotSupported;
            }

            pub fn start(_: *@This()) !void {
                return error.NotSupported;
            }

            pub fn stop(_: *@This()) void {}

            pub fn isCapturing(_: *const @This()) bool {
                return false;
            }
        };

        pub const Frame = struct {
            data: []const u8,
            width: u32,
            height: u32,
            stride: u32,
            format: u32,
        };

        pub const CaptureOptions = struct {
            capture_type: u32 = 1,
            cursor_mode: u32 = 2,
            multiple: bool = false,
            target_fps: u8 = 30,
        };
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

/// Check if capture is available on this platform
pub fn isCaptureAvailable() bool {
    return build_options.enable_capture;
}

test {
    // Run all tests from submodules
    std.testing.refAllDecls(@This());
}
