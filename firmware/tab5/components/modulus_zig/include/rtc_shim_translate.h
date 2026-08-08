#pragma once

/* Translate-C safe RTC API — forward-declares struct tm (no time.h). Full API: rtc_shim.h */

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

struct tm;

void modulus_rtc_init(void);
bool modulus_rtc_is_ready(void);

void modulus_rtc_apply_timezone(void);
void modulus_rtc_tz_changed(uint8_t tz_idx);

void modulus_rtc_format_time(char *buf, size_t len);
void modulus_rtc_format_date(char *buf, size_t len);
void modulus_rtc_get_local_time(struct tm *out);

bool modulus_rtc_set_local_time(int year, int month, int day, int hour, int min, int sec);
bool modulus_rtc_write_hw_from_system(void);

const char *modulus_rtc_ntp_status_text(void);
bool modulus_rtc_ntp_sync_now(void);
void modulus_rtc_ntp_on_wifi_connected(void);
void modulus_rtc_ntp_poll(void);
void modulus_rtc_ntp_set_enabled(bool enabled);

void modulus_rtc_format_uptime(char *buf, size_t len);

#ifdef __cplusplus
}
#endif
