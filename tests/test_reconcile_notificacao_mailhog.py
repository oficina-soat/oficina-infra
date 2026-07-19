import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPOSITORY_ROOT / "scripts" / "actions" / "ci-reconcile-notificacao-mailhog.sh"
CURRENT_NLB_HOST = "eks-lab-mailhog-smtp-current.elb.us-east-1.amazonaws.com"


class ReconcileNotificacaoMailhogTest(unittest.TestCase):
    def run_reconcile(self, mailer_host: str) -> tuple[subprocess.CompletedProcess[str], dict]:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = Path(temporary_directory)
            bin_path = temporary_path / "bin"
            bin_path.mkdir()
            state_path = temporary_path / "state.json"
            state_path.write_text(
                json.dumps(
                    {
                        "Environment": {
                            "Variables": {
                                "QUARKUS_MAILER_FROM": "noreply@oficina.local",
                                "QUARKUS_MAILER_HOST": mailer_host,
                                "CUSTOM_SETTING": "preserved",
                            }
                        },
                        "updateCalls": 0,
                    }
                ),
                encoding="utf-8",
            )

            fake_aws = bin_path / "aws"
            fake_aws.write_text(
                """#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

arguments = sys.argv[1:]
state_path = Path(os.environ["FAKE_AWS_STATE"])
state = json.loads(state_path.read_text(encoding="utf-8"))

if "elbv2" in arguments and "describe-load-balancers" in arguments:
    print(os.environ["FAKE_NLB_HOST"])
elif "lambda" in arguments and "get-function-configuration" in arguments:
    print(json.dumps(state))
elif "lambda" in arguments and "wait" in arguments:
    pass
elif "lambda" in arguments and "update-function-configuration" in arguments:
    environment_argument = arguments[arguments.index("--environment") + 1]
    environment_path = Path(environment_argument.removeprefix("file://"))
    state["Environment"] = json.loads(environment_path.read_text(encoding="utf-8"))
    state["updateCalls"] += 1
    state_path.write_text(json.dumps(state), encoding="utf-8")
else:
    raise SystemExit(f"unexpected aws invocation: {arguments}")
""",
                encoding="utf-8",
            )
            fake_aws.chmod(fake_aws.stat().st_mode | stat.S_IXUSR)

            environment = os.environ.copy()
            environment.update(
                {
                    "PATH": f"{bin_path}:{environment['PATH']}",
                    "FAKE_AWS_STATE": str(state_path),
                    "FAKE_NLB_HOST": CURRENT_NLB_HOST,
                }
            )
            result = subprocess.run(
                ["bash", str(SCRIPT)],
                check=False,
                capture_output=True,
                text=True,
                env=environment,
            )
            return result, json.loads(state_path.read_text(encoding="utf-8"))

    def test_replaces_stale_managed_nlb_and_preserves_environment(self):
        result, state = self.run_reconcile(
            "eks-lab-mailhog-smtp-stale.elb.us-east-1.amazonaws.com"
        )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(1, state["updateCalls"])
        self.assertEqual(
            CURRENT_NLB_HOST,
            state["Environment"]["Variables"]["QUARKUS_MAILER_HOST"],
        )
        self.assertEqual(
            "preserved", state["Environment"]["Variables"]["CUSTOM_SETTING"]
        )

    def test_preserves_explicit_external_smtp(self):
        result, state = self.run_reconcile("smtp.example.com")

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(0, state["updateCalls"])
        self.assertEqual(
            "smtp.example.com",
            state["Environment"]["Variables"]["QUARKUS_MAILER_HOST"],
        )


if __name__ == "__main__":
    unittest.main()
