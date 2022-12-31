const std = @import("std");

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
    return @bitCast(@TypeOf(value), @bitCast(number_type, value) | @bitCast(number_type, other_value));
}
