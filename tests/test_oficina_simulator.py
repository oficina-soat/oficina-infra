import io
import unittest
from contextlib import redirect_stderr

from scripts.simulator.oficina_simulator import Config, Simulator, main, mask, synthetic_cpf


def config(**overrides):
    values = dict(base_url="http://example.invalid", token=None, duration=2, intensity=4,
                  profile="cotidiano", seed=42, dry_run=True, max_events=20,
                  max_cost_brl=1.0, interval=0, timeout=1, cleanup=False, async_wait=0)
    values.update(overrides)
    return Config(**values)


class SimulatorTest(unittest.TestCase):
    def test_same_seed_produces_same_plan(self):
        self.assertEqual(Simulator(config()).select_scenarios(), Simulator(config()).select_scenarios())

    def test_different_seed_changes_plan(self):
        self.assertNotEqual(Simulator(config()).select_scenarios(), Simulator(config(seed=43)).select_scenarios())

    def test_limits_number_of_events(self):
        self.assertEqual(3, len(Simulator(config(max_events=3)).select_scenarios()))

    def test_dry_run_classifies_expected_rejection(self):
        simulator = Simulator(config(duration=1, intensity=1), output=lambda _: None)
        simulator.request("payload_invalido", simulator.specs_for("payload_invalido", 1)[0], 1)
        self.assertEqual("expected_rejection", simulator.results[0].classification)

    def test_idempotency_retry_reuses_body_and_key(self):
        specs = Simulator(config()).specs_for("retry_idempotente", 3)
        self.assertEqual(specs[0], specs[1])

    def test_customer_arrival_creates_client_vehicle_and_order(self):
        simulator = Simulator(config(), output=lambda _: None)
        simulator.execute_scenario("chegada_cliente", 1)
        self.assertEqual(5, len(simulator.results))
        self.assertEqual(["chegada_cliente", "chegada_cliente", "chegada_cliente",
                          "capabilities_os", "transicao_direta_bloqueada"],
                         [result.scenario for result in simulator.results])
        self.assertEqual("expected_rejection", simulator.results[-1].classification)
        self.assertEqual(1, len(simulator.orders))

    def test_divergent_idempotency_key_is_expected_conflict(self):
        simulator = Simulator(config(), output=lambda _: None)
        simulator.execute_scenario("chave_idempotente_divergente", 1)
        self.assertNotEqual(simulator.specs_for("chave_idempotente_divergente", 1)[0].body,
                            simulator.specs_for("chave_idempotente_divergente", 1)[1].body)
        self.assertEqual(["approved", "expected_rejection"],
                         [result.classification for result in simulator.results])

    def test_vehicle_plate_varies_with_seed(self):
        first = Simulator(config(seed=3), output=lambda _: None)
        second = Simulator(config(seed=4), output=lambda _: None)
        first.execute_scenario("chegada_cliente", 1)
        second.execute_scenario("chegada_cliente", 1)
        self.assertNotEqual(first.client.config.seed, second.client.config.seed)

    def test_catalog_flow_includes_expected_stock_failure(self):
        simulator = Simulator(config(), output=lambda _: None)
        simulator.execute_scenario("catalogo_estoque", 1)
        self.assertEqual(["approved", "approved", "expected_rejection"],
                         [result.classification for result in simulator.results])

    def test_user_cleanup_only_inactivates_created_user(self):
        simulator = Simulator(config(cleanup=True), output=lambda _: None)
        simulator.execute_scenario("usuario_operacional", 1)
        self.assertEqual(["POST", "PUT", "PUT", "DELETE"],
                         [result.detail.split()[0] for result in simulator.results])

    def test_cost_guard_blocks_execution(self):
        with self.assertRaises(ValueError):
            Simulator(config(max_cost_brl=0), output=lambda _: None).run()

    def test_cpf_has_eleven_digits_and_marker_is_masked(self):
        self.assertRegex(synthetic_cpf(42, 1), r"^\d{11}$")
        self.assertEqual("12345678...cdef", mask("1234567890abcdef"))

    def test_dry_run_cli_succeeds_without_token(self):
        self.assertEqual(0, main(["--dry-run", "--duration", "1", "--intensity", "2", "--seed", "1"]))

    def test_live_cli_requires_token(self):
        stderr = io.StringIO()
        with redirect_stderr(stderr):
            self.assertEqual(2, main(["--duration", "1", "--intensity", "1"]))
        self.assertIn("OFICINA_SIM_TOKEN", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
