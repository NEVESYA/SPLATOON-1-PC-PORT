"""Repeat authored standalone workloads; this tool cannot launch the game.

Example (from the repository root):
  python recompiler/tests/run_shader_benchmarks.py --baseline build/shader-before/gambit_shader_bench.exe
Only application caches are controlled. Vendor-managed driver caches are opaque.
"""
import argparse
import json
import os
from pathlib import Path
import statistics
import subprocess

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--candidate", type=Path, default=ROOT / "build/game/Release/gambit_shader_bench.exe")
parser.add_argument("--baseline", type=Path)
parser.add_argument("--repeats", type=int, default=5)
parser.add_argument("--case", choices=["all", "compiler", "translation", "scheduling", "gpu"], default="all")
parser.add_argument("--gpu", choices=["both", "nvidia", "intel", "none"], default="both")
parser.add_argument("--output", type=Path, default=ROOT / "build/shader-benchmark-results.json")
args = parser.parse_args()
if not 1 <= args.repeats <= 100:
    parser.error("repeats must be between 1 and 100")
executables = {"after": args.candidate.resolve()}
if args.baseline:
    executables["before"] = args.baseline.resolve()
for path in executables.values():
    # Deliberate strict allowlist. No arbitrary executable arguments or commands.
    if path.name.lower() != "gambit_shader_bench.exe" or not path.is_file():
        parser.error("only an existing gambit_shader_bench.exe is accepted")

runs = []
cpu_cases=("compiler", "translation", "scheduling") if args.case=="all" else (args.case,) if args.case!="gpu" else ()
cases = [("cpu", case, None) for case in cpu_cases]
if args.case in ("all","gpu") and args.gpu in ("both", "nvidia"):
    cases.append(("nvidia", "gpu", "nv-vk64.json"))
if args.case in ("all","gpu") and args.gpu in ("both", "intel"):
    cases.append(("intel", "gpu", "igvk64.json"))
for adapter, case, driver in cases:
    for repeat in range(args.repeats):
        order = list(executables)
        if repeat % 2:
            order.reverse()
        for version in order:
            environment = os.environ.copy()
            if driver:
                environment["VK_LOADER_DRIVERS_SELECT"] = driver
            print(f"{adapter}/{case}: {version}, repetition {repeat + 1}/{args.repeats}", flush=True)
            run = subprocess.run([str(executables[version]), case], cwd=ROOT, env=environment,
                                 capture_output=True, text=True, timeout=120, check=True)
            records = [json.loads(line) for line in run.stdout.splitlines() if line.startswith("{")]
            runs.append({"adapter": adapter, "case": case, "version": version, "repeat": repeat,
                         "metrics": records, "stdout": run.stdout, "stderr": run.stderr})

summary = {}
for run in runs:
    for metric in run["metrics"]:
        # Process memory is per executable/case, not comparable across cases.
        prefix=f'{run["adapter"]}/{run["case"]}' if metric["metric"] in ("process_memory","vulkan_allocations","application_allocation_peak") else run["adapter"]
        name = f'{prefix}/{metric["metric"]}'
        summary.setdefault(name, {}).setdefault(run["version"], []).append(metric)
for name, versions in summary.items():
    for version, samples in list(versions.items()):
        versions[version] = {key: statistics.median(s[key] for s in samples)
                             for key, value in samples[0].items()
                             if isinstance(value, (float, int))}
    if "before" in versions and "wall_ms" in versions["before"]:
        versions["wall_time_reduction_percent"] = 100 * (1 - versions["after"]["wall_ms"] /
                                                         versions["before"]["wall_ms"])
    if "translation_output" in name and "before" in versions:
        if versions["before"]["checksum"] != versions["after"]["checksum"]:
            raise RuntimeError("before/after GX2 output checksums differ")
result = {"synthetic_only": True, "game_executed": False,
          "pipeline_cache_scope": "fresh VkPipelineCache; vendor driver cache is uncontrolled",
          "summary": summary, "runs": runs}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
for name, metric in summary.items():
    if "wall_time_reduction_percent" in metric:
        print(f'{name}: {metric["before"]["wall_ms"]:.3f} -> {metric["after"]["wall_ms"]:.3f} ms '
              f'({metric["wall_time_reduction_percent"]:+.1f}% reduction)')
print(f"Saved raw runs and summary to {args.output}")
