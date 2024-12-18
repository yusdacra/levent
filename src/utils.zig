const std = @import("std");

pub const mpsc = @import("./utils/mpsc.zig");

pub inline fn merge_packed_structs(comptime number_type: type, value: anytype, other_value: anytype) @TypeOf(value) {
    comptime {
        const struct_type = @TypeOf(value);
        const other_struct_type = @TypeOf(other_value);
        std.testing.expect(struct_type == other_struct_type) catch {
            // zig fmt: off
            @compileError(
                "packed structs are not of the same type: "
                ++ @typeName(struct_type)
                ++ " != "
                ++ @typeName(other_struct_type)
            );
        };
    }
    return @bitCast(@as(number_type, @bitCast(value)) | @as(number_type, @bitCast(other_value)));
}

pub inline fn oomPanic() noreturn {
    @panic("out of memory");
}

pub inline fn channelCapacityPanic() noreturn {
    @panic("channel capacity reached");
}