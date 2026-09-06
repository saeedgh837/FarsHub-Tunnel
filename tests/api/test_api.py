"""تست‌های farshub-api.

هیچ سوکتی باز نمی‌شود و هیچ زیرفرایندی اجرا نمی‌شود: run_cli در سطح ماژول
جایگزین می‌شود. این تست‌ها روی ویندوز هم بی‌تغییر اجرا می‌شوند، پس توسعه
لازم نیست روی سرور انجام شود.
"""

import importlib.machinery
import importlib.util
import json
import os
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def load():
    # فایل پسوند .py ندارد (یک اجرایی است)، پس با مسیر بارش می‌کنیم.
    path = os.path.join(REPO, "bin", "farshub-api")
    spec = importlib.util.spec_from_loader(
        "farshub_api", importlib.machinery.SourceFileLoader("farshub_api", path)
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


api = load()

ORIGIN = {"Origin": "http://box:8088", "Host": "box:8088"}

PATHS_OUT = (
    "side=server\n"
    "conf=/etc/farshub/server.toml\n"
    "unit=farshub-server.service\n"
    "site_name=farshub-panel\n"
    "installed_server=1\n"
    "installed_client=0\n"
)

CONFIG_OUT = (
    'bind_addr = "0.0.0.0:3080"\n'
    'transport = "tcpmux"\n'
    'token = "********"   # مخفی شده\n'
    "ports = [\n"
    '    "443",\n'
    "]\n"
    "web_port = 2060\n"
    'log_level = "warn"\n'
    "sniffer = false\n"
)


class Fake:
    """run_cli جعلی که فراخوانی‌ها را ضبط می‌کند."""

    def __init__(self, replies=None):
        self.calls = []
        self.replies = replies or {}

    def __call__(self, args, stdin=None, root=True, timeout=None):
        self.calls.append({"args": list(args), "stdin": stdin, "root": root})
        key = args[0]
        return self.replies.get(key, (0, "", ""))

    def args_of(self, name):
        return [c["args"] for c in self.calls if c["args"][0] == name]


class Base(unittest.TestCase):
    def setUp(self):
        self.fake = Fake(
            {
                "paths": (0, PATHS_OUT, ""),
                "config": (0, CONFIG_OUT, ""),
                "logs": (0, "line one\nline two\n", ""),
                "token": (0, "a" * 64 + "\n", ""),
            }
        )
        self._real = api.run_cli
        api.run_cli = self.fake
        api._last_write = 0.0

    def tearDown(self):
        api.run_cli = self._real

    def call(self, method, path, query=None, headers=None, body=None):
        h = dict(ORIGIN)
        if headers is not None:
            h = headers
        return api.handle(method, path, query or {}, h, body)


class TestRouting(Base):
    def test_unknown_path_is_404(self):
        st, out = self.call("GET", "/api/nope")
        self.assertEqual(st, 404)
        self.assertEqual(out["error"], "not_found")

    def test_wrong_method_is_405(self):
        st, out = self.call("DELETE", "/api/config")
        self.assertEqual(st, 405)

    def test_state_reports_install_and_service(self):
        st, out = self.call("GET", "/api/state")
        self.assertEqual(st, 200)
        self.assertTrue(out["installed"]["server"])
        self.assertFalse(out["installed"]["client"])
        self.assertIn("service", out)
        self.assertIn("unit", out["service"])

    def test_state_needs_no_root(self):
        self.call("GET", "/api/state")
        for c in self.fake.calls:
            if c["args"][0] == "paths":
                self.assertFalse(c["root"], "paths نباید با sudo صدا زده شود")


class TestOrigin(Base):
    def test_write_without_origin_is_rejected(self):
        st, out = self.call("PUT", "/api/config", headers={"Host": "box:8088"},
                            body={"side": "server", "values": {"log_level": "info"}})
        self.assertEqual(st, 403)
        self.assertEqual(out["error"], "origin")

    def test_write_with_foreign_origin_is_rejected(self):
        st, out = self.call(
            "PUT", "/api/config",
            headers={"Origin": "http://evil.example", "Host": "box:8088"},
            body={"side": "server", "values": {"log_level": "info"}},
        )
        self.assertEqual(st, 403)
        self.assertEqual(out["error"], "origin")

    def test_origin_must_match_port_too(self):
        st, out = self.call(
            "PUT", "/api/config",
            headers={"Origin": "http://box:9999", "Host": "box:8088"},
            body={"side": "server", "values": {"log_level": "info"}},
        )
        self.assertEqual(st, 403)

    def test_read_needs_no_origin(self):
        st, out = self.call("GET", "/api/state", headers={"Host": "box:8088"})
        self.assertEqual(st, 200)


class TestConfig(Base):
    def test_get_config_goes_through_cli(self):
        st, out = self.call("GET", "/api/config", query={"side": ["server"]})
        self.assertEqual(st, 200)
        self.assertEqual(out["side"], "server")
        self.assertEqual(out["values"]["transport"], "tcpmux")
        self.assertEqual(out["values"]["web_port"], 2060)
        self.assertIs(out["values"]["sniffer"], False)
        self.assertEqual(out["values"]["ports"], ["443"])
        self.assertEqual([["config", "server"]], self.fake.args_of("config"))

    def test_token_never_leaves_the_box(self):
        st, out = self.call("GET", "/api/config", query={"side": ["server"]})
        self.assertEqual(out["values"]["token"], "********")
        self.assertTrue(out["tokenSet"])

    def test_placeholder_token_is_reported_unset(self):
        self.fake.replies["config"] = (0, 'token = "CHANGE_ME"\n', "")
        st, out = self.call("GET", "/api/config", query={"side": ["server"]})
        self.assertFalse(out["tokenSet"])

    def test_put_sends_json_on_stdin(self):
        st, out = self.call("PUT", "/api/config",
                            body={"side": "server", "values": {"log_level": "info"}})
        self.assertEqual(st, 200)
        call = [c for c in self.fake.calls if c["args"][0] == "apply-config"][0]
        self.assertEqual(call["args"], ["apply-config", "server"])
        self.assertEqual(json.loads(call["stdin"]), {"log_level": "info"})
        self.assertTrue(call["root"])

    def test_put_reports_restart_needed(self):
        self.fake.replies["apply-config"] = (0, "changed log_level\n", "")
        st, out = self.call("PUT", "/api/config",
                            body={"side": "server", "values": {"log_level": "info"}})
        self.assertTrue(out["restartNeeded"])
        self.assertEqual(out["changed"], ["log_level"])

    def test_put_with_no_change_needs_no_restart(self):
        self.fake.replies["apply-config"] = (0, "unchanged log_level\n", "")
        st, out = self.call("PUT", "/api/config",
                            body={"side": "server", "values": {"log_level": "warn"}})
        self.assertFalse(out["restartNeeded"])

    def test_empty_token_field_is_dropped(self):
        st, out = self.call("PUT", "/api/config",
                            body={"side": "server", "values": {"token": "", "log_level": "info"}})
        call = [c for c in self.fake.calls if c["args"][0] == "apply-config"][0]
        self.assertNotIn("token", json.loads(call["stdin"]))

    def test_cli_failure_passes_persian_message_through(self):
        self.fake.replies["apply-config"] = (1, "", "transport نامعتبر: «quic»\n")
        st, out = self.call("PUT", "/api/config",
                            body={"side": "server", "values": {"transport": "quic"}})
        self.assertEqual(st, 400)
        self.assertEqual(out["error"], "cli_failed")
        self.assertIn("quic", out["detail"])

    def test_bad_side_is_rejected_before_the_cli(self):
        st, out = self.call("PUT", "/api/config",
                            body={"side": "../../etc", "values": {"log_level": "info"}})
        self.assertEqual(st, 400)
        self.assertEqual(out["error"], "bad_request")
        self.assertEqual(self.fake.calls, [])

    def test_values_must_be_an_object(self):
        st, out = self.call("PUT", "/api/config", body={"side": "server", "values": [1, 2]})
        self.assertEqual(st, 400)


class TestService(Base):
    def test_action_is_passed_as_fixed_argv(self):
        st, out = self.call("POST", "/api/service", body={"side": "server", "action": "restart"})
        self.assertEqual(st, 200)
        self.assertEqual([["restart", "server"]], self.fake.args_of("restart"))

    def test_unknown_action_is_rejected(self):
        st, out = self.call("POST", "/api/service", body={"side": "server", "action": "rm -rf /"})
        self.assertEqual(st, 400)
        self.assertEqual(self.fake.calls, [])

    def test_rate_limited(self):
        self.call("POST", "/api/service", body={"side": "server", "action": "restart"})
        st, out = self.call("POST", "/api/service", body={"side": "server", "action": "restart"})
        self.assertEqual(st, 429)
        self.assertEqual(out["error"], "rate_limit")

    def test_reads_are_not_rate_limited(self):
        self.call("POST", "/api/service", body={"side": "server", "action": "restart"})
        st, _ = self.call("GET", "/api/state")
        self.assertEqual(st, 200)


class TestInstall(Base):
    def test_install_then_config_then_panel_up(self):
        st, out = self.call(
            "POST", "/api/install",
            body={"side": "server", "values": {"bind_addr": "0.0.0.0:3080", "token": "b" * 40}},
        )
        self.assertEqual(st, 200)
        order = [c["args"][0] for c in self.fake.calls if c["args"][0] in
                 ("install", "apply-config", "panel-up")]
        self.assertEqual(order, ["install", "apply-config", "panel-up"])

    def test_install_stops_if_install_fails(self):
        self.fake.replies["install"] = (1, "", "دسترسی نوشتن نیست\n")
        st, out = self.call("POST", "/api/install", body={"side": "server", "values": {}})
        self.assertEqual(st, 400)
        self.assertEqual(self.fake.args_of("apply-config"), [])


class TestLogs(Base):
    def test_line_count_is_clamped(self):
        self.call("GET", "/api/logs", query={"side": ["server"], "n": ["100000"]})
        self.assertEqual([["logs", "server", "-n", "1000"]], self.fake.args_of("logs"))

    def test_non_numeric_n_falls_back(self):
        self.call("GET", "/api/logs", query={"side": ["server"], "n": ["-f"]})
        self.assertEqual([["logs", "server", "-n", "100"]], self.fake.args_of("logs"))


class TestToken(Base):
    def test_token_is_generated_without_root(self):
        st, out = self.call("POST", "/api/token")
        self.assertEqual(st, 200)
        self.assertEqual(len(out["token"]), 64)
        call = [c for c in self.fake.calls if c["args"][0] == "token"][0]
        self.assertFalse(call["root"], "token به root نیاز ندارد")


class TestPreflight(Base):
    def test_default_token_is_flagged(self):
        self.fake.replies["config"] = (
            0, 'bind_addr = "0.0.0.0:3080"\ntoken = "CHANGE_ME"\nports = [\n]\n', "")
        st, out = self.call("GET", "/api/preflight", query={"side": ["server"]})
        self.assertEqual(st, 200)
        ids = [c["id"] for c in out["checks"]]
        self.assertIn("pf.tokenDefault", ids)
        self.assertIn("pf.noPorts", ids)
        bad = [c for c in out["checks"] if c["id"] == "pf.tokenDefault"][0]
        self.assertEqual(bad["level"], "error")

    def test_wss_without_cert_is_flagged(self):
        self.fake.replies["config"] = (
            0, 'transport = "wssmux"\ntoken = "' + "c" * 40 + '"\ntls_cert = ""\n', "")
        st, out = self.call("GET", "/api/preflight", query={"side": ["server"]})
        self.assertIn("pf.tlsMissing", [c["id"] for c in out["checks"]])

    def test_clean_config_has_no_errors(self):
        self.fake.replies["config"] = (
            0,
            'bind_addr = "0.0.0.0:3080"\ntransport = "tcpmux"\ntoken = "' + "d" * 40 + '"\n'
            'ports = [\n    "443",\n]\nweb_port = 2060\nsniffer = false\n',
            "",
        )
        st, out = self.call("GET", "/api/preflight", query={"side": ["server"]})
        self.assertEqual([c for c in out["checks"] if c["level"] == "error"], [])

    def test_client_placeholder_remote_is_flagged(self):
        self.fake.replies["config"] = (
            0, 'remote_addr = "SERVER_IP:3080"\ntoken = "' + "e" * 40 + '"\n', "")
        st, out = self.call("GET", "/api/preflight", query={"side": ["client"]})
        self.assertIn("pf.remoteUnset", [c["id"] for c in out["checks"]])


class TestTimeout(Base):
    def test_timeout_becomes_504(self):
        self.fake.replies["restart"] = (-1, "", "timeout")
        st, out = self.call("POST", "/api/service", body={"side": "server", "action": "restart"})
        self.assertEqual(st, 504)
        self.assertEqual(out["error"], "timeout")


if __name__ == "__main__":
    unittest.main()
