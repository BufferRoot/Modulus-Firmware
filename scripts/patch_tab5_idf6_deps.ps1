# Apply IDF 6.0 dependency patches to managed components (esp_hosted, audio player).
$ErrorActionPreference = "Stop"
$Tab5 = Join-Path (Split-Path -Parent $PSScriptRoot) "firmware\tab5"
$Tab5C6 = Join-Path (Split-Path -Parent $PSScriptRoot) "firmware\tab5-c6"
$HostedCmake = Join-Path $Tab5 "managed_components\espressif__esp_hosted\CMakeLists.txt"
$AudioCmake = Join-Path $Tab5 "managed_components\chmorgan__esp-audio-player\CMakeLists.txt"

if (Test-Path $HostedCmake) {
    $h = Get-Content $HostedCmake -Raw
    $h2 = $h -replace 'PRIV_REQUIRES soc esp_event esp_netif esp_timer driver esp_wifi', `
        'PRIV_REQUIRES soc esp_event esp_netif esp_timer esp_driver_sdmmc esp_driver_sdspi driver esp_wifi'
    if ($h -ne $h2) {
        Set-Content -Path $HostedCmake -Value $h2 -NoNewline
        Write-Host "Patched espressif__esp_hosted CMakeLists for IDF 6 sdmmc"
    }
}

# NOTE: Do NOT strip esp_hosted's final H_RESET_VAL_ACTIVE write from the SDIO
# reset pulse. GPIO15 -> C6 CHIP_EN is configured ACTIVE HIGH
# (CONFIG_ESP_HOSTED_RESET_GPIO_ACTIVE_LOW unset), so ACTIVE = HIGH = C6 enabled.
# Upstream sequence (HIGH -> LOW pulse -> HIGH -> boot delay) is correct and must
# stand: ending on LOW holds the C6 in reset on the internal WLAN rail and every
# CMD5 times out (0x107). A prior patch here inverted that and was the SDIO bug.

$HostOs = Join-Path $Tab5 "managed_components\espressif__esp_hosted\host\port\esp\freertos\src\port_esp_hosted_host_os.c"
if (Test-Path $HostOs) {
    $o = Get-Content $HostOs -Raw
    # Tab5: transport retries re-call hosted_config_gpio on GPIO15 — release before reconfig.
    if ($o -notmatch 'gpio_reset_pin\(gpio_num\);\s*\r?\n\s*gpio_hold_dis\(gpio_num\);') {
        $o2 = $o -replace '(int hosted_config_gpio\(void\* gpio_port, uint32_t gpio_num, uint32_t mode\)\r?\n\{[^}]+io_conf=\{[^}]+\};\r?\n)(\s*ESP_LOGI\(TAG, "GPIO \[%d\] configured", \(int\) gpio_num\);\r?\n\s*gpio_config\(&io_conf\);)', @'
$1	gpio_reset_pin(gpio_num);
	gpio_hold_dis(gpio_num);
$2
'@
        if ($o -ne $o2) {
            Set-Content -Path $HostOs -Value $o2 -NoNewline
            Write-Host "Patched esp_hosted port_esp_hosted_host_os: gpio_reset_pin before config (retry-safe)"
        }
    }
}

$IfaceHdrs = @(
    (Join-Path $Tab5 "managed_components\espressif__esp_hosted\common\esp_hosted_interface.h"),
    (Join-Path $Tab5C6 "main\common\esp_hosted_interface.h")
)
$SdioDrvHost = Join-Path $Tab5 "managed_components\espressif__esp_hosted\host\drivers\transport\sdio\sdio_drv.c"
if (Test-Path $SdioDrvHost) {
    $sd = Get-Content $SdioDrvHost -Raw
    $sdOrig = $sd

    # Modulus SDIO RX diagnostics + streaming padding skip + queue-depth logging
    if ($sd -notmatch 'modulus_sdio_diag_t') {
        $sd = $sd -replace '(semaphore_handle_t sem_from_slave_queue;\r?\n)',
            @'
$1
/* Modulus: rate-limited SDIO RX diagnostics (patch_tab5_idf6_deps.ps1) */
#define MODULUS_SDIO_DRAIN_CHUNK (16384) /* stale-session drain chunk, 512-multiple */
typedef struct {
	uint32_t stream_drop;
	uint32_t queue_stall;
	uint32_t pad_skip;
	int64_t last_log_us;
} modulus_sdio_diag_t;

static modulus_sdio_diag_t s_sdio_diag;

extern void modulus_c6_sdio_health(uint32_t stream_drop, uint32_t queue_stall, uint32_t pad_skip);

static uint8_t sdio_rx_pkt_prio(uint8_t if_type)
{
	if (if_type == ESP_SERIAL_IF)
		return PRIO_Q_SERIAL;
	if (if_type == ESP_HCI_IF)
		return PRIO_Q_BT;
	return PRIO_Q_OTHERS;
}

static void modulus_sdio_diag_log(const char *reason, uint8_t if_type, uint16_t len,
		uint16_t offset, uint32_t stream_remain, uint8_t prio_q)
{
	int64_t now = esp_timer_get_time();
	if (s_sdio_diag.last_log_us && (now - s_sdio_diag.last_log_us) < 500000LL) {
		return;
	}
	s_sdio_diag.last_log_us = now;
	uint32_t q_depth = 0;
	if (from_slave_queue[prio_q]) {
		q_depth = (uint32_t)g_h.funcs->_h_queue_msg_waiting(from_slave_queue[prio_q]);
	}
	ESP_LOGW(TAG, "RX drop [%s] if=%u len=%u off=%u stream_left=%lu q[%u]_depth=%lu "
		"(tot pad_skip=%lu stream_drop=%lu stall=%lu)",
		reason, (unsigned)if_type, (unsigned)len, (unsigned)offset,
		(unsigned long)stream_remain, (unsigned)prio_q, (unsigned long)q_depth,
		(unsigned long)s_sdio_diag.pad_skip,
		(unsigned long)s_sdio_diag.stream_drop,
		(unsigned long)s_sdio_diag.queue_stall);
	modulus_c6_sdio_health(s_sdio_diag.stream_drop, s_sdio_diag.queue_stall, s_sdio_diag.pad_skip);
}

'@
        if ($sd -notmatch '#include "esp_timer.h"') {
            $sd = $sd -replace '(#include "esp_hosted_event.h"\r?\n)', "`$1#include `"esp_timer.h`"`r`n"
        }
        Write-Host "Patched host sdio_drv.c: Modulus SDIO RX diagnostics"
    }

    if ($sd -match 'if \(!is_valid_sdio_rx_packet\(buf, &len, &offset\)\) \{\r?\n\t\t\t/\* Have to drop packets in the stream') {
        $sd2 = $sd -replace 'if \(!is_valid_sdio_rx_packet\(buf, &len, &offset\)\) \{\r?\n\t\t\t/\* Have to drop packets in the stream[\s\S]*?\r?\n\t\t\treturn ESP_FAIL;\r?\n\t\t\}',
            @'
if (!is_valid_sdio_rx_packet(buf, &len, &offset)) {
			struct esp_payload_header *bad_h = (struct esp_payload_header *)buf;
			uint16_t bad_len = le16toh(bad_h->len);
			uint16_t bad_off = le16toh(bad_h->offset);
			/* Trailing SDIO stream padding: header-only zero-len slot after last packet */
			if (bad_len == 0 && bad_off == sizeof(struct esp_payload_header) &&
					buf_len >= bad_off) {
				s_sdio_diag.pad_skip++;
				buf_len -= bad_off;
				buf += bad_off;
				continue;
			}
			s_sdio_diag.stream_drop++;
			modulus_sdio_diag_log("stream_parse", bad_h->if_type, bad_len, bad_off,
				(uint32_t)buf_len, sdio_rx_pkt_prio(bad_h->if_type));
			return ESP_FAIL;
		}
'@
        if ($sd -ne $sd2) {
            $sd = $sd2
            Write-Host "Patched host sdio_drv.c: skip zero-len stream padding"
        }
    }

    if ($sd -match 'g_h\.funcs->_h_queue_item\(from_slave_queue\[pkt_prio\], &buf_handle, HOSTED_BLOCK_MAX\);\r?\n\tg_h\.funcs->_h_post_semaphore\(sem_from_slave_queue\);') {
        $sd2 = $sd -replace 'g_h\.funcs->_h_queue_item\(from_slave_queue\[pkt_prio\], &buf_handle, HOSTED_BLOCK_MAX\);\r?\n\tg_h\.funcs->_h_post_semaphore\(sem_from_slave_queue\);\r?\n\r?\n\treturn ESP_OK;',
            @'
if (g_h.funcs->_h_queue_item(from_slave_queue[pkt_prio], &buf_handle, HOSTED_BLOCK_MAX) != RET_OK) {
		s_sdio_diag.queue_stall++;
		modulus_sdio_diag_log("queue_push", h->if_type, len, offset, 0, pkt_prio);
		return ESP_FAIL;
	}
	g_h.funcs->_h_post_semaphore(sem_from_slave_queue);

	return ESP_OK;
'@
        if ($sd -ne $sd2) {
            $sd = $sd2
            Write-Host "Patched host sdio_drv.c: queue push failure logging"
        }
    }

    if ($sd -match 'if \(sdio_push_pkt_to_queue\(pkt_rxbuff, len, offset\)\) \{\r?\n\t\t\tESP_LOGI\(TAG, "Failed to push a packet to queue from stream"\);\r?\n\t\t\}') {
        $sd2 = $sd -replace 'if \(sdio_push_pkt_to_queue\(pkt_rxbuff, len, offset\)\) \{\r?\n\t\t\tESP_LOGI\(TAG, "Failed to push a packet to queue from stream"\);\r?\n\t\t\}',
            @'
if (sdio_push_pkt_to_queue(pkt_rxbuff, len, offset)) {
			ESP_LOGW(TAG, "Failed to push a packet to queue from stream (if=%u len=%u)",
				(unsigned)((struct esp_payload_header *)pkt_rxbuff)->if_type, (unsigned)len);
			sdio_buffer_free(pkt_rxbuff);
		}
'@
        if ($sd -ne $sd2) {
            $sd = $sd2
            Write-Host "Patched host sdio_drv.c: free buffer on stream queue push fail"
        }
    }

    if ($sd -match 'ESP_LOGE\(TAG, "task still writing Rx data to queue!"\);') {
        $sd2 = $sd -replace 'sdio_rx_free_buffer\(rxbuff\);\r?\n\t\t\tESP_LOGE\(TAG, "task still writing Rx data to queue!"\);',
            @'
sdio_rx_free_buffer(rxbuff);
			s_sdio_diag.queue_stall++;
			modulus_sdio_diag_log("double_buf_busy", 0, 0, 0, 0, PRIO_Q_OTHERS);
			ESP_LOGE(TAG, "task still writing Rx data to queue (rx path backpressure)");
'@
        if ($sd -ne $sd2) {
            $sd = $sd2
            Write-Host "Patched host sdio_drv.c: double-buffer stall diagnostics"
        }
    }

    if ($sd -match 'sdio_process_rx_thread = g_h\.funcs->_h_thread_create\("sdio_process_rx",\r?\n\t\tDFLT_TASK_PRIO,') {
        $sd2 = $sd -replace 'sdio_process_rx_thread = g_h\.funcs->_h_thread_create\("sdio_process_rx",\r?\n\t\tDFLT_TASK_PRIO,',
            "sdio_process_rx_thread = g_h.funcs->_h_thread_create(`"sdio_process_rx`",`r`n`t`tDFLT_TASK_PRIO + 1,"
        if ($sd -ne $sd2) {
            $sd = $sd2
            Write-Host "Patched host sdio_drv.c: raise sdio_process_rx task priority"
        }
    }

    if ($sd -notmatch 'modulus_c6_sdio_rx_dispatch') {
        if ($sd -notmatch 'extern void modulus_c6_sdio_rx_dispatch') {
            $sd = $sd -replace '(#include "hci_drv.h"\r?\n)', "`$1`r`n`r`nextern void modulus_c6_sdio_rx_dispatch(uint8_t if_type, const uint8_t *payload, uint16_t len);`r`n"
        }
        $sd2 = $sd -replace '\} else \{\r?\n\t\t\tESP_LOGW\(TAG, "unknown type %d ", buf_handle->if_type\);\r?\n\t\t\}',
            @'
} else if (buf_handle->if_type == ESP_ESPNOW_IF ||
			buf_handle->if_type == ESP_ZIGBEE_IF ||
			buf_handle->if_type == ESP_THREAD_IF) {
			modulus_c6_sdio_rx_dispatch(buf_handle->if_type,
				buf_handle->payload, buf_handle->payload_len);
		} else {
			ESP_LOGW(TAG, "unknown type %d ", buf_handle->if_type);
		}
