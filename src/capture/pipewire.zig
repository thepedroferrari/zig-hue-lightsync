//! PipeWire C bindings wrapper
//! Minimal bindings for screen capture frame processing
const std = @import("std");

// C library imports
const c = @cImport({
    @cInclude("pipewire/pipewire.h");
    @cInclude("spa/param/video/format-utils.h");
    @cInclude("spa/debug/types.h");
    @cInclude("spa/param/video/type-info.h");
});

// Re-export types
pub const MainLoop = c.pw_main_loop;
pub const Context = c.pw_context;
pub const Core = c.pw_core;
pub const Stream = c.pw_stream;
pub const Buffer = c.pw_buffer;
pub const Properties = c.pw_properties;

// Video format info
pub const VideoFormat = enum(u32) {
    unknown = c.SPA_VIDEO_FORMAT_UNKNOWN,
    rgba = c.SPA_VIDEO_FORMAT_RGBA,
    rgbx = c.SPA_VIDEO_FORMAT_RGBx,
    bgra = c.SPA_VIDEO_FORMAT_BGRA,
    bgrx = c.SPA_VIDEO_FORMAT_BGRx,
    rgb = c.SPA_VIDEO_FORMAT_RGB,
    bgr = c.SPA_VIDEO_FORMAT_BGR,
};

pub const StreamState = enum(c_int) {
    unconnected = c.PW_STREAM_STATE_UNCONNECTED,
    connecting = c.PW_STREAM_STATE_CONNECTING,
    paused = c.PW_STREAM_STATE_PAUSED,
    streaming = c.PW_STREAM_STATE_STREAMING,
    @"error" = c.PW_STREAM_STATE_ERROR,
};

pub const Frame = struct {
    data: []const u8,
    width: u32,
    height: u32,
    stride: u32,
    format: VideoFormat,
};

pub const StreamEvents = struct {
    on_process: ?*const fn (*anyopaque) void = null,
    on_state_changed: ?*const fn (*anyopaque, StreamState, StreamState) void = null,
    on_param_changed: ?*const fn (*anyopaque, u32, ?*const anyopaque) void = null,
    user_data: ?*anyopaque = null,
};

/// Initialize PipeWire library
pub fn init() void {
    c.pw_init(null, null);
}

/// Deinitialize PipeWire library
pub fn deinit() void {
    c.pw_deinit();
}

/// Create a new main loop
pub fn mainLoopNew() ?*MainLoop {
    return c.pw_main_loop_new(null);
}

/// Destroy main loop
pub fn mainLoopDestroy(loop: *MainLoop) void {
    c.pw_main_loop_destroy(loop);
}

/// Get the loop from main loop
pub fn mainLoopGetLoop(loop: *MainLoop) *c.pw_loop {
    return c.pw_main_loop_get_loop(loop);
}

/// Run the main loop
pub fn mainLoopRun(loop: *MainLoop) void {
    _ = c.pw_main_loop_run(loop);
}

/// Quit the main loop
pub fn mainLoopQuit(loop: *MainLoop) void {
    _ = c.pw_main_loop_quit(loop);
}

/// Create a new context
pub fn contextNew(loop: *c.pw_loop, properties: ?*Properties) ?*Context {
    return c.pw_context_new(loop, properties, 0);
}

/// Destroy context
pub fn contextDestroy(ctx: *Context) void {
    c.pw_context_destroy(ctx);
}

/// Connect to the PipeWire daemon
pub fn contextConnect(ctx: *Context, properties: ?*Properties) ?*Core {
    return c.pw_context_connect(ctx, properties, 0);
}

/// Create new properties
pub fn propertiesNew(key: ?[*c]const u8, value: ?[*c]const u8) ?*Properties {
    return c.pw_properties_new(key, value, null);
}

/// Set a property
pub fn propertiesSet(props: *Properties, key: [*c]const u8, value: [*c]const u8) c_int {
    return c.pw_properties_set(props, key, value);
}

/// Destroy properties
pub fn propertiesFree(props: *Properties) void {
    c.pw_properties_free(props);
}

