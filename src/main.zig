//! Image Compressor — full native Native SDK app (no WebView / no frontend).
//! View: src/app.native · logic: Model / Msg / update_fx · encode: Bun.Image via fx.spawn.

const std = @import("std");
const builtin = @import("builtin");
const runner = @import("runner");
const native_sdk = @import("native_sdk");

pub const panic = std.debug.FullPanic(native_sdk.debug.capturePanic);

const canvas = native_sdk.canvas;
const geometry = native_sdk.geometry;

pub const canvas_label = "compressor-canvas";
pub const window_width: f32 = 480;
pub const window_height: f32 = 640;
pub const window_min_width: f32 = 420;
pub const window_min_height: f32 = 560;
pub const header_natural_height: f32 = 52;

const max_path_bytes = 512;
const max_name_bytes = 128;
const max_status_bytes = 192;
const max_error_bytes = 192;

pub const browse_key: u64 = 1;
pub const compress_key: u64 = 2;
pub const preview_key: u64 = 3;
pub const preview_image_id_base: u64 = 100;

const app_permissions = [_][]const u8{ native_sdk.security.permission_command, native_sdk.security.permission_view };
const shell_views = [_]native_sdk.ShellView{
    .{
        .label = canvas_label,
        .kind = .gpu_surface,
        .fill = true,
        .role = "Image compressor canvas",
        .accessibility_label = "Compressor",
        .gpu_backend = .software,
        .gpu_pixel_format = .bgra8_unorm,
        .gpu_present_mode = .timer,
        .gpu_alpha_mode = .@"opaque",
        .gpu_color_space = .srgb,
        .gpu_vsync = true,
    },
};
const shell_windows = [_]native_sdk.ShellWindow{.{
    .label = "main",
    .title = "Compressor",
    .width = window_width,
    .height = window_height,
    .min_width = window_min_width,
    .min_height = window_min_height,
    .restore_state = false,
    .titlebar = .hidden_inset_tall,
    .views = &shell_views,
}};
pub const shell_scene: native_sdk.ShellConfig = .{ .windows = &shell_windows };

pub const cmd_settings = "compressor.settings";
pub const cmd_compress = "compressor.compress";
pub const cmd_browse = "compressor.browse";

pub fn command(name: []const u8) ?Msg {
    if (std.mem.eql(u8, name, cmd_settings)) return .toggle_settings;
    if (std.mem.eql(u8, name, cmd_compress)) return .compress;
    if (std.mem.eql(u8, name, cmd_browse)) return .browse;
    return null;
}

// ------------------------------------------------------------------ model

pub const Msg = union(enum) {
    browse,
    clear,
    compress,
    toggle_settings,
    set_preset_light,
    set_preset_medium,
    set_preset_heavy,
    quality_changed,
    files_dropped: DroppedPaths,
    preview_exited: native_sdk.EffectExit,
    browse_exited: native_sdk.EffectExit,
    compress_exited: native_sdk.EffectExit,
    chrome_changed: native_sdk.WindowChrome,

    pub const view_unbound = .{ "chrome_changed", "browse_exited", "compress_exited", "files_dropped", "preview_exited" };
};

/// Paths copied out of a platform `files_dropped` event (UiApp ignores those
/// events today, so we wrap `App.event` and forward them here).
pub const DroppedPaths = struct {
    storage: [4][max_path_bytes]u8 = undefined,
    lengths: [4]usize = .{ 0, 0, 0, 0 },
    count: usize = 0,

    pub fn fromPaths(paths: []const []const u8) DroppedPaths {
        var out: DroppedPaths = .{};
        const n = @min(paths.len, out.storage.len);
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const trimmed = std.mem.trim(u8, paths[i], " \t\r\n");
            const len = @min(trimmed.len, max_path_bytes);
            @memcpy(out.storage[i][0..len], trimmed[0..len]);
            out.lengths[i] = len;
        }
        out.count = n;
        return out;
    }

    pub fn pathAt(self: *const DroppedPaths, index: usize) []const u8 {
        return self.storage[index][0..self.lengths[index]];
    }
};