'@
        if ($sd -ne $sd2) {
            $sd = $sd2
            Write-Host "Patched host sdio_drv.c: Modulus custom IF RX dispatch"
        }
    }

    # Modulus: RX counter resync v5 helpers + stale FIFO flush (see sdio_drv.c).
    if ($sd -notmatch 'modulus_sdio_slave_reset_and_reinit') {
        $recoverHelpers = @'

extern void modulus_sdio_slave_reset_notify(void) __attribute__((weak));
void modulus_sdio_slave_reset_notify(void) {}

static int64_t s_last_slave_gpio_reset_us = 0;

static esp_err_t transport_card_init(void *bus_handle, uint32_t timeout_ms);
static esp_err_t transport_gpio_reset(void *bus_handle, gpio_pin_t reset_pin);
static int modulus_sdio_slave_reset_and_reinit(void);
static int modulus_sdio_bus_recover(void);
static int modulus_sdio_counter_resync(void);
static int modulus_sdio_poll_slave_regs(int timeout_ms);
int ensure_slave_bus_ready(void *bus_handle);

'@
        $sd2 = $sd -replace '(static uint32_t sdio_rx_byte_count = 0;\r?\n)', "`$1$recoverHelpers"
        if ($sd -ne $sd2) {
            $sd = $sd2
            Write-Host "Patched host sdio_drv.c: forward decls for v5 SDIO recover"
        }
        $recoverFns = @'

#define CARD_INIT_TIMEOUT_MS 1500

static void modulus_sdio_reset_host_rx_state(void)
{
	double_buf.read_index = -1;
	double_buf.read_data_len = 0;
	double_buf.write_index = 0;
	if (sem_double_buf_xfer_data) {
		while (g_h.funcs->_h_get_semaphore(sem_double_buf_xfer_data, 0) == ESP_OK);
	}
	sdio_rx_byte_count = 0;
	sdio_tx_buf_count = 0;
}

static int modulus_sdio_poll_slave_regs(int timeout_ms)
{
	const int step_ms = 100;

	for (int elapsed = 0; elapsed < timeout_ms; elapsed += step_ms) {
		uint32_t probe = 0;

		if (g_h.funcs->_h_sdio_read_reg(sdio_handle, ESP_SLAVE_PACKET_LEN_REG,
				(uint8_t *)&probe, sizeof(probe), ACQUIRE_LOCK) != 0) {
			g_h.funcs->_h_msleep(step_ms);
			continue;
		}
        probe &= ESP_SLAVE_LEN_MASK;
		/* v6: after GPIO15 reset C6 may already stream init padding (non-zero
		 * PACKET_LEN). Align host counter to slave; v5 zero-wait never cleared
		 * during boot -> OPEN_DATA_PATH never ran -> ESP-NOW / WiFi down. */
		sdio_rx_byte_count = probe;
		ESP_LOGI(TAG, "slave PACKET_LEN readable: align host=%lu",
			(unsigned long)probe);
		return 0;
	}
	ESP_LOGW(TAG, "slave PACKET_LEN unreadable after %d ms", timeout_ms);
	return -1;
}

static int modulus_sdio_slave_reset_and_reinit(void)
{
	gpio_pin_t reset_pin = { .port = H_GPIO_PORT_RESET, .pin = H_GPIO_PIN_RESET };
	extern void *bus_handle;

	if (ESP_TRANSPORT_OK != esp_hosted_transport_get_reset_config(&reset_pin)) {
		return -1;
	}

	modulus_sdio_reset_host_rx_state();
	modulus_sdio_slave_reset_notify();
	if (transport_gpio_reset(bus_handle, reset_pin) != ESP_OK) {
		return -1;
	}
	s_last_slave_gpio_reset_us = esp_timer_get_time();
	if (transport_card_init(bus_handle, CARD_INIT_TIMEOUT_MS) != ESP_OK) {
		return -1;
	}
	if (modulus_sdio_poll_slave_regs(H_HOST_SDIO_RESET_DELAY_MS) != 0) {
		ESP_LOGW(TAG, "slave register poll timeout after GPIO reset");
		return -1;
	}
	return 0;
}

/* Modulus: recover wedged SDIO after CMD53 0x107 or register failure. */
static int modulus_sdio_bus_recover(void)
{
	extern void *bus_handle;
	const int64_t cooldown_us = (int64_t)H_HOST_SDIO_RESET_DELAY_MS * 1000LL;

	if (s_last_slave_gpio_reset_us &&
	    (esp_timer_get_time() - s_last_slave_gpio_reset_us) < cooldown_us) {
		ESP_LOGW(TAG, "Modulus: SDIO bus recover (card reinit only, skip GPIO)");
		modulus_sdio_reset_host_rx_state();
		if (transport_card_init(bus_handle, CARD_INIT_TIMEOUT_MS) != ESP_OK) {
			ESP_LOGE(TAG, "Modulus: card-only recover failed");
			return -1;
		}
		return 0;
	}

	ESP_LOGW(TAG, "Modulus: SDIO bus recover (GPIO15 reset + card reinit)");
	if (modulus_sdio_slave_reset_and_reinit() != 0) {
		ESP_LOGE(TAG, "Modulus: bus recover failed");
		return -1;
	}
	return 0;
}

/* Modulus: v6 stale-session resync. Returns 0 on success. */
static int modulus_sdio_counter_resync(void)
{
	uint32_t slave_cnt = 0;
	int rc = g_h.funcs->_h_sdio_read_reg(sdio_handle, ESP_SLAVE_PACKET_LEN_REG,
			(uint8_t *)&slave_cnt, sizeof(slave_cnt), ACQUIRE_LOCK);

	if (rc != 0) {
		ESP_LOGW(TAG, "RX counter resync: PACKET_LEN read failed (%d)", rc);
		return -1;
	}
	slave_cnt &= ESP_SLAVE_LEN_MASK;
	uint32_t stale;
	if (slave_cnt >= sdio_rx_byte_count)
		stale = slave_cnt - sdio_rx_byte_count;
	else
		stale = ESP_RX_BYTE_MAX - sdio_rx_byte_count + slave_cnt;
	if (stale == 0) {
		return 0;
	}
	if (stale < MODULUS_SDIO_GPIO_FLUSH_MIN) {
		ESP_LOGW(TAG, "RX counter resync v6: small stale %lu bytes "
			"(host %lu -> slave %lu) - align only",
			(unsigned long)stale, (unsigned long)sdio_rx_byte_count,
			(unsigned long)slave_cnt);
		sdio_rx_byte_count = slave_cnt;
		return 0;
	}
	ESP_LOGW(TAG, "RX counter resync v6: large stale %lu bytes "
		"(host %lu -> slave %lu) - GPIO15 flush",
		(unsigned long)stale, (unsigned long)sdio_rx_byte_count,
		(unsigned long)slave_cnt);
	if (modulus_sdio_slave_reset_and_reinit() != 0) {
		return -1;
	}
	ESP_LOGI(TAG, "RX counter resync v6: post-flush aligned host=%lu",
		(unsigned long)sdio_rx_byte_count);
	return 0;
}

'@
        $sd2 = [regex]::Replace($sd,
            '(#define CARD_INIT_DELAY_MS 100\r?\n)',
            "`$1$recoverFns")
        if ($sd -ne $sd2) {
            $sd = $sd2
            Write-Host "Patched host sdio_drv.c: v5 SDIO recover helpers"
        }
        # v5: stamp GPIO reset time in transport_gpio_reset
        if ($sd -notmatch 's_last_slave_gpio_reset_us = esp_timer_get_time') {
            $sd2 = $sd -replace '(g_h\.funcs->_h_msleep\(H_HOST_SDIO_RESET_DELAY_MS\);\r?\n)(\treturn ESP_OK;\r?\n\})',
                "`$1`t`s_last_slave_gpio_reset_us = esp_timer_get_time();`r`n`$2"
            if ($sd -ne $sd2) {
                $sd = $sd2
                Write-Host "Patched host sdio_drv.c: stamp last GPIO reset time"
            }
        }
        # v5: skip redundant GPIO reset in ensure_slave_bus_ready
        if ($sd -notmatch 'Skip redundant GPIO') {
            $sd2 = $sd -replace '(} else \{\r?\n\t\t/\* Always reset slave on host boot up \*/\r?\n\t\tESP_LOGW\(TAG, "Reset slave using GPIO\[%u\]", reset_pin\.pin\);\r?\n\t\ttransport_gpio_reset\(bus_handle, reset_pin\);\r?\n\r?\n\t\tres = transport_card_init\(bus_handle, CARD_INIT_TIMEOUT_MS\);)',
                @'
} else {
		const int64_t cooldown_us = (int64_t)H_HOST_SDIO_RESET_DELAY_MS * 1000LL;
		const int64_t now_us = esp_timer_get_time();

		if (s_last_slave_gpio_reset_us &&
		    (now_us - s_last_slave_gpio_reset_us) < cooldown_us) {
			ESP_LOGW(TAG, "Skip redundant GPIO[%u] reset (recent flush, card reinit only)",
				reset_pin.pin);
			res = transport_card_init(bus_handle, CARD_INIT_TIMEOUT_MS);
		} else {
			ESP_LOGW(TAG, "Reset slave using GPIO[%u]", reset_pin.pin);
			transport_gpio_reset(bus_handle, reset_pin);
			res = transport_card_init(bus_handle, CARD_INIT_TIMEOUT_MS);
		}
'@
            if ($sd -ne $sd2) {
                $sd = $sd2
                Write-Host "Patched host sdio_drv.c: skip redundant GPIO reset"
            }
        }
    }

    $resyncV6 = @'
	/* Modulus: RX counter resync v6 before OPEN_DATA_PATH.
	 * Small stale (<4 KiB): align host counter only — no GPIO15 during C6 boot.
	 * Large stale: GPIO15 flush + align to slave PACKET_LEN (not zero-wait).
	 * bus_recover skips redundant GPIO reset within boot delay window. */
	{
		int open_rc = -1;
		for (int boot_try = 0; boot_try < 3; boot_try++) {
			SDIO_DRV_LOCK();
			int resync_ok = modulus_sdio_counter_resync();
			SDIO_DRV_UNLOCK();

			if (resync_ok != 0) {
				if (modulus_sdio_bus_recover() != 0) {
					g_h.funcs->_h_msleep(200);
					continue;
				}
				continue;
			}

			open_rc = sdio_generate_slave_intr(ESP_OPEN_DATA_PATH);
			if (open_rc == 0) {
				break;
			}
			ESP_LOGW(TAG, "OPEN_DATA_PATH failed (%d) - bus recover (try %d)",
				open_rc, boot_try + 1);
			if (modulus_sdio_bus_recover() != 0) {
				g_h.funcs->_h_msleep(200);
			}
		}
		if (open_rc != 0) {
			ESP_LOGE(TAG, "OPEN_DATA_PATH failed after recover retries");
		}
	}
