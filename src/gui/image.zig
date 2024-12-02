const std = @import("std");
const zgpu = @import("zgpu");
const zstbi = @import("zstbi");

const assert = std.debug.assert;

pub const id = struct {
    pub const ImageId = u128;
    pub const ImageIdStrBuf = [40]u8;

    pub inline fn new_str_buf() ImageIdStrBuf {
        return std.mem.zeroes(ImageIdStrBuf);
    }

    pub inline fn to_str(image_id: id.ImageId, buf: *ImageIdStrBuf) [:0]const u8 {
        return std.fmt.bufPrintZ(buf, "{d}", .{image_id}) catch unreachable;
    }

    pub inline fn hash(data: []const u8) id.ImageId {
        return std.hash.Fnv1a_128.hash(data);
    }
};
pub const ImageId = id.ImageId;

pub fn scale_image_size(scale: f32, width: u32, height: u32) [2]f32 {
    assert(scale != 0.0);
    assert(width != 0);
    assert(height != 0);

    const w: f32 = @floatFromInt(width);
    const h: f32 = @floatFromInt(height);

    const ratio = w / h;
    const new_width = w * scale;
    const new_height = new_width / ratio;

    return .{ new_width, new_height };
}

pub fn make_thumbnail(image: *const zstbi.Image) zstbi.Image {
    const max_size = 200;
    const scale = if (image.width > image.height)
        @as(f32, @floatFromInt(max_size)) / @as(f32, @floatFromInt(image.width))
    else
        @as(f32, @floatFromInt(max_size)) / @as(f32, @floatFromInt(image.height));
    const size = scale_image_size(
        scale,
        image.width,
        image.height,
    );
    const thumb = image.resize(
        @intFromFloat(size[0]),
        @intFromFloat(size[1]),
    );
    return thumb;
}

pub const ImageHandle = struct {
    texture: zgpu.TextureViewHandle,
    width: u32,
    height: u32,

    pub inline fn scaled_size(self: *const ImageHandle, scale: f32) [2]f32 {
        return scale_image_size(scale, self.width, self.height);
    }

    pub inline fn fit_to_width_size(self: *const ImageHandle, width: u32) [2]f32 {
        return self.scaled_size(@as(f32, @floatFromInt(width)) / self.widthf());
    }

    pub inline fn fit_to_height_size(self: *const ImageHandle, height: u32) [2]f32 {
        return self.scaled_size(@as(f32, @floatFromInt(height)) / self.heightf());
    }

    pub inline fn widthf(self: *const ImageHandle) f32 {
        return @floatFromInt(self.width);
    }

    pub inline fn heightf(self: *const ImageHandle) f32 {
        return @floatFromInt(self.height);
    }
};

pub fn load_image(gctx: *zgpu.GraphicsContext, image: *const zstbi.Image) ImageHandle {
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

    // TODO: we actually need to destroy these textures after we stop using them
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

const InternalImageMap = std.AutoHashMap(ImageId, ImageHandle);
pub const ImageMap = struct {
    map: InternalImageMap,

    pub inline fn add(self: *ImageMap, image_id: ImageId, handle: ImageHandle) !void {
        try self.map.put(image_id, handle);
    }

    pub fn get(self: *const ImageMap, image_id: ImageId) ?ImageHandle {
        return self.map.get(image_id);
    }

    pub fn has(self: *const ImageMap, image_id: ImageId) bool {
        return self.map.contains(image_id);
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
