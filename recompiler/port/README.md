# Native Vulkan runtime

`Gambit.rpx` is recompiled into native C++, linked with the Cafe OS runtime and rendered through Vulkan. SDL supplies static Windows window/input support. The shader compiler accepts Vulkan GLSL and emits SPIR-V.

Configure this directory with the existing generated guest checkpoint and the audited dependency profiles. `RBREW_GRAPHICS_BACKEND` accepts only `Vulkan`. Required Vulkan features are checked by `os/gx2/vk/gx2_vk.cpp`.

`gambit_runtime` is the host library. `Gambit` is the graphical release executable. `gx2_replay_quiet` validates saved draws using the same silent runtime. Renderer-free ABI tests use a separate headless implementation.

GPU memory uses all resource-compatible Vulkan memory types, including shared
UMA RAM and discrete-GPU system-memory fallback. GPU-local access stays preferred;
mapped uploads and readbacks support non-coherent memory. See
[`docs/vulkan-memory.md`](../../docs/vulkan-memory.md) for placement,
synchronization and hardware verification details.

For host changes, build `gambit_runtime` and the replay target incrementally, then relink the game with unchanged generated objects. Do not regenerate original game code for a host-only renderer change. The complete local manual contains dependency commands, exact build identities, runtime layout and verification limits.

MSVC Release builds now enable host-runtime and Latte-translator LTCG (`RBREW_RUNTIME_IPO=ON`,
compiler support checked by CMake). Generated guest objects retain their existing
flags and incremental reuse. Floating-point compilation stays precise.

`gambit_shader_bench` is an authored standalone workload and never links the
generated title. Modes `compiler`, `translation`, `scheduling`, `engine`, `gpu`, and
`gpu_memory` report cold/warm timings, latency percentiles, throughput, process
memory, Vulkan allocation costs, upload/draw recording and GPU output checks.
The last mode additionally samples driver heap estimates; sampling is excluded
from normal timing runs. `recompiler/tests/run_shader_benchmarks.py` alternates
candidate/baseline runs and saves raw JSON results. See `docs/performance.md`
for methodology and limits. Neither building nor running these tools launches
the game.
