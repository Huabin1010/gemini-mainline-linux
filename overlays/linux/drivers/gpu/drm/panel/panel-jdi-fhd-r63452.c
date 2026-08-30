// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (c) 2021 Raffaele Tranquillini <raffaele.tranquillini@gmail.com>
 *
 * Generated using linux-mdss-dsi-panel-driver-generator from Lineage OS device tree:
 * https://github.com/LineageOS/android_kernel_xiaomi_msm8996/blob/lineage-18.1/arch/arm/boot/dts/qcom/a1-msm8996-mtp.dtsi
 *
 * Sleep vs reset: connector DPMS must put the panel into DCS sleep
 * (disable) without holding the GPIO reset. Reset + DSI retrain on every
 * unblank paints a cluster of white lines on the right edge and glitches
 * the Synaptics S3330. WLED is owned by userspace so enable() does not
 * unblank the lamp before the first clean frame.
 */

#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/sysfs.h>

#include <video/mipi_display.h>

#include <drm/drm_mipi_dsi.h>
#include <drm/drm_modes.h>
#include <drm/drm_panel.h>

struct jdi_fhd_r63452 {
	struct drm_panel panel;
	struct mipi_dsi_device *dsi;
	struct gpio_desc *reset_gpio;
	bool inited;
	bool asleep;
};

static inline struct jdi_fhd_r63452 *to_jdi_fhd_r63452(struct drm_panel *panel)
{
	return container_of(panel, struct jdi_fhd_r63452, panel);
}

static void jdi_fhd_r63452_reset(struct jdi_fhd_r63452 *ctx)
{
	gpiod_set_value_cansleep(ctx->reset_gpio, 0);
	usleep_range(10000, 11000);
	gpiod_set_value_cansleep(ctx->reset_gpio, 1);
	usleep_range(1000, 2000);
	gpiod_set_value_cansleep(ctx->reset_gpio, 0);
	usleep_range(10000, 11000);
}

static int jdi_fhd_r63452_init_regs(struct jdi_fhd_r63452 *ctx)
{
	struct mipi_dsi_device *dsi = ctx->dsi;
	struct mipi_dsi_multi_context dsi_ctx = { .dsi = dsi };

	dsi->mode_flags |= MIPI_DSI_MODE_LPM;

	mipi_dsi_generic_write_seq_multi(&dsi_ctx, 0xb0, 0x00);
	mipi_dsi_generic_write_seq_multi(&dsi_ctx, 0xd6, 0x01);
	mipi_dsi_generic_write_seq_multi(&dsi_ctx, 0xec,
					 0x64, 0xdc, 0xec, 0x3b, 0x52, 0x00, 0x0b, 0x0b,
					 0x13, 0x15, 0x68, 0x0b, 0xb5);
	mipi_dsi_generic_write_seq_multi(&dsi_ctx, 0xb0, 0x03);

	mipi_dsi_dcs_set_tear_on_multi(&dsi_ctx, MIPI_DSI_DCS_TEAR_MODE_VBLANK);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, MIPI_DCS_SET_ADDRESS_MODE, 0x00);
	mipi_dsi_dcs_set_pixel_format_multi(&dsi_ctx, 0x77);
	mipi_dsi_dcs_set_column_address_multi(&dsi_ctx, 0x0000, 0x0437);
	mipi_dsi_dcs_set_page_address_multi(&dsi_ctx, 0x0000, 0x077f);
	mipi_dsi_dcs_set_tear_scanline_multi(&dsi_ctx, 0x0000);
	mipi_dsi_dcs_set_display_brightness_multi(&dsi_ctx, 0x00ff);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, MIPI_DCS_WRITE_CONTROL_DISPLAY, 0x24);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, MIPI_DCS_WRITE_POWER_SAVE, 0x00);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, MIPI_DCS_SET_CABC_MIN_BRIGHTNESS, 0x00);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0x84, 0x00);

	return dsi_ctx.accum_err;
}

