//! Screen library for zig-hue-lightsync
//!
//! Complete UI screens built from widgets.

pub const pairing = @import("screens/pairing.zig");
pub const area_picker = @import("screens/area_picker.zig");
pub const tray_popup = @import("screens/tray_popup.zig");
pub const overlay = @import("screens/overlay.zig");

// Re-export screen data types
pub const PairingData = pairing.PairingData;
pub const PairingState = pairing.PairingState;
pub const AreaPickerData = area_picker.AreaPickerData;
pub const AreaInfo = area_picker.AreaInfo;
pub const TrayPopupData = tray_popup.TrayPopupData;
pub const OverlayData = overlay.OverlayData;

