const std = @import("std");
const img = @import("./gui/image.zig");

const InternalImagesMap = std.AutoHashMap(img.ImageId, [:0]const u8);
pub const Images = struct {
    map: InternalImagesMap,
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) Images {
        return Images{
            .map = InternalImagesMap.init(alloc),
            .alloc = alloc,
        };
    }

    pub fn from_data(data: []const u8, alloc: std.mem.Allocator) !Images {
        var images = Images.init(alloc);
        errdefer images.deinit();

        // each new line means one item
        var capacity: u32 = 0;
        for (data) |char| {
            if (char == '\n') capacity += 1;
        }
        try images.map.ensureUnusedCapacity(capacity);

        var current_id: ?img.ImageId = null;
        var start: usize = 0;
        var end: usize = 0;
        while (end < data.len) : (end += 1) {
            if (current_id == null and data[end] == ' ') {
                const buf = data[start..end];
                current_id = std.fmt.parseUnsigned(img.ImageId, buf, 10) catch |err| {
                    std.log.err("could not parse ID '{s}': {}", .{ buf, err });
                    return err;
                };
                // start is end + 1 to skip the space char
                start = end + 1;
            } else if (current_id != null and data[end] == '\n') {
                const buf = data[start..end];
                const path = try alloc.dupeZ(u8, buf);
                // this cannot fail since we ensure capacity before
                images.map.put(current_id.?, path) catch unreachable;
                // start is end + 1 to skip the newline
                start = end + 1;
                current_id = null;
            }
        }

        return images;
    }

    pub fn add(self: *Images, image_id: img.ImageId, path: [:0]const u8) !void {
        var result = try self.map.getOrPut(image_id);
        if (result.found_existing) {
            // destroy old path
            self.alloc.destroy(result.value_ptr.*.ptr);
        }
        result.value_ptr.* = path;
    }

    pub fn writeToFile(self: *const Images, file: std.fs.File) !void {
        var writer = file.writer();
        var key_iter = self.map.keyIterator();
        while (key_iter.next()) |key| {
            try writer.print("{d} {s}\n", .{ key.*, self.map.get(key.*).? });
        }
    }

    pub fn deinit(self: *Images) void {
        var value_iter = self.map.valueIterator();
        while (value_iter.next()) |path| {
            self.alloc.destroy(path.ptr);
        }
        self.map.deinit();
    }
};
