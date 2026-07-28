import re
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
LAB_TERRAFORM = REPOSITORY_ROOT / "terraform" / "environments" / "lab" / "main.tf"
SUSPEND_SCRIPT = REPOSITORY_ROOT / "scripts" / "actions" / "ci-suspend.sh"
RESUME_WORKFLOW = REPOSITORY_ROOT / ".github" / "workflows" / "resume-lab.yml"


class SuspendResumeWorkflowTest(unittest.TestCase):
    def setUp(self):
        self.terraform = LAB_TERRAFORM.read_text(encoding="utf-8")

    def resource_body(self, resource_type, resource_name):
        match = re.search(
            rf'resource "{resource_type}" "{resource_name}" \{{(?P<body>.*?)^\}}',
            self.terraform,
            re.MULTILINE | re.DOTALL,
        )
        self.assertIsNotNone(match)
        return match.group("body")

    def test_suspend_preserves_notification_lambda_security_group(self):
        security_group = self.resource_body(
            "aws_security_group",
            "notificacao_lambda",
        )

        self.assertIn("count = 1", security_group)
        self.assertNotIn("var.create_eks", security_group)

    def test_smtp_rule_still_follows_eks_lifecycle(self):
        smtp_rule = self.resource_body(
            "aws_vpc_security_group_egress_rule",
            "notificacao_lambda_to_mailhog_smtp",
        )

        self.assertIn("count = var.create_eks ? 1 : 0", smtp_rule)

    def test_suspend_and_resume_use_the_expected_eks_values(self):
        suspend = SUSPEND_SCRIPT.read_text(encoding="utf-8")
        resume = RESUME_WORKFLOW.read_text(encoding="utf-8")

        self.assertIn("TF_VAR_create_eks=false", suspend)
        self.assertIn("uses: ./.github/workflows/deploy-lab.yml", resume)
        self.assertIn("start_rds: true", resume)


if __name__ == "__main__":
    unittest.main()
