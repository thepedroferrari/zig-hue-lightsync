//! Wayland client bindings for zig-hue-lightsync
//! Pure Zig wrappers around libwayland-client
//!
//! This module provides the core Wayland protocol handling:
//! - Display connection management
//! - Registry and global object binding
//! - Event loop integration

const std = @import("std");
const builtin = @import("builtin");

/// Raw C bindings to libwayland-client
pub const c = @cImport({
    @cInclude("wayland-client.h");
    @cInclude("wayland-client-protocol.h");
});

/// Wayland display connection
pub const Display = struct {
    ptr: *c.wl_display,

    const Self = @This();

    /// Connect to the default Wayland display
    pub fn connect() !Self {
        const display = c.wl_display_connect(null) orelse {
            return error.ConnectionFailed;
        };
        return .{ .ptr = display };
    }

    /// Connect to a specific Wayland display
    pub fn connectTo(name: [*:0]const u8) !Self {
        const display = c.wl_display_connect(name) orelse {
            return error.ConnectionFailed;
        };
        return .{ .ptr = display };
    }

    /// Disconnect from the display
    pub fn disconnect(self: *Self) void {
        c.wl_display_disconnect(self.ptr);
    }

    /// Get the file descriptor for polling
    pub fn getFd(self: *const Self) i32 {
        return c.wl_display_get_fd(self.ptr);
    }

    /// Dispatch events (blocking)
    pub fn dispatch(self: *Self) !void {
        const result = c.wl_display_dispatch(self.ptr);
        if (result < 0) return error.DispatchFailed;
    }

    /// Dispatch pending events (non-blocking)
    pub fn dispatchPending(self: *Self) !void {
        const result = c.wl_display_dispatch_pending(self.ptr);
        if (result < 0) return error.DispatchFailed;
    }

    /// Flush outgoing requests
    pub fn flush(self: *Self) !void {
        const result = c.wl_display_flush(self.ptr);
        if (result < 0) return error.FlushFailed;
    }

    /// Roundtrip - flush and wait for all pending requests to be processed
    pub fn roundtrip(self: *Self) !void {
        const result = c.wl_display_roundtrip(self.ptr);
        if (result < 0) return error.RoundtripFailed;
    }

    /// Get the registry
    pub fn getRegistry(self: *Self) !Registry {
        const registry = c.wl_display_get_registry(self.ptr) orelse {
            return error.RegistryFailed;
        };
        return .{ .ptr = registry };
    }
};

/// Wayland registry for binding global objects
pub const Registry = struct {
    ptr: *c.wl_registry,

    const Self = @This();

    /// Add a listener for registry events
    pub fn addListener(self: *Self, listener: *const c.wl_registry_listener, data: ?*anyopaque) void {
        _ = c.wl_registry_add_listener(self.ptr, listener, data);
    }

    /// Bind a global object
    pub fn bind(self: *Self, name: u32, interface: *const c.wl_interface, version: u32) ?*anyopaque {
        return c.wl_registry_bind(self.ptr, name, interface, version);
    }

    /// Destroy the registry
    pub fn destroy(self: *Self) void {
        c.wl_registry_destroy(self.ptr);
    }
};

/// Wayland compositor
pub const Compositor = struct {
    ptr: *c.wl_compositor,

    const Self = @This();

    /// Create a new surface
    pub fn createSurface(self: *Self) !Surface {
        const surface = c.wl_compositor_create_surface(self.ptr) orelse {
            return error.SurfaceCreationFailed;
        };
        return .{ .ptr = surface };
    }

    /// Create a new region
    pub fn createRegion(self: *Self) !Region {
        const region = c.wl_compositor_create_region(self.ptr) orelse {
            return error.RegionCreationFailed;
        };
        return .{ .ptr = region };
    }
};

