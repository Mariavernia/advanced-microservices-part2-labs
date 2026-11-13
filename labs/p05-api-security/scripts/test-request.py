#!/usr/bin/env python3
"""Offline tests of the token-safe P05 request helper."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch, MagicMock

spec = importlib.util.spec_from_file_location("p05_request", Path(__file__).with_name("request.py"))
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class RequestTests(unittest.TestCase):
    def call(self, *args):
        out, err = io.StringIO(), io.StringIO()
        with patch.object(sys, "argv", ["request.py", *args]), contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            result = helper.main()
        return result, out.getvalue(), err.getvalue()

    def test_private_file_and_fixed_loopback_request(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(helper, "CACHE", Path(tmp)):
            token_file = Path(tmp) / "reader.jwt"
            token_file.write_text("synthetic-private-token")
            os.chmod(token_file, 0o600)
            response = MagicMock(status=403)
            response.getheader.return_value = None
            with patch.object(helper.http.client, "HTTPConnection") as connect:
                connect.return_value.getresponse.return_value = response
                code, out, err = self.call("reader", "/api/payments/methods", "--status-only")
                self.assertEqual((code, out.strip(), err), (0, "403", ""))
                connect.assert_called_once_with("127.0.0.1", 8080, timeout=10)
                connect.return_value.request.assert_called_once_with(
                    "GET", "/api/payments/methods",
                    headers={"Accept": "application/json", "Authorization": "Bearer synthetic-private-token"})
            os.chmod(token_file, 0o644)
            with patch.object(helper.http.client, "HTTPConnection") as connect:
                code, out, err = self.call("reader", "/api/payments/methods")
                self.assertEqual(code, 1)
                self.assertNotIn("synthetic-private-token", out + err)
                connect.assert_not_called()

    def test_rejects_external_destination(self):
        with patch.object(helper.http.client, "HTTPConnection") as connect:
            with self.assertRaises(SystemExit):
                self.call("none", "//example.com/api/orders/preview")
            connect.assert_not_called()

    def test_reports_rate_limit_without_token(self):
        with patch.object(helper.http.client, "HTTPConnection") as connect:
            response = MagicMock(status=429)
            response.getheader.return_value = "7"
            connect.return_value.getresponse.return_value = response
            code, out, err = self.call("invalid", "/api/orders/preview")
            self.assertEqual(code, 0)
            self.assertIn("HTTP 429 Retry-After=7s", out)
            self.assertNotIn("invalid-training-token", out + err)


if __name__ == "__main__":
    unittest.main()