static void jdi_fhd_r63452_log_status(struct jdi_fhd_r63452 *ctx, const char *tag)
{
	struct mipi_dsi_device *dsi = ctx->dsi;
	u8 pm = 0, id[4] = { }, madctl = 0, colmod = 0, dmode = 0;
	int r;

	r = mipi_dsi_dcs_get_power_mode(dsi, &pm);
	pr_info("jdi-r63452: %s power_mode ret=%d val=0x%02x disp=%d sleep_out=%d partial=%d idle=%d\n",
		tag, r, pm,
		!!(pm & MIPI_DSI_DCS_POWER_MODE_DISPLAY),
		!!(pm & MIPI_DSI_DCS_POWER_MODE_SLEEP),
		!!(pm & MIPI_DSI_DCS_POWER_MODE_PARTIAL),
		!!(pm & MIPI_DSI_DCS_POWER_MODE_IDLE));
	r = mipi_dsi_dcs_read(dsi, 0xbf, id, sizeof(id));
	pr_info("jdi-r63452: %s id ret=%d %02x %02x %02x %02x\n",
		tag, r, id[0], id[1], id[2], id[3]);
	r = mipi_dsi_dcs_read(dsi, MIPI_DCS_GET_ADDRESS_MODE, &madctl, 1);
	if (r == 1)
		pr_info("jdi-r63452: %s madctl=0x%02x\n", tag, madctl);
	r = mipi_dsi_dcs_read(dsi, MIPI_DCS_GET_PIXEL_FORMAT, &colmod, 1);
	if (r == 1)
		pr_info("jdi-r63452: %s colmod=0x%02x\n", tag, colmod);
	r = mipi_dsi_dcs_read(dsi, MIPI_DCS_GET_DISPLAY_MODE, &dmode, 1);
	if (r == 1)
		pr_info("jdi-r63452: %s display_mode=0x%02x\n", tag, dmode);
}

static int jdi_fhd_r63452_enable(struct drm_panel *panel)
{
	struct jdi_fhd_r63452 *ctx = to_jdi_fhd_r63452(panel);
	struct mipi_dsi_device *dsi = ctx->dsi;
	struct mipi_dsi_multi_context dsi_ctx = { .dsi = dsi };
	u8 pm = 0;
	int ret, i;

	dsi->mode_flags |= MIPI_DSI_MODE_LPM;

	/*
	 * Host power_on kills LK's DSI PHY; pre-enable 0xBF is ENODATA.
	 * GPIO reset is required once. Later CRTC/DPMS off keeps analog
	 * (disable is 0x28 only); do not reset or 0x11 on resume.
	 */
	if (!ctx->inited) {
		jdi_fhd_r63452_reset(ctx);
		msleep(20);
		ctx->inited = true;
	} else {
		/*
		 * Analog is still up (disable is 0x28 only). DCS 0x11 after a
		 * PHY retrain paints the right-edge white cluster. Only 0x29.
		 */
		dsi->mode_flags &= ~MIPI_DSI_MODE_LPM;
		mipi_dsi_dcs_set_display_on_multi(&dsi_ctx);
		mipi_dsi_msleep(&dsi_ctx, 20);
		ret = mipi_dsi_dcs_get_power_mode(dsi, &pm);
		if (ret == 0 && pm != 0x38) {
			mipi_dsi_dcs_set_display_on_multi(&dsi_ctx);
			mipi_dsi_msleep(&dsi_ctx, 20);
			(void)mipi_dsi_dcs_get_power_mode(dsi, &pm);
		}
		ctx->asleep = false;
		pr_info("jdi-r63452: enable resume (DCS 0x29, no 0x11) err=%d pm=0x%02x\n",
			dsi_ctx.accum_err, pm);
		jdi_fhd_r63452_log_status(ctx, "enable-resume");
		return dsi_ctx.accum_err;
	}

	ret = jdi_fhd_r63452_init_regs(ctx);
	if (ret) {
		pr_err("jdi-r63452: enable init failed %d\n", ret);
		return ret;
	}

	mipi_dsi_dcs_set_display_on_multi(&dsi_ctx);
	mipi_dsi_msleep(&dsi_ctx, 20);
	mipi_dsi_dcs_exit_sleep_mode_multi(&dsi_ctx);
	mipi_dsi_msleep(&dsi_ctx, 120);

	mipi_dsi_generic_write_seq_multi(&dsi_ctx, 0xb0, 0x04);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0x84, 0x00);
	mipi_dsi_generic_write_seq_multi(&dsi_ctx, 0xc8, 0x11);
	mipi_dsi_generic_write_seq_multi(&dsi_ctx, 0xb0, 0x03);

	/* Huaxing/ginkgo: extra settle before HS pixel traffic. */
	msleep(120);

	for (i = 0; i < 6; i++) {
		ret = mipi_dsi_dcs_get_power_mode(dsi, &pm);
		pr_info("jdi-r63452: poll[%d] power ret=%d val=0x%02x\n", i, ret, pm);
		if (ret == 0 && (pm & MIPI_DSI_DCS_POWER_MODE_DISPLAY) &&
		    (pm & MIPI_DSI_DCS_POWER_MODE_SLEEP))
			break;
		mipi_dsi_dcs_set_display_on(dsi);
		msleep(50);
	}

	pr_info("jdi-r63452: enable done (want 0x9c, got 0x%02x) err=%d\n",
		pm, dsi_ctx.accum_err);
	ctx->asleep = false;
	jdi_fhd_r63452_log_status(ctx, "enable");
	return dsi_ctx.accum_err;
}

