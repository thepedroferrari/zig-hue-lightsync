//! Region mapping and frame color extraction
//! Maps screen regions to lights based on entertainment area coordinates
const std = @import("std");
const color = @import("color.zig");

pub const RGB = color.RGB;
pub const LinearRGB = color.LinearRGB;
pub const HueColor = color.HueColor;
pub const Gamut = color.Gamut;
pub const PixelFormat = color.PixelFormat;

/// Screen region mapped to a light
pub const Region = struct {
    /// Light identifier
    light_id: []const u8,
    /// Region bounds (normalized 0-1)
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    /// Color gamut for this light
    gamut: Gamut,
};

/// Light position from entertainment area
pub const LightPosition = struct {
    id: []const u8,
    name: []const u8,
    /// X position (-1 to 1, left to right)
    x: f32,
    /// Y position (-1 to 1, front to back)
    y: f32,
    /// Z position (-1 to 1, bottom to top)
    z: f32,
    /// Color gamut
    gamut: Gamut,
};

/// Frame processor for extracting colors per region
pub const FrameProcessor = struct {
    allocator: std.mem.Allocator,
    regions: []Region,
    screen_width: u32,
    screen_height: u32,

    /// Smoothing state for each region (EMA)
    smooth_state: []LinearRGB,
    smoothing_factor: f32,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .regions = &.{},
            .screen_width = 0,
            .screen_height = 0,
            .smooth_state = &.{},
            .smoothing_factor = 0.5,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.regions) |*region| {
            self.allocator.free(region.light_id);
        }
        self.allocator.free(self.regions);
        self.allocator.free(self.smooth_state);
    }

    /// Set up regions based on light positions
    /// Maps 3D entertainment area coordinates to 2D screen regions
    pub fn setupRegions(self: *Self, lights: []const LightPosition, screen_width: u32, screen_height: u32) !void {
        // Clean up existing regions
        for (self.regions) |*region| {
            self.allocator.free(region.light_id);
        }
        self.allocator.free(self.regions);
        self.allocator.free(self.smooth_state);

        self.screen_width = screen_width;
        self.screen_height = screen_height;

        var regions = std.ArrayList(Region).init(self.allocator);
        errdefer regions.deinit();

        // Calculate region size based on number of lights
        const n_lights = lights.len;
        if (n_lights == 0) {
            self.regions = &.{};
            self.smooth_state = &.{};
            return;
        }

        // Simple approach: divide screen based on light x positions
        // More sophisticated approaches could use Voronoi diagrams
        for (lights) |light| {
            // Map light position (-1 to 1) to screen position (0 to 1)
            const norm_x = (light.x + 1.0) / 2.0;
            const norm_y = (light.y + 1.0) / 2.0;

            // Region size inversely proportional to number of lights
            const region_width = 1.0 / @as(f32, @floatFromInt(n_lights));
            const region_height: f32 = 0.5; // Sample top or bottom half based on y

            try regions.append(.{
                .light_id = try self.allocator.dupe(u8, light.id),
                .x = std.math.clamp(norm_x - region_width / 2, 0.0, 1.0),
                .y = if (norm_y > 0.5) 0.0 else 0.5, // Top or bottom half
                .width = region_width,
                .height = region_height,
                .gamut = light.gamut,
            });
        }

        self.regions = try regions.toOwnedSlice();

        // Initialize smooth state
        self.smooth_state = try self.allocator.alloc(LinearRGB, self.regions.len);
        for (self.smooth_state) |*s| {
            s.* = .{ .r = 0, .g = 0, .b = 0 };
        }
    }

    /// Set smoothing factor (0 = no smoothing, 1 = max smoothing)
    pub fn setSmoothingFactor(self: *Self, factor: f32) void {
        self.smoothing_factor = std.math.clamp(factor, 0.0, 1.0);
    }

    /// Process a frame and extract colors for each region
    pub fn processFrame(
        self: *Self,
        frame_data: []const u8,
        stride: u32,
        format: PixelFormat,
    ) ![]HueColor {
        const bpp = format.bytesPerPixel();
        var colors = try self.allocator.alloc(HueColor, self.regions.len);
        errdefer self.allocator.free(colors);

        for (self.regions, 0..) |region, i| {
            // Calculate pixel bounds
            const start_x: u32 = @intFromFloat(region.x * @as(f32, @floatFromInt(self.screen_width)));
            const start_y: u32 = @intFromFloat(region.y * @as(f32, @floatFromInt(self.screen_height)));
            const end_x: u32 = @intFromFloat((region.x + region.width) * @as(f32, @floatFromInt(self.screen_width)));
            const end_y: u32 = @intFromFloat((region.y + region.height) * @as(f32, @floatFromInt(self.screen_height)));

            // Sample and average colors in linear space
            const avg_linear = self.sampleRegion(
                frame_data,
                stride,
                format,
                bpp,
                start_x,
                start_y,
                end_x,
                end_y,
            );

            // Apply temporal smoothing (EMA)
            const smoothed = if (self.smoothing_factor > 0)
                self.smooth_state[i].blend(avg_linear, 1.0 - self.smoothing_factor)
            else
                avg_linear;

            self.smooth_state[i] = smoothed;

            // Convert to Hue color with gamut clamping
            colors[i] = HueColor.fromLinearRGB(smoothed, region.gamut);
        }

        return colors;
    }

    fn sampleRegion(
        self: *Self,
        frame_data: []const u8,
        stride: u32,
        format: PixelFormat,
        bpp: u8,
        start_x: u32,
        start_y: u32,
        end_x: u32,
        end_y: u32,
    ) LinearRGB {
        _ = self;

        var sum_r: f64 = 0;
        var sum_g: f64 = 0;
        var sum_b: f64 = 0;
        var count: u64 = 0;

        // Sample every nth pixel for performance
        const sample_step: u32 = 4;

        var y = start_y;
        while (y < end_y) : (y += sample_step) {
            const row_start = y * stride;

            var x = start_x;
            while (x < end_x) : (x += sample_step) {
                const pixel_offset = row_start + x * @as(u32, bpp);

                if (pixel_offset + bpp <= frame_data.len) {
                    const rgb = RGB.fromSlice(frame_data[pixel_offset..], format);
                    const linear = rgb.toLinear();

                    sum_r += linear.r;
                    sum_g += linear.g;
                    sum_b += linear.b;
                    count += 1;
                }
            }
        }

        if (count == 0) {
            return .{ .r = 0, .g = 0, .b = 0 };
        }

        const n: f32 = @floatFromInt(count);
        return .{
            .r = @floatCast(sum_r / n),
            .g = @floatCast(sum_g / n),
            .b = @floatCast(sum_b / n),
        };
    }

    /// Get the light IDs in order
    pub fn getLightIds(self: *const Self) []const []const u8 {
        var ids = self.allocator.alloc([]const u8, self.regions.len) catch return &.{};
        for (self.regions, 0..) |region, i| {
            ids[i] = region.light_id;
        }
        return ids;
    }
};

