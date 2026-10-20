"""Synthetic-only tests. No SSH invocation and no database connection."""
import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location("live_compare", pathlib.Path(__file__).with_name("live-compare.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SafetyTests(unittest.TestCase):
    def test_requires_two_distinct_captures_no_all_data_fallback(self):
        for ids in [[], [""], ["not-a-uuid", "bad"], ["0" * 36, "1" * 36], ["00000000-0000-0000-0000-000000000001"] * 2]:
            with self.assertRaises(ValueError):
                module.query(ids)

    def test_sql_explicit_read_only_and_stable_capture_order(self):
        sql = module.query(["00000000-0000-0000-0000-000000000001", "00000000-0000-0000-0000-000000000002"])
        self.assertTrue(sql.startswith("BEGIN READ ONLY;"))
        self.assertTrue(sql.endswith("ROLLBACK;"))
        self.assertIn("ORDER BY requested.ordinal", sql)
        self.assertNotIn("UPDATE", sql)
        self.assertNotIn("DELETE", sql)
        self.assertNotIn("INSERT", sql)

    def test_output_sanitizer_rejects_diagnostics_and_identity(self):
        for value in [{"captures": [{"latitude": 47}]}, {"error": "URL with coordinates"}, {"captureId": 1}, {"points": float("nan")}]:
            with self.assertRaises(ValueError):
                module.numeric_only(value)
        module.numeric_only({"captures": [{"points": 2, "before": {"p50": None}}]})
        module.numeric_only({"sourceHashes": {"api": "a" * 64, "ios": "b" * 64, "replay": "c" * 64}})

    def test_remote_script_parses_and_suppresses_stderr(self):
        source = module.remote_program("BEGIN READ ONLY; ROLLBACK;", {"code": "", "apiBundle": ""})
        compile(source, "remote-calculation", "exec")
        self.assertNotIn("calc.stderr", source)
        self.assertNotIn("db.stderr", source)
        self.assertIn("numeric_only(report)", source)
        self.assertIn("'114'", source)


if __name__ == "__main__":
    unittest.main()
