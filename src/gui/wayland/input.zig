//! Input handling for Wayland
//!
//! Manages pointer and keyboard input from wl_seat,
//! dispatching events to the focused surface/widget.

const std = @import("std");
const client = @import("client.zig");
const c = client.c;

/// Pointer state
pub const PointerState = struct {
    x: f32 = 0,
    y: f32 = 0,
    buttons: u32 = 0,
    surface: ?*c.wl_surface = null,
    serial: u32 = 0,

    pub fn isButtonPressed(self: *const PointerState, button: u32) bool {
        return (self.buttons & (@as(u32, 1) << @intCast(button))) != 0;
    }

    pub fn isLeftPressed(self: *const PointerState) bool {
        return self.isButtonPressed(272); // BTN_LEFT
    }

    pub fn isRightPressed(self: *const PointerState) bool {
        return self.isButtonPressed(273); // BTN_RIGHT
    }
};

/// Keyboard state
pub const KeyboardState = struct {
    surface: ?*c.wl_surface = null,
    modifiers: Modifiers = .{},
    serial: u32 = 0,
};

/// Keyboard modifiers
pub const Modifiers = struct {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    super: bool = false,

    pub fn fromMods(mods_depressed: u32, mods_latched: u32, mods_locked: u32) Modifiers {
        const mods = mods_depressed | mods_latched | mods_locked;
        return .{
            .shift = (mods & 1) != 0,
            .ctrl = (mods & 4) != 0,
            .alt = (mods & 8) != 0,
            .super = (mods & 64) != 0,
        };
    }
};

/// Input event callback types
pub const PointerEnterCallback = *const fn (surface: *c.wl_surface, x: f32, y: f32, serial: u32) void;
pub const PointerLeaveCallback = *const fn (surface: *c.wl_surface, serial: u32) void;
pub const PointerMotionCallback = *const fn (x: f32, y: f32) void;
pub const PointerButtonCallback = *const fn (button: u32, pressed: bool, serial: u32) void;
pub const PointerScrollCallback = *const fn (dx: f32, dy: f32) void;
pub const KeyboardEnterCallback = *const fn (surface: *c.wl_surface, serial: u32) void;
pub const KeyboardLeaveCallback = *const fn (surface: *c.wl_surface, serial: u32) void;
pub const KeyboardKeyCallback = *const fn (keycode: u32, pressed: bool, serial: u32) void;
pub const KeyboardModifiersCallback = *const fn (modifiers: Modifiers) void;

