const std = @import("std");
const zgpu = @import("zgpu");
const zstbi = @import("zstbi");

pub fn scale_image_size(scale: f32, width: u32, height: u32) [2]f32 {
    const w = @intToFloat(f32, width);
    const h = @intToFloat(f32, height);

    const ratio = w / h;
    const new_width = w * scale;
    const new_height = new_width / ratio;

    return .{ new_width, new_height };
}

pub const ImageHandle = struct {
    texture: zgpu.TextureViewHandle,
    width: u32,
    height: u32,

    pub inline fn scaled_size(self: *const ImageHandle, scale: f32) [2]f32 {
        return scale_image_size(scale, self.width, self.height);
    }
};

// this function assumes zstbi is initialized.
pub fn load_image(gctx: *zgpu.GraphicsContext, image_path: [:0]const u8) !ImageHandle {
    var image = try zstbi.Image.init(image_path, 4);
    defer image.deinit();

    // Create a texture.
    const texture = gctx.createTexture(.{
        .usage = .{ .texture_binding = true, .copy_dst = true },
        .size = .{
            .width = image.width,
            .height = image.height,
            .depth_or_array_layers = 1,
        },
        .format = zgpu.imageInfoToTextureFormat(
            image.num_components,
            image.bytes_per_component,
            image.is_hdr,
        ),
        .mip_level_count = 1,
    });
    const texture_view = gctx.createTextureView(texture, .{});

    // TODO: we actuall need to destroy these textures after we stop using them
    gctx.queue.writeTexture(
        .{ .texture = gctx.lookupResource(texture).? },
        .{
            .bytes_per_row = image.bytes_per_row,
            .rows_per_image = image.height,
        },
        .{ .width = image.width, .height = image.height },
        u8,
        image.data,
    );

    return ImageHandle{
        .texture = texture_view,
        .width = image.width,
        .height = image.height,
    };
}

pub const ImageMap = struct {
    map: std.StringHashMap(ImageHandle),

    pub inline fn add(self: *ImageMap, id: []const u8, handle: ImageHandle) void {
        self.map.put(id, handle) catch std.debug.panic("couldn't allocate", .{});
    }

    pub fn load(self: *ImageMap, gctx: *zgpu.GraphicsContext, id: []const u8, image_path: [:0]const u8) !void {
        const handle = try load_image(gctx, image_path);
        self.add(id, handle);
    }

    pub fn get(self: *const ImageMap, id: []const u8) ?ImageHandle {
        return self.map.get(id);
    }

    pub fn deinit(self: *ImageMap) void {
        self.map.deinit();
    }
};

pub fn create_image_map(allocator: std.mem.Allocator) ImageMap {
    const hashmap = std.StringHashMap(ImageHandle).init(allocator);
    return ImageMap{
        .map = hashmap,
    };
}
