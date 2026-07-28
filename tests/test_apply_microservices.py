import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPOSITORY_ROOT / "scripts" / "manual" / "apply-microservices.sh"


class ApplyMicroservicesTest(unittest.TestCase):
    def test_defines_canonical_lab_payer_defaults(self):
        script = SCRIPT.read_text(encoding="utf-8")

        self.assertIn(
            'OFICINA_MERCADO_PAGO_PAYER_EMAIL="${OFICINA_MERCADO_PAGO_PAYER_EMAIL:-test_user_br@testuser.com}"',
            script,
        )
        self.assertIn(
            'OFICINA_MERCADO_PAGO_PAYER_FIRST_NAME="${OFICINA_MERCADO_PAGO_PAYER_FIRST_NAME:-APRO}"',
            script,
        )

    def run_with_access_token(self, access_token: str) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temporary_directory:
            bin_path = Path(temporary_directory) / "bin"
            bin_path.mkdir()
            fake_kubectl = bin_path / "kubectl"
            fake_kubectl.write_text("#!/usr/bin/env bash\nexit 99\n", encoding="utf-8")
            fake_kubectl.chmod(fake_kubectl.stat().st_mode | stat.S_IXUSR)

            environment = os.environ.copy()
            environment.update(
                {
                    "PATH": f"{bin_path}:{environment['PATH']}",
                    "MICROSERVICE_NAMES": "oficina-billing-service",
                    "OFICINA_BILLING_SERVICE_IMAGE": "example.invalid/oficina-billing-service:1.9.0",
                    "OFICINA_MERCADO_PAGO_ENABLED": "true",
                    "OFICINA_MERCADO_PAGO_API_MODE": "orders",
                    "OFICINA_MERCADO_PAGO_ACCESS_TOKEN": access_token,
                    "OFICINA_MERCADO_PAGO_WEBHOOK_SECRET": "webhook-secret-value",
                }
            )
            return subprocess.run(
                ["bash", str(SCRIPT)],
                check=False,
                capture_output=True,
                text=True,
                env=environment,
            )

    def test_rejects_test_credentials_before_accessing_cluster(self):
        access_token = "TEST-token-that-must-not-be-logged"

        result = self.run_with_access_token(access_token)

        self.assertEqual(1, result.returncode)
        self.assertIn("credencial de teste APP_USR da aplicacao", result.stderr)
        self.assertIn("credenciais TEST-* nao sao aceitas", result.stderr)
        self.assertNotIn(access_token, result.stderr)
        self.assertNotIn(access_token, result.stdout)

    def test_accepts_app_usr_credentials_and_continues_to_cluster(self):
        result = self.run_with_access_token("APP_USR-test-application-token")

        self.assertEqual(99, result.returncode)
        self.assertNotIn("credenciais TEST-* nao sao aceitas", result.stderr)


if __name__ == "__main__":
    unittest.main()
