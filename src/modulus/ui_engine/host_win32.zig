//! Minimal Win32 viewer for RGB565 logical framebuffer (no SDL).

const std = @import("std");
const color = @import("color.zig");
const tokens = @import("tokens.zig");
const geom = @import("geom.zig");

pub const Input = struct {
    quit: bool = false,
    wheel_y: i32 = 0,
    click_x: i32 = -1,
    click_y: i32 = -1,
    /// Pointer drag while LMB held (updated every poll).
    drag_active: bool = false,
    drag_x: i32 = -1,
    drag_y: i32 = -1,
    pointer_up: bool = false,
    hover_x: i32 = -1,
    hover_y: i32 = -1,
    key_space: bool = false,
    key_theme: bool = false,
    key_dialog: bool = false,
    key_pin: bool = false,
    key_catalog: bool = false,
    key_tab: bool = false,
    key_shift_tab: bool = false,
    key_enter: bool = false,
    /// Typed chars this frame (search); 0-terminated in practice via len.
    chars: [8]u8 = .{0} ** 8,
    chars_len: usize = 0,
    key_backspace: bool = false,
};

pub fn sleepMs(ms: u32) void {
    win.kernel32.Sleep(ms);
}

/// Sleep only leftover time toward a ~60 Hz frame (avoids fixed 8 ms chop).
pub fn paceFrameMs(frame_start_ms: u64, target_ms: u32) void {
    const now = win.kernel32.GetTickCount64();
    const elapsed = now -% frame_start_ms;
    if (elapsed < target_ms) sleepMs(@intCast(target_ms - elapsed));
}

pub fn tickMs() u64 {
    return win.kernel32.GetTickCount64();
}