/// Wayland surface
pub const Surface = struct {
    ptr: *c.wl_surface,

    const Self = @This();

    /// Attach a buffer to the surface
    pub fn attach(self: *Self, buffer: ?*c.wl_buffer, x: i32, y: i32) void {
        c.wl_surface_attach(self.ptr, buffer, x, y);
    }

    /// Mark the entire surface as damaged
    pub fn damage(self: *Self, x: i32, y: i32, width: i32, height: i32) void {
        c.wl_surface_damage(self.ptr, x, y, width, height);
    }

    /// Mark the entire surface as damaged (buffer coordinates)
    pub fn damageBuffer(self: *Self, x: i32, y: i32, width: i32, height: i32) void {
        c.wl_surface_damage_buffer(self.ptr, x, y, width, height);
    }

    /// Commit pending changes
    pub fn commit(self: *Self) void {
        c.wl_surface_commit(self.ptr);
    }

    /// Set input region
    pub fn setInputRegion(self: *Self, region: ?*c.wl_region) void {
        c.wl_surface_set_input_region(self.ptr, region);
    }

    /// Set opaque region
    pub fn setOpaqueRegion(self: *Self, region: ?*c.wl_region) void {
        c.wl_surface_set_opaque_region(self.ptr, region);
    }

    /// Add a frame callback
    pub fn frame(self: *Self) ?*c.wl_callback {
        return c.wl_surface_frame(self.ptr);
    }

    /// Destroy the surface
    pub fn destroy(self: *Self) void {
        c.wl_surface_destroy(self.ptr);
    }
};

/// Wayland region
pub const Region = struct {
    ptr: *c.wl_region,

    const Self = @This();

    /// Add a rectangle to the region
    pub fn add(self: *Self, x: i32, y: i32, width: i32, height: i32) void {
        c.wl_region_add(self.ptr, x, y, width, height);
    }

    /// Subtract a rectangle from the region
    pub fn subtract(self: *Self, x: i32, y: i32, width: i32, height: i32) void {
        c.wl_region_subtract(self.ptr, x, y, width, height);
    }

    /// Destroy the region
    pub fn destroy(self: *Self) void {
        c.wl_region_destroy(self.ptr);
    }
};

/// Shared memory pool for creating buffers
pub const ShmPool = struct {
    ptr: *c.wl_shm_pool,
    fd: std.posix.fd_t,
    data: []align(4096) u8,
    size: usize,

    const Self = @This();

    /// Create a shared memory pool
    pub fn create(shm: *c.wl_shm, size: usize) !Self {
        // Create anonymous file
        const fd = try std.posix.memfd_create("zig-hue-shm", .{});
        errdefer std.posix.close(fd);

        // Resize to requested size
        try std.posix.ftruncate(fd, @intCast(size));

        // Memory map
        const data = try std.posix.mmap(
            null,
            size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .SHARED },
            fd,
            0,
        );

        // Create Wayland pool
        const pool = c.wl_shm_create_pool(shm, fd, @intCast(size)) orelse {
            return error.PoolCreationFailed;
        };

        return .{
            .ptr = pool,
            .fd = fd,
            .data = @alignCast(data),
            .size = size,
        };
    }

    /// Create a buffer from this pool
    pub fn createBuffer(
        self: *Self,
        offset: i32,
        width: i32,
        height: i32,
        stride: i32,
        format: u32,
    ) !Buffer {
        const buffer = c.wl_shm_pool_create_buffer(
            self.ptr,
            offset,
            width,
            height,
            stride,
            format,
        ) orelse {
            return error.BufferCreationFailed;
        };
        return .{ .ptr = buffer };
    }

    /// Resize the pool
    pub fn resize(self: *Self, new_size: usize) !void {
        try std.posix.ftruncate(self.fd, @intCast(new_size));
        c.wl_shm_pool_resize(self.ptr, @intCast(new_size));
        self.size = new_size;
    }

    /// Destroy the pool
    pub fn destroy(self: *Self) void {
        c.wl_shm_pool_destroy(self.ptr);
        std.posix.munmap(self.data);
        std.posix.close(self.fd);
    }
};

