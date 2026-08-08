#include "ui_settings_priv.h"
#include "ui_settings_common.h"
#include "nvs_shim.h"
#include "audio_shim.h"

#include <stdio.h>
#include <string.h>

static bool s_audio_ref_exp = false;
static lv_obj_t *s_audio_vol_slider = NULL;
static lv_obj_t *s_audio_tsound = NULL;
static lv_obj_t *s_audio_tone = NULL;
static lv_obj_t *s_audio_mic = NULL;

static void audio_clear_widget_refs(void)
{
    s_audio_vol_slider = NULL;
    s_audio_tsound = NULL;
    s_audio_tone = NULL;
    s_audio_mic = NULL;
}

static void audio_set_control_enabled(lv_obj_t *ctrl, bool enabled)
{
    if (!ctrl) {
        return;
    }
    modulus_ui_settings_row_set_enabled(lv_obj_get_parent(ctrl), ctrl, enabled);
}

static void audio_sync_codec_ui(void)
{
    const bool out = modulus_audio_is_output_ready();
    const bool mic = modulus_audio_is_input_ready();
    audio_set_control_enabled(s_audio_vol_slider, out);
    audio_set_control_enabled(s_audio_tsound, out);
    audio_set_control_enabled(s_audio_tone, out);
    audio_set_control_enabled(s_audio_mic, mic);
}

static void toggle_nvs_u8_cb(lv_event_t *e)
{
    const char *key = lv_event_get_user_data(e);
    modulus_nvs_set_u8(key, lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED) ? 1 : 0);
}

static void audio_vol_label_set(lv_obj_t *vl, uint8_t val)
{
    if (!vl) {
        return;
    }
    char buf[12];
    snprintf(buf, sizeof(buf), "%u%%", val);
    modulus_ui_label_set_text_if_changed(vl, buf);
}

static void audio_vol_cb(lv_event_t *e)
{
    const lv_event_code_t code = lv_event_get_code(e);
    if (code != LV_EVENT_VALUE_CHANGED && code != LV_EVENT_RELEASED) {
        return;
    }
    lv_obj_t *s = lv_event_get_target(e);
    const uint8_t val = (uint8_t)lv_slider_get_value(s);
    modulus_audio_set_volume(val);
    audio_vol_label_set(lv_obj_get_user_data(s), val);
    if (code == LV_EVENT_RELEASED) {
        modulus_nvs_set_u8("vol", val);
    }
}

static void audio_tsound_cb(lv_event_t *e)
{
    const bool on = lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED);
    modulus_audio_set_touch_sounds(on);
    /* Global pointer-indev RELEASED hook plays UI_TICK — no duplicate here (C++ v1.5). */
}

static void audio_tone_cb(lv_event_t *e)
{
    uint8_t idx = modulus_ui_segmented_get_selected(lv_event_get_target(e));
    if (idx >= 4) {
        idx = 0;
    }
    modulus_audio_set_tone_profile(idx);
    modulus_audio_play_ui(MODULUS_UI_SOUND_POP);
}

static void audio_mic_cb(lv_event_t *e)
{
    uint8_t idx = (uint8_t)modulus_ui_segmented_get_selected(lv_event_get_target(e));
    if (idx >= 5) {
        idx = 2;
    }
    modulus_nvs_set_u8("mic_gain", idx);
    modulus_audio_set_mic_gain_idx(idx);
}

void modulus_ui_settings_audio_tab_pause_activity(void)
{
    s_audio_ref_exp = false;
    audio_clear_widget_refs();
}

