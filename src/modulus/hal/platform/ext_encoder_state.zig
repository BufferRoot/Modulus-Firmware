//! ExtEncoder instance state — lifecycle and motion accumulator reset.

const build_options = @import("build_options");
const cnc_state = @import("../../cnc/cnc_state.zig");
const driver = @import("../../cnc/driver.zig");
const settings_keys = @import("../../core/settings_keys.zig");
const settings_store = @import("../../core/settings_store.zig");
const i2c_coex = @import("i2c_coex.zig");
const consts = @import("ext_encoder_const.zig");
const util = @import("ext_encoder_util.zig");
const idf_ext = if (build_options.device_nvs)
    @import("idf_ext_encoder.zig")
else
    struct {};

pub const ExtEncoder = struct {
    coex: *i2c_coex.I2cCoex,
    store: ?*settings_store.Store = null,
    drv: ?*driver.Driver = null,
    connected: bool = false,
    count: i32 = 0,
    last_count: i32 = 0,
    pulse_remainder: i32 = 0,
    pending_steps: i32 = 0,
    cont_feed: f32 = 0,
    last_cont_sign: i32 = 0,
    last_jog_mode: cnc_state.JogMode = .step,
    last_poll_ms: u32 = 0,
    jog_active: bool = false,
    fw_version: u8 = 2,
    encdiv: u8 = 2,
    mpgpol: u8 = 0,
    jogspd: u16 = 1000,
    /// CONT feed scale, percent (settings_keys.cnc_contpct, 10–200).
    contpct: u8 = 100,
    /// STEP accuracy mode — detent queue never clamps (exact wheel distance).
    step_acc: bool = false,
    /// Coalesce window (ms) before draining STEP queue.
    coal_ms: u8 = consts.default_coal_ms,
    /// Max |pending_steps| when not in accuracy mode.
    pend_max: i32 = consts.default_pend_max,
    /// Timestamp of last STEP drain / CONT jog send.
    last_jog_send_ms: u32 = 0,
    /// Timestamp of the most recent non-zero encoder delta.
    last_wheel_move_ms: u32 = 0,
    /// First detent arrival in current coalesce window.
    coal_start_ms: u32 = 0,
    /// Per-chip jog increments from NVS `cnc_incr` (mm) — handwheel distance.
    increments: [4]f32 = .{ 0.001, 0.01, 0.1, 1.0 },

    pub fn init(self: *ExtEncoder, coex: *i2c_coex.I2cCoex, drv: *driver.Driver, store: *settings_store.Store) void {
        self.coex = coex;
        self.drv = drv;
        self.store = store;
        self.reloadJogSettings();
        if (build_options.device_nvs) {
            idf_ext.hwInit();
        }
    }

    pub fn reloadJogSettings(self: *ExtEncoder) void {
        if (self.store) |s| {
            self.encdiv = util.loadEncdivFromStore(s);
            self.mpgpol = s.getU8(settings_keys.cnc_mpgpol, 0);
            self.jogspd = util.loadJogspdFromStore(s);
            self.contpct = util.loadContPctFromStore(s);
            self.step_acc = s.getU8(settings_keys.cnc_stepacc, 0) != 0;
            self.coal_ms = s.getU8(settings_keys.jog_coal_ms, consts.default_coal_ms);
            const pm = s.getU8(settings_keys.jog_pend_max, consts.default_pend_max);
            self.pend_max = if (pm < 4) 4 else @as(i32, pm);
            util.loadIncrementsFromStore(s, &self.increments);
        }
    }

    pub fn deinit(self: *ExtEncoder) void {
        if (self.jog_active) {
            if (self.drv) |d| d.cmdJogCancel();
            self.jog_active = false;
        }
        if (build_options.device_nvs) {
            idf_ext.hwDeinit();
        }
        self.connected = false;
        self.resetJogMotion();
    }

    pub fn connectMock(self: *ExtEncoder) void {
        self.connected = true;
        self.last_count = self.count;
        self.resetJogMotion();
    }

    pub fn isConnected(self: *const ExtEncoder) bool {
        return self.connected;
    }

    pub fn getCount(self: *const ExtEncoder) i32 {
        return self.count;
    }

    pub fn setCount(self: *ExtEncoder, value: i32) void {
        self.count = value;
    }

    pub fn resetCount(self: *ExtEncoder) void {
        self.count = 0;
        self.last_count = 0;
        self.resetJogMotion();
    }

    pub fn resetJogMotion(self: *ExtEncoder) void {
        self.pulse_remainder = 0;
        self.pending_steps = 0;
        self.cont_feed = 0;
        self.last_cont_sign = 0;
        self.last_wheel_move_ms = 0;
    }

    pub fn clampPending(self: *ExtEncoder) void {
        if (self.step_acc) return; // accuracy mode: never drop queued detents
        const lim = if (self.pend_max > 0) self.pend_max else consts.step_queue_max;
        if (self.pending_steps > lim) {
            self.pending_steps = lim;
        } else if (self.pending_steps < -lim) {
            self.pending_steps = -lim;
        }
    }

    pub fn poll(self: *ExtEncoder, now_ms: u32) void {
        @import("ext_encoder_poll.zig").run(self, now_ms);
    }

    pub fn onDisconnect(self: *ExtEncoder) void {
        if (self.jog_active) {
            if (self.drv) |d| d.cmdJogCancel();
            self.jog_active = false;
        }
        self.resetJogMotion();
        self.last_count = self.count;
    }
};
