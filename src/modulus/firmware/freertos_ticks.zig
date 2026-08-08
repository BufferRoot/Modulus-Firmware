//! FreeRTOS tick conversion — `CONFIG_FREERTOS_HZ` = 1000 in Tab5 sdkconfig.

/// Match `CONFIG_FREERTOS_HZ` in `firmware/tab5/sdkconfig.defaults`.
pub const hz: u32 = 1000;

pub fn msToTicks(ms: u32) u32 {
    return @max(@as(u32, 1), (ms * hz + 999) / 1000);
}
