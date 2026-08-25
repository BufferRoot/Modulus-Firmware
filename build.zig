const std = @import("std");

// Host tests use std.testing.allocator (leak-checked). Tab5 objects: ReleaseSafe per zig-port.
// If incremental builds misbehave: `zig build -fno-incremental` then clean zig-out/.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const host_options = b.addOptions();
    host_options.addOption(bool, "device_nvs", false);

    const host_shim_module = b.createModule(.{
        .root_source_file = b.path("src/modulus/c/shim_host_stub.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Build-time NVS key manifest (stdout → generated .zig module).
    const settings_keys_module = b.createModule(.{
        .root_source_file = b.path("src/modulus/core/settings_keys.zig"),
        .target = target,
        .optimize = optimize,
    });
    const gen_nvs_module = b.createModule(.{
        .root_source_file = b.path("tools/gen_nvs_manifest.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });
    gen_nvs_module.addImport("settings_keys", settings_keys_module);
    const gen_nvs_exe = b.addExecutable(.{
        .name = "gen_nvs_manifest",
        .root_module = gen_nvs_module,
    });
    const run_gen_nvs = b.addRunArtifact(gen_nvs_exe);
    run_gen_nvs.addFileInput(b.path("src/modulus/core/settings_keys.zig"));
    const nvs_manifest_path = run_gen_nvs.addOutputFileArg("nvs_key_manifest.zig");
    const nvs_manifest_module = b.createModule(.{
        .root_source_file = nvs_manifest_path,
        .target = target,
        .optimize = optimize,
    });

    const modulus_module = b.createModule(.{
        .root_source_file = b.path("src/modulus/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    modulus_module.addOptions("build_options", host_options);
    modulus_module.addImport("modulus_shims", host_shim_module);
    modulus_module.addImport("nvs_key_manifest", nvs_manifest_module);

    // Host ABI proof: translate real `ui_shim.h` so stub ≠ hand-copied fantasy layout.
    const translate_ui_shim = b.addTranslateC(.{
        .root_source_file = b.path("firmware/tab5/components/modulus_zig/include/ui_shim.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    translate_ui_shim.addIncludePath(b.path("firmware/tab5/components/modulus_zig/include"));
    modulus_module.addImport("ui_shim_hdr", translate_ui_shim.createModule());

    const tests = b.addTest(.{
        .root_module = modulus_module,
    });
    const run_tests = b.addRunArtifact(tests);
    run_tests.step.dependOn(&run_gen_nvs.step);
    // Per-test timeout: `zig build test -- --test-timeout 60s` (0.16 build_runner flag).
    if (b.args) |args| {
        run_tests.addArgs(args);
    }

    const test_step = b.step("test", "Run unit tests (leak-checked; optional --test-timeout 60s via b.args)");
    test_step.dependOn(&run_tests.step);

    const fuzz_tests = b.addTest(.{
        .name = "fuzz",
        .root_module = modulus_module,
        .filters = &.{"parser fuzz"},
    });
    const run_fuzz = b.addRunArtifact(fuzz_tests);
    run_fuzz.step.dependOn(&run_gen_nvs.step);
    const fuzz_step = b.step("fuzz", "Run grblHAL parser fuzz corpus (continuous: zig build test -- --fuzz on Unix)");
    fuzz_step.dependOn(&run_fuzz.step);

    const gen_nvs_step = b.step("gen-nvs-manifest", "Regenerate NVS key manifest from settings_keys");
    gen_nvs_step.dependOn(&run_gen_nvs.step);

    const host_module = b.createModule(.{
        .root_source_file = b.path("src/modulus/host_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    host_module.addOptions("build_options", host_options);
    host_module.addImport("modulus_shims", host_shim_module);

    const exe = b.addExecutable(.{
        .name = "modulus-host",
        .root_module = host_module,
    });
    b.installArtifact(exe);

    const build_step = b.step("build", "Build host smoke binary");
    build_step.dependOn(&b.addInstallArtifact(exe, .{}).step);

    // Match ESP32-P4 GCC: rv32imafc (single-float). Default `baseline` includes `d` → link error.
    const tab5_target = b.resolveTargetQuery(std.Target.Query.parse(.{
        .arch_os_abi = "riscv32-freestanding-none",
        .cpu_features = "generic_rv32+m+a+c+f+zicsr+zifencei-d-zcd-zcf",
    }) catch unreachable);
    const tab5_options = b.addOptions();
    tab5_options.addOption(bool, "device_nvs", true);

    const tab5_modulus_module = b.createModule(.{
        .root_source_file = b.path("src/modulus/tab5_root.zig"),
        .target = tab5_target,
        .optimize = .ReleaseSafe,
        .single_threaded = true,
    });
    tab5_modulus_module.addOptions("build_options", tab5_options);

    const translate_shims = b.addTranslateC(.{
        .root_source_file = b.path("firmware/tab5/components/modulus_zig/include/modulus_shims_bundle.h"),
        .target = tab5_target,
        .optimize = .ReleaseSafe,
        .link_libc = true,
    });
    translate_shims.addIncludePath(b.path("firmware/tab5/components/modulus_zig/include"));
    tab5_modulus_module.addImport("modulus_shims", translate_shims.createModule());

    const translate_check_step = b.step("translate-check", "Verify Modulus shim headers translate for Tab5");
    translate_check_step.dependOn(&translate_shims.step);

    const tab5_lib = b.addLibrary(.{
        .name = "modulus_zig_core",
        .linkage = .static,
        .root_module = tab5_modulus_module,
    });
    tab5_lib.root_module.link_libc = true;
    tab5_lib.bundle_compiler_rt = true;
    const tab5_install = b.addInstallArtifact(tab5_lib, .{});
    const tab5_step = b.step("tab5-lib", "Build Modulus Zig static lib for Tab5 (riscv32 freestanding)");
    tab5_step.dependOn(&tab5_install.step);

    // C ABI + shim headers alongside static lib.
    _ = b.addInstallHeaderFile(b.path("firmware/tab5/components/modulus_zig/include/ui_shim.h"), "modulus/ui_shim.h");
    _ = b.addInstallHeaderFile(b.path("firmware/tab5/components/modulus_zig/include/modulus_zig.h"), "modulus/modulus_zig.h");
    _ = b.addInstallHeaderFile(b.path("firmware/tab5/components/modulus_zig/include/modulus_shims_bundle.h"), "modulus/modulus_shims_bundle.h");
    _ = b.addInstallHeaderFile(b.path("firmware/tab5/components/modulus_zig/include/rtc_shim_translate.h"), "modulus/rtc_shim_translate.h");
    const install_headers_step = b.step("install-headers", "Install Modulus C ABI and shim headers");
    install_headers_step.dependOn(b.getInstallStep());

    const host_release_install = b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .{ .custom = "host" } },
    });
    const tab5_release_install = b.addInstallArtifact(tab5_lib, .{
        .dest_dir = .{ .override = .{ .custom = "tab5" } },
    });
    const release_step = b.step("release", "Install host binary + Tab5 lib under zig-out/{host,tab5}/ + headers");
    release_step.dependOn(&host_release_install.step);
    release_step.dependOn(&tab5_release_install.step);
    release_step.dependOn(install_headers_step);

    const run_host = b.addRunArtifact(exe);
    const run_host_step = b.step("run-host", "Run modulus-host (pass args via zig build run-host -- …)");
    run_host_step.dependOn(&run_host.step);
    if (b.args) |args| {
        run_host.addArgs(args);
    }

    const run_host_diag = b.addRunArtifact(exe);
    run_host_diag.addArg("--export-diagnostics");
    const host_diag_step = b.step("host-diag", "Export host diagnostics (zig build host-diag -- path.txt)");
    host_diag_step.dependOn(&run_host_diag.step);
    if (b.args) |args| {
        run_host_diag.addArgs(args);
    }

    // Host-first UI engine demo (no LVGL / no firmware). Prove dirty + rotate-on-write.
    const ui_engine_module = b.createModule(.{
        .root_source_file = b.path("src/modulus/ui_engine/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const ui_demo_module = b.createModule(.{
        .root_source_file = b.path("src/modulus/ui_engine/demo_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    ui_demo_module.addImport("ui_engine", ui_engine_module);
    if (target.result.os.tag == .windows) {
        ui_demo_module.linkSystemLibrary("user32", .{});
        ui_demo_module.linkSystemLibrary("gdi32", .{});
    }
    const ui_demo_exe = b.addExecutable(.{
        .name = "modulus-ui-demo",
        .root_module = ui_demo_module,
    });
    b.installArtifact(ui_demo_exe);

    const run_ui_demo = b.addRunArtifact(ui_demo_exe);
    // Window stays open — do not attach to `ci`.
    if (b.args) |args| {
        run_ui_demo.addArgs(args);
    }
    const ui_demo_step = b.step("ui-demo", "Open host UI-engine window (Esc quit; --bench for headless)");
    ui_demo_step.dependOn(&run_ui_demo.step);

    const run_ui_bench = b.addRunArtifact(ui_demo_exe);
    run_ui_bench.addArg("--bench");
    const ui_bench_step = b.step("ui-demo-bench", "Headless UI-engine dirty-path proof");
    ui_bench_step.dependOn(&run_ui_bench.step);

    // The Noto bake stops at 0x7E and the Montserrat LVGL fonts are ASCII too,
    // so a stray em dash or ellipsis paints a blank cell at full advance width.
    const ui_ascii_step = b.step("ui-ascii", "Reject non-ASCII drawn literals (C shims + Zig UI engine)");
    const run_ui_ascii = b.addSystemCommand(&.{
        "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File",      b.pathFromRoot("scripts/check_ui_ascii.ps1"),
    });
    run_ui_ascii.has_side_effects = true;
    ui_ascii_step.dependOn(&run_ui_ascii.step);

    const ci_step = b.step("ci", "Full Zig gate: test + fuzz + translate + tab5-lib + headers + NVS codegen + UI ASCII");
    ci_step.dependOn(&run_tests.step);
    ci_step.dependOn(&run_fuzz.step);
    ci_step.dependOn(&translate_shims.step);
    ci_step.dependOn(&tab5_install.step);
    ci_step.dependOn(install_headers_step);
    ci_step.dependOn(&run_gen_nvs.step);
    ci_step.dependOn(&run_ui_bench.step);
    // PowerShell-only gate; keep `ci` usable on non-Windows hosts.
    if (@import("builtin").os.tag == .windows) ci_step.dependOn(&run_ui_ascii.step);
}
