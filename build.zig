const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const src_path = b.pathJoin(&.{"src"});
    const exe = b.addExecutable(.{
        .name = "levent",
        .root_source_file = b.path(b.pathJoin(&.{ src_path, "main.zig" })),
        .target = target,
        .optimize = optimize,
    });

    const zglfw = b.dependency("zglfw", .{
        .target = target,
    });
    exe.root_module.addImport("zglfw", zglfw.module("root"));
    exe.linkLibrary(zglfw.artifact("glfw"));

    @import("zgpu").addLibraryPathsTo(exe);
    const zgpu = b.dependency("zgpu", .{
        .target = target,
    });
    exe.root_module.addImport("zgpu", zgpu.module("root"));
    exe.linkLibrary(zgpu.artifact("zdawn"));

    const zgui = b.dependency("zgui", .{
        .target = target,
        .backend = .glfw_wgpu,
        .with_te = true,
    });
    exe.root_module.addImport("zgui", zgui.module("root"));
    exe.linkLibrary(zgui.artifact("imgui"));

    const zstbi = b.dependency("zstbi", .{
        .target = target,
    });
    exe.root_module.addImport("zstbi", zstbi.module("root"));
    exe.linkLibrary(zstbi.artifact("zstbi"));

    const nfd = b.dependency("nfd", .{});
    exe.root_module.addImport("nfd", nfd.module("nfd"));

    const clap = b.dependency("clap", .{});
    exe.root_module.addImport("clap", clap.module("clap"));

    const exe_options = b.addOptions();
    var envmap = std.process.getEnvMap(b.allocator) catch @panic("oom?");
    defer envmap.deinit();
    exe_options.addOption([]const u8, "git_commit", b.option([]const u8, "git_commit", "Current git commit") orelse envmap.get("LEVENT_GIT_COMMIT") orelse "unknown");
    exe_options.addOption([]const u8, "version", b.option([]const u8, "version", "Current version") orelse envmap.get("LEVENT_VERSION") orelse "unknown");
    exe.root_module.addOptions("build_options", exe_options);

    // exe_b.options.addOption([]const u8, "content_dir", content_dir);
    // const content_path = b.pathJoin(&.{ cwd_path, content_dir });
    // const install_content_step = b.addInstallDirectory(.{
    //     .source_dir = b.path(content_path),
    //     .install_dir = .{ .custom = "" },
    //     .install_subdir = b.pathJoin(&.{ "bin", content_dir }),
    // });
    // exe.step.dependOn(&install_content_step.step);

    if (target.result.os.tag == .macos) {
        if (b.lazyDependency("system_sdk", .{})) |system_sdk| {
            exe.addLibraryPath(system_sdk.path("macos12/usr/lib"));
            exe.addSystemFrameworkPath(system_sdk.path("macos12/System/Library/Frameworks"));
        }
    }

    // TODO: Problems with LTO on Windows.
    if (exe.rootModuleTarget().os.tag == .windows) {
        exe.want_lto = false;
    }

    if (exe.root_module.optimize != .Debug) {
        exe.root_module.strip = true;
    }

    const install_exe = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&install_exe.step);
    b.step("levent", "Build levent").dependOn(&install_exe.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(&install_exe.step);
    b.step("run", "Run levent").dependOn(&run_cmd.step);
}