pub const View = struct {
    hwnd: ?win.HWND = null,
    hdc: ?win.HDC = null,
    w: i32 = tokens.Logical.width,
    h: i32 = tokens.Logical.height,

    pub fn open(title: []const u8) !View {
        const class_name = std.unicode.utf8ToUtf16LeStringLiteral("ModulusUiEngine");
        const hinstance = win.kernel32.GetModuleHandleW(null) orelse return error.NoModule;

        const wc = win.WNDCLASSW{
            .style = 0,
            .lpfnWndProc = wndProc,
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hInstance = hinstance,
            .hIcon = null,
            .hCursor = win.user32.LoadCursorW(null, win.IDC_ARROW),
            .hbrBackground = null,
            .lpszMenuName = null,
            .lpszClassName = class_name,
        };
        _ = win.user32.RegisterClassW(&wc);

        var title_buf: [128]u16 = undefined;
        const n = try std.unicode.utf8ToUtf16Le(&title_buf, title);
        title_buf[n] = 0;

        const style: u32 = win.WS_OVERLAPPEDWINDOW;
        var rect = win.RECT{ .left = 0, .top = 0, .right = tokens.Logical.width, .bottom = tokens.Logical.height };
        _ = win.user32.AdjustWindowRect(&rect, style, 0);

        const hwnd = win.user32.CreateWindowExW(
            0,
            class_name,
            title_buf[0..n :0].ptr,
            style,
            win.CW_USEDEFAULT,
            win.CW_USEDEFAULT,
            rect.right - rect.left,
            rect.bottom - rect.top,
            null,
            null,
            hinstance,
            null,
        ) orelse return error.CreateWindowFailed;

        _ = win.user32.ShowWindow(hwnd, win.SW_SHOW);
        _ = win.user32.UpdateWindow(hwnd);

        const hdc = win.user32.GetDC(hwnd) orelse return error.GetDCFailed;
        return .{ .hwnd = hwnd, .hdc = hdc };
    }

    pub fn close(self: *View) void {
        if (self.hdc) |hdc| {
            _ = win.user32.ReleaseDC(self.hwnd, hdc);
            self.hdc = null;
        }
        if (self.hwnd) |hwnd| {
            _ = win.user32.DestroyWindow(hwnd);
            self.hwnd = null;
        }
    }

    pub fn poll(self: *View, input: *Input) void {
        _ = self;
        var msg: win.MSG = undefined;
        while (win.user32.PeekMessageW(&msg, null, 0, 0, win.PM_REMOVE) != 0) {
            if (msg.message == win.WM_QUIT) {
                input.quit = true;
                return;
            }
            _ = win.user32.TranslateMessage(&msg);
            _ = win.user32.DispatchMessageW(&msg);
        }
        if (g_wheel != 0) {
            input.wheel_y += g_wheel;
            g_wheel = 0;
        }
        if (g_click_x >= 0) {
            input.click_x = g_click_x;
            input.click_y = g_click_y;
            g_click_x = -1;
            g_click_y = -1;
        }
        if (g_pointer_down) {
            input.drag_active = true;
            input.drag_x = g_drag_x;
            input.drag_y = g_drag_y;
        }
        if (g_pointer_up) {
            input.pointer_up = true;
            g_pointer_up = false;
        }
        if (g_space) {
            input.key_space = true;
            g_space = false;
        }
        if (g_theme) {
            input.key_theme = true;
            g_theme = false;
        }
        if (g_dialog) {
            input.key_dialog = true;
            g_dialog = false;
        }
        if (g_pin) {
            input.key_pin = true;
            g_pin = false;
        }
        if (g_catalog) {
            input.key_catalog = true;
            g_catalog = false;
        }
        if (g_tab) {
            input.key_tab = true;
            g_tab = false;
        }
        if (g_shift_tab) {
            input.key_shift_tab = true;
            g_shift_tab = false;
        }
        if (g_enter) {
            input.key_enter = true;
            g_enter = false;
        }
        if (g_backspace) {
            input.key_backspace = true;
            g_backspace = false;
        }
        if (g_chars_len > 0) {
            const n = @min(g_chars_len, input.chars.len);
            @memcpy(input.chars[0..n], g_chars[0..n]);
            input.chars_len = n;
            g_chars_len = 0;
        }
        input.hover_x = g_hover_x;
        input.hover_y = g_hover_y;
    }

    pub fn present(self: *View, pixels: []const color.Rgb565) void {
        _ = self.presentDirty(pixels, &.{.{
            .x = 0,
            .y = 0,
            .w = self.w,
            .h = self.h,
        }}, false);
    }

    /// Blit only dirty logical rects. Returns total pixels touched (host cost proxy).
    ///
    /// Packs each rect into a contiguous top-down DIB before StretchDIBits.
    /// Passing src (x,y) against a full-frame top-down BITMAPINFO makes GDI treat
    /// source Y as bottom-up: settings content dirty at y=win_y+title_h maps to
    /// sample y=win_y — title bar (and close X) appears duplicated under the header.
    ///
    /// `flip`: 180° present (LVGL flip 90↔270 stand-in) — sample mirrored logical pixels.
    pub fn presentDirty(self: *View, pixels: []const color.Rgb565, rects: []const geom.Rect, flip: bool) u32 {
        const expected = @as(usize, @intCast(self.w)) * @as(usize, @intCast(self.h));
        if (pixels.len < expected) return 0;
        const hdc = self.hdc orelse return 0;
        if (rects.len == 0) return 0;

        var total: u32 = 0;
        for (rects) |r0| {
            if (r0.isEmpty()) continue;
            const r = if (flip) flipRect(r0, self.w, self.h) else r0;
            const x = @max(r.x, 0);
            const y = @max(r.y, 0);
            const x2 = @min(r.x + r.w, self.w);
            const y2 = @min(r.y + r.h, self.h);
            const rw = x2 - x;
            const rh = y2 - y;
            if (rw <= 0 or rh <= 0) continue;

            const dib_stride = dibRowStridePx(rw);
            const need: usize = @intCast(dib_stride * rh);
            if (need > g_present_scratch.len) continue;
            if (flip) {
                packLogicalRectFlipped(g_present_scratch[0..need], pixels, self.w, self.h, x, y, rw, rh, dib_stride);
            } else {
                packLogicalRect(g_present_scratch[0..need], pixels, self.w, x, y, rw, rh, dib_stride);
            }

            var info = Bmi16{
                .hdr = .{
                    .biSize = @sizeOf(win.BITMAPINFOHEADER),
                    .biWidth = rw,
                    .biHeight = -rh,
                    .biPlanes = 1,
                    .biBitCount = 16,
                    .biCompression = win.BI_BITFIELDS,
                    .biSizeImage = 0,
                    .biXPelsPerMeter = 0,
                    .biYPelsPerMeter = 0,
                    .biClrUsed = 0,
                    .biClrImportant = 0,
                },
                .masks = .{ 0xF800, 0x07E0, 0x001F },
            };
            _ = win.gdi32.StretchDIBits(
                hdc,
                x,
                y,
                rw,
                rh,
                0,
                0,
                rw,
                rh,
                g_present_scratch[0..need].ptr,
                @ptrCast(&info),
                win.DIB_RGB_COLORS,
                win.SRCCOPY,
            );
            total += @intCast(rw * rh);
        }
        return total;
    }
};

