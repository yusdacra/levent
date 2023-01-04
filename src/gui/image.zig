const std = @import("std");
const zgpu = @import("zgpu");
const zstbi = @import("zstbi");

const assert = std.debug.assert;

pub const ImageId = u128;

pub fn image_id_to_str(id: ImageId) [:0]const u8 {
    var buf: [40:0]u8 = undefined;
    return std.fmt.bufPrintZ(&buf, "{}", .{id}) catch unreachable;
}

pub fn scale_image_size(scale: f32, width: u32, height: u32) [2]f32 {
    assert(scale != 0.0);
    assert(width != 0);
    assert(height != 0);

    const w = @intToFloat(f32, width);
    const h = @intToFloat(f32, height);

    const ratio = w / h;
    const new_width = w * scale;
    const new_height = new_width / ratio;

    return .{ new_width, new_height };
}

pub inline fn hash_image_data(data: []const u8) ImageId {
    return std.hash.Fnv1a_128.hash(data);
}

pub const ImageHandle = struct {
    texture: zgpu.TextureViewHandle,
    width: u32,
    height: u32,
    id: ImageId,

    pub inline fn scaled_size(self: *const ImageHandle, scale: f32) [2]f32 {
        return scale_image_size(scale, self.width, self.height);
    }

    pub inline fn fit_to_width_size(self: *const ImageHandle, width: u32) [2]f32 {
        return self.scaled_size(@intToFloat(f32, width) / @intToFloat(f32, self.width));
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
        .id = hash_image_data(image.data),
    };
}

const InternalImageMap = std.AutoHashMap(ImageId, ImageHandle);
pub const ImageMap = struct {
    map: InternalImageMap,

    pub inline fn add(self: *ImageMap, handle: ImageHandle) void {
        self.map.put(handle.id, handle) catch std.debug.panic("couldn't allocate", .{});
    }

    pub fn load(self: *ImageMap, gctx: *zgpu.GraphicsContext, image_path: [:0]const u8) !ImageId {
        const handle = try load_image(gctx, image_path);
        defer self.add(handle);
        return handle.id;
    }

    pub fn get(self: *const ImageMap, id: ImageId) ?ImageHandle {
        return self.map.get(id);
    }

    pub fn deinit(self: *ImageMap) void {
        self.map.deinit();
    }
};

pub fn create_image_map(allocator: std.mem.Allocator) ImageMap {
    const hashmap = InternalImageMap.init(allocator);
    return ImageMap{
        .map = hashmap,
    };
}