/// Calculate optimal region layout for a set of lights
pub fn calculateOptimalLayout(
    allocator: std.mem.Allocator,
    lights: []const LightPosition,
    screen_aspect: f32,
) ![]Region {
    var regions = std.ArrayList(Region).init(allocator);
    errdefer regions.deinit();

    if (lights.len == 0) return regions.toOwnedSlice();

    // Sort lights by x position for horizontal layout
    const sorted_lights = try allocator.alloc(LightPosition, lights.len);
    defer allocator.free(sorted_lights);
    @memcpy(sorted_lights, lights);

    std.mem.sort(LightPosition, sorted_lights, {}, struct {
        fn lessThan(_: void, a: LightPosition, b: LightPosition) bool {
            return a.x < b.x;
        }
    }.lessThan);

    // Create regions based on sorted positions
    const region_width = 1.0 / @as(f32, @floatFromInt(lights.len));
    _ = screen_aspect;

    for (sorted_lights, 0..) |light, i| {
        const x_start = @as(f32, @floatFromInt(i)) * region_width;

        try regions.append(.{
            .light_id = try allocator.dupe(u8, light.id),
            .x = x_start,
            .y = 0,
            .width = region_width,
            .height = 1.0,
            .gamut = light.gamut,
        });
    }

    return regions.toOwnedSlice();
}

test "frame processor initialization" {
    const allocator = std.testing.allocator;
    var processor = FrameProcessor.init(allocator);
    defer processor.deinit();

    try std.testing.expectEqual(@as(usize, 0), processor.regions.len);
}

test "region setup" {
    const allocator = std.testing.allocator;
    var processor = FrameProcessor.init(allocator);
    defer processor.deinit();

    const lights = [_]LightPosition{
        .{ .id = "1", .name = "Left", .x = -0.5, .y = 0, .z = 0, .gamut = Gamut.C },
        .{ .id = "2", .name = "Right", .x = 0.5, .y = 0, .z = 0, .gamut = Gamut.C },
    };

    try processor.setupRegions(&lights, 1920, 1080);
    try std.testing.expectEqual(@as(usize, 2), processor.regions.len);
}
