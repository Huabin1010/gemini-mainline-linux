/* Unit tests for gemini-wifi-flow.h — join / switch / password / forget. */
#include "../../initramfs/gemini-wifi-flow.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int fails;

static void expect(int cond, const char *name)
{
	if (cond)
		printf("ok  %s\n", name);
	else {
		printf("FAIL  %s\n", name);
		fails++;
	}
}

/* Tiny HUD sheet simulator: enough to lock the whole user journey. */
struct hud {
	int sheet;
	int connecting;
	int forgetting;
	int connected;
	char live[96];
	char selected[96];
	char connect_ssid[96];
	char pend_ssid[96];
	char pend_pass[64];
	int want_connect;
	int used_pass;
	char known_ssid[96];
	char known_psk[64];
	int opened_pass;
};

static void hud_select(struct hud *h, const char *ssid)
{
	snprintf(h->selected, sizeof(h->selected), "%s", ssid);
	h->sheet = GW_SHEET_DETAIL;
}

static int hud_join(struct hud *h)
{
	if (!gw_allow_join(h->connecting, h->forgetting,
			   gw_already_on(h->connected, h->live, h->selected)))
		return 0;
	snprintf(h->connect_ssid, sizeof(h->connect_ssid), "%s", h->selected);
	h->connecting = 1;
	if (gw_join_use_session_psk(h->selected, h->known_ssid, h->known_psk))
		h->used_pass = 1;
	else
		h->used_pass = 0;
	return 1;
}

static void hud_type_pass(struct hud *h, const char *psk)
{
	const char *ssid = gw_pass_ssid(h->connect_ssid, h->selected);

	snprintf(h->known_ssid, sizeof(h->known_ssid), "%s", ssid);
	snprintf(h->known_psk, sizeof(h->known_psk), "%s", psk);
	h->used_pass = 1;
	if (h->connecting) {
		snprintf(h->pend_ssid, sizeof(h->pend_ssid), "%s", ssid);
		snprintf(h->pend_pass, sizeof(h->pend_pass), "%s", psk);
		h->want_connect = 1;
	}
}

static enum gw_connect_act hud_job(struct hud *h, int rc, const char *out)
{
	struct gw_connect_in in;
	enum gw_connect_act act;

	memset(&in, 0, sizeof(in));
	in.rc = rc;
	in.out = out;
	in.connected = h->connected;
	in.live_ssid = h->live;
	in.connect_ssid = h->connect_ssid;
	in.left_home = (h->sheet == GW_SHEET_HOME);
	in.want_connect = h->want_connect;
	in.pend_ssid = h->pend_ssid;
	in.pend_has_pass = h->pend_pass[0] != 0;
	in.used_pass = h->used_pass;
	in.have_session_psk = gw_join_use_session_psk(h->connect_ssid,
						      h->known_ssid,
						      h->known_psk);
	act = gw_on_connect_job(&in);
	h->connecting = 0;
	if (act == GW_CONN_SUCCESS) {
		h->connected = 1;
		snprintf(h->live, sizeof(h->live), "%s", h->connect_ssid);
		if (gw_drop_pending(1, h->connect_ssid, h->pend_ssid))
			h->want_connect = 0;
		h->sheet = GW_SHEET_HOME;
		h->opened_pass = 0;
	} else if (act == GW_CONN_RETRY_PSK) {
		h->connecting = 1;
		h->used_pass = 1;
		if (gw_ssid_eq(h->pend_ssid, h->connect_ssid) && !h->pend_pass[0])
			h->want_connect = 0;
	} else if (act == GW_CONN_WRONG_PASS) {
		h->known_psk[0] = 0;
		h->sheet = GW_SHEET_PASS;
		h->opened_pass = 1;
	} else if (act == GW_CONN_OPEN_PASS) {
		h->sheet = GW_SHEET_PASS;
		h->opened_pass = 1;
	} else if (act == GW_CONN_WAIT_PENDING) {
		h->connecting = 1;
		h->used_pass = 1;
		h->want_connect = 0;
	} else {
		h->sheet = h->used_pass ? GW_SHEET_PASS : GW_SHEET_DETAIL;
	}
	return act;
}