/// Wayland buffer
pub const Buffer = struct {
    ptr: *c.wl_buffer,

    const Self = @This();

    /// Add a listener for buffer events
    pub fn addListener(self: *Self, listener: *const c.wl_buffer_listener, data: ?*anyopaque) void {
        _ = c.wl_buffer_add_listener(self.ptr, listener, data);
    }

    /// Destroy the buffer
    pub fn destroy(self: *Self) void {
        c.wl_buffer_destroy(self.ptr);
    }
};

/// SHM formats
pub const ShmFormat = enum(u32) {
    argb8888 = c.WL_SHM_FORMAT_ARGB8888,
    xrgb8888 = c.WL_SHM_FORMAT_XRGB8888,
    rgb888 = c.WL_SHM_FORMAT_RGB888,
    bgr888 = c.WL_SHM_FORMAT_BGR888,
    _,
};

/// Wayland seat (input devices)
pub const Seat = struct {
    ptr: *c.wl_seat,

    const Self = @This();

    /// Add a listener for seat events
    pub fn addListener(self: *Self, listener: *const c.wl_seat_listener, data: ?*anyopaque) void {
        _ = c.wl_seat_add_listener(self.ptr, listener, data);
    }

    /// Get the pointer device
    pub fn getPointer(self: *Self) ?Pointer {
        const ptr = c.wl_seat_get_pointer(self.ptr) orelse return null;
        return .{ .ptr = ptr };
    }

    /// Get the keyboard device
    pub fn getKeyboard(self: *Self) ?Keyboard {
        const ptr = c.wl_seat_get_keyboard(self.ptr) orelse return null;
        return .{ .ptr = ptr };
    }

    /// Destroy the seat
    pub fn destroy(self: *Self) void {
        c.wl_seat_destroy(self.ptr);
    }
};

/// Wayland pointer
pub const Pointer = struct {
    ptr: *c.wl_pointer,

    const Self = @This();

    /// Add a listener for pointer events
    pub fn addListener(self: *Self, listener: *const c.wl_pointer_listener, data: ?*anyopaque) void {
        _ = c.wl_pointer_add_listener(self.ptr, listener, data);
    }

    /// Set the cursor
    pub fn setCursor(self: *Self, serial: u32, surface: ?*c.wl_surface, hotspot_x: i32, hotspot_y: i32) void {
        c.wl_pointer_set_cursor(self.ptr, serial, surface, hotspot_x, hotspot_y);
    }

    /// Destroy the pointer
    pub fn destroy(self: *Self) void {
        c.wl_pointer_destroy(self.ptr);
    }
};

/// Wayland keyboard
pub const Keyboard = struct {
    ptr: *c.wl_keyboard,

    const Self = @This();

    /// Add a listener for keyboard events
    pub fn addListener(self: *Self, listener: *const c.wl_keyboard_listener, data: ?*anyopaque) void {
        _ = c.wl_keyboard_add_listener(self.ptr, listener, data);
    }

    /// Destroy the keyboard
    pub fn destroy(self: *Self) void {
        c.wl_keyboard_destroy(self.ptr);
    }
};

/// Output (monitor)
pub const Output = struct {
    ptr: *c.wl_output,

    const Self = @This();

    /// Add a listener for output events
    pub fn addListener(self: *Self, listener: *const c.wl_output_listener, data: ?*anyopaque) void {
        _ = c.wl_output_add_listener(self.ptr, listener, data);
    }

    /// Destroy the output
    pub fn destroy(self: *Self) void {
        c.wl_output_destroy(self.ptr);
    }
};

/// Check if we're running on Wayland
pub fn isWaylandSession() bool {
    return std.posix.getenv("WAYLAND_DISPLAY") != null;
}

test "wayland session detection" {
    // This just tests that the function compiles
    _ = isWaylandSession();
}