'@
    if ($sd -match 'RX counter resync v5' -and $sd -notmatch 'RX counter resync v6') {
        $sd2 = [regex]::Replace($sd,
            '/\* Modulus: RX counter resync v5[\s\S]*?OPEN_DATA_PATH failed after recover retries[\s\S]*?\r?\n\t\}',
            $resyncV6.TrimEnd())
        if ($sd -ne $sd2) {
            $sd = $sd2
            Write-Host "Patched host sdio_drv.c: RX counter resync v5 -> v6"
        }
        if ($sd -notmatch '#define\s+MODULUS_SDIO_GPIO_FLUSH_MIN') {
            $sd2 = $sd -replace '(#define MODULUS_SDIO_DRAIN_CHUNK \(16384\)[^\r\n]*)',
                "`$1`r`n#define MODULUS_SDIO_GPIO_FLUSH_MIN (4096) /* below: align counters only, no GPIO15 */"
            if ($sd -ne $sd2) {
                $sd = $sd2
                Write-Host "Patched host sdio_drv.c: MODULUS_SDIO_GPIO_FLUSH_MIN"
            }
        }
        # v6 poll_slave_regs + counter_resync body
        $sd2 = $sd -replace 'slave PACKET_LEN not clear after', 'slave PACKET_LEN unreadable after'
        if ($sd -ne $sd2) { $sd = $sd2 }
    }
    $resyncV5 = $resyncV6
    if ($sd -match 'RX counter resync v4' -and $sd -notmatch 'RX counter resync v5 - stale FIFO flush') {
        $sd2 = [regex]::Replace($sd,
            '/\* Modulus: RX counter resync v4[\s\S]*?OPEN_DATA_PATH failed after recover retries[\s\S]*?\r?\n\t\}',
            $resyncV5.TrimEnd())
        if ($sd -ne $sd2) {
            $sd = $sd2
            Write-Host "Patched host sdio_drv.c: RX counter resync v4 -> v5 (stale FIFO flush)"
        }
    } elseif ($sd -notmatch 'RX counter resync v5') {
        $sd2 = [regex]::Replace($sd,
            '(ESP_LOGI\(TAG, "Open data path at slave"\);)\s*\r?\n\s*\r?\n\s*(sdio_generate_slave_intr\(ESP_OPEN_DATA_PATH\);)',
            "`$1`r`n`r`n$resyncV5`r`n`r`n`t/* v5 replaces bare OPEN_DATA_PATH */")
        if ($sd -ne $sd2) {
            $sd = $sd2
            Write-Host "Patched host sdio_drv.c: RX counter resync v5 before OPEN_DATA_PATH"
        }
    }

    # Modulus: back off when register reads fail (bus down / slave re-enumerating).
    # The ~10ms spin floods the log and contends the CMD lines against concurrent
    # card re-init during transport reconfigure, making 0x107 permanent.
    if ($sd -notmatch 'Modulus: back off') {
        $sd2 = [regex]::Replace($sd,
            '(ESP_LOGE\(TAG, "failed to read (?:registers|interrupt register)"\);[\s\S]*?#endif\r?\n)(\t\t\tcontinue;)',
            @'
$1			/* Modulus: back off - bus likely down or mid re-enumeration */
			g_h.funcs->_h_msleep(100);
$2
'@)
        if ($sd -ne $sd2) {
            $sd = $sd2
            Write-Host "Patched host sdio_drv.c: backoff on register read failure"
        }
    }

    # Modulus: rx_buf parser must outrank sdio_read (equal priority starved the
    # double-buffer handoff -> "task still writing Rx data to queue" drops).
    if ($sd -match 'sdio_rx_buf_thread = g_h\.funcs->_h_thread_create\("sdio_rx_buf",\r?\n\t\tDFLT_TASK_PRIO,') {
        $sd2 = $sd -replace 'sdio_rx_buf_thread = g_h\.funcs->_h_thread_create\("sdio_rx_buf",\r?\n\t\tDFLT_TASK_PRIO,',
            "sdio_rx_buf_thread = g_h.funcs->_h_thread_create(`"sdio_rx_buf`",`r`n`t`tDFLT_TASK_PRIO + 1,"
        if ($sd -ne $sd2) {
            $sd = $sd2
            Write-Host "Patched host sdio_drv.c: raise sdio_rx_buf task priority"
        }
    }

    # Modulus: bounded grace wait before discarding an already-read SDIO chunk.
    if ($sd -notmatch 'grace window before declaring backpressure') {
        $sd2 = [regex]::Replace($sd,
            '(if \(unlikely\(ret\)\)\r?\n\t\t\tcontinue;\r?\n\r?\n)(\t\tif \(double_buf\.read_index < 0\) \{)',
            @'
$1		/* Modulus: data is already consumed off the SDIO bus - dropping it
		 * here loses packets permanently. Give the parser a short, bounded
		 * grace window before declaring backpressure. */
		if (double_buf.read_index >= 0) {
			int grace_ms = 0;
			while (double_buf.read_index >= 0 && grace_ms < 20) {
				g_h.funcs->_h_msleep(1);
				grace_ms++;
			}
		}

$2
'@)
        if ($sd -ne $sd2) {
            $sd = $sd2
            Write-Host "Patched host sdio_drv.c: double-buffer backpressure grace wait"
        }
    }

    if ($sd -ne $sdOrig) {
        try {
            Set-Content -Path $SdioDrvHost -Value $sd -NoNewline
        } catch {
            Write-Warning "Could not write $SdioDrvHost (in use) - edits may already be applied"
        }
    }
}

$TransportDrv = Join-Path $Tab5 "managed_components\espressif__esp_hosted\host\drivers\transport\transport_drv.c"
if (Test-Path $TransportDrv) {
    $td = Get-Content $TransportDrv -Raw
    $tdOldRetry = @'
				if (retry_slave_connection%50==0) {
					ESP_LOGI(TAG, "Not able to connect with ESP-Hosted slave device");
					if (ESP_OK != ensure_slave_bus_ready(bus_handle)) {
						ESP_LOGE(TAG, "ensure_slave_bus_ready failed");
						return ESP_FAIL;
					}
				}
'@
    $tdNewRetry = @'
				if (retry_slave_connection%50==0) {
					ESP_LOGI(TAG, "Not able to connect with ESP-Hosted slave device");
					/* Modulus: sdio_read_task may be mid v5 flush - do not
					 * GPIO-reset an RX-active bus; that races register reads. */
					if (!is_transport_rx_ready()) {
						if (ESP_OK != ensure_slave_bus_ready(bus_handle)) {
							ESP_LOGE(TAG, "ensure_slave_bus_ready failed");
							return ESP_FAIL;
						}
					} else if (retry_slave_connection >= 75) {
						ESP_LOGW(TAG, "RX active slave init timeout - bus recover");
						if (ESP_OK != ensure_slave_bus_ready(bus_handle)) {
							ESP_LOGE(TAG, "ensure_slave_bus_ready failed");
							return ESP_FAIL;
						}
					} else {
						ESP_LOGW(TAG, "RX active - awaiting slave init event (skip GPIO reset)");
					}
				}
'@
    if ($td -notmatch 'RX active - awaiting slave init event' -and $td.Contains($tdOldRetry)) {
        $td2 = $td.Replace($tdOldRetry, $tdNewRetry)
        Set-Content -Path $TransportDrv -Value $td2 -NoNewline
        Write-Host "Patched esp_hosted transport_drv.c: skip GPIO reset when RX active"
    }
}

foreach ($iface in $IfaceHdrs) {
    if (-not (Test-Path $iface)) { continue }
    $ih = Get-Content $iface -Raw
    if ($ih -notmatch 'ESP_ESPNOW_IF') {
        $ih2 = $ih -replace '(\s+ESP_ETH_IF,\r?\n)(\s+ESP_MAX_IF,)', "`$1`tESP_ESPNOW_IF,`r`n`tESP_ZIGBEE_IF,`r`n`tESP_THREAD_IF,`r`n`$2"
        if ($ih -ne $ih2) {
            Set-Content -Path $iface -Value $ih2 -NoNewline
            Write-Host "Patched $(Split-Path $iface -Leaf): Modulus SDIO custom IF types"
        }
    }
}