/// Screen capture stream handler
pub const CaptureStream = struct {
    allocator: std.mem.Allocator,
    main_loop: ?*MainLoop = null,
    context: ?*Context = null,
    core: ?*Core = null,
    stream: ?*Stream = null,
    format: VideoFormat = .unknown,
    width: u32 = 0,
    height: u32 = 0,
    stride: u32 = 0,

    // Callback for frame processing
    frame_callback: ?*const fn (Frame) void = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        pipewire.init();
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.stream) |stream| {
            c.pw_stream_destroy(stream);
        }
        if (self.core) |core| {
            c.pw_core_disconnect(core);
        }
        if (self.context) |ctx| {
            contextDestroy(ctx);
        }
        if (self.main_loop) |loop| {
            mainLoopDestroy(loop);
        }
        pipewire.deinit();
    }

    /// Connect to a PipeWire stream by node ID (from portal)
    pub fn connectToNode(self: *Self, node_id: u32) !void {
        self.main_loop = mainLoopNew() orelse return error.InitFailed;
        const loop = mainLoopGetLoop(self.main_loop.?);

        self.context = contextNew(loop, null) orelse return error.InitFailed;
        self.core = contextConnect(self.context.?, null) orelse return error.ConnectionFailed;

        // Create stream properties
        var props = propertiesNew("media.type", "Video") orelse return error.InitFailed;
        _ = propertiesSet(props, "media.category", "Capture");
        _ = propertiesSet(props, "media.role", "Screen");

        // Create the stream
        self.stream = c.pw_stream_new(self.core.?, "zig-hue-capture", props);
        if (self.stream == null) return error.StreamCreationFailed;

        // Set up stream events
        // Note: In real implementation, we'd set up proper callbacks here

        // Build format parameters - prefer RGB formats
        var params: [1][*c]const c.spa_pod = undefined;
        var buffer: [1024]u8 = undefined;
        var builder = c.spa_pod_builder{
            .data = &buffer,
            .size = buffer.len,
            ._padding = undefined,
            .state = c.spa_pod_builder_state{
                .offset = 0,
                .flags = 0,
                .frame = null,
            },
            .callbacks = c.spa_callbacks{ .funcs = null, .data = null },
        };

        // This would build proper video format params
        // Simplified for now - full implementation would enumerate formats
        _ = params;
        _ = builder;

        // Connect to the stream
        _ = c.pw_stream_connect(
            self.stream.?,
            c.PW_DIRECTION_INPUT,
            node_id,
            c.PW_STREAM_FLAG_AUTOCONNECT | c.PW_STREAM_FLAG_MAP_BUFFERS,
            null,
            0,
        );
    }

    /// Start capturing frames
    pub fn start(self: *Self) void {
        if (self.main_loop) |loop| {
            mainLoopRun(loop);
        }
    }

    /// Stop capturing
    pub fn stop(self: *Self) void {
        if (self.main_loop) |loop| {
            mainLoopQuit(loop);
        }
    }

    /// Set the frame callback
    pub fn setFrameCallback(self: *Self, callback: *const fn (Frame) void) void {
        self.frame_callback = callback;
    }

    /// Process a single frame (called from PipeWire callback)
    pub fn processFrame(self: *Self) ?Frame {
        if (self.stream == null) return null;

        const buffer = c.pw_stream_dequeue_buffer(self.stream.?);
        if (buffer == null) return null;
        defer c.pw_stream_queue_buffer(self.stream.?, buffer);

        const spa_buffer = buffer.*.buffer;
        if (spa_buffer == null) return null;

        const data = spa_buffer.*.datas;
        if (data == null or data[0].data == null) return null;

        const frame_data: [*]const u8 = @ptrCast(data[0].data.?);
        const frame_size = data[0].chunk.*.size;

        return Frame{
            .data = frame_data[0..frame_size],
            .width = self.width,
            .height = self.height,
            .stride = self.stride,
            .format = self.format,
        };
    }
};

// Module-level reference for the pipewire namespace
const pipewire = @This();
