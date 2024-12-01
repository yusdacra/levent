const std = @import("std");
const img = @import("./gui/image.zig");

pub const Paths = StrStorage("Paths");
pub const Tags = StrStorage("Tags");

pub fn StrStorage(comptime Id: []const u8) type {
    return struct {
        map: InternalMap,
        alloc: std.mem.Allocator,

        const Key = img.ImageId;
        const Value = [:0]const u8;
        const InternalMap = std.AutoHashMap(Self.Key, Self.Value);

        const Self = @This();
        const StorageId = Id;

        pub fn init(alloc: std.mem.Allocator) Self {
            return Self{
                .map = InternalMap.init(alloc),
                .alloc = alloc,
            };
        }

        pub fn from_data(data: []const u8, alloc: std.mem.Allocator) !Self {
            var self = Self.init(alloc);
            errdefer self.deinit();

            // each new line means one item
            var capacity: u32 = 0;
            for (data) |char| {
                if (char == '\n') capacity += 1;
            }
            try self.map.ensureUnusedCapacity(capacity);

            var current_id: ?Self.Key = null;
            var start: usize = 0;
            var end: usize = 0;
            while (end < data.len) : (end += 1) {
                const is_id_null = current_id == null;
                const has_space = data[end] == ' ';
                const has_newline = data[end] == '\n';
                if (is_id_null and (has_space or has_newline)) {
                    const buf = data[start..end];
                    current_id = std.fmt.parseUnsigned(Self.Key, buf, 10) catch |err| {
                        std.log.err("could not parse ID '{s}': {}", .{ buf, err });
                        return err;
                    };
                    // skip this entry if we didn't get a value
                    if (has_newline) current_id = null;
                    // start is end + 1 to skip the space char
                    start = end + 1;
                } else if (!is_id_null and has_newline) {
                    const buf = data[start..end];
                    const str = try alloc.dupeZ(u8, buf);
                    // this cannot fail since we ensure capacity before
                    self.map.putAssumeCapacity(current_id.?, str);
                    // start is end + 1 to skip the newline
                    start = end + 1;
                    current_id = null;
                }
            }

            return self;
        }

        pub fn add(self: *Self, image_id: Self.Key, str: Self.Value) !void {
            const result = try self.map.getOrPut(image_id);
            // destroy old path
            if (result.found_existing)
                self.alloc.free(result.value_ptr.*);
            result.value_ptr.* = str;
        }

        pub fn writeToFile(self: *const Self, file: std.fs.File) !void {
            var writer = file.writer();
            var key_iter = self.map.keyIterator();
            while (key_iter.next()) |key| {
                try writer.print("{d} {s}\n", .{ key.*, self.map.get(key.*).? });
            }
        }

        pub fn deinit(self: *Self) void {
            var value_iter = self.map.valueIterator();
            while (value_iter.next()) |path| self.alloc.free(path.*);
            self.map.deinit();
        }
    };
}

pub fn filter_tags(
    comptime T: type,
    comptime get_images: fn (*const T) *const Tags,
    comptime found_fn: fn (*T, img.ImageId) void,
    t_value: *T,
    tags: [:0]const u8,
) void {
    var separated_tags = std.mem.splitAny(u8, tags, " ");

    var images = get_images(t_value);
    var key_iter = images.map.keyIterator();
    while (key_iter.next()) |id| {
        var img_tags = std.mem.splitAny(u8, images.map.get(id.*).?, " ");
        const found = found: {
            while (separated_tags.next()) |tag| {
                while (img_tags.next()) |otag| {
                    if (std.mem.startsWith(u8, otag, tag))
                        break :found true;
                }
            }
            break :found false;
        };
        if (found) found_fn(t_value, id.*);
        separated_tags.reset();
    }
}