$RpcWrap = Join-Path $Tab5 "managed_components\espressif__esp_hosted\host\drivers\rpc\wrap\rpc_wrap.c"
if (Test-Path $RpcWrap) {
    $rw = Get-Content $RpcWrap -Raw
    $staStartNew = @'
					g_h.funcs->_h_event_wifi_post(wifi_event_id, 0, 0, HOSTED_BLOCK_MAX);
					/* C6 slave auto-connects on STA_START when provisioned.
					 * Do not call esp_wifi_get_config / rpc_wifi_connect_async here:
					 * synchronous Req_WifiGetConfig (0x11d) races SDIO boot and
					 * times out ~5 s; empty-SSID connect is already blocked on C6. */
					netif_started = true;
'@
    if ($rw -notmatch 'Req_WifiGetConfig \(0x11d\) races SDIO boot') {
        $staStartOldGetConfig = @'
					g_h.funcs->_h_event_wifi_post(wifi_event_id, 0, 0, HOSTED_BLOCK_MAX);
					wifi_config_t _sta_cfg = {0};
					if (esp_wifi_get_config(WIFI_IF_STA, &_sta_cfg) == ESP_OK &&
					    _sta_cfg.sta.ssid[0] != '\0') {
						rpc_wifi_connect_async();
					} else {
						ESP_LOGI(TAG, "STA started, no SSID — skip connect (ESP-NOW/idle)");
					}
					netif_started = true;
'@
        $staStartOldUpstream = @'
					g_h.funcs->_h_event_wifi_post(wifi_event_id, 0, 0, HOSTED_BLOCK_MAX);
					rpc_wifi_connect_async();
					netif_started = true;
'@
        if ($rw.Contains($staStartOldGetConfig)) {
            $rw2 = $rw.Replace($staStartOldGetConfig, $staStartNew)
            Set-Content -Path $RpcWrap -Value $rw2 -NoNewline
            Write-Host "Patched esp_hosted rpc_wrap.c: skip STA_START get_config/connect (was get_config patch)"
        } elseif ($rw.Contains($staStartOldUpstream)) {
            $rw2 = $rw.Replace($staStartOldUpstream, $staStartNew)
            Set-Content -Path $RpcWrap -Value $rw2 -NoNewline
            Write-Host "Patched esp_hosted rpc_wrap.c: skip STA_START get_config/connect (was upstream auto-connect)"
        }
    }
}