int main(void)
{
	printf("1..52\n");

	expect(gw_ssid_eq("HomeNet-5G", "HomeNet-5G"), "ssid exact match");
	expect(!gw_ssid_eq("HomeNet-5G", "HomeNet"), "ssid does not prefix-match");
	expect(!gw_ssid_eq("", "x"), "empty ssid is not live");
	expect(!gw_already_on(0, "A", "A"), "disconnected is not already-on");
	expect(gw_already_on(1, "Home", "Home"), "connected same ssid");
	expect(!gw_already_on(1, "Home", "Cafe"), "connected other ssid");

	expect(!gw_allow_join(0, 0, 1), "no join while already on");
	expect(!gw_allow_join(1, 0, 0), "no join while connecting");
	expect(!gw_allow_join(0, 1, 0), "no join while forgetting");
	expect(gw_allow_join(0, 0, 0), "join other network");

	expect(gw_forget_can_start(0, 0, 0), "forget starts when idle");
	expect(gw_forget_can_start(1, 0, 0),
	       "queued forget still starts with no job");
	expect(!gw_forget_can_start(1, 1, 1),
	       "forget does not restart while forget job runs");
	expect(gw_forget_can_start(1, 1, 0),
	       "forget may abort a scan job");

	expect(gw_drop_pending(1, "Cafe", "Cafe"),
	       "drop queued probe after success");
	expect(!gw_drop_pending(1, "Cafe", "Home"),
	       "keep queued join for a different ssid");
	expect(!gw_drop_pending(0, "Cafe", "Cafe"),
	       "keep pending on failure");

	expect(!gw_job_need_pw(0, "NEED_PASSWORD\n已连接 Cafe\n"),
	       "success rc is never need-password");
	expect(gw_job_ok(2, "已连接 Cafe"), "已连接 wins over rc 2");
	expect(gw_job_need_pw(2, "NEED_PASSWORD"), "rc 2 is need-password");
	expect(!gw_open_pass(1, 1, 0, 0),
	       "already on: do not pop password");
	expect(!gw_open_pass(1, 0, 1, 0),
	       "user left home: do not pop password");
	expect(!gw_open_pass(1, 0, 0, 1),
	       "password already queued: do not pop again");
	expect(gw_open_pass(1, 0, 0, 0),
	       "new secure network: pop password");

	expect(gw_saved_profile_usable(0, 0),
	       "flags 0 usable even if psk hidden");
	expect(!gw_saved_profile_usable(1, 1),
	       "agent-owned not usable without agent");
	expect(gw_keep_pending_psk(1, 1, "Cafe", "secret12", "Cafe"),
	       "keep queued psk over empty probe");
	expect(!gw_keep_pending_psk(0, 1, "Cafe", "secret12", "Cafe"),
	       "password join may replace pending");
	expect(!strcmp(gw_pass_ssid("Cafe", "Home"), "Cafe"),
	       "password sheet uses in-flight ssid");

	/* Journey 1: Home → pick Cafe → empty probe → type password → connected
	 * → leftover NEED_PASSWORD must not reopen the sheet. */
	{
		struct hud h;
		enum gw_connect_act act;

		memset(&h, 0, sizeof(h));
		h.connected = 1;
		snprintf(h.live, sizeof(h.live), "%s", "Home");
		h.sheet = GW_SHEET_LIST;
		hud_select(&h, "Cafe");
		expect(h.sheet == GW_SHEET_DETAIL, "journey: row opens detail");
		expect(hud_join(&h), "journey: join Cafe while on Home");
		act = hud_job(&h, 2, "NEED_PASSWORD");
		expect(act == GW_CONN_OPEN_PASS, "journey: first probe asks password");
		expect(h.sheet == GW_SHEET_PASS, "journey: password sheet");
		hud_type_pass(&h, "correct-password");
		h.connecting = 1;
		h.want_connect = 0;
		h.pend_pass[0] = 0;
		act = hud_job(&h, 0, "已连接 Cafe");
		expect(act == GW_CONN_SUCCESS, "journey: password join succeeds");
		expect(h.sheet == GW_SHEET_HOME, "journey: sheet closes");
		expect(!strcmp(h.live, "Cafe"), "journey: live ssid is Cafe");
		/* stale empty probe after success */
		h.connecting = 1;
		h.used_pass = 0;
		snprintf(h.connect_ssid, sizeof(h.connect_ssid), "%s", "Cafe");
		act = hud_job(&h, 2, "NEED_PASSWORD");
		expect(act == GW_CONN_SUCCESS || act == GW_CONN_RETRY_PSK,
		       "journey: already on Cafe does not pop password");
		expect(h.sheet != GW_SHEET_PASS,
		       "journey: password sheet stays closed");
		hud_select(&h, "Cafe");
		expect(!hud_join(&h), "journey: join current network is no-op");
	}

	/* Journey 2: user typed password while empty probe still running. */
	{
		struct hud h;
		enum gw_connect_act act;

		memset(&h, 0, sizeof(h));
		h.sheet = GW_SHEET_DETAIL;
		hud_select(&h, "Cafe");
		hud_join(&h);
		hud_type_pass(&h, "correct-password");
		act = hud_job(&h, 2, "NEED_PASSWORD");
		expect(act == GW_CONN_WAIT_PENDING,
		       "typed-while-probe: wait for queued psk");
		expect(h.sheet != GW_SHEET_PASS,
		       "typed-while-probe: do not pop a second sheet");
		act = hud_job(&h, 0, "已连接 Cafe");
		expect(act == GW_CONN_SUCCESS, "typed-while-probe: then succeed");
		expect(h.sheet == GW_SHEET_HOME, "typed-while-probe: close");
	}

	/* Journey 3: session PSK retries instead of popping again. */
	{
		struct hud h;
		enum gw_connect_act act;

		memset(&h, 0, sizeof(h));
		h.sheet = GW_SHEET_DETAIL;
		hud_select(&h, "Cafe");
		snprintf(h.known_ssid, sizeof(h.known_ssid), "%s", "Cafe");
		snprintf(h.known_psk, sizeof(h.known_psk), "%s", "correct-password");
		expect(gw_join_use_session_psk("Cafe", h.known_ssid, h.known_psk),
		       "session: reuse typed psk");
		hud_join(&h);
		expect(h.used_pass == 1, "session: join sends psk not empty");
		h.used_pass = 0; /* empty probe still in flight from earlier tap */
		act = hud_job(&h, 2, "NEED_PASSWORD");
		expect(act == GW_CONN_RETRY_PSK,
		       "session: empty probe retries with stored psk");
		expect(h.sheet != GW_SHEET_PASS,
		       "session: no extra password sheet");
	}

	/* Journey 4: forget returns to list; joining current AP is blocked. */
	{
		struct hud h;

		memset(&h, 0, sizeof(h));
		h.connected = 1;
		snprintf(h.live, sizeof(h.live), "%s", "Cafe");
		hud_select(&h, "Cafe");
		expect(!gw_allow_join(0, 0, gw_already_on(h.connected, h.live,
							  h.selected)),
		       "forget-setup: cannot rejoin current");
		h.forgetting = 1;
		expect(!gw_allow_join(0, h.forgetting, 0),
		       "forget: join blocked while forgetting");
	}

	/* Journey 5: saved/typed PSK is wrong — show 密码不对, stay on pass. */
	{
		struct hud h;
		enum gw_connect_act act;

		memset(&h, 0, sizeof(h));
		h.connected = 1;
		snprintf(h.live, sizeof(h.live), "%s", "Home");
		hud_select(&h, "Cafe");
		hud_join(&h);
		act = hud_job(&h, 3, "密码不对，请再试一次");
		expect(act == GW_CONN_WRONG_PASS,
		       "wrong-saved: empty probe with bad psk");
		expect(h.sheet == GW_SHEET_PASS, "wrong-saved: password sheet");
		hud_type_pass(&h, "still-wrong1");
		h.connecting = 1;
		h.used_pass = 1;
		h.want_connect = 0;
		h.pend_pass[0] = 0;
		act = hud_job(&h, 2, "NEED_PASSWORD");
		expect(act == GW_CONN_WRONG_PASS,
		       "wrong-typed: secrets after sending psk is wrong-pass");
		expect(h.sheet == GW_SHEET_PASS, "wrong-typed: stay on sheet");
		expect(gw_job_wrong_pw(3, "x"), "rc 3 is wrong-pass");
		expect(!gw_job_need_pw(3, "密码不对，请再试一次"),
		       "wrong-pass is not need-password");
	}

	expect(!strcmp(gw_display_ssid(1, "Cafe", "Home"), "Cafe"),
	       "display: joining shows target");
	expect(!strcmp(gw_display_ssid(0, "Cafe", "Home"), "Home"),
	       "display: idle shows live not leftover target");
	expect(gw_join_fell_back(1, "HomeNet-5G", "Cafe"),
	       "fallback: radio back on previous AP");
	expect(!gw_join_fell_back(1, "Cafe", "Cafe"),
	       "fallback: same ssid is not fallback");
	expect(!gw_join_fell_back(0, "Home", "Cafe"),
	       "fallback: disconnected is not fallback");
	expect(!gw_join_confirm_fail(0, 1, "Home", "Cafe"),
	       "confirm: still on old AP is not yet a fail");
	expect(gw_join_confirm_ok(1, "Cafe", "Cafe"),
	       "confirm: live target is success");
	expect(gw_join_confirm_fail(1, 1, "Home", "Cafe"),
	       "confirm: timeout still on old AP is fail");
	expect(gw_forget_hold_connected("Cafe", 1, "Cafe"),
	       "forget: leftover live ssid is held");
	expect(gw_forget_hold_connected("Cafe", 1, ""),
	       "forget: leftover IP without ssid is held");
	expect(!gw_forget_hold_connected("Cafe", 1, "Home"),
	       "forget: a different live ssid is not held");
	expect(!gw_forget_hold_connected("Cafe", 0, "Cafe"),
	       "forget: disconnected is not held");

	expect(gw_classify_fail("psk mismatch reported by supplicant") ==
	       GW_FAIL_WRONG_PW, "classify: psk mismatch");
	expect(gw_classify_fail("The Wi-Fi network could not be found") ==
	       GW_FAIL_NOT_FOUND, "classify: not found");
	expect(gw_classify_fail("Error: Timeout expired (15 seconds)") ==
	       GW_FAIL_TIMEOUT, "classify: timeout");
	expect(gw_classify_fail("No suitable device found") ==
	       GW_FAIL_NO_DEVICE, "classify: no device");
	expect(gw_classify_fail("已连接 Cafe") == GW_FAIL_UNKNOWN,
	       "classify: success text is not a fail kind");
	expect(gw_classify_fail("NEED_PASSWORD") == GW_FAIL_NEED_PW,
	       "classify: need password");

	if (fails) {
		printf("# %d failed\n", fails);
		return 1;
	}
	printf("# all passed\n");
	return 0;
}