void modulus_ui_settings_build_audio_tab(void)
{
    lv_obj_t *p = modulus_ui_settings_tab_panel(MOD_UI_SETTINGS_TAB_AUDIO);
    if (!p) {
        return;
    }

    const lv_coord_t scroll_y = lv_obj_get_scroll_y(p);
    lv_obj_clean(p);
    audio_clear_widget_refs();

    if (!modulus_audio_is_output_ready()) {
        settings_detail_row(p, "Output", "Codec unavailable");
    }

    settings_section(p, "Volume", NULL);
    {
        const uint8_t cur_vol = modulus_audio_get_volume();
        lv_obj_t *vol = settings_slider_row(p, "Master volume", cur_vol, 0, 100);
        s_audio_vol_slider = vol;
        lv_obj_add_event_cb(vol, audio_vol_cb, LV_EVENT_VALUE_CHANGED, NULL);
        lv_obj_add_event_cb(vol, audio_vol_cb, LV_EVENT_RELEASED, NULL);
        audio_vol_label_set(lv_obj_get_user_data(vol), cur_vol);
    }

    settings_section(p, "Touch feedback", NULL);
    lv_obj_t *ts = settings_toggle_row(p, "Touch sounds", modulus_audio_touch_sounds_enabled());
    s_audio_tsound = ts;
    lv_obj_add_event_cb(ts, audio_tsound_cb, LV_EVENT_VALUE_CHANGED, NULL);
    {
        uint8_t tone_idx = modulus_audio_get_tone_profile();
        if (tone_idx >= 4) {
            tone_idx = 0;
        }
        static const char *const k_tones[] = {"Standard", "Soft", "Crisp", "Industrial"};
        lv_obj_t *tp = settings_segmented_row(p, "Tone profile", k_tones, 4, tone_idx, 96);
        s_audio_tone = tp;
        lv_obj_add_event_cb(tp, audio_tone_cb, LV_EVENT_VALUE_CHANGED, NULL);
    }

    settings_section(p, "System sounds", NULL);
    {
        lv_obj_t *su = settings_toggle_row(p, "Startup sound", modulus_nvs_get_u8("snd_up", 1) != 0);
        lv_obj_add_event_cb(su, toggle_nvs_u8_cb, LV_EVENT_VALUE_CHANGED, (void *)"snd_up");
        lv_obj_t *sd = settings_toggle_row(p, "Shutdown sound", modulus_nvs_get_u8("snd_dn", 1) != 0);
        lv_obj_add_event_cb(sd, toggle_nvs_u8_cb, LV_EVENT_VALUE_CHANGED, (void *)"snd_dn");
    }

    settings_section(p, "Microphone", NULL);
    settings_detail_row(p, "System", "Dual Mic + AEC (ES7210)");
    {
        uint8_t mic_idx = modulus_audio_get_mic_gain_idx();
        if (mic_idx >= 5) {
            mic_idx = 2;
        }
        static const char *const k_gains[] = {"Off", "Low", "Med", "High", "Max"};
        lv_obj_t *mg = settings_segmented_row(p, "Microphone gain", k_gains, 5, mic_idx, 68);
        s_audio_mic = mg;
        lv_obj_add_event_cb(mg, audio_mic_cb, LV_EVENT_VALUE_CHANGED, NULL);
    }
    if (!modulus_audio_is_input_ready()) {
        settings_detail_row(p, "Input", "Codec unavailable");
    }

    audio_sync_codec_ui();

    settings_expandable_link(p, "Show hardware reference", "Hide hardware reference",
                             &s_audio_ref_exp, modulus_ui_settings_build_audio_tab);
    if (s_audio_ref_exp) {
        settings_detail_row(p, "Codec", "ES8388 DAC/ADC");
        settings_detail_row(p, "AEC front-end", "ES7210 (4-ch ADC)");
        settings_detail_row(p, "Speaker", "1W @ 8 ohm (NS4150B)");
        settings_detail_row(p, "Headphone", "3.5mm Jack");
        settings_detail_row(p, "Headphone jack",
                            modulus_audio_headphone_inserted() ? "Inserted" : "Not connected");
    }

    lv_obj_update_layout(p);
    if (scroll_y > 0) {
        lv_obj_scroll_to_y(p, scroll_y, LV_ANIM_OFF);
    }

    modulus_ui_settings_note_tab_built(MOD_UI_SETTINGS_TAB_AUDIO);
}
