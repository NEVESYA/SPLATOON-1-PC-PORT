"""Alternate authored heavy-scene benchmarks; never accepts a game executable."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--baseline", type=Path, default=root / "build/heavy-before/gambit_render_bench.exe")
parser.add_argument("--candidate", type=Path, default=root / "build/game/Release/gambit_render_bench.exe")
parser.add_argument("--repeats", type=int, default=7)
parser.add_argument("--cases", nargs="+", choices=("plaza", "heavy", "heavy_push", "overdraw", "watch", "geometry"),
                    default=["plaza", "heavy", "heavy_push", "overdraw", "watch", "geometry"])
parser.add_argument("--output", type=Path, default=root / "build/heavy-benchmark-results.json")
args = parser.parse_args()
for path in (args.baseline, args.candidate):
    if path.name.lower() != "gambit_render_bench.exe" or not path.is_file():
        parser.error("only existing standalone gambit_render_bench.exe files are accepted")
if args.repeats < 3:
    parser.error("at least three alternating repetitions are required")
hashes = {name: hashlib.sha256(path.read_bytes()).hexdigest()
          for name, path in (("baseline", args.baseline), ("candidate", args.candidate))}
if hashes["baseline"] == hashes["candidate"]:
    parser.error("identical binaries; rebuild both versions explicitly")
result = {"synthetic_only": True, "game_executed": False, "repeats": args.repeats,
          "sha256": hashes, "runs": [], "summary": {}, "regressions": []}
for driver in ("nv-vk64.json", "igvk64.json"):
    env = dict(os.environ, VK_LOADER_DRIVERS_SELECT=driver, RBREW_VK_VALIDATION="0")
    for case in args.cases:
        runs = {"baseline": [], "candidate": []}
        for repeat in range(args.repeats):
            for version in (("baseline", "candidate") if repeat % 2 == 0 else ("candidate", "baseline")):
                executable = args.baseline if version == "baseline" else args.candidate
                run = subprocess.run([str(executable.resolve()), case], cwd=root, env=env,
                                     text=True, capture_output=True, check=True, timeout=120)
                records = [json.loads(line) for line in run.stdout.splitlines() if line.startswith("{")]
                if not any(record.get("passed") for record in records):
                    raise RuntimeError("authored output validation missing")
                result["runs"].append({"driver": driver, "case": case, "version": version,
                                       "repeat": repeat, "records": records, "stderr": run.stderr})
                runs[version].append(next(record for record in records if record.get("passed")))
        summary = {}
        for version, samples in runs.items():
            summary[version] = {key: statistics.median(sample[key] for sample in samples)
                                for key, value in samples[0].items()
                                if isinstance(value, (int, float)) and not isinstance(value, bool)}
        for field in ("objects", "draws_per_frame", "indices_per_draw", "checked_pixels", "operations", "checksum", "programs", "pipelines"):
            if field in summary["baseline"] and summary["baseline"][field] != summary["candidate"][field]:
                raise RuntimeError(f"workload changed: {driver}/{case}/{field}")
        primary = "cpu_median_ms" if case in ("plaza", "heavy", "heavy_push", "overdraw") else "wall_ms"
        before, after = summary["baseline"][primary], summary["candidate"][primary]
        summary["primary_metric"] = primary
        summary["cpu_time_reduction_percent"] = (1 - after / before) * 100
        for field in ("wall_ms", "cpu_median_ms", "cpu_p95_ms", "cpu_p99_ms", "gpu_median_ms"):
            if field not in summary["baseline"]:
                continue
            b = [sample[field] for sample in runs["baseline"]]
            a = [sample[field] for sample in runs["candidate"]]
            if statistics.median(a) > statistics.median(b) * 1.05 and statistics.quantiles(a)[0] > statistics.quantiles(b)[2]:
                result["regressions"].append(f"{driver}/{case}/{field}")
        result["summary"][f"{driver}/{case}"] = summary
        args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
        print(f"{driver}/{case}: {before:.4f} -> {after:.4f} ms, "
              f"{summary['cpu_time_reduction_percent']:.1f}% less synthetic CPU time", flush=True)
if result["regressions"]:
    raise SystemExit("sustained regressions: " + ", ".join(result["regressions"]))