pub const Model = struct {
    path_storage: [max_path_bytes]u8 = undefined,
    path_len: usize = 0,
    name_storage: [max_name_bytes]u8 = undefined,
    name_len: usize = 0,
    output_storage: [max_path_bytes]u8 = undefined,
    output_len: usize = 0,
    status_storage: [max_status_bytes]u8 = undefined,
    status_len: usize = 0,
    error_storage: [max_error_bytes]u8 = undefined,
    error_len: usize = 0,

    quality: u8 = 80,
    busy: bool = false,
    settings_open: bool = false,
    input_bytes: u64 = 0,
    output_bytes: u64 = 0,
    has_result: bool = false,
    preview_image: canvas.ImageId = 0,
    preview_generation: u64 = 0,

    chrome_leading: f32 = 0,
    chrome_trailing: f32 = 140,
    chrome_top: f32 = 36,
    header_height: f32 = header_natural_height,

    /// Storage / internal fields only read from Zig (not markup bindings).
    pub const view_unbound = .{
        "path_storage",  "path_len",
        "name_storage",  "name_len",
        "output_storage","output_len",
        "status_storage","status_len",
        "error_storage", "error_len",
        "quality",       "busy",
        "input_bytes",   "output_bytes",
        "has_result",    "header_height",
        "preview_generation",
    };

    pub fn pathText(model: *const Model) []const u8 {
        return model.path_storage[0..model.path_len];
    }

    pub fn fileName(model: *const Model) []const u8 {
        return model.name_storage[0..model.name_len];
    }

    pub fn outputName(model: *const Model) []const u8 {
        if (model.output_len == 0) return "";
        return std.fs.path.basename(model.output_storage[0..model.output_len]);
    }

    pub fn statusText(model: *const Model) []const u8 {
        return model.status_storage[0..model.status_len];
    }

    pub fn errorText(model: *const Model) []const u8 {
        return model.error_storage[0..model.error_len];
    }

    pub fn hasFile(model: *const Model) bool {
        return model.path_len > 0;
    }

    pub fn hasResult(model: *const Model) bool {
        return model.has_result;
    }

    pub fn hasStatus(model: *const Model) bool {
        return model.status_len > 0;
    }

    pub fn hasError(model: *const Model) bool {
        return model.error_len > 0;
    }

    pub fn busyOrNoFile(model: *const Model) bool {
        return model.busy or model.path_len == 0;
    }

    pub fn qualityFraction(model: *const Model) f32 {
        return @as(f32, @floatFromInt(model.quality)) / 100.0;
    }

    pub fn qualityPercent(model: *const Model, arena: std.mem.Allocator) []const u8 {
        return std.fmt.allocPrint(arena, "{d}%", .{model.quality}) catch "";
    }

    pub fn compressLabel(model: *const Model) []const u8 {
        return if (model.busy) "Working…" else "Compress";
    }

    pub fn presetLight(model: *const Model) bool {
        return model.quality == 90;
    }
    pub fn presetMedium(model: *const Model) bool {
        return model.quality == 80;
    }
    pub fn presetHeavy(model: *const Model) bool {
        return model.quality == 50;
    }

    pub fn resultLine(model: *const Model, arena: std.mem.Allocator) []const u8 {
        if (!model.has_result) return "";
        const savings = if (model.input_bytes > 0)
            @as(i64, @intCast(100 - (model.output_bytes * 100 / model.input_bytes)))
        else
            0;
        return std.fmt.allocPrint(arena, "{s} → {s} · −{d}%", .{
            formatBytes(arena, model.input_bytes),
            formatBytes(arena, model.output_bytes),
            savings,
        }) catch "";
    }

    pub fn statusLabel(model: *const Model) []const u8 {
        if (model.busy) return "Compressing…";
        if (model.has_result) return "Saved";
        if (model.path_len > 0) return "Ready";
        return "Drop or browse an image";
    }

    pub fn setPath(model: *Model, path: []const u8) void {
        const trimmed = std.mem.trim(u8, path, " \t\r\n");
        const len = @min(trimmed.len, max_path_bytes);
        @memcpy(model.path_storage[0..len], trimmed[0..len]);
        model.path_len = len;
        // Handle both POSIX and Windows separators so dropped Win32 paths
        // still yield a short file name when tests/hosts run on Linux.
        const base = fileBasename(model.pathText());
        const nlen = @min(base.len, max_name_bytes);
        @memcpy(model.name_storage[0..nlen], base[0..nlen]);
        model.name_len = nlen;
        model.has_result = false;
        model.output_len = 0;
        model.input_bytes = 0;
        model.output_bytes = 0;
        model.preview_image = 0;
        model.clearError();
        model.setStatus("Image selected");
    }

    fn clearFile(model: *Model) void {
        model.path_len = 0;
        model.name_len = 0;
        model.output_len = 0;
        model.has_result = false;
        model.input_bytes = 0;
        model.output_bytes = 0;
        model.preview_image = 0;
        model.clearError();
        model.setStatus("");
    }

    fn setStatus(model: *Model, text: []const u8) void {
        const len = @min(text.len, max_status_bytes);
        @memcpy(model.status_storage[0..len], text[0..len]);
        model.status_len = len;
    }

    fn setError(model: *Model, text: []const u8) void {
        const len = @min(text.len, max_error_bytes);
        @memcpy(model.error_storage[0..len], text[0..len]);
        model.error_len = len;
    }

    fn clearError(model: *Model) void {
        model.error_len = 0;
    }

    fn setOutput(model: *Model, path: []const u8) void {
        const len = @min(path.len, max_path_bytes);
        @memcpy(model.output_storage[0..len], path[0..len]);
        model.output_len = len;
    }
};