static int jdi_fhd_r63452_disable(struct drm_panel *panel)
{
	struct jdi_fhd_r63452 *ctx = to_jdi_fhd_r63452(panel);
	struct mipi_dsi_device *dsi = ctx->dsi;
	struct mipi_dsi_multi_context dsi_ctx = { .dsi = dsi };

	/*
	 * CRTC/DPMS off comes here before host_power_off. Do not rewrite
	 * 0xec … 0x95: that drops incell AVDD and the S3330 falls off I2C.
	 * 0x28 is enough; PHY clocks can gate after this returns.
	 */
	dsi->mode_flags &= ~MIPI_DSI_MODE_LPM;
	mipi_dsi_dcs_set_display_off_multi(&dsi_ctx);
	mipi_dsi_usleep_range(&dsi_ctx, 2000, 3000);
	ctx->asleep = true;
	pr_info("jdi-r63452: disable (DCS 0x28, analog kept) err=%d\n",
		dsi_ctx.accum_err);
	jdi_fhd_r63452_log_status(ctx, "disable");
	return dsi_ctx.accum_err;
}

/*
 * HUD blank/unblank. Android day-to-day on this incell is 0x28 / 0x29.
 *
 * 0x10 (enter-sleep) plus a later enable() re-init paints the right-edge
 * white cluster. Rewriting 0xec … 0x95 drops incell AVDD and the S3330
 * falls off I2C until a panel GPIO reset (more white lines). Leave the
 * DSI PHY up: no connector DPMS.
 */
static int jdi_fhd_r63452_set_display(struct drm_panel *panel, bool on)
{
	struct jdi_fhd_r63452 *ctx = to_jdi_fhd_r63452(panel);
	struct mipi_dsi_device *dsi = ctx->dsi;
	struct mipi_dsi_multi_context dsi_ctx = { .dsi = dsi };

	if (on == !ctx->asleep)
		return 0;

	dsi->mode_flags &= ~MIPI_DSI_MODE_LPM;
	if (on) {
		mipi_dsi_dcs_set_display_on_multi(&dsi_ctx);
		mipi_dsi_msleep(&dsi_ctx, 20);
		ctx->asleep = false;
		pr_info("jdi-r63452: unblank (DCS 0x29, RAM/analog kept) err=%d\n",
			dsi_ctx.accum_err);
		jdi_fhd_r63452_log_status(ctx, "unblank");
		return dsi_ctx.accum_err;
	}

	mipi_dsi_dcs_set_display_off_multi(&dsi_ctx);
	mipi_dsi_usleep_range(&dsi_ctx, 2000, 3000);
	ctx->asleep = true;
	pr_info("jdi-r63452: blank (DCS 0x28, RAM/sleep-out/analog kept) err=%d\n",
		dsi_ctx.accum_err);
	jdi_fhd_r63452_log_status(ctx, "blank");
	return dsi_ctx.accum_err;
}

