//! GTK4 C bindings wrapper
//! Minimal bindings for the GUI panel
const std = @import("std");
const builtin = @import("builtin");

// Only import GTK on Linux
const c = if (builtin.os.tag == .linux) @cImport({
    @cInclude("gtk/gtk.h");
}) else struct {};

pub const GtkWidget = if (builtin.os.tag == .linux) *c.GtkWidget else *anyopaque;
pub const GtkWindow = if (builtin.os.tag == .linux) *c.GtkWindow else *anyopaque;
pub const GtkApplication = if (builtin.os.tag == .linux) *c.GtkApplication else *anyopaque;
pub const GtkBuilder = if (builtin.os.tag == .linux) *c.GtkBuilder else *anyopaque;

pub const GCallback = *const fn () callconv(.c) void;

/// Check if GTK is available
pub fn isAvailable() bool {
    return builtin.os.tag == .linux;
}

/// Initialize GTK
pub fn init() bool {
    if (builtin.os.tag != .linux) return false;
    return c.gtk_init_check() != 0;
}

/// Create a new application
pub fn applicationNew(app_id: [*c]const u8, flags: u32) ?GtkApplication {
    if (builtin.os.tag != .linux) return null;
    return @ptrCast(c.gtk_application_new(app_id, @enumFromInt(flags)));
}

/// Run the application
pub fn applicationRun(app: GtkApplication, argc: c_int, argv: [*c][*c]u8) c_int {
    if (builtin.os.tag != .linux) return 1;
    return c.g_application_run(@ptrCast(app), argc, argv);
}

/// Unref a GObject
pub fn objectUnref(obj: anytype) void {
    if (builtin.os.tag != .linux) return;
    c.g_object_unref(@ptrCast(obj));
}

/// Create a new window
pub fn applicationWindowNew(app: GtkApplication) ?GtkWidget {
    if (builtin.os.tag != .linux) return null;
    return c.gtk_application_window_new(@ptrCast(app));
}

/// Set window title
pub fn windowSetTitle(window: GtkWidget, title: [*c]const u8) void {
    if (builtin.os.tag != .linux) return;
    c.gtk_window_set_title(@ptrCast(window), title);
}

/// Set default window size
pub fn windowSetDefaultSize(window: GtkWidget, width: c_int, height: c_int) void {
    if (builtin.os.tag != .linux) return;
    c.gtk_window_set_default_size(@ptrCast(window), width, height);
}

/// Create a box container
pub fn boxNew(orientation: Orientation, spacing: c_int) ?GtkWidget {
    if (builtin.os.tag != .linux) return null;
    return c.gtk_box_new(@intFromEnum(orientation), spacing);
}

pub const Orientation = enum(c_int) {
    horizontal = 0,
    vertical = 1,
};

/// Append a widget to a box
pub fn boxAppend(box: GtkWidget, child: GtkWidget) void {
    if (builtin.os.tag != .linux) return;
    c.gtk_box_append(@ptrCast(box), child);
}

/// Create a label
pub fn labelNew(text: [*c]const u8) ?GtkWidget {
    if (builtin.os.tag != .linux) return null;
    return c.gtk_label_new(text);
}

/// Set label text
pub fn labelSetText(label: GtkWidget, text: [*c]const u8) void {
    if (builtin.os.tag != .linux) return;
    c.gtk_label_set_text(@ptrCast(label), text);
}

/// Create a button with label
pub fn buttonNewWithLabel(label: [*c]const u8) ?GtkWidget {
    if (builtin.os.tag != .linux) return null;
    return c.gtk_button_new_with_label(label);
}

/// Create a scale (slider)
pub fn scaleNewWithRange(orientation: Orientation, min: f64, max: f64, step: f64) ?GtkWidget {
    if (builtin.os.tag != .linux) return null;
    return c.gtk_scale_new_with_range(@intFromEnum(orientation), min, max, step);
}

/// Get scale value
pub fn rangeGetValue(range: GtkWidget) f64 {
    if (builtin.os.tag != .linux) return 0;
    return c.gtk_range_get_value(@ptrCast(range));
}

/// Set scale value
pub fn rangeSetValue(range: GtkWidget, value: f64) void {
    if (builtin.os.tag != .linux) return;
    c.gtk_range_set_value(@ptrCast(range), value);
}

/// Create a dropdown
pub fn dropDownNewFromStrings(strings: [*c][*c]const u8) ?GtkWidget {
    if (builtin.os.tag != .linux) return null;
    return c.gtk_drop_down_new_from_strings(strings);
}

/// Get selected dropdown item
pub fn dropDownGetSelected(dropdown: GtkWidget) u32 {
    if (builtin.os.tag != .linux) return 0;
    return c.gtk_drop_down_get_selected(@ptrCast(dropdown));
}

/// Set selected dropdown item
pub fn dropDownSetSelected(dropdown: GtkWidget, position: u32) void {
    if (builtin.os.tag != .linux) return;
    c.gtk_drop_down_set_selected(@ptrCast(dropdown), position);
}

/// Create a switch (toggle)
pub fn switchNew() ?GtkWidget {
    if (builtin.os.tag != .linux) return null;
    return c.gtk_switch_new();
}

/// Get switch state
pub fn switchGetActive(sw: GtkWidget) bool {
    if (builtin.os.tag != .linux) return false;
    return c.gtk_switch_get_active(@ptrCast(sw)) != 0;
}

/// Set switch state
pub fn switchSetActive(sw: GtkWidget, active: bool) void {
    if (builtin.os.tag != .linux) return;
    c.gtk_switch_set_active(@ptrCast(sw), if (active) 1 else 0);
}

/// Set widget child
pub fn windowSetChild(window: GtkWidget, child: GtkWidget) void {
    if (builtin.os.tag != .linux) return;
    c.gtk_window_set_child(@ptrCast(window), child);
}

/// Show widget
pub fn widgetSetVisible(widget: GtkWidget, visible: bool) void {
    if (builtin.os.tag != .linux) return;
    c.gtk_widget_set_visible(widget, if (visible) 1 else 0);
}

/// Set widget margin
pub fn widgetSetMarginAll(widget: GtkWidget, margin: c_int) void {
    if (builtin.os.tag != .linux) return;
    c.gtk_widget_set_margin_start(widget, margin);
    c.gtk_widget_set_margin_end(widget, margin);
    c.gtk_widget_set_margin_top(widget, margin);
    c.gtk_widget_set_margin_bottom(widget, margin);
}

/// Set widget horizontal expand
pub fn widgetSetHexpand(widget: GtkWidget, expand: bool) void {
    if (builtin.os.tag != .linux) return;
    c.gtk_widget_set_hexpand(widget, if (expand) 1 else 0);
}

/// Connect a signal
pub fn signalConnect(
    instance: anytype,
    signal: [*c]const u8,
    callback: GCallback,
    data: ?*anyopaque,
) u64 {
    if (builtin.os.tag != .linux) return 0;
    return c.g_signal_connect_data(
        @ptrCast(instance),
        signal,
        @ptrCast(callback),
        data,
        null,
        0,
    );
}

/// Main loop iteration (for non-blocking updates)
pub fn mainContextIteration(may_block: bool) bool {
    if (builtin.os.tag != .linux) return false;
    return c.g_main_context_iteration(null, if (may_block) 1 else 0) != 0;
}