$RpcRsp = Join-Path $Tab5 "managed_components\espressif__esp_hosted\host\drivers\rpc\core\rpc_rsp.c"
if (Test-Path $RpcRsp) {
    $rr = Get-Content $RpcRsp -Raw
    if ($rr -notmatch 'esp_err_to_name\(\(esp_err_t\)app_resp->resp_event_status\)') {
        if ($rr -notmatch '#include "esp_err.h"') {
            $rr = $rr.Replace('#include "esp_hosted_os_abstraction.h"', "#include `"esp_hosted_os_abstraction.h`"`r`n#include `"esp_err.h`"")
        }
        $oldMacro = @'
        ESP_LOGW(TAG, "Hosted RPC_Resp [0x%"PRIx16"], uid [%"PRIu32"], resp code [%"PRIi32"]", \
                app_resp->msg_id, app_resp->uid, app_resp->resp_event_status); \
'@
        $newMacro = @'
        ESP_LOGW(TAG, "Hosted RPC_Resp [0x%"PRIx16"], uid [%"PRIu32"], resp code [%"PRIi32"] (%s)", \
                app_resp->msg_id, app_resp->uid, app_resp->resp_event_status, \
                esp_err_to_name((esp_err_t)app_resp->resp_event_status)); \
'@
        if ($rr.Contains($oldMacro)) {
            $rr2 = $rr.Replace($oldMacro, $newMacro)
            Set-Content -Path $RpcRsp -Value $rr2 -NoNewline
            Write-Host "Patched esp_hosted rpc_rsp.c: log esp_err_to_name for RPC errors"
        }
    }
}

$C6Sdio = Join-Path $Tab5C6 "main\sdio_slave_api.c"
if (Test-Path $C6Sdio) {
    $s = Get-Content $C6Sdio -Raw
    if ($s -match '#include "soc/sdio_slave_periph.h"') {
        $s2 = $s -replace '#include "soc/sdio_slave_periph.h"', '#include "hal/sdio_slave_periph.h"'
        Set-Content -Path $C6Sdio -Value $s2 -NoNewline
        Write-Host "Patched tab5-c6 sdio_slave_api: hal/sdio_slave_periph.h (IDF 6)"
    }
}

if (Test-Path $AudioCmake) {
    $a = Get-Content $AudioCmake -Raw
    $aOrig = $a
    if ($a -match 'REQUIRES driver') {
        $a = $a -replace 'REQUIRES driver', 'REQUIRES esp_driver_i2s'
    }
    # GCC 15: reinterpret_cast<void*>(fn_ptr) → -Wignored-qualifiers; component
    # treats warnings as errors (BufferRoot/Modulus-Firmware#2).
    if ($a -notmatch 'Wno-error=ignored-qualifiers') {
        $a = $a.TrimEnd() + "`r`n`r`ntarget_compile_options(`${COMPONENT_LIB} PRIVATE -Wno-error=ignored-qualifiers)`r`n"
    }
    if ($a -ne $aOrig) {
        Set-Content -Path $AudioCmake -Value $a -NoNewline
        Write-Host "Patched chmorgan__esp-audio-player for esp_driver_i2s + GCC 15 ignored-qualifiers"
    }
}

# bmi270_sensor ships prebuilt libs for IDF 5.3-5.5 only; IDF 6.x must fall back in CMake.
$Bmi270Root = Join-Path $Tab5 "managed_components\espressif__bmi270_sensor"
$Bmi270Cmake = Join-Path $Bmi270Root "CMakeLists.txt"
if (Test-Path $Bmi270Cmake) {
    $bc = Get-Content $Bmi270Cmake -Raw
    if ($bc -notmatch '_bmi270_lib') {
        $pat = '(?ms)^if\(NOT EXISTS "\$\{CMAKE_CURRENT_SOURCE_DIR\}/bmi270_api\.c"\)\r?\n\s+add_prebuilt_library\(bmi270_lib "\$\{CMAKE_CURRENT_SOURCE_DIR\}/\$\{IDF_VERSION_MAJOR\}\.\$\{IDF_VERSION_MINOR\}/\$\{CONFIG_IDF_TARGET\}/libbmi270_sensor\.a"\)'
        $repl = @'
if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/bmi270_api.c")
    set(_bmi270_lib "${CMAKE_CURRENT_SOURCE_DIR}/${IDF_VERSION_MAJOR}.${IDF_VERSION_MINOR}/${CONFIG_IDF_TARGET}/libbmi270_sensor.a")
    if(NOT EXISTS "${_bmi270_lib}")
        foreach(_ver 5.5 5.4 5.3)
            set(_try "${CMAKE_CURRENT_SOURCE_DIR}/${_ver}/${CONFIG_IDF_TARGET}/libbmi270_sensor.a")
            if(EXISTS "${_try}")
                set(_bmi270_lib "${_try}")
                break()
            endif()
        endforeach()
    endif()
    if(NOT EXISTS "${_bmi270_lib}")
        message(FATAL_ERROR "bmi270_sensor prebuilt missing for ${CONFIG_IDF_TARGET} (IDF ${IDF_VERSION_MAJOR}.${IDF_VERSION_MINOR})")
    endif()
    add_prebuilt_library(bmi270_lib "${_bmi270_lib}")
'@
        $bc2 = [regex]::Replace($bc, $pat, $repl)
        if ($bc -ne $bc2) {
            Set-Content -Path $Bmi270Cmake -Value $bc2 -NoNewline
            Write-Host "Patched espressif__bmi270_sensor CMakeLists: IDF 6.x -> 5.5 prebuilt fallback"
        }
    }
}