static int jdi_fhd_r63452_prepare(struct drm_panel *panel)
{
	struct jdi_fhd_r63452 *ctx = to_jdi_fhd_r63452(panel);

	(void)ctx;
	pr_info("jdi-r63452: prepare (reset/DCS deferred to enable)\n");
	return 0;
}

static int jdi_fhd_r63452_unprepare(struct drm_panel *panel)
{
	struct jdi_fhd_r63452 *ctx = to_jdi_fhd_r63452(panel);

	/*
	 * Panel is already in DCS sleep from disable(). Do not assert
	 * reset: the next prepare would retrain DSI from a cold IC.
	 */
	(void)ctx;
	pr_info("jdi-r63452: unprepare (sleep kept, reset released)\n");
	return 0;
}

static const struct drm_display_mode jdi_fhd_r63452_mode = {
	/*
	 * Keep the generator's 120/16/40. Lineage cmd DTS is 80/10/40, but
	 * that clock (140118 kHz) makes pclk0_clk_src RCG fail to latch
	 * ("rcg didn't update") → backlight with a black panel.
	 */
	.clock = (1080 + 120 + 16 + 40) * (1920 + 4 + 2 + 4) * 60 / 1000,
	.hdisplay = 1080,
	.hsync_start = 1080 + 120,
	.hsync_end = 1080 + 120 + 16,
	.htotal = 1080 + 120 + 16 + 40,
	.vdisplay = 1920,
	.vsync_start = 1920 + 4,
	.vsync_end = 1920 + 4 + 2,
	.vtotal = 1920 + 4 + 2 + 4,
	.width_mm = 64,
	.height_mm = 114,
};

static int jdi_fhd_r63452_get_modes(struct drm_panel *panel,
				    struct drm_connector *connector)
{
	struct drm_display_mode *mode;

	mode = drm_mode_duplicate(connector->dev, &jdi_fhd_r63452_mode);
	if (!mode)
		return -ENOMEM;

	drm_mode_set_name(mode);

	mode->type = DRM_MODE_TYPE_DRIVER | DRM_MODE_TYPE_PREFERRED;
	connector->display_info.width_mm = mode->width_mm;
	connector->display_info.height_mm = mode->height_mm;
	drm_mode_probed_add(connector, mode);

	return 1;
}

static ssize_t panel_sleep_show(struct device *dev,
				struct device_attribute *attr, char *buf)
{
	struct mipi_dsi_device *dsi = to_mipi_dsi_device(dev);
	struct jdi_fhd_r63452 *ctx = mipi_dsi_get_drvdata(dsi);

	u8 pm = 0;
	int r;

	(void)attr;
	/*
	 * A DCS read here would pm_runtime_get the DSI host and undo
	 * blank-time suspend. When analog is kept but the host is off,
	 * only report the software flag.
	 */
	if (ctx->asleep)
		return sysfs_emit(buf, "1 power=0/0x30\n");
	r = mipi_dsi_dcs_get_power_mode(dsi, &pm);
	if (r < 0) {
		msleep(20);
		r = mipi_dsi_dcs_get_power_mode(dsi, &pm);
	}
	return sysfs_emit(buf, "%d power=%d/0x%02x\n", ctx->asleep, r, pm);
}

static ssize_t panel_sleep_store(struct device *dev,
				 struct device_attribute *attr,
				 const char *buf, size_t count)
{
	struct mipi_dsi_device *dsi = to_mipi_dsi_device(dev);
	struct jdi_fhd_r63452 *ctx = mipi_dsi_get_drvdata(dsi);
	bool sleep;
	int ret;

	(void)attr;
	ret = kstrtobool(buf, &sleep);
	if (ret)
		return ret;
	if (sleep == ctx->asleep)
		return count;
	ret = jdi_fhd_r63452_set_display(&ctx->panel, !sleep);
	if (ret)
		return ret;
	return count;
}

