#!/usr/bin/env python3
# ABOUTME: TDD suite for scripts/speed-report.py, the wall-clock speed report over session transcripts.
# ABOUTME: Builds tiny synthetic transcripts with known timings and checks the request splits.
# ABOUTME: Covers prompt detection, AskUserQuestion exclusion, the day window, ranking,
# ABOUTME: --save output files and the per-hook benchmark. No real transcripts are read.
# ABOUTME: Run: python3 scripts/tests/test-speed-report.py  (exit 0 = all green).

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "speed-report.py")
spec = importlib.util.spec_from_file_location("speed_report", SCRIPT)
sr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sr)

NOW = datetime(2026, 11, 1, 12, 0, 0, tzinfo=timezone.utc)


def ts(sec, base=NOW - timedelta(hours=1)):
    """Return an ISO timestamp `sec` seconds after `base`, in the transcript's Z format."""
    return (base + timedelta(seconds=sec)).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def prompt(sec, text="do it"):
    return {"type": "user", "entrypoint": "cli", "timestamp": ts(sec), "message": {"role": "user", "content": text}}


def use(sec, tid, name, command=""):
    return {"type": "assistant", "timestamp": ts(sec),
            "message": {"content": [{"type": "tool_use", "id": tid, "name": name, "input": {"command": command}}]}}


def result(sec, tid):
    return {"type": "user", "timestamp": ts(sec),
            "message": {"content": [{"type": "tool_result", "tool_use_id": tid, "content": "ok"}]}}


def say(sec):
    return {"type": "assistant", "timestamp": ts(sec), "message": {"content": [{"type": "text", "text": "done"}]}}


def write_session(folder, name, entries):
    path = os.path.join(folder, name)
    with open(path, "w") as f:
        for e in entries:
            f.write(json.dumps(e) + "\n")
    return path


class ParseRequests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()

    def test_splits_tool_and_model_time(self):
        p = write_session(self.tmp, "a.jsonl", [prompt(0), use(2, "t1", "Bash"), result(5, "t1"), say(9)])
        reqs = sr.parse_requests(p)
        self.assertEqual(len(reqs), 1)
        self.assertAlmostEqual(reqs[0]["wall"], 9)
        self.assertAlmostEqual(reqs[0]["buckets"]["tool:Bash"], 3)
        self.assertAlmostEqual(reqs[0]["buckets"]["model"], 6)
        self.assertEqual(reqs[0]["bash_calls"], [3])

    def test_ask_user_question_wait_is_excluded(self):
        p = write_session(self.tmp, "b.jsonl", [prompt(0), use(2, "q", "AskUserQuestion"), result(102, "q"), say(104)])
        req = sr.parse_requests(p)[0]
        self.assertAlmostEqual(req["wall"], 4)
        self.assertNotIn("tool:AskUserQuestion", req["buckets"])

    def test_notifications_and_meta_do_not_start_requests(self):
        note = {"type": "user", "timestamp": ts(20), "message": {"content": "<task-notification> x"}}
        meta = {"type": "user", "timestamp": ts(25), "isMeta": True, "message": {"content": "hook text"}}
        p = write_session(self.tmp, "c.jsonl", [prompt(0), say(3), note, meta, say(30), prompt(100), say(110)])
        reqs = sr.parse_requests(p)
        self.assertEqual(len(reqs), 2)
        self.assertAlmostEqual(reqs[0]["wall"], 30)
        self.assertAlmostEqual(reqs[1]["wall"], 10)


    def test_headless_and_warmup_prompts_are_skipped(self):
        headless = dict(prompt(0), entrypoint="sdk-cli")
        warmup = {k: v for k, v in prompt(50).items() if k != "entrypoint"}
        p = write_session(self.tmp, "d.jsonl", [headless, say(5), warmup, say(60), prompt(100), say(103)])
        reqs = sr.parse_requests(p)
        self.assertEqual(len(reqs), 1)
        self.assertAlmostEqual(reqs[0]["wall"], 3)


    def test_bash_commands_are_grouped(self):
        p = write_session(self.tmp, "e.jsonl", [prompt(0), use(1, "a", "Bash", "cd /x && bash scripts/tests/run.sh -v"),
                                                result(11, "a"), use(12, "b", "Bash", "git commit -m hi"), result(14, "b"), say(15)])
        self.assertEqual([c[:2] for c in sr.parse_requests(p)[0]["bash_cmds"]], [("run.sh", 10.0), ("git commit", 2.0)])
        top = sr.summarize(sr.parse_requests(p))["top_bash"]
        self.assertEqual(top[0][0], "run.sh")
        self.assertEqual(sr.command_key("cd ~/.claude; ls x; bash scripts/a.sh"), "a.sh")
        self.assertEqual(sr.command_key("echo hi\nsleep 270 && git push diligent main"), "sleep")
        self.assertEqual(sr.command_key("cd /tmp"), "cd")
        self.assertEqual(sr.command_key("# note\nFOO=1 bash x.sh"), "x.sh")
        self.assertEqual(sr.command_key("cat > f <<'E'\nhello\nE\ngit status"), "git status")

    def test_long_bash_calls_are_listed(self):
        p = write_session(self.tmp, "f.jsonl", [prompt(0), use(1, "a", "Bash", "sed -n 1,5p f.txt"), result(301, "a"),
                                                use(302, "b", "Bash", "ls"), result(303, "b"), say(304)])
        s = sr.summarize(sr.parse_requests(p))
        self.assertEqual(len(s["long_bash"]), 1)
        self.assertEqual(s["long_bash"][0][0], 300.0)
        self.assertIn("sed -n", s["long_bash"][0][1])