fn fileBasename(path: []const u8) []const u8 {
    if (path.len == 0) return path;
    var i = path.len;
    while (i > 0) {
        i -= 1;
        const c = path[i];
        if (c == '/' or c == '\\') return path[i + 1 ..];
    }
    return path;
}

fn formatBytes(arena: std.mem.Allocator, n: u64) []const u8 {
    if (n < 1024) return std.fmt.allocPrint(arena, "{d} B", .{n}) catch "?";
    if (n < 1024 * 1024) return std.fmt.allocPrint(arena, "{d:.1} KB", .{@as(f64, @floatFromInt(n)) / 1024.0}) catch "?";
    return std.fmt.allocPrint(arena, "{d:.2} MB", .{@as(f64, @floatFromInt(n)) / (1024.0 * 1024.0)}) catch "?";
}

fn defaultOutputPath(input: []const u8, buffer: []u8) ![]const u8 {
    const dir = std.fs.path.dirname(input);
    const base = std.fs.path.basename(input);
    const ext = std.fs.path.extension(base);
    const stem = if (ext.len > 0) base[0 .. base.len - ext.len] else base;
    const suffix: []const u8 = if (std.ascii.eqlIgnoreCase(ext, ".webp")) ".compressed.webp" else ".webp";
    if (dir) |d| {
        return try std.fmt.bufPrint(buffer, "{s}/{s}{s}", .{ d, stem, suffix });
    }
    return try std.fmt.bufPrint(buffer, "{s}{s}", .{ stem, suffix });
}

fn firstLine(text: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, text, '\n')) |idx| {
        return std.mem.trim(u8, text[0..idx], " \t\r");
    }
    return std.mem.trim(u8, text, " \t\r\n");
}

