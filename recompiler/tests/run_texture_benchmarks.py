"""Repeat only authored texture/uniform benchmarks, alternating executable order."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--baseline", type=Path, default=root / "build/next-before/gambit_texture_bench.exe")
parser.add_argument("--candidate", type=Path, default=root / "build/game/Release/gambit_texture_bench.exe")
parser.add_argument("--repeats", type=int, default=7)
parser.add_argument("--output", type=Path, default=root / "build/next-texture-results.json")
args = parser.parse_args()
for executable in (args.baseline, args.candidate):
    if executable.name.lower() != "gambit_texture_bench.exe" or not executable.is_file():
        parser.error("only existing standalone gambit_texture_bench.exe files are accepted")
if args.repeats < 3:
    parser.error("use at least three repetitions")
hashes = {name: hashlib.sha256(path.read_bytes()).hexdigest()
          for name, path in (("baseline", args.baseline), ("candidate", args.candidate))}
if hashes["baseline"] == hashes["candidate"]:
    parser.error("baseline and candidate binaries are identical; rebuild the baseline sources explicitly")
result = {"synthetic_only": True, "game_executed": False, "repeats": args.repeats, "runs": [], "summary": {}, "regressions": []}
result["executable_sha256"] = hashes
for name, case, driver in (("cpu", "uniforms", None), ("nvidia", "textures", "nv-vk64.json"), ("intel", "textures", "igvk64.json")):
    env = dict(os.environ)
    if driver:
        env["VK_LOADER_DRIVERS_SELECT"] = driver
    collected = {"baseline": {}, "candidate": {}}
    for repeat in range(args.repeats):
        for version in (("baseline", "candidate") if repeat % 2 == 0 else ("candidate", "baseline")):
            executable = args.baseline if version == "baseline" else args.candidate
            run = subprocess.run([str(executable.resolve()), case], cwd=root, env=env, text=True,
                                 capture_output=True, check=True, timeout=120)
            records = [json.loads(line) for line in run.stdout.splitlines() if line.startswith("{")]
            result["runs"].append({"adapter": name, "case": case, "version": version, "repeat": repeat,
                                   "records": records, "stderr": run.stderr})
            for record in records:
                if "metric" in record:
                    collected[version].setdefault(record["metric"], []).append(record)
    for metric, before in collected["baseline"].items():
        summary = {}
        for version in ("baseline", "candidate"):
            samples = collected[version][metric]
            summary[version] = {key: statistics.median(sample[key] for sample in samples)
                                for key, value in samples[0].items() if isinstance(value, (int, float))}
        key = "wall_ms" if "wall_ms" in before[0] else "median_ms"
        summary["time_reduction_percent"] = (1 - summary["candidate"][key] / summary["baseline"][key]) * 100
        # Report a sustained regression only when both the median is worse
        # and the middle halves of the measurements no longer overlap.
        before_q3 = statistics.quantiles([sample[key] for sample in before], n=4)[2]
        after_q1 = statistics.quantiles([sample[key] for sample in collected["candidate"][metric]], n=4)[0]
        summary["sustained_regression"] = (summary["candidate"][key] > summary["baseline"][key] * 1.05
                                            and after_q1 > before_q3)
        if summary["sustained_regression"]:
            result["regressions"].append(f"{name}/{metric}")
        result["summary"][f"{name}/{metric}"] = summary
        print(f"{name}/{metric}: {summary['baseline'][key]:.4f} -> {summary['candidate'][key]:.4f} ms "
              f"({summary['time_reduction_percent']:.1f}% less synthetic time)", flush=True)
    args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
if result["regressions"]:
    raise SystemExit("sustained performance regressions: " + ", ".join(result["regressions"]))
