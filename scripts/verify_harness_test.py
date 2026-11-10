"""Failure-contract regressions for the verification entry point (no MoonBit build)."""
import argparse
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

import verify


class VerificationFailureTests(unittest.TestCase):
    def setUp(self):
        work = verify.ROOT / "work"
        work.mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix="harness-regression-", dir=work)
        self.directory = pathlib.Path(self.temporary.name)
        args = argparse.Namespace(node="node", moon="moon", profile="quick", targets=["js"], timeout=10)
        self.verification = verify.Verification(args, self.directory)

    def tearDown(self):
        self.temporary.cleanup()

    def test_child_failure_blocks_dependents_and_fails_summary(self):
        marker = self.directory / "must-not-exist"
        self.verification.task("failing-child", [sys.executable, "-c", "raise SystemExit(23)"])
        self.verification.task("dependent", [sys.executable, "-c",
                               "import pathlib,sys; pathlib.Path(sys.argv[1]).touch()", str(marker)],
                               requires=("failing-child",))
        self.assertEqual(self.verification.tasks[0]["exit_code"], 23)
        self.assertEqual(self.verification.tasks[1]["status"], "skipped")
        self.assertFalse(marker.exists())
        self.assertEqual(self.verification.finish(), 1)

    def test_exit_zero_without_fresh_report_is_failure(self):
        (self.directory / "old-success.json").write_text('{"passed":true}')
        fresh = self.directory / "this-run-report.json"
        self.verification.task("missing-report", [sys.executable, "-c", "pass"], artifacts=(fresh,))
        self.assertEqual(self.verification.tasks[0]["status"], "failed")
        self.assertIn("Expected artifact missing", self.verification.tasks[0]["reason"])
        self.assertEqual(self.verification.finish(), 1)

    def test_missing_executable_is_failure_not_empty_success(self):
        self.verification.task("missing-tool", ["capnp-nonexistent-test-tool", "--version"])
        self.assertEqual(self.verification.tasks[0]["status"], "failed")
        self.assertIsNone(self.verification.tasks[0]["exit_code"])
        self.assertEqual(self.verification.finish(), 1)
        summary = self.directory / "summary.json"
        report = json.loads(summary.read_text(encoding="utf-8"))
        self.assertEqual(report["status"], "failed")
        self.assertEqual(report["counts"]["failed"], 1)
        self.assertEqual(report["counts"]["passed"], 0)

    def test_release_requires_explicit_version(self):
        run = subprocess.run([sys.executable, str(verify.ROOT / "scripts/verify.py"), "--profile", "release"],
                             cwd=verify.ROOT, capture_output=True, text=True)
        self.assertEqual(run.returncode, 2)
        self.assertIn("explicit --version", run.stderr)

    def test_artifact_from_another_run_cannot_pass(self):
        stale = self.directory.parent / "old-capnp-harness-artifact.json"
        try:
            stale.write_text('{"status":"passed"}')
            self.verification.task("stale-report", [sys.executable, "-c", "pass"], artifacts=(stale,))
            self.assertEqual(self.verification.tasks[0]["status"], "failed")
            self.assertIn("outside this run", self.verification.tasks[0]["reason"])
        finally:
            stale.unlink(missing_ok=True)

    def test_timeout_is_failed_and_records_log_digest(self):
        self.verification.args.timeout = 1
        self.verification.task("timeout", [sys.executable, "-c", "import time; time.sleep(30)"])
        task = self.verification.tasks[0]
        self.assertEqual(task["status"], "failed")
        self.assertIn("timed out", task["reason"])
        self.assertEqual(len(task["log_sha256"]), 64)

    def test_minimum_compiler_version_is_enforced(self):
        self.assertFalse(verify.supported_toolchain("moonc v0.10.14+old"))
        self.assertFalse(verify.supported_toolchain("moon 0.10.16"))
        self.assertTrue(verify.supported_toolchain("moon version\nmoonc v0.10.16+b1a0e846e"))
        self.assertTrue(verify.supported_toolchain("moonc v0.11.0 new"))


if __name__ == "__main__":
    unittest.main()