fn parseJsonU64(payload: []const u8, field: []const u8) ?u64 {
    var key_buf: [64]u8 = undefined;
    const key = std.fmt.bufPrint(&key_buf, "\"{s}\"", .{field}) catch return null;
    const start = std.mem.indexOf(u8, payload, key) orelse return null;
    var i = start + key.len;
    while (i < payload.len and (payload[i] == ' ' or payload[i] == ':' or payload[i] == '\t')) : (i += 1) {}
    var value: u64 = 0;
    var digits: usize = 0;
    while (i < payload.len and payload[i] >= '0' and payload[i] <= '9') : (i += 1) {
        value = value * 10 + (payload[i] - '0');
        digits += 1;
        if (digits > 18) return null;
    }
    if (digits == 0) return null;
    return value;
}

fn extractJsonString(payload: []const u8, field: []const u8) ?[]const u8 {
    var key_buf: [64]u8 = undefined;
    const key = std.fmt.bufPrint(&key_buf, "\"{s}\"", .{field}) catch return null;
    const start = std.mem.indexOf(u8, payload, key) orelse return null;
    var i = start + key.len;
    while (i < payload.len and (payload[i] == ' ' or payload[i] == ':' or payload[i] == '\t')) : (i += 1) {}
    if (i >= payload.len or payload[i] != '"') return null;
    i += 1;
    const value_start = i;
    while (i < payload.len) : (i += 1) {
        if (payload[i] == '\\') {
            i += 1;
            continue;
        }
        if (payload[i] == '"') return payload[value_start..i];
    }
    return null;
}

// ----------------------------------------------------------------- effects

pub const CompressorApp = native_sdk.UiApp(Model, Msg);
pub const Effects = CompressorApp.Effects;

pub fn update(model: *Model, msg: Msg, fx: *Effects) void {
    switch (msg) {
        .chrome_changed => |chrome| {
            model.chrome_leading = chrome.insets.left;
            model.chrome_trailing = @max(140, chrome.insets.right);
            if (chrome.insets.top > 0) {
                model.chrome_top = @max(36, chrome.insets.top);
                model.header_height = @max(header_natural_height, chrome.insets.top);
            }
            if (chrome.buttons.height > 0) {
                model.chrome_top = @max(model.chrome_top, chrome.buttons.height + 8);
            }
        },
        .toggle_settings => model.settings_open = !model.settings_open,
        .set_preset_light => {
            model.quality = 90;
            model.setStatus("Quality set to 90% (Light)");
        },
        .set_preset_medium => {
            model.quality = 80;
            model.setStatus("Quality set to 80% (Medium)");
        },
        .set_preset_heavy => {
            model.quality = 50;
            model.setStatus("Quality set to 50% (Heavy)");
        },
        .quality_changed => {
            // Value mirrored by Options.sync from the live slider widget.
        },
        .files_dropped => |dropped| handleFilesDropped(model, fx, dropped),
        .preview_exited => |exit| handlePreviewExit(model, fx, exit),
        .clear => clearSelection(model, fx),
        .browse => startBrowse(model, fx),
        .compress => startCompress(model, fx),
        .browse_exited => |exit| handleBrowseExit(model, fx, exit),
        .compress_exited => |exit| handleCompressExit(model, exit),
    }
}

fn clearSelection(model: *Model, fx: *Effects) void {
    clearPreview(model, fx);
    model.clearFile();
}

fn clearPreview(model: *Model, fx: *Effects) void {
    if (model.preview_image != 0) {
        _ = fx.unregisterImage(model.preview_image);
        model.preview_image = 0;
    }
    fx.cancel(preview_key);
}

fn selectPath(model: *Model, fx: *Effects, path: []const u8) void {
    clearPreview(model, fx);
    model.setPath(path);
    startPreviewLoad(model, fx);
}

fn startPreviewLoad(model: *Model, fx: *Effects) void {
    if (model.path_len == 0) return;
    // Native fx.readFile caps at 1 MiB and truncates larger files, which
    // breaks PNG/JPEG decode. Bun builds a small thumbnail that always fits
    // the spawn collect budget (512 KiB).
    model.preview_generation +%= 1;
    if (model.preview_generation == 0) model.preview_generation = 1;
    const argv = [_][]const u8{
        "bun",
        "run",
        "scripts/preview.ts",
        "--input",
        model.pathText(),
        "--size",
        "192",
    };
    fx.spawn(.{
        .key = preview_key,
        .argv = &argv,
        .output = .collect,
        .on_exit = Effects.exitMsg(.preview_exited),
    });
}

