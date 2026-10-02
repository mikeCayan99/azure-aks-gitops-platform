import json
import os
import subprocess
import sys
import time
import unittest
from urllib.error import URLError
from urllib.request import urlopen


class EndpointTests(unittest.TestCase):
    def check_server(self, app_version, expected_version):
        env = os.environ.copy()
        env.pop("APP_VERSION", None)
        if app_version is not None:
            env["APP_VERSION"] = app_version

        server = subprocess.Popen(
            [sys.executable, "-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "8000"],
            env=env,
        )
        try:
            deadline = time.monotonic() + 10
            while True:
                if server.poll() is not None:
                    self.fail("Server exited before becoming ready")
                try:
                    with urlopen("http://127.0.0.1:8000/health/ready", timeout=1):
                        break
                except URLError:
                    if time.monotonic() >= deadline:
                        self.fail("Server did not become ready within 10 seconds")
                    time.sleep(0.1)

            expected = {
                "/version": {"version": expected_version},
                "/health/live": {"status": "alive"},
                "/health/ready": {"status": "ready"},
            }
            for path, body in expected.items():
                with self.subTest(path=path):
                    with urlopen("http://127.0.0.1:8000" + path, timeout=2) as response:
                        self.assertEqual(response.status, 200)
                        self.assertEqual(response.headers.get_content_type(), "application/json")
                        self.assertEqual(json.load(response), body)
        finally:
            server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=5)

    def test_default_version_and_health(self):
        self.check_server(None, "0.1.0")

    def test_configured_version_and_health(self):
        self.check_server("ci-test", "ci-test")


if __name__ == "__main__":
    unittest.main()
