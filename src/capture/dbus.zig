//! DBus C bindings wrapper
//! Minimal bindings to libdbus-1 for portal communication
const std = @import("std");

// C library imports
const c = @cImport({
    @cInclude("dbus/dbus.h");
});

// Re-export common types
pub const Connection = c.DBusConnection;
pub const Message = c.DBusMessage;
pub const MessageIter = c.DBusMessageIter;
pub const Error = c.DBusError;

// Type constants
pub const DBUS_TYPE_INVALID = c.DBUS_TYPE_INVALID;
pub const DBUS_TYPE_BYTE = c.DBUS_TYPE_BYTE;
pub const DBUS_TYPE_BOOLEAN = c.DBUS_TYPE_BOOLEAN;
pub const DBUS_TYPE_INT16 = c.DBUS_TYPE_INT16;
pub const DBUS_TYPE_UINT16 = c.DBUS_TYPE_UINT16;
pub const DBUS_TYPE_INT32 = c.DBUS_TYPE_INT32;
pub const DBUS_TYPE_UINT32 = c.DBUS_TYPE_UINT32;
pub const DBUS_TYPE_INT64 = c.DBUS_TYPE_INT64;
pub const DBUS_TYPE_UINT64 = c.DBUS_TYPE_UINT64;
pub const DBUS_TYPE_DOUBLE = c.DBUS_TYPE_DOUBLE;
pub const DBUS_TYPE_STRING = c.DBUS_TYPE_STRING;
pub const DBUS_TYPE_OBJECT_PATH = c.DBUS_TYPE_OBJECT_PATH;
pub const DBUS_TYPE_SIGNATURE = c.DBUS_TYPE_SIGNATURE;
pub const DBUS_TYPE_UNIX_FD = c.DBUS_TYPE_UNIX_FD;
pub const DBUS_TYPE_ARRAY = c.DBUS_TYPE_ARRAY;
pub const DBUS_TYPE_VARIANT = c.DBUS_TYPE_VARIANT;
pub const DBUS_TYPE_STRUCT = c.DBUS_TYPE_STRUCT;
pub const DBUS_TYPE_DICT_ENTRY = c.DBUS_TYPE_DICT_ENTRY;

pub const BusType = enum(c_int) {
    session = c.DBUS_BUS_SESSION,
    system = c.DBUS_BUS_SYSTEM,
    starter = c.DBUS_BUS_STARTER,
};

/// Initialize DBus error structure
pub fn errorInit(err: *Error) void {
    c.dbus_error_init(err);
}

/// Free DBus error resources
pub fn errorFree(err: *Error) void {
    c.dbus_error_free(err);
}

/// Check if error is set
pub fn errorIsSet(err: *const Error) bool {
    return c.dbus_error_is_set(err) != 0;
}

/// Get connection to a well-known bus
pub fn busGet(bus_type: BusType) ?*Connection {
    var err: Error = undefined;
    errorInit(&err);
    defer errorFree(&err);

    const conn = c.dbus_bus_get(@intFromEnum(bus_type), &err);
    if (errorIsSet(&err) or conn == null) {
        return null;
    }
    return conn;
}

/// Get the unique name of the connection
pub fn busGetUniqueName(conn: *Connection) ?[]const u8 {
    const name = c.dbus_bus_get_unique_name(conn);
    if (name == null) return null;
    return std.mem.span(name);
}

/// Decrease the reference count of a connection
pub fn connectionUnref(conn: *Connection) void {
    c.dbus_connection_unref(conn);
}

/// Create a new method call message
pub fn messageNewMethodCall(
    destination: [*c]const u8,
    path: [*c]const u8,
    interface: [*c]const u8,
    method: [*c]const u8,
) ?*Message {
    return c.dbus_message_new_method_call(destination, path, interface, method);
}

/// Decrease the reference count of a message
pub fn messageUnref(msg: *Message) void {
    c.dbus_message_unref(msg);
}

/// Initialize a message iterator for appending
pub fn messageIterInitAppend(msg: *Message, iter: *MessageIter) void {
    c.dbus_message_iter_init_append(msg, iter);
}

/// Initialize a message iterator for reading
pub fn messageIterInit(msg: *Message, iter: *MessageIter) bool {
    return c.dbus_message_iter_init(msg, iter) != 0;
}

/// Get the argument type at current iterator position
pub fn messageIterGetArgType(iter: *MessageIter) c_int {
    return c.dbus_message_iter_get_arg_type(iter);
}

/// Get a basic value from the iterator
pub fn messageIterGetBasic(iter: *MessageIter, value: anytype) void {
    c.dbus_message_iter_get_basic(iter, @ptrCast(value));
}

/// Move to the next argument
pub fn messageIterNext(iter: *MessageIter) bool {
    return c.dbus_message_iter_next(iter) != 0;
}

/// Open a container (array, struct, dict entry, variant)
pub fn messageIterOpenContainer(
    iter: *MessageIter,
    container_type: c_int,
    contained_signature: ?[*c]const u8,
    sub_iter: *MessageIter,
) bool {
    return c.dbus_message_iter_open_container(iter, container_type, contained_signature, sub_iter) != 0;
}

/// Close a container
pub fn messageIterCloseContainer(iter: *MessageIter, sub_iter: *MessageIter) bool {
    return c.dbus_message_iter_close_container(iter, sub_iter) != 0;
}

/// Append a basic value
pub fn messageIterAppendBasic(iter: *MessageIter, arg_type: c_int, value: anytype) bool {
    return c.dbus_message_iter_append_basic(iter, arg_type, @ptrCast(value)) != 0;
}

/// Recurse into a container
pub fn messageIterRecurse(iter: *MessageIter, sub_iter: *MessageIter) void {
    c.dbus_message_iter_recurse(iter, sub_iter);
}

/// Send a message and wait for a reply
pub fn connectionSendWithReply(
    conn: *Connection,
    msg: *Message,
    timeout_ms: c_int,
) ?*Message {
    var err: Error = undefined;
    errorInit(&err);
    defer errorFree(&err);

    const reply = c.dbus_connection_send_with_reply_and_block(conn, msg, timeout_ms, &err);
    if (errorIsSet(&err) or reply == null) {
        return null;
    }
    return reply;
}

/// Add a match rule to receive signals
pub fn busAddMatch(conn: *Connection, rule: [*c]const u8) bool {
    var err: Error = undefined;
    errorInit(&err);
    defer errorFree(&err);

    c.dbus_bus_add_match(conn, rule, &err);
    return !errorIsSet(&err);
}

/// Read write dispatch for processing messages
pub fn connectionReadWriteDispatch(conn: *Connection, timeout_ms: c_int) bool {
    return c.dbus_connection_read_write_dispatch(conn, timeout_ms) != 0;
}

/// Pop a message from the incoming queue
pub fn connectionPopMessage(conn: *Connection) ?*Message {
    return c.dbus_connection_pop_message(conn);
}

/// Get the message type
pub fn messageGetType(msg: *Message) c_int {
    return c.dbus_message_get_type(msg);
}

/// Check if message is a signal
pub fn messageIsSignal(msg: *Message, interface: [*c]const u8, signal_name: [*c]const u8) bool {
    return c.dbus_message_is_signal(msg, interface, signal_name) != 0;
}

/// Get the path from a message
pub fn messageGetPath(msg: *Message) ?[]const u8 {
    const path = c.dbus_message_get_path(msg);
    if (path == null) return null;
    return std.mem.span(path);
}
