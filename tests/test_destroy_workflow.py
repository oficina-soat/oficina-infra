from pathlib import Path
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
TERRAFORM_SCRIPT = REPOSITORY_ROOT / "scripts" / "actions" / "ci-terraform.sh"


class DestroyWorkflowTest(unittest.TestCase):
    def test_suspends_optional_ui_before_destroying_main_infrastructure(self):
        script = TERRAFORM_SCRIPT.read_text(encoding="utf-8")
        destroy_branch = script.rsplit("  destroy)\n", maxsplit=1)[1]

        self.assertIn(
            '"${SCRIPT_DIR}/ci-ui-workload-lifecycle.sh" suspend',
            script,
        )
        self.assertLess(
            destroy_branch.index("suspend_optional_ui_for_destroy"),
            destroy_branch.index("delete_ecr_repository_images_for_destroy"),
        )
        self.assertLess(
            destroy_branch.index("suspend_optional_ui_for_destroy"),
            destroy_branch.index('terraform -chdir="${TERRAFORM_DIR}" destroy'),
        )


if __name__ == "__main__":
    unittest.main()
