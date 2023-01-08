const std = @import("std");

// zgui stuff
const zgui = @import("libs/zig-gamedev/libs/zgui/build.zig");
// Needed for glfw/wgpu rendering backend
const zglfw = @import("libs/zig-gamedev/libs/zglfw/build.zig");
const zgpu = @import("libs/zig-gamedev/libs/zgpu/build.zig");
const zpool = @import("libs/zig-gamedev/libs/zpool/build.zig");
const zstbi = @import("libs/zig-gamedev/libs/zstbi/build.zig");
const nfdzig = @import("libs/nfd-zig/build.zig");

pub fn build(b: *std.build.Builder) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("levent", "src/main.zig");

    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_tsan", false);
    exe.addOptions("build_options", build_options);

    if (b.option(bool, "enable_tsan", "Enable thread sanitizer") orelse false) {
        exe.sanitize_thread = true;
    }
    exe.addLibraryPath(std.os.getenv("ZLIB_LIBRARY_PATH").?);

    // Needed for glfw/wgpu rendering backend
    const zgpu_options = zgpu.BuildOptionsStep.init(b, .{});
    const zgpu_pkg = zgpu.getPkg(&.{ zgpu_options.getPkg(), zpool.pkg, zglfw.pkg });

    const zgui_options = zgui.BuildOptionsStep.init(b, .{ .backend = .glfw_wgpu });
    const zgui_pkg = zgui.getPkg(&.{zgui_options.getPkg()});

    exe.addPackage(zgui_pkg);
    exe.addPackage(zglfw.pkg);
    exe.addPackage(zgpu_pkg);
    exe.addPackage(zstbi.pkg);
    exe.addPackage(nfdzig.getPackage("nfd"));
    exe.addPackage(.{
        .name = "zig-ring-buffer",
        .source = .{ .path = thisDir() ++ "/libs/zig-ring-buffer/src/main.zig" },
    });

    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    zgpu.link(exe, zgpu_options);
    zgui.link(exe, zgui_options);
    zglfw.link(exe);
    zstbi.link(exe);
    exe.linkLibrary(nfdzig.makeLib(b, mode, target));

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
