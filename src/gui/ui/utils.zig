const zgui = @import("zgui");

pub inline fn pushStyleVar(comptime idx: zgui.StyleVar, comptime value: anytype) void {
    const value_type_info = @typeInfo(@TypeOf(value));
    const f = switch (value_type_info) {
        .Struct => zgui.pushStyleVar2f,
        else => zgui.pushStyleVar1f,
    };
    f(.{ .idx = idx, .v = value });
}

pub inline fn popStyleVars(comptime count: u32) void {
    zgui.popStyleVar(.{
        .count = count,
    });
}
