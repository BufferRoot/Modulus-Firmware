//! DSP HAL — FFT/IIR pipeline on Core 1 (`dsp_shim.c` + esp-dsp).

const build_options = @import("build_options");
const idf_dsp_mod = if (build_options.device_nvs)
    @import("idf_dsp.zig")
else
    struct {
        pub fn hwInit() void {}
        pub fn hwProcess() void {}
        pub fn isReady() bool {
            return false;
        }
    };

pub const Dsp = struct {
    initialized: bool = false,

    pub fn init(self: *Dsp) void {
        if (build_options.device_nvs) {
            idf_dsp_mod.hwInit();
        }
        self.initialized = true;
    }

    pub fn process(self: *const Dsp) void {
        if (!self.initialized) return;
        idf_dsp_mod.hwProcess();
    }

    pub fn isReady(self: *const Dsp) bool {
        if (!self.initialized) return false;
        return idf_dsp_mod.isReady();
    }
};
