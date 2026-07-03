from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class HubApiSecurityStaticTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.server = (ROOT / "hub-api" / "server.js").read_text(encoding="utf-8")
        cls.hub_app = (ROOT / "hub" / "app.js").read_text(encoding="utf-8")
        cls.hub_html = (ROOT / "hub" / "index.html").read_text(encoding="utf-8")

    def test_optional_auth_paths_do_not_include_admin_reset_or_passwordless_bypass_by_default(self) -> None:
        match = re.search(r"function isSessionOptionalPath\(path\) \{(?P<body>.*?)\n\}", self.server, re.S)
        self.assertIsNotNone(match)
        body = match.group("body")

        self.assertNotIn("/auth/reset-admin", body)
        self.assertIn("/auth/login", body)
        self.assertIn("/auth/register", body)
        self.assertIn("/auth/setup-admin", body)
        self.assertIn("HUB_ENABLE_LEGACY_PASSWORDLESS_ACCOUNTS", body)
        self.assertIn("/session/create", body)
        self.assertIn("/accounts/create", body)

    def test_legacy_passwordless_endpoints_are_explicitly_disabled_unless_opted_in(self) -> None:
        self.assertIn("HUB_ENABLE_LEGACY_PASSWORDLESS_ACCOUNTS = process.env.HUB_ENABLE_LEGACY_PASSWORDLESS_ACCOUNTS === 'true'", self.server)
        self.assertIn("legacy_passwordless_session_create_disabled", self.server)
        self.assertIn("legacy_passwordless_account_create_disabled", self.server)
        self.assertNotIn("/hub/session/create\"", (ROOT / "tools" / "sim_multiuser.sh").read_text(encoding="utf-8"))

    def test_public_bootstrap_does_not_enumerate_accounts(self) -> None:
        self.assertIn("authenticated: false", self.server)
        self.assertIn("accounts: []", self.server)
        self.assertIn("where account_id=", self.server)
        self.assertIn("canAdmin(viewerRole) ? ''", self.server)

    def test_admin_reset_is_not_exposed_on_login_screen(self) -> None:
        self.assertNotIn('id="showResetAdminPath"', self.hub_html)
        self.assertNotIn('id="resetAdminBtn"', self.hub_html)
        self.assertIn("Lost-admin recovery is an operator-side DB/runbook action", self.hub_html)
        self.assertNotIn("showResetAdminPath", self.hub_app)
        self.assertNotIn("/hub/auth/reset-admin", self.hub_app)

    def test_password_and_cors_defaults_are_hardened(self) -> None:
        self.assertIn("MIN_PASSWORD_LENGTH = Number(process.env.HUB_MIN_PASSWORD_LENGTH || 12)", self.server)
        self.assertIn("function passwordTooShort", self.server)
        self.assertIn("crypto.timingSafeEqual", self.server)
        self.assertIn("app.use(cors({", self.server)
        self.assertNotIn("app.use(cors());", self.server)
        self.assertIn("express.json({ limit:", self.server)

    def test_hub_ui_escapes_user_supplied_html_paths(self) -> None:
        self.assertIn("function escHtml", self.hub_app)
        self.assertIn("function truncHtml", self.hub_app)
        self.assertNotIn("${s.title}</strong>", self.hub_app)
        self.assertNotIn("${s.description.slice", self.hub_app)
        self.assertNotIn("${s.verdict}", self.hub_app)
        self.assertNotIn("${accountLabel(a)}</option>", self.hub_app)
        self.assertIn("${escHtml(s.title)}</strong>", self.hub_app)
        self.assertIn("${truncHtml(s.description, 100)}", self.hub_app)
        self.assertIn("${escHtml(accountLabel(a))}</option>", self.hub_app)
        self.assertNotIn("process?.env", self.hub_app)


if __name__ == "__main__":
    unittest.main()