fn handlePreviewExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.key != preview_key) return;
    if (exit.reason != .exited or exit.code != 0 or exit.output.len == 0) {
        model.preview_image = 0;
        return;
    }
    const image_id = preview_image_id_base + model.preview_generation;
    if (model.preview_image != 0 and model.preview_image != image_id) {
        _ = fx.unregisterImage(model.preview_image);
    }
    _ = fx.registerImageBytes(image_id, exit.output) catch {
        model.preview_image = 0;
        return;
    };
    model.preview_image = image_id;
}

fn isImagePath(path: []const u8) bool {
    const ext = std.fs.path.extension(path);
    if (ext.len == 0) return false;
    const known = [_][]const u8{ ".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".tif", ".tiff", ".heic", ".heif", ".avif" };
    for (known) |candidate| {
        if (std.ascii.eqlIgnoreCase(ext, candidate)) return true;
    }
    return false;
}

fn handleFilesDropped(model: *Model, fx: *Effects, dropped: DroppedPaths) void {
    if (model.busy) return;
    if (dropped.count == 0) {
        model.setStatus("Drop cancelled");
        return;
    }
    var i: usize = 0;
    while (i < dropped.count) : (i += 1) {
        const path = dropped.pathAt(i);
        if (path.len == 0) continue;
        if (!isImagePath(path)) {
            model.setError("Drop an image file (.jpg, .png, .webp, …)");
            model.setStatus("Unsupported file type");
            return;
        }
        selectPath(model, fx, path);
        return;
    }
    model.setStatus("Drop cancelled");
}

fn startBrowse(model: *Model, fx: *Effects) void {
    if (model.busy) return;
    model.clearError();
    model.setStatus("Opening file picker…");
    // Platform file dialogs print a single path on stdout.
    const argv = if (builtin.os.tag == .windows) [_][]const u8{
        "powershell",
        "-NoProfile",
        "-Command",
        "Add-Type -AssemblyName System.Windows.Forms; $d=New-Object System.Windows.Forms.OpenFileDialog; $d.Filter='Images|*.jpg;*.jpeg;*.png;*.webp;*.gif;*.bmp;*.tif;*.tiff;*.heic;*.heif;*.avif|All|*.*'; $d.Title='Choose an image'; if($d.ShowDialog() -eq 'OK'){ Write-Output $d.FileName }",
    } else if (builtin.os.tag == .macos) [_][]const u8{
        "osascript",
        "-e",
        "POSIX path of (choose file with prompt \"Choose an image\" of type {\"public.image\"})",
    } else [_][]const u8{
        "/bin/sh",
        "-c",
        "if command -v zenity >/dev/null 2>&1; then zenity --file-selection --title='Choose an image' --file-filter='Images | *.jpg *.jpeg *.png *.webp *.gif *.bmp *.tif *.tiff *.heic *.heif *.avif'; elif command -v kdialog >/dev/null 2>&1; then kdialog --getopenfilename . 'Images (*.jpg *.png *.webp *.gif *.bmp)'; else echo ''; fi",
    };
    fx.spawn(.{
        .key = browse_key,
        .argv = &argv,
        .output = .collect,
        .on_exit = Effects.exitMsg(.browse_exited),
    });
}

fn handleBrowseExit(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
    if (exit.reason != .exited or exit.code != 0) {
        model.setStatus("Browse cancelled");
        return;
    }
    const path = firstLine(exit.output);
    if (path.len == 0) {
        model.setStatus("Browse cancelled");
        return;
    }
    selectPath(model, fx, path);
}

fn startCompress(model: *Model, fx: *Effects) void {
    if (model.busy or model.path_len == 0) return;
    model.busy = true;
    model.clearError();
    model.setStatus("Compressing with Bun…");

    var out_buf: [max_path_bytes]u8 = undefined;
    const out_path = defaultOutputPath(model.pathText(), &out_buf) catch {
        model.busy = false;
        model.setError("Could not build output path");
        return;
    };
    model.setOutput(out_path);

    var quality_buf: [8]u8 = undefined;
    const quality_text = std.fmt.bufPrint(&quality_buf, "{d}", .{model.quality}) catch "80";

    // argv slices must live until spawn copies them — use model path/output storage.
    const argv = [_][]const u8{
        "bun",
        "run",
        "scripts/compress.ts",
        "--input",
        model.pathText(),
        "--output",
        model.output_storage[0..model.output_len],
        "--quality",
        quality_text,
    };
    fx.spawn(.{
        .key = compress_key,
        .argv = &argv,
        .output = .collect,
        .on_exit = Effects.exitMsg(.compress_exited),
    });
}

fn handleCompressExit(model: *Model, exit: native_sdk.EffectExit) void {
    model.busy = false;
    if (exit.reason != .exited or exit.code != 0) {
        const msg = firstLine(exit.stderr_tail);
        if (msg.len > 0) {
            model.setError(msg);
        } else if (exit.output.len > 0) {
            model.setError(firstLine(exit.output));
        } else {
            model.setError("Compression failed");
        }
        model.setStatus("Failed");
        return;
    }
    const line = firstLine(exit.output);
    if (extractJsonString(line, "output")) |out| model.setOutput(out);
    model.input_bytes = parseJsonU64(line, "inputBytes") orelse 0;
    model.output_bytes = parseJsonU64(line, "outputBytes") orelse 0;
    model.has_result = true;
    model.setStatus("Done");
    model.clearError();
}

// --------------------------------------------------------------- sync + chrome

/// Markup sliders dispatch a plain on-change with no payload — copy the
/// reconciled widget value into the model before the next rebuild.
fn syncModel(model: *Model, layout: canvas.WidgetLayoutTree) void {
    for (layout.nodes) |node| {
        if (node.widget.kind == .slider) {
            const q = @as(u8, @intFromFloat(@round(std.math.clamp(node.widget.value, 0, 1) * 100.0)));
            model.quality = if (q < 1) 1 else q;
        }
    }
}

fn onChrome(chrome: native_sdk.WindowChrome) ?Msg {
    return .{ .chrome_changed = chrome };
}

// ------------------------------------------------------------------- view

pub const AppUi = canvas.Ui(Msg);
pub const app_markup = @embedFile("app.native");

// -------------------------------------------------------------------- app

pub fn initialModel() Model {
    return .{};
}

/// UiApp's event switch ignores `.files_dropped` today. Wrap the generated
/// App so OS drops still reach `update` as `Msg.files_dropped`.
fn wrapAppWithFileDrops(app_state: *CompressorApp) native_sdk.App {
    var app = app_state.app();
    app.context = app_state;
    app.event_fn = fileDropEventFn;
    return app;
}

fn fileDropEventFn(context: *anyopaque, runtime: *native_sdk.Runtime, event_value: native_sdk.Event) anyerror!void {
    const self: *CompressorApp = @ptrCast(@alignCast(context));
    const base = self.app();
    try base.event(runtime, event_value);
    switch (event_value) {
        .files_dropped => |drop| {
            if (drop.paths.len == 0) return;
            try self.dispatch(runtime, self.canvas_window_id, .{ .files_dropped = DroppedPaths.fromPaths(drop.paths) });
        },
        else => {},
    }
}

/// Make the Win32 process DPI-aware before any window is created.
///
/// Native SDK's embedded Windows manifest only declares common-controls v6 —
/// it does not declare DPI awareness. Without this, `GetDpiForWindow` reports
/// 96 DPI, the software canvas rasterizes at 1×, and Windows stretches the
/// bitmap to the display scale (soft / blurry text and edges).
///
/// With Per-Monitor V2 awareness the host reports the real scale factor, the
/// software renderer paints at device pixels, and blits 1:1 via SetDIBitsToDevice.
fn enableWindowsDpiAwareness() void {
    // Comptime switch so non-Windows targets never analyze Win32 externs.
    switch (comptime builtin.os.tag) {
        .windows => {
            const LoadLibraryA = struct {
                extern "kernel32" fn LoadLibraryA(name: [*:0]const u8) callconv(.winapi) ?*anyopaque;
            }.LoadLibraryA;
            const GetProcAddress = struct {
                extern "kernel32" fn GetProcAddress(module: *anyopaque, name: [*:0]const u8) callconv(.winapi) ?*const anyopaque;
            }.GetProcAddress;
            const FreeLibrary = struct {
                extern "kernel32" fn FreeLibrary(module: *anyopaque) callconv(.winapi) c_int;
            }.FreeLibrary;

            // Per-Monitor V2 (Windows 10 1703+): -4 as DPI_AWARENESS_CONTEXT.
            const DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2: *anyopaque = @ptrFromInt(@as(usize, @bitCast(@as(isize, -4))));
            if (LoadLibraryA("user32.dll")) |user32| {
                defer _ = FreeLibrary(user32);
                if (GetProcAddress(user32, "SetProcessDpiAwarenessContext")) |addr| {
                    const SetProcessDpiAwarenessContext = *const fn (*anyopaque) callconv(.winapi) c_int;
                    const set_ctx: SetProcessDpiAwarenessContext = @ptrCast(addr);
                    if (set_ctx(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2) != 0) return;
                }
            }

            // Fallback: Per-Monitor V1 via Shcore (Windows 8.1+).
            const PROCESS_PER_MONITOR_DPI_AWARE: c_int = 2;
            if (LoadLibraryA("Shcore.dll")) |shcore| {
                defer _ = FreeLibrary(shcore);
                if (GetProcAddress(shcore, "SetProcessDpiAwareness")) |addr| {
                    const SetProcessDpiAwareness = *const fn (c_int) callconv(.winapi) c_long;
                    const set_awareness: SetProcessDpiAwareness = @ptrCast(addr);
                    _ = set_awareness(PROCESS_PER_MONITOR_DPI_AWARE);
                }
            }
        },
        else => {},
    }
}

pub fn main(init: std.process.Init) !void {
    // Must run before the first HWND is created (runner.runWithOptions).
    enableWindowsDpiAwareness();

    const app_state = try CompressorApp.create(std.heap.page_allocator, .{
        .name = "image-compressor",
        .scene = shell_scene,
        .canvas_label = canvas_label,
        .update_fx = update,
        .sync = syncModel,
        .on_chrome = onChrome,
        .on_command = command,
        .markup = .{
            .source = app_markup,
            .watch_path = "src/app.native",
            .io = init.io,
        },
    });
    defer app_state.destroy();
    app_state.model = initialModel();

    try runner.runWithOptions(wrapAppWithFileDrops(app_state), .{
        .app_name = "Compressor",
        .window_title = "Compressor",
        .bundle_id = "com.sonny.image-compressor",
        .icon_path = "assets/icon.png",
        .default_frame = geometry.RectF.init(0, 0, window_width, window_height),
        .restore_state = false,
        .js_window_api = false,
        .security = .{
            .permissions = &app_permissions,
            .navigation = .{ .allowed_origins = &.{ "zero://inline", "zero://app" } },
        },
    }, init);
}

test {
    _ = @import("tests.zig");
}

test "default output path for jpeg becomes webp" {
    var buf: [256]u8 = undefined;
    const out = try defaultOutputPath("/tmp/photo.JPEG", &buf);
    try std.testing.expectEqualStrings("/tmp/photo.webp", out);
}

test "default output path for webp avoids overwrite" {
    var buf: [256]u8 = undefined;
    const out = try defaultOutputPath("/tmp/shot.webp", &buf);
    try std.testing.expectEqualStrings("/tmp/shot.compressed.webp", out);
}