fn dibRowStridePx(width_px: i32) i32 {
    const bytes = width_px * 2;
    const padded = (bytes + 3) & ~@as(i32, 3);
    return @divTrunc(padded, 2);
}

fn flipRect(r: geom.Rect, w: i32, h: i32) geom.Rect {
    return .{
        .x = w - r.x - r.w,
        .y = h - r.y - r.h,
        .w = r.w,
        .h = r.h,
    };
}

fn packLogicalRect(
    dst: []color.Rgb565,
    src: []const color.Rgb565,
    src_stride: i32,
    x: i32,
    y: i32,
    rw: i32,
    rh: i32,
    dst_stride: i32,
) void {
    var row: i32 = 0;
    while (row < rh) : (row += 1) {
        const src_off: usize = @intCast((y + row) * src_stride + x);
        const dst_off: usize = @intCast(row * dst_stride);
        const n: usize = @intCast(rw);
        @memcpy(dst[dst_off..][0..n], src[src_off..][0..n]);
        if (dst_stride > rw) {
            @memset(dst[dst_off + n ..][0..@intCast(dst_stride - rw)], .{ .r = 0, .g = 0, .b = 0 });
        }
    }
}

fn packLogicalRectFlipped(
    dst: []color.Rgb565,
    src: []const color.Rgb565,
    fb_w: i32,
    fb_h: i32,
    x: i32,
    y: i32,
    rw: i32,
    rh: i32,
    dst_stride: i32,
) void {
    // Window (x,y) shows logical (W-1-x, H-1-y).
    var row: i32 = 0;
    while (row < rh) : (row += 1) {
        const dst_off: usize = @intCast(row * dst_stride);
        var col: i32 = 0;
        while (col < rw) : (col += 1) {
            const sx = fb_w - 1 - (x + col);
            const sy = fb_h - 1 - (y + row);
            const src_off: usize = @intCast(sy * fb_w + sx);
            dst[dst_off + @as(usize, @intCast(col))] = src[src_off];
        }
        if (dst_stride > rw) {
            @memset(dst[dst_off + @as(usize, @intCast(rw)) ..][0..@intCast(dst_stride - rw)], .{ .r = 0, .g = 0, .b = 0 });
        }
    }
}

/// Full-frame scratch for packed dirty DIBs (host demo only).
var g_present_scratch: [@as(usize, tokens.Logical.width) * @as(usize, tokens.Logical.height)]color.Rgb565 = undefined;

test "gdi top-down srcY trap maps content dirty onto title" {
    // Repro math for the ghost title bar: bottom-up decode of top-down srcY.
    const H: i32 = tokens.Logical.height;
    const win_y: i32 = 32;
    const title_h: i32 = 52;
    const content_y = win_y + title_h;
    const content_h = 656 - title_h;
    const bogus_sample_y = H - content_y - content_h;
    try std.testing.expectEqual(win_y, bogus_sample_y);
}

test "packLogicalRect copies subrect" {
    var src: [8 * 4]color.Rgb565 = undefined;
    @memset(&src, .{ .r = 0, .g = 0, .b = 0 });
    src[2 * 8 + 3] = .{ .r = 31, .g = 0, .b = 0 };
    var dst: [2 * 2]color.Rgb565 = undefined;
    packLogicalRect(&dst, &src, 8, 3, 2, 2, 2, 2);
    try std.testing.expectEqual(@as(u5, 31), dst[0].r);
}

const Bmi16 = extern struct {
    hdr: win.BITMAPINFOHEADER,
    masks: [3]u32,
};

var g_wheel: i32 = 0;
var g_click_x: i32 = -1;
var g_click_y: i32 = -1;
var g_pointer_down: bool = false;
var g_pointer_up: bool = false;
var g_drag_x: i32 = -1;
var g_drag_y: i32 = -1;
var g_space: bool = false;
var g_theme: bool = false;
var g_dialog: bool = false;
var g_pin: bool = false;
var g_catalog: bool = false;
var g_tab: bool = false;
var g_shift_tab: bool = false;
var g_enter: bool = false;
var g_shift_held: bool = false;
var g_backspace: bool = false;
var g_chars: [8]u8 = .{0} ** 8;
var g_chars_len: usize = 0;
var g_hover_x: i32 = -1;
var g_hover_y: i32 = -1;