class Summary(unittest.TestCase):
    def test_ranking_and_bash_overhead(self):
        reqs = [{"start": NOW, "wall": 100.0, "bash_calls": [2.0, 3.0, 4.0, 30.0],
                 "buckets": {"model": 61.0, "tool:Bash": 39.0}}]
        s = sr.summarize(reqs)
        self.assertEqual(s["requests"], 1)
        self.assertEqual([b["name"] for b in s["buckets"]][:2], ["model", "tool:Bash"])
        self.assertAlmostEqual(s["buckets"][0]["pct"], 61.0)
        self.assertAlmostEqual(s["bash_overhead_s"], 2.0 * 4)


class Cli(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        proj = os.path.join(self.tmp, "projects", "-repo")
        os.makedirs(proj)
        write_session(proj, "new.jsonl", [prompt(0), use(1, "t1", "Bash"), result(4, "t1"), say(6)])
        old = [dict(e, timestamp=(NOW - timedelta(days=30)).strftime("%Y-%m-%dT%H:%M:%S.000Z"))
               for e in [prompt(0), say(0)]]
        write_session(proj, "old.jsonl", old)
        self.state = os.path.join(self.tmp, "state")

    def run_cli(self, *args):
        return subprocess.run([sys.executable, SCRIPT, "--projects", os.path.join(self.tmp, "projects"),
                               "--now", NOW.isoformat(), *args], capture_output=True, text=True)

    def test_window_and_save(self):
        r = self.run_cli("--days", "7", "--save", "--state", self.state)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("Requests: 1", r.stdout)
        with open(os.path.join(self.state, "history.jsonl")) as f:
            line = json.loads(f.readline())
        self.assertEqual(line["requests"], 1)
        self.assertTrue(os.path.exists(os.path.join(self.state, "latest.md")))

    def test_hook_benchmark(self):
        hook = os.path.join(self.tmp, "slow-hook.sh")
        with open(hook, "w") as f:
            f.write("#!/bin/bash\ncat >/dev/null\nsleep 0.2\n")
        os.chmod(hook, 0o755)
        settings = os.path.join(self.tmp, "settings.json")
        with open(settings, "w") as f:
            json.dump({"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": hook}]},
                                                {"matcher": "Read", "hooks": [{"type": "command", "command": "/bin/false"}]}]}}, f)
        r = self.run_cli("--hooks", "--settings", settings, "--runs", "2")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("slow-hook.sh", r.stdout)
        self.assertNotIn("/bin/false", r.stdout)
        ms = [int(x) for x in r.stdout.split() if x.isdigit()]
        self.assertTrue(any(180 <= m <= 600 for m in ms), r.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=1)
