import re
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
LAB_TERRAFORM = REPOSITORY_ROOT / "terraform" / "environments" / "lab" / "main.tf"
LAB_OUTPUTS = REPOSITORY_ROOT / "terraform" / "environments" / "lab" / "outputs.tf"


class ApiGatewayRoutesTest(unittest.TestCase):
    def test_lab_route_keys_do_not_end_with_slash(self):
        terraform = LAB_TERRAFORM.read_text(encoding="utf-8")
        route_keys = re.findall(r'^\s*"([A-Z]+ /[^"]+)"\s*=', terraform, re.MULTILINE)

        invalid_route_keys = [route_key for route_key in route_keys if route_key.endswith("/")]

        self.assertEqual([], invalid_route_keys)

    def test_public_swagger_urls_do_not_end_with_slash(self):
        outputs = LAB_OUTPUTS.read_text(encoding="utf-8")
        swagger_urls = re.findall(r'api_endpoint}(/q/swagger-ui/[^"]+)', outputs)

        self.assertEqual(3, len(swagger_urls))
        self.assertFalse(any(url.endswith("/") for url in swagger_urls))

    def test_base_swagger_route_rewrites_the_integration_path(self):
        terraform = LAB_TERRAFORM.read_text(encoding="utf-8")

        self.assertIn('"overwrite:path" = "${trimprefix(route_key, "GET ")}/"', terraform)


if __name__ == "__main__":
    unittest.main()