fn wndProc(hwnd: ?win.HWND, msg: u32, wparam: win.WPARAM, lparam: win.LPARAM) callconv(win.WINAPI) win.LRESULT {
    switch (msg) {
        win.WM_CLOSE => {
            if (hwnd) |h| _ = win.user32.DestroyWindow(h);
            return 0;
        },
        win.WM_DESTROY => {
            win.user32.PostQuitMessage(0);
            return 0;
        },
        win.WM_MOUSEWHEEL => {
            const delta: i16 = @bitCast(@as(u16, @truncate(wparam >> 16)));
            g_wheel += @divTrunc(@as(i32, delta), 30);
            return 0;
        },
        win.WM_LBUTTONDOWN => {
            g_click_x = signExtend16(@truncate(@as(usize, @bitCast(lparam))));
            g_click_y = signExtend16(@truncate(@as(usize, @bitCast(lparam)) >> 16));
            g_pointer_down = true;
            g_drag_x = g_click_x;
            g_drag_y = g_click_y;
            return 0;
        },
        win.WM_LBUTTONUP => {
            g_pointer_down = false;
            g_pointer_up = true;
            return 0;
        },
        win.WM_MOUSEMOVE => {
            g_hover_x = signExtend16(@truncate(@as(usize, @bitCast(lparam))));
            g_hover_y = signExtend16(@truncate(@as(usize, @bitCast(lparam)) >> 16));
            if (g_pointer_down) {
                g_drag_x = g_hover_x;
                g_drag_y = g_hover_y;
            }
            return 0;
        },
        win.WM_KEYDOWN => {
            if (wparam == win.VK_SHIFT) g_shift_held = true;
            if (wparam == ' ') g_space = true;
            if (wparam == 'T' or wparam == 't') g_theme = true;
            if (wparam == 'D' or wparam == 'd') g_dialog = true;
            if (wparam == 'P' or wparam == 'p') g_pin = true;
            if (wparam == 'M' or wparam == 'm') g_catalog = true;
            if (wparam == win.VK_BACK) g_backspace = true;
            if (wparam == win.VK_TAB) {
                if (g_shift_held) g_shift_tab = true else g_tab = true;
            }
            if (wparam == win.VK_RETURN) g_enter = true;
            if (wparam == win.VK_ESCAPE) {
                if (hwnd) |h| _ = win.user32.DestroyWindow(h);
            }
            return 0;
        },
        win.WM_KEYUP => {
            if (wparam == win.VK_SHIFT) g_shift_held = false;
            return 0;
        },
        win.WM_CHAR => {
            const ch: u8 = @truncate(wparam);
            if (ch >= 32 and ch < 127 and g_chars_len < g_chars.len) {
                g_chars[g_chars_len] = ch;
                g_chars_len += 1;
            }
            return 0;
        },
        else => return win.user32.DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

fn signExtend16(v: u16) i32 {
    return @as(i16, @bitCast(v));
}

const win = struct {
    pub const WINAPI: std.builtin.CallingConvention = .winapi;
    // Handles are opaque pointers; nullability is on the return/param, not double-optional.
    pub const HWND = *anyopaque;
    pub const HDC = *anyopaque;
    pub const HINSTANCE = *anyopaque;
    pub const HICON = *anyopaque;
    pub const HCURSOR = *anyopaque;
    pub const HBRUSH = *anyopaque;
    pub const HMENU = *anyopaque;
    pub const WPARAM = usize;
    pub const LPARAM = isize;
    pub const LRESULT = isize;

    pub const WM_CLOSE: u32 = 0x0010;
    pub const WM_DESTROY: u32 = 0x0002;
    pub const WM_QUIT: u32 = 0x0012;
    pub const WM_MOUSEWHEEL: u32 = 0x020A;
    pub const WM_LBUTTONDOWN: u32 = 0x0201;
    pub const WM_LBUTTONUP: u32 = 0x0202;
    pub const WM_MOUSEMOVE: u32 = 0x0200;
    pub const WM_KEYDOWN: u32 = 0x0100;
    pub const WM_KEYUP: u32 = 0x0101;
    pub const WM_CHAR: u32 = 0x0102;
    pub const VK_ESCAPE: usize = 0x1B;
    pub const VK_BACK: usize = 0x08;
    pub const VK_TAB: usize = 0x09;
    pub const VK_RETURN: usize = 0x0D;
    pub const VK_SHIFT: i32 = 0x10;
    pub const PM_REMOVE: u32 = 0x0001;
    pub const SW_SHOW: i32 = 5;
    pub const CW_USEDEFAULT: i32 = -2147483648;
    pub const WS_OVERLAPPEDWINDOW: u32 = 0x00CF0000;
    pub const BI_BITFIELDS: u32 = 3;
    pub const DIB_RGB_COLORS: u32 = 0;
    pub const SRCCOPY: u32 = 0x00CC0020;
    pub const IDC_ARROW: [*:0]const u16 = @ptrFromInt(32512);

    pub const RECT = extern struct { left: i32, top: i32, right: i32, bottom: i32 };
    pub const POINT = extern struct { x: i32, y: i32 };
    pub const MSG = extern struct {
        hwnd: ?HWND,
        message: u32,
        wParam: WPARAM,
        lParam: LPARAM,
        time: u32,
        pt: POINT,
    };
    pub const WNDCLASSW = extern struct {
        style: u32,
        lpfnWndProc: *const fn (?HWND, u32, WPARAM, LPARAM) callconv(WINAPI) LRESULT,
        cbClsExtra: i32,
        cbWndExtra: i32,
        hInstance: HINSTANCE,
        hIcon: ?HICON,
        hCursor: ?HCURSOR,
        hbrBackground: ?HBRUSH,
        lpszMenuName: ?[*:0]const u16,
        lpszClassName: [*:0]const u16,
    };
    pub const BITMAPINFOHEADER = extern struct {
        biSize: u32,
        biWidth: i32,
        biHeight: i32,
        biPlanes: u16,
        biBitCount: u16,
        biCompression: u32,
        biSizeImage: u32,
        biXPelsPerMeter: i32,
        biYPelsPerMeter: i32,
        biClrUsed: u32,
        biClrImportant: u32,
    };

    pub const kernel32 = struct {
        pub extern "kernel32" fn GetModuleHandleW(lpModuleName: ?[*:0]const u16) callconv(WINAPI) ?HINSTANCE;
        pub extern "kernel32" fn Sleep(dwMilliseconds: u32) callconv(WINAPI) void;
        pub extern "kernel32" fn GetTickCount64() callconv(WINAPI) u64;
    };
    pub const user32 = struct {
        pub extern "user32" fn RegisterClassW(lpWndClass: *const WNDCLASSW) callconv(WINAPI) u16;
        pub extern "user32" fn CreateWindowExW(
            dwExStyle: u32,
            lpClassName: [*:0]const u16,
            lpWindowName: [*:0]const u16,
            dwStyle: u32,
            X: i32,
            Y: i32,
            nWidth: i32,
            nHeight: i32,
            hWndParent: ?HWND,
            hMenu: ?HMENU,
            hInstance: HINSTANCE,
            lpParam: ?*anyopaque,
        ) callconv(WINAPI) ?HWND;
        pub extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: i32) callconv(WINAPI) i32;
        pub extern "user32" fn UpdateWindow(hWnd: HWND) callconv(WINAPI) i32;
        pub extern "user32" fn DestroyWindow(hWnd: HWND) callconv(WINAPI) i32;
        pub extern "user32" fn GetDC(hWnd: HWND) callconv(WINAPI) ?HDC;
        pub extern "user32" fn ReleaseDC(hWnd: ?HWND, hDC: HDC) callconv(WINAPI) i32;
        pub extern "user32" fn PeekMessageW(lpMsg: *MSG, hWnd: ?HWND, wMsgFilterMin: u32, wMsgFilterMax: u32, wRemoveMsg: u32) callconv(WINAPI) i32;
        pub extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(WINAPI) i32;
        pub extern "user32" fn DispatchMessageW(lpMsg: *const MSG) callconv(WINAPI) LRESULT;
        pub extern "user32" fn DefWindowProcW(hWnd: ?HWND, Msg: u32, wParam: WPARAM, lParam: LPARAM) callconv(WINAPI) LRESULT;
        pub extern "user32" fn PostQuitMessage(nExitCode: i32) callconv(WINAPI) void;
        pub extern "user32" fn LoadCursorW(hInstance: ?HINSTANCE, lpCursorName: [*:0]const u16) callconv(WINAPI) ?HCURSOR;
        pub extern "user32" fn AdjustWindowRect(lpRect: *RECT, dwStyle: u32, bMenu: i32) callconv(WINAPI) i32;
    };
    pub const gdi32 = struct {
        pub extern "gdi32" fn StretchDIBits(
            hdc: HDC,
            xDest: i32,
            yDest: i32,
            DestWidth: i32,
            DestHeight: i32,
            xSrc: i32,
            ySrc: i32,
            SrcWidth: i32,
            SrcHeight: i32,
            lpBits: ?*const anyopaque,
            lpbmi: *const anyopaque,
            iUsage: u32,
            rop: u32,
        ) callconv(WINAPI) i32;
    };
};