static DEVICE_ATTR_RW(panel_sleep);

static const struct drm_panel_funcs jdi_fhd_r63452_panel_funcs = {
	.prepare = jdi_fhd_r63452_prepare,
	.unprepare = jdi_fhd_r63452_unprepare,
	.enable = jdi_fhd_r63452_enable,
	.disable = jdi_fhd_r63452_disable,
	.get_modes = jdi_fhd_r63452_get_modes,
};

static int jdi_fhd_r63452_probe(struct mipi_dsi_device *dsi)
{
	struct device *dev = &dsi->dev;
	struct jdi_fhd_r63452 *ctx;
	int ret;

	ctx = devm_drm_panel_alloc(dev, struct jdi_fhd_r63452, panel,
				   &jdi_fhd_r63452_panel_funcs,
				   DRM_MODE_CONNECTOR_DSI);
	if (IS_ERR(ctx))
		return PTR_ERR(ctx);

	ctx->reset_gpio = devm_gpiod_get(dev, "reset", GPIOD_OUT_HIGH);
	if (IS_ERR(ctx->reset_gpio))
		return dev_err_probe(dev, PTR_ERR(ctx->reset_gpio),
				     "Failed to get reset-gpios\n");

	ctx->dsi = dsi;
	mipi_dsi_set_drvdata(dsi, ctx);

	dsi->lanes = 4;
	dsi->format = MIPI_DSI_FMT_RGB888;
	/*
	 * Command mode, burst (Lineage traffic-mode = burst_mode).
	 * MSM8996 14nm PHY: CLOCK_NON_CONTINUOUS is required so
	 * dsi_ctrl_enable() does not set LANE_CTRL bit28
	 * (CLKLN_HS_FORCE_REQUEST). That bit leaves data lanes in
	 * STOPSTATE → backlight on, black panel. White lines are a
	 * separate issue; do not drop this flag to chase them.
	 */
	dsi->mode_flags = MIPI_DSI_MODE_VIDEO_BURST |
			  MIPI_DSI_CLOCK_NON_CONTINUOUS;

	ctx->panel.prepare_prev_first = true;

	/*
	 * Do not drm_panel_of_backlight(): enable() would turn WLED on
	 * before the first scanout. gemini-status owns the lamp and
	 * unblanks it after the first flip.
	 */

	drm_panel_add(&ctx->panel);

	ret = mipi_dsi_attach(dsi);
	if (ret < 0) {
		dev_err(dev, "Failed to attach to DSI host: %d\n", ret);
		return ret;
	}

	ret = device_create_file(dev, &dev_attr_panel_sleep);
	if (ret)
		dev_warn(dev, "panel_sleep sysfs failed: %d\n", ret);

	return 0;
}

static void jdi_fhd_r63452_remove(struct mipi_dsi_device *dsi)
{
	struct jdi_fhd_r63452 *ctx = mipi_dsi_get_drvdata(dsi);
	int ret;

	device_remove_file(&dsi->dev, &dev_attr_panel_sleep);

	ret = mipi_dsi_detach(dsi);
	if (ret < 0)
		dev_err(&dsi->dev, "Failed to detach from DSI host: %d\n", ret);

	drm_panel_remove(&ctx->panel);
}

static const struct of_device_id jdi_fhd_r63452_of_match[] = {
	{ .compatible = "jdi,fhd-r63452" },
	{ /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, jdi_fhd_r63452_of_match);

static struct mipi_dsi_driver jdi_fhd_r63452_driver = {
	.probe = jdi_fhd_r63452_probe,
	.remove = jdi_fhd_r63452_remove,
	.driver = {
		.name = "panel-jdi-fhd-r63452",
		.of_match_table = jdi_fhd_r63452_of_match,
	},
};
module_mipi_dsi_driver(jdi_fhd_r63452_driver);

MODULE_AUTHOR("Raffaele Tranquillini <raffaele.tranquillini@gmail.com>");
MODULE_DESCRIPTION("DRM driver for JDI FHD R63452 DSI panel, command mode");
MODULE_LICENSE("GPL v2");