/// Input manager
pub const InputManager = struct {
    pointer: ?client.Pointer = null,
    keyboard: ?client.Keyboard = null,
    pointer_state: PointerState = .{},
    keyboard_state: KeyboardState = .{},

    // Callbacks
    on_pointer_enter: ?PointerEnterCallback = null,
    on_pointer_leave: ?PointerLeaveCallback = null,
    on_pointer_motion: ?PointerMotionCallback = null,
    on_pointer_button: ?PointerButtonCallback = null,
    on_pointer_scroll: ?PointerScrollCallback = null,
    on_keyboard_enter: ?KeyboardEnterCallback = null,
    on_keyboard_leave: ?KeyboardLeaveCallback = null,
    on_keyboard_key: ?KeyboardKeyCallback = null,
    on_keyboard_modifiers: ?KeyboardModifiersCallback = null,

    const Self = @This();

    /// Initialize input from seat capabilities
    pub fn initFromSeat(self: *Self, seat: *client.Seat, capabilities: u32) void {
        const WL_SEAT_CAPABILITY_POINTER = 1;
        const WL_SEAT_CAPABILITY_KEYBOARD = 2;

        if ((capabilities & WL_SEAT_CAPABILITY_POINTER) != 0 and self.pointer == null) {
            self.pointer = seat.getPointer();
            if (self.pointer) |*ptr| {
                ptr.addListener(&pointer_listener, self);
            }
        }

        if ((capabilities & WL_SEAT_CAPABILITY_KEYBOARD) != 0 and self.keyboard == null) {
            self.keyboard = seat.getKeyboard();
            if (self.keyboard) |*kbd| {
                kbd.addListener(&keyboard_listener, self);
            }
        }
    }

    /// Cleanup
    pub fn deinit(self: *Self) void {
        if (self.pointer) |*ptr| ptr.destroy();
        if (self.keyboard) |*kbd| kbd.destroy();
    }

    // Pointer listener
    const pointer_listener = c.wl_pointer_listener{
        .enter = pointerEnter,
        .leave = pointerLeave,
        .motion = pointerMotion,
        .button = pointerButton,
        .axis = pointerAxis,
        .frame = null,
        .axis_source = null,
        .axis_stop = null,
        .axis_discrete = null,
        .axis_value120 = null,
        .axis_relative_direction = null,
    };

    fn pointerEnter(
        data: ?*anyopaque,
        _: ?*c.wl_pointer,
        serial: u32,
        surface: ?*c.wl_surface,
        x: c.wl_fixed_t,
        y: c.wl_fixed_t,
    ) callconv(.C) void {
        const self: *Self = @ptrCast(@alignCast(data));
        self.pointer_state.surface = surface;
        self.pointer_state.x = fixedToFloat(x);
        self.pointer_state.y = fixedToFloat(y);
        self.pointer_state.serial = serial;

        if (self.on_pointer_enter) |cb| {
            if (surface) |s| cb(s, self.pointer_state.x, self.pointer_state.y, serial);
        }
    }

    fn pointerLeave(
        data: ?*anyopaque,
        _: ?*c.wl_pointer,
        serial: u32,
        surface: ?*c.wl_surface,
    ) callconv(.C) void {
        const self: *Self = @ptrCast(@alignCast(data));

        if (self.on_pointer_leave) |cb| {
            if (surface) |s| cb(s, serial);
        }

        self.pointer_state.surface = null;
        self.pointer_state.serial = serial;
    }

    fn pointerMotion(
        data: ?*anyopaque,
        _: ?*c.wl_pointer,
        _: u32,
        x: c.wl_fixed_t,
        y: c.wl_fixed_t,
    ) callconv(.C) void {
        const self: *Self = @ptrCast(@alignCast(data));
        self.pointer_state.x = fixedToFloat(x);
        self.pointer_state.y = fixedToFloat(y);

        if (self.on_pointer_motion) |cb| {
            cb(self.pointer_state.x, self.pointer_state.y);
        }
    }

    fn pointerButton(
        data: ?*anyopaque,
        _: ?*c.wl_pointer,
        serial: u32,
        _: u32,
        button: u32,
        state: u32,
    ) callconv(.C) void {
        const self: *Self = @ptrCast(@alignCast(data));
        const pressed = state == 1;

        if (pressed) {
            self.pointer_state.buttons |= @as(u32, 1) << @intCast(button & 0x1F);
        } else {
            self.pointer_state.buttons &= ~(@as(u32, 1) << @intCast(button & 0x1F));
        }
        self.pointer_state.serial = serial;

        if (self.on_pointer_button) |cb| {
            cb(button, pressed, serial);
        }
    }

    fn pointerAxis(
        data: ?*anyopaque,
        _: ?*c.wl_pointer,
        _: u32,
        axis: u32,
        value: c.wl_fixed_t,
    ) callconv(.C) void {
        const self: *Self = @ptrCast(@alignCast(data));
        const v = fixedToFloat(value);

        if (self.on_pointer_scroll) |cb| {
            if (axis == 0) {
                cb(0, v); // Vertical scroll
            } else {
                cb(v, 0); // Horizontal scroll
            }
        }
    }

    // Keyboard listener
    const keyboard_listener = c.wl_keyboard_listener{
        .keymap = keyboardKeymap,
        .enter = keyboardEnter,
        .leave = keyboardLeave,
        .key = keyboardKey,
        .modifiers = keyboardModifiers,
        .repeat_info = null,
    };

    fn keyboardKeymap(
        _: ?*anyopaque,
        _: ?*c.wl_keyboard,
        _: u32,
        _: i32,
        _: u32,
    ) callconv(.C) void {
        // Keymap handling - we'd typically use xkbcommon here
        // For now, just ignore
    }

    fn keyboardEnter(
        data: ?*anyopaque,
        _: ?*c.wl_keyboard,
        serial: u32,
        surface: ?*c.wl_surface,
        _: ?*c.wl_array,
    ) callconv(.C) void {
        const self: *Self = @ptrCast(@alignCast(data));
        self.keyboard_state.surface = surface;
        self.keyboard_state.serial = serial;

        if (self.on_keyboard_enter) |cb| {
            if (surface) |s| cb(s, serial);
        }
    }

    fn keyboardLeave(
        data: ?*anyopaque,
        _: ?*c.wl_keyboard,
        serial: u32,
        surface: ?*c.wl_surface,
    ) callconv(.C) void {
        const self: *Self = @ptrCast(@alignCast(data));

        if (self.on_keyboard_leave) |cb| {
            if (surface) |s| cb(s, serial);
        }

        self.keyboard_state.surface = null;
        self.keyboard_state.serial = serial;
    }

    fn keyboardKey(
        data: ?*anyopaque,
        _: ?*c.wl_keyboard,
        serial: u32,
        _: u32,
        key: u32,
        state: u32,
    ) callconv(.C) void {
        const self: *Self = @ptrCast(@alignCast(data));
        const pressed = state == 1;
        self.keyboard_state.serial = serial;

        if (self.on_keyboard_key) |cb| {
            cb(key, pressed, serial);
        }
    }

    fn keyboardModifiers(
        data: ?*anyopaque,
        _: ?*c.wl_keyboard,
        _: u32,
        mods_depressed: u32,
        mods_latched: u32,
        mods_locked: u32,
        _: u32,
    ) callconv(.C) void {
        const self: *Self = @ptrCast(@alignCast(data));
        self.keyboard_state.modifiers = Modifiers.fromMods(mods_depressed, mods_latched, mods_locked);

        if (self.on_keyboard_modifiers) |cb| {
            cb(self.keyboard_state.modifiers);
        }
    }
};

/// Convert Wayland fixed-point to float
fn fixedToFloat(fixed: c.wl_fixed_t) f32 {
    return @as(f32, @floatFromInt(fixed)) / 256.0;
}

/// Mouse button codes
pub const MouseButton = struct {
    pub const left: u32 = 272;
    pub const right: u32 = 273;
    pub const middle: u32 = 274;
};

/// Common key codes
pub const KeyCode = struct {
    pub const escape: u32 = 1;
    pub const enter: u32 = 28;
    pub const space: u32 = 57;
    pub const tab: u32 = 15;
    pub const backspace: u32 = 14;
    pub const up: u32 = 103;
    pub const down: u32 = 108;
    pub const left: u32 = 105;
    pub const right: u32 = 106;
};

