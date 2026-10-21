"""Alternate authored draw benchmarks. Never accepts a game executable."""
import argparse
import json
import os
from pathlib import Path
import statistics
import subprocess

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--baseline", type=Path, default=root / "build/render-before/gambit_render_bench.exe")
parser.add_argument("--candidate", type=Path, default=root / "build/game/Release/gambit_render_bench.exe")
parser.add_argument("--repeats", type=int, default=7)
parser.add_argument("--output", type=Path, default=root / "build/render-benchmark-results.json")
args = parser.parse_args()
for executable in (args.baseline, args.candidate):
    if executable.name.lower() != "gambit_render_bench.exe" or not executable.is_file():
        parser.error("only an existing standalone gambit_render_bench.exe is allowed")
if args.repeats < 3:
    parser.error("use at least three alternating repetitions")
results = []
for driver in ("nv-vk64.json", "igvk64.json"):
    env = dict(os.environ, VK_LOADER_DRIVERS_SELECT=driver)
    for case in ("fallback", "push", "churn"):
        runs = {"baseline": [], "candidate": []}
        for repeat in range(args.repeats):
            for name in (("baseline", "candidate") if repeat % 2 == 0 else ("candidate", "baseline")):
                executable = args.baseline if name == "baseline" else args.candidate
                completed = subprocess.run([str(executable.resolve()), case], env=env, cwd=root,
                    text=True, encoding="utf-8", errors="replace", capture_output=True, timeout=120, check=True)
                records = [json.loads(line) for line in completed.stdout.splitlines() if line.startswith("{")]
                if not any(r.get("passed") for r in records):
                    raise RuntimeError("missing draw output verification")
                runs[name].append(records)
        summary = {"driver": driver, "case": case, "runs": runs, "median": {}}
        for name, records in runs.items():
            draws = [next(r for r in run if r.get("metric") == "draws") for run in records]
            summary["median"][name] = {key: statistics.median(r[key] for r in draws)
                for key in draws[0] if isinstance(draws[0][key], (int, float))}
        before = summary["median"]["baseline"]["wall_ms"]
        after = summary["median"]["candidate"]["wall_ms"]
        summary["wall_time_reduction_percent"] = (1 - after / before) * 100
        results.append(summary)
        print(f"{driver} {case}: {before:.3f} -> {after:.3f} ms ({summary['wall_time_reduction_percent']:.1f}% less synthetic time)", flush=True)
        args.output.write_text(json.dumps({"synthetic_only": True, "repeats": args.repeats, "results": results}, indent=2), encoding="utf-8")
