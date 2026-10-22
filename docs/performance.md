The October 20 efficiency pass supersedes the earlier Low-End preset. Worker counts, cache capacities, shader/pipeline warm-up coverage, resource residency, GPU memory placement, frame pacing and visual settings have been restored to their original policies. Setup no longer creates a separate launcher. No new resource caps or age-based eviction remain.

The retained implementation changes remove repeated work:

- Detile/retile prepares invariant Latte addressing once per transfer, uses constant-sized element copies, and validates full microtiles instead of recalculating every texel address twice. An exact bounds-check fallback preserves partial allocations and failure-before-write behavior. Thread counts are unchanged.
- Shader-module hits allocate no unused promise. Both existing FNV fingerprints are evaluated together, and a miss reuses its identity for disk lookup instead of hashing again. Existing SPIR-V filenames remain valid; concurrent requests still share one compilation.
- Pipeline-cache loading sizes its buffer once and reads the file in bulk instead of growing a vector through byte iterators.
- Normal window close now exports the driver pipeline cache before process termination. Valid `VK_INCOMPLETE` snapshots are retained, and failed writes do not replace a good cache. No per-frame export, GPU idle wait or worker join was added. Vulkan permits reloading these partial snapshots: [Khronos API contract](https://docs.vulkan.org/refpages/latest/refpages/source/vkGetPipelineCacheData.html).

Release component benchmarks, median of seven repeats on this host:

| Same workload | Before | After |
|---|---:|---:|
| 1024x1024 RGBA8 detile, mode 4, three helpers | 3.801 ms | 1.511 ms |
| Same retile | 26.617 ms | 6.590 ms |
| 100,000 module hits, 128-byte source | 39.129 ms / 100,000 allocations | 13.694 ms / zero allocations |
| 2,000 module hits, 64 KiB source | 215.200 ms | 109.141 ms |
| Load and verify a 16 MiB pipeline-cache file | 59.768 ms / 42 allocations | 12.154 ms / one allocation |

The independent AddrLib comparison covers 680 tiling/depth/slice/element-size combinations, plus truncated and partial allocations. Tests also cover serial/parallel conversion, persistent cache filename/output compatibility, concurrent module requests, GPU texture/context reuse without reuploads, upload residency, queue ordering and compiler demand priority. Configure `-DRBREW_BUILD_TESTS=ON`; run CTest in `build/game` with Release. The final incremental Release rebuild succeeded and all 14 isolated regression tests passed. Component measurements and test logs are under `build/efficiency-*` and are intentionally untracked.

Earlier 65-second probes covered startup/loading only; screenshots did not establish plaza gameplay. The longer passive run reached the title screen and waited for input. These intervals provide no plaza FPS or 1% low result. The owner subsequently prohibited game launches: the active isolated probe was stopped, and all temporary recording/input hooks were removed. Further validation uses builds and Nintendo-free automated tests only. The plaza's original 30 FPS timing is unchanged.

An earlier normal-close probe confirmed a 55,455,507-byte driver pipeline-cache export; the baseline exported none. The owner's save hash was unchanged. Raw evidence is in `build/efficiency-live-20261020`.

A submit-mutex removal experiment was rejected: its handoff benchmark was slower. Full gameplay, level transitions, audio under load and actual low-end/integrated-GPU hardware remain unverified. Vulkan validation layers are unavailable locally.


The subsequent display-resolution update selects physical desktop pixels at launch (SDL desktop mode, per-monitor DPI awareness) and starts in borderless desktop fullscreen. Screen-sized TV color/depth attachments and their 1280x720 downsample chain allocate at the selected resolution; raster viewports/scissors, fragment-coordinate and texel-fetch scales, numeric depth transfers, aliases and scan encoding follow those physical sizes. Guest descriptors/CPU copies keep their original layout. Independent shadow maps, integer block encoders, asset textures and GamePad-sized resources retain their own dimensions. The game retains its existing camera/UI projection; this does not add alternate aspect-ratio/FOV logic. Resolution is selected at startup; moving a window or changing desktop modes during a running session does not recreate cached scene targets.

The new Nintendo-free GPU regression failed on the old allocation path, then passed at 960x540, 1024x768, 1280x720, 1366x768, 1920x1080, 2560x1440 and 3840x2160. It draws alternating physical-pixel rows/columns beyond the old console edges and verifies scissored clears, depth conversion, sampled target scales, GPU/CPU surface copies, array aliases and full-size sRGB scan-out. A window-free SDL query detected display 0 at 2560x1440 / 165 Hz and display 1 at 1920x1080 / 75 Hz. No game launch was used for this update. The plaza's 30 FPS timing is untouched.

Final display-resolution validation: incremental Release build succeeded; all 15 isolated CTest cases passed. `Game/Splatoon.exe` was updated from that build without launching it.

The October 21 native optimization pass caches stable host synchronization objects
per thread, specializes paired-single stores by quantization type, and resolves
shader/program/pipeline futures once. An exact byte-key front cache reuses the
last pipeline entry while retaining the complete pipeline map. MSVC Release
host-runtime LTCG is enabled after compiler-support and benchmark checks;
generated guest sources/objects keep their existing build policy. Floating-point
semantics, ordered guest writes/reservation observers, cache capacities, worker
counts, prewarming, render settings and timing policies are preserved.

Interleaved Release component benchmarks on the i7-12650H (medians of three
alternating runs, each reporting seven repetitions):

| Same workload | Before | After |
|---|---:|---:|
| 1,000,000 paired float stores | 17.603 ms | 8.331 ms |
| 1,000,000 quantized paired stores, u8/u16/s8/s16 | 19.908–21.721 ms | 12.472–14.316 ms |
| 200,000 independent guest lock/unlock pairs, four threads | 18.911 ms | 1.073 ms |

The production cache helpers' lookup model (1,000,000 lookups, 637-byte state keys,
16-draw batches, seven repetitions) measured 689.346 ms for the previous hash/future
path and 109.707 ms with exact-key/resolved-value reuse. These are component
measurements, not game FPS. Repeat detile and render-handoff measurements found
no material regression. Logs, baseline executables and the interleaved benchmark
runner are under `build/advanced-*` and `build/run_advanced_benchmarks.py`.

All 23 automated tests pass on both RTX 4050 and Intel UHD. Added coverage includes
58,240 quantized-store cases against an independent `ldexp` reference, strict
reservation invalidation, ordered write observers, recursive/contended locks,
condition-variable handoffs, cache collisions and object reinitialization.
Real Vulkan pipelines verify repeated-key reuse, distinct blend/topology state,
warm-up job reuse and returning to an earlier key. Existing tests retain texture,
display-resolution, upload-residency and shared-memory coverage. Validation layers
remain unavailable; stable 60 FPS and gameplay frame-time distributions have not
been established. These checks did not launch the game or load its saves.

The source comparison used [Cemu's pipeline compiler](https://github.com/cemu-project/Cemu/blob/a53cf0ece75964aa361056edab46f281dcc0bc44/src/Cafe/HW/Latte/Renderer/Vulkan/VulkanPipelineCompiler.cpp),
[Dolphin's quantized-store specialization](https://github.com/dolphin-emu/dolphin/blob/cf5cb7ef81c3e8e7af5c9d566334219ffda9f68b/Source/Core/Core/PowerPC/Jit64/Jit_LoadStorePaired.cpp),
[Dolphin's state tracker](https://github.com/dolphin-emu/dolphin/blob/cf5cb7ef81c3e8e7af5c9d566334219ffda9f68b/Source/Core/VideoBackends/Vulkan/StateTracker.cpp)
and [PCSX2's selective-LTO build policy](https://github.com/PCSX2/pcsx2/blob/1f4dd94db0633679e49bdec7faa0dd5246123ad0/cmake/BuildParameters.cmake).
Dolphin's Windows memory arena and block linker, plus PCSX2's fastmem mappings,
were also inspected. The port already has direct base-plus-address guest RAM,
native known-function calls, Windows write tracking, asynchronous compilation,
dynamic rendering, timeline submissions and mapped rings. Replacing those with
another MMU/JIT layer offers no identified saving. Extensions for graphics
pipeline libraries and descriptor indexing are advertised by both drivers,
but changing shader/resource binding architecture
needs workload evidence; it was not enabled speculatively. PGO was not trained
on synthetic workloads, and no process affinity, security or priority policy was
changed.

## Standalone cold shader pass, October 21

No game executable was executed for this pass. `gambit_shader_bench` links only
the host runtime and authored shaders/bytecode. It measures actual GX2 decoding,
GLSL emission, glslang compilation, real graphics pipelines, offscreen shader
pixels, draw recording, ring uploads, Vulkan allocations, worker scheduling and
native dispatch. It never loads title assets or calls a game entry point.

Implemented changes:

- Parse original GLSL once. The glslang C wrapper otherwise serializes expanded
  GLSL and preprocesses it again during parsing. Macro/version/extension handling
  and compiler checks remain enabled. Already initialized workers use an atomic
  fast path; disk hits do not initialize the compiler.
  File-include shaders retain the original preprocessing fallback.
- Append formatted shader text directly, with a `to_chars`/string fast path for
  plain single replacements and the original general formatter for other forms.
  Reserve decoded clause capacity once. Let transient text grow from 16 KiB
  instead of reserving 12 MiB per shader and shrinking immediately before copying.
  This changes scratch capacity, not cache size or shader limits.
- Assemble returned source directly into its final allocation. Avoid zeroing
  private bytecode/register storage immediately before overwriting every byte.
  A missing register snapshot still initializes all registers to zero.
- Scan geometry output declarations once instead of constructing/running regexes
  over every source. The original regex implementation remains a test oracle.
- Include the Cemu-derived translator in checked MSVC Release LTCG. Retain precise
  floating point and reuse all generated guest objects incrementally.
- Prepare the shader-cache directory once. Check cache file length before
  trusting its word count, and check completed writes before replacing a cache.

Seven alternating before/after process runs on this i7-12650H, using identical
inputs and unchanged worker counts, produced these median totals:

| Authored synthetic workload | Before | After |
|---|---:|---:|
| 60 uncached GLSL compilations, serial | 117.765 ms | 91.673 ms |
| Same 60 compilations, four workers | 32.230 ms | 20.675 ms |
| 60 requests into an empty SPIR-V disk cache | 156.480 ms | 108.476 ms |
| 240 GX2-to-GLSL translations | 10.104 ms | 5.245 ms |
| 160 rectangle geometry translations, 32 varyings | 26.644 ms | 3.564 ms |
| 50,000 tiny worker tasks | 43.561 ms | 43.143 ms |

Cold serial per-shader median/P95/P99 changed from 1.3443/2.5787/28.1774 ms to
0.8981/2.0471/26.9539 ms. Stage built-in initialization contributes the P99 outlier.
Process-first compiler initialization remained about 74 ms; it is not
claimed as a significant improvement. The disk corpus contains 58 unique sources
and two duplicates; both versions use identical deduplication. The cache-disabled
serial and parallel phases really compile all 60 requests. Warm disk hit rate is
100%; warm I/O fluctuated around 6–8 ms and is not claimed as a speedup. In the
final comparison it increased from 5.825 to 7.240 ms for 60 requests. A separate
same-process reader comparison isolates the small cost of validating actual file
length, retained to prevent corrupted headers from requesting enormous memory.
This is a startup-cache correctness tradeoff, not a memory-saving speed claim.

Translator-only peak process commit was 14,946,304 -> 2,326,528 bytes; resident
working set stayed about 9 MB. Most of that change is removal of the speculative
12 MiB transient reserve. Compiler-process peak memory remained about 59 MB.
No shader/pipeline cache, precompilation coverage, worker count, graphical
setting, memory budget or GPU memory placement was reduced.

Pipeline timings use a fresh **application** `VkPipelineCache`; vendor driver
caches are opaque and were not cleared. No driver-cold pipeline acceleration or
in-game FPS is claimed. Tiny draw-recording totals varied by microseconds between
the two benchmark binaries; these are not frame times. Driver heap usage/budget
sampling runs separately in `gpu_memory`, since sampling can perturb timing.
These are driver allocation estimates, not measured dedicated-VRAM residency;
an integrated GPU's local heap is shared RAM. `checkpoint_peak_bytes` records
owned allocation checkpoints, and process peak commit/working set come from
Windows. CPU time uses process accounting and has Windows accounting granularity.

Reusable commands, which execute only authored standalone tests:

```powershell
build/game/Release/gambit_shader_bench.exe compiler
build/game/Release/gambit_shader_bench.exe translation
build/game/Release/gambit_shader_bench.exe scheduling
build/game/Release/gambit_shader_bench.exe engine
build/game/Release/gambit_shader_bench.exe gpu
build/game/Release/gambit_shader_bench.exe gpu_memory
python recompiler/tests/run_shader_benchmarks.py --baseline build/shader-before/gambit_shader_bench.exe
```

The runner accepts only executables named `gambit_shader_bench.exe`, alternates
run order, preserves raw JSON samples, and compares output checksums. `--case`
selects a workload; `--gpu` selects either/both installed adapters or CPU-only
testing. Raw comparisons are in `build/shader-final-benchmark-results.json`.

Output checks include exact SPIR-V equality against the original two-pass
compiler, macro/line directive handling, invalid-source errors, geometry output
equality, integer/hex/string formatting, null-register snapshots, cache corruption
recovery, and concurrent queue consumers/exception/reference/move-only results.
Real offscreen GPU checks verify all 32 authored R700 pixel shaders and every
byte of a 16 MiB streamed upload. Other suites retain paired-store, detile,
texture/context reuse and shared/UMA memory fallback coverage.

The task-allocation/queue-layout rewrite was rejected after tiny-task throughput
regressed. The renderer already bypasses completed jobs, so adding a ready-result
shortcut to the queue itself was also dropped; its direct API benchmark was not
a representative renderer saving. A native Windows cache-reader experiment was
removed because it did not beat the existing buffered reader reliably. Source research compared
[Dolphin's single-parse compiler](https://github.com/dolphin-emu/dolphin/blob/cf5cb7ef81c3e8e7af5c9d566334219ffda9f68b/Source/Core/VideoCommon/Spirv.cpp),
[Cemu's shader compiler](https://github.com/cemu-project/Cemu/blob/a53cf0ece75964aa361056edab46f281dcc0bc44/src/Cafe/HW/Latte/Renderer/Vulkan/RendererShaderVk.cpp)
and [PCSX2's Vulkan cache](https://github.com/PCSX2/pcsx2/blob/1f4dd94db0633679e49bdec7faa0dd5246123ad0/pcsx2/GS/Renderers/Vulkan/VKShaderCache.cpp).
Only applicable techniques were adapted; shader optimizers, additional pipeline
architectures and synthetic PGO were not enabled without supporting evidence.

The final incremental Release build succeeded with all generated guest objects
reused. All 29 CTest cases pass on both RTX 4050 and Intel UHD. Final test logs and
driver heap samples are in `build/shader-final-{nvidia,intel}-test-details.log`;
`build/shader-verification.json` records source hashes and the delivered binary.
`Game/Splatoon.exe` SHA-256 is
`264426d155880d92bd655b56f737f685c8af07f25427f7563a7f4a9965a35dd4`.
No game launch or actual in-game FPS, physics, gameplay or audio validation was
performed.

## Rendering follow-up (2026-10-21)

The ordinary-descriptor fallback now caches exact resource bindings within each
submission, streams uniform offsets through dynamic UBO descriptors up to the
device's advertised limit, and resets retired pools only after GPU completion.
Push descriptors retain their supported descriptor types. Index bindings are
shadowed, immutable vertex semantics are collected once, identical sampler
parameters bypass repeated normalization, and raster validation is repeated
inside a draw only when command state was invalidated. Idle completion queries
and the unused pre-submission completion poll were removed. Shader prewarming,
worker counts, cache capacities, rendering quality and memory policy are unchanged.

`gambit_render_bench` links only the runtime and authored shaders. It submits
16,384 indexed draws with texture changes, four pipeline variants, uniform
changes, scissor changes and two render targets, then checks 4,096 pixels.
Seven alternating baseline/candidate runs produced these median total times:

| Workload | RTX 4050 before → after | Intel UHD before → after |
| --- | --- | --- |
| Reused fallback descriptors | 17.124 → 12.783 ms | 22.470 → 15.550 ms |
| Push descriptors | 15.767 → 11.572 ms | 17.062 → 13.003 ms |
| Changing uniforms with fallback descriptors | 17.861 → 13.998 ms | 23.982 → 16.627 ms |

These are synthetic CPU recording/submission/completion times, not frame times
or measured game FPS. Descriptor updates fall from 16,384 to 512 in the fallback
workloads and index binds from 16,384 to 16; draw and submission counts and
barriers remain equal. `build/render-benchmark-results.json` retains every run.
`recompiler/tests/run_render_benchmarks.py` repeats the comparison and accepts
only the standalone benchmark executable name.

The separate `contracts` case checks dynamic-offset binding order, cache keys,
pool-exhaustion recovery, bounded device-OOM failure, sampler identity and state
invalidation. `lifetime` holds 16 submissions behind a host-signalled timeline
semaphore while replacing/uploading textures; it proves that live pools are
retained and reused after completion, with correct output. These cases also run
on both GPUs. The cache-reader experiment was rejected: controlled reads improved
but total warm-cache requests did not reliably improve, so integrity checks and
the existing reader are retained.

Source comparisons used [Cemu's dynamic uniform descriptors](https://github.com/cemu-project/Cemu/blob/a53cf0ece75964aa361056edab46f281dcc0bc44/src/Cafe/HW/Latte/Renderer/Vulkan/VulkanRendererCore.cpp),
[Dolphin's state invalidation](https://github.com/dolphin-emu/dolphin/blob/cf5cb7ef81c3e8e7af5c9d566334219ffda9f68b/Source/Core/VideoBackends/Vulkan/StateTracker.cpp)
and [PCSX2's Vulkan state tracking](https://github.com/PCSX2/pcsx2/blob/1f4dd94db0633679e49bdec7faa0dd5246123ad0/pcsx2/GS/Renderers/Vulkan/GSDeviceVK.cpp).
No game executable was launched.

The incremental Release build and all 34 tests passed on each adapter, with all
five new rendering cases also passing with serial command recording. The built
binary was copied to `Game/Splatoon.exe` and its hash verified against the build.
`build/render-verification.json` records the binary/source hashes and final logs.

## Texture and uniform follow-up (2026-10-22)

Macro-tiled decoding and retiling now derive the eight-by-eight pixel address
offsets once and calculate bank/pipe/tile addresses once per eight texels. Bounds
checks, partial rows, depth and thick-tile addressing remain intact. Textures
narrower than eight texels retain their scalar path. Texture levels decode into
the existing mapped upload ring, avoiding the temporary linear allocation,
zero-initialization and full-image staging memcpy. Missing mips and failed
decodes retain their established fallback behavior. Uniform-register updates
convert directly into native state using baseline SSE2 with a scalar fallback,
removing the temporary vector and second copy.

Seven alternating runs of distinct, explicitly rebuilt baseline and candidate
binaries measured 16-upload bursts through the actual texture-binding path:

| 1024×1024 RGBA8, 16 uploads | RTX 4050 before → after | Intel UHD before → after |
| --- | --- | --- |
| Linear | 37.058 → 13.573 ms | 39.773 → 16.275 ms |
| Macro tile 4 | 58.689 → 14.877 ms | 56.839 → 17.273 ms |
| Thick tile 7 | 84.057 → 35.963 ms | 80.757 → 43.177 ms |

Across the ten tested sizes/layouts, burst time fell 26–75% on RTX and 14–72%
on Intel. These totals include hashing, CPU conversion, command recording,
submission and final completion. They are not GPU timestamps or game frame
times. Uniform API tests (100,000 updates, 16–1,024 words) take 85–93% less time;
a volatile function pointer prevents IPO from eliminating repeated writes.
Raw runs, P95/P99 recording latency, memory samples and executable hashes are
in `build/next-texture-results.json`. The initial comparison accidentally reused
identical binaries due to preserved source timestamps and was discarded; the
runner now rejects identical hashes.

Separate CPU tests of 1024×1024 RGBA8 macro layouts 4, 8 and 12 show 53–62%
less detile time with the existing serial and three-helper configurations, and
69–74% less retile time. Three alternating runs, each using seven internal
timing samples, are retained in `build/next-detile-results.json`.

The standalone `gambit_texture_bench` adds 1,452 independent AddrLib layout cases,
unaligned uniform conversion, asynchronous texture bursts and byte-exact GPU
checks of compressed mips, selected array slices, cube faces, 3D mips, absent
mips, short-source fallback and zero image-size descriptors. Existing
16,384-draw and resource-lifetime tests
remain enabled. Worker counts, precompilation, caches, resolution, Vulkan memory
type ranking, and required barriers are unchanged.

Engineering references: [Cemu's staging reservations and flushes](https://github.com/cemu-project/Cemu/blob/main/src/Cafe/HW/Latte/Renderer/Vulkan/VulkanRenderer.cpp),
[Dolphin's upload stream](https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/VideoBackends/Vulkan/VKTexture.cpp),
and [PCSX2's directly mapped texture upload path](https://github.com/PCSX2/pcsx2/blob/master/pcsx2/GS/Renderers/Vulkan/GSTextureVK.cpp).
No game executable is used by these benchmarks.

All 38 tests passed on both RTX 4050 and Intel UHD; all nine rendering/streaming
cases also passed on each adapter with serial command recording. The full
Release rebuild and final incremental build succeeded. The incremental build
reused all 193 generated guest-code objects. The delivered `Game/Splatoon.exe`
matches the built executable; `build/next-verification.json` records its hash,
source hashes and validation logs. One full-build recursion warning matches a
linked self-call verified statically in the original RPX; its behavior was
preserved. The actual game was never launched, so in-game FPS and gameplay,
physics, graphics and audio correctness remain unmeasured.

## Populated-scene follow-up (2026-10-22)

Large, unchanged geometry ranges reuse their exact write generation within the
existing render-batch epoch. Renderer stores and collections by other threads
invalidate those answers conservatively; outside-batch callers still collect
Windows write watch normally. Small uniform ranges retain their direct scan.
Vertex-fetch plans retain the decoded format/location mapping while checking
fetch-program revisions and the complete semantic-import register list. Stream
availability, strides, write generations, buffer lifetime and instance offsets
remain live on each draw.

Equivalent Vulkan shader interfaces now share descriptor and pipeline layouts.
The exact key includes descriptor type/count, shader visibility, immutable
samplers and push-layout flags. Compiler workers synchronize only during layout
lookup/creation; draws acquire no new lock. Shared ownership and the device
cache retain layouts through shader compilation, submitted commands and final
renderer shutdown. This also permits descriptor reuse across compatible material
programs, preserving draw order.

The authored `heavy`, `heavy_push` and `overdraw` workloads use 1,024 objects,
2,304 indexed draws per simulated frame, four geometry streams, 64 material
textures, eight color programs, a shadow program, changing pose uniforms,
render-target changes and repeated alpha blending. Twelve frames are queued
without per-frame GPU waits. GPU timestamps bracket rendering; a separate
readback history checks every submitted frame, followed by 2,048 object/depth
samples. The overdraw variant doubles the vertex count per draw and increases
fragment integer work. These are workload proxies, not captured Plaza frames.

Standalone contracts cover overlapping memory ranges, producer writes,
cross-thread collection, changed imports/strides/fetch programs, missing
streams, malformed formats, instance divisors, layout compatibility and
concurrent compiler creation. `run_heavy_benchmarks.py` alternates distinct
baseline/candidate binaries, verifies output and identical workload counts,
and records CPU/GPU median, P95/P99, throughput and memory samples separately.

Engineering references: [Cemu's minimal state and vertex-layout separation](https://github.com/cemu-project/Cemu/blob/main/src/Cafe/HW/Latte/Renderer/Vulkan/VulkanRendererCore.cpp),
[Dolphin's cached vertex loaders](https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/VideoCommon/VertexLoaderManager.cpp),
and [PCSX2's Vulkan state tracking](https://github.com/PCSX2/pcsx2/blob/master/pcsx2/GS/Renderers/Vulkan/GSDeviceVK.cpp).
Scene-level culling, sorting and indirect batching were not guessed from GX2
draws; the translator lacks the visibility and ordering proofs those require.

Command recording also publishes each draw's existing packets as one batch,
reducing cross-thread publication and wakeups. Nested scopes, direct operations
and queue-capacity pressure still publish/drain in order. A 500,001-command
fixture forces ring wrap, publication during an open batch and submission
inside nested scopes. Draw order, Vulkan commands and GPU submission policy
are unchanged. Legacy/synchronization2 timestamps and query resets now use the
same recording queue, allowing valid GPU timings with split recording enabled.
Initial timestamp probes bypassed that queue and were discarded after Vulkan
validation identified the test-harness race. Corrected baseline and candidate
runs are checked with Khronos synchronization validation.

## Plaza-scale draw path (2026-10-22)

The earlier heavy proxies call the draw helper directly, so they skip guest
program-key resolution and guest texture binds. The new authored `plaza` case
goes through `gx2_render_draw_indexed`: 1,664 draws per frame (shadow, opaque,
blended), 32 register-selected R700 program pairs of 1.5–3.3 KiB, alpha-test and
far-clip register changes, big-endian guest indices, per-draw uniforms and four
`gx2_render_bind_texture` calls per colour draw over 64 tile-mode-4 textures. The
owner's shader cache holds about 49,800 exact keys for about 2,400 SPIR-V modules,
so program and state combinations vary heavily between draws.

Changes (draw order, workload, shaders, caches and visuals are unchanged):

- The exact-key memo keeps 256 slots chosen by a hash of all key inputs and
  checks the previous draw's slot first. A hit still compares every input.
  Bytecode is compared byte for byte unless the page write generations
  (already trusted for index, vertex and uniform reuse) prove no write since
  the bytes were last compared. Untracked memory always compares.
- The SPI_PS_INPUT_CNTL clear no longer searches the register table per word
  (8% of main-thread time), key registers use one flat gather, and the legacy
  key's texture words are built only when that key is used.
- Per-program masks of live uniform banks and texture slots; sampler compare
  state is touched only when it differs.
- Pipeline and descriptor-set maps hash with the renderer's KeyHash instead of
  MSVC's byte-serial FNV; full-key equality is unchanged.
- An exact descriptor-bytes index maps a bind to its `tex_map` entry, using the
  per-slot cache's rule for every slot, instead of rebuilding the 33-word key
  and walking the tree.

Seven alternating runs of distinct baseline/candidate executables, identical
workloads and output checksums (`build/plaza-benchmark-results.json`):

| Synthetic CPU time per frame | RTX 4050 before → after | Intel UHD before → after |
| --- | --- | --- |
| `plaza` median | 3.920 → 1.345 ms | 4.117 → 1.523 ms |
| `plaza` P99 | 4.231 → 1.584 ms | 4.366 → 1.727 ms |
| `heavy` median | 3.052 → 2.225 ms | 3.753 → 2.893 ms |
| `heavy_push` median | 2.556 → 1.923 ms | 2.607 → 2.288 ms |
| `overdraw` median | 3.358 → 2.398 ms | 3.614 → 2.786 ms |

`plaza` throughput rose from 409k to 1.14M draws/s (RTX) and from 382k to 961k
draws/s (Intel). In `heavy`/`overdraw` the GPU time dominates (RTX 4.3/13.5 ms,
Intel 10.6/38.8 ms) and did not change, so their wall time is unchanged. These
are CPU translation-layer measurements, not game FPS. A cached SPSC ring tail was
reverted: it was not measurably faster.

`gambit_render_profile` (MSVC) is the same benchmark with an opt-in sampler:
`RBREW_BENCH_SAMPLE=1`, `RBREW_BENCH_SAMPLE_LINES=<function>`,
`RBREW_BENCH_SAMPLE_CALLERS=1`, `RBREW_BENCH_FRAMES=<n>`. Configure
`-DRBREW_GX2_DEBUG_INFO=ON` for renderer function and line names. All 45 tests
passed on both adapters, the render/streaming suite passed with serial recording,
and `render_plaza`, `heavy`, `heavy_push`, `contracts`, `lifetime` and `geometry`
passed Khronos synchronization validation on both. The game was not launched.

### Second draw-path pass and FPS overlay (2026-10-22)

Further changes, with draw order, workload and visuals unchanged:

- Closed draw batches are published to the recording thread in 16 KiB chunks
  rather than per draw. `drain()` still publishes everything before each
  submission, direct command or wait, so recorded commands are unchanged.
- The descriptor-set key is built in a stack buffer and looked up through a
  transparent `string_view` hash; only a new set's key is copied into the map.
- Vertex setup visits only the fetch plan's live streams, and the pipeline key
  buffer is no longer zero-filled before each draw.

Seven alternating runs against the original baseline executable, with
identical workloads and checksums (`build/plaza2-benchmark-results.json`):

| Synthetic CPU time per frame | RTX 4050 before → after | Intel UHD before → after |
| --- | --- | --- |
| `plaza` median / P99 | 3.847 → 1.194 / 4.116 → 1.434 ms | 4.080 → 1.287 / 4.884 → 1.610 ms |
| `heavy` median | 3.067 → 1.911 ms | 3.728 → 2.613 ms |
| `heavy_push` median | 2.578 → 1.698 ms | 2.514 → 2.131 ms |
| `overdraw` median | 3.301 → 2.056 ms | 3.484 → 2.534 ms |

`plaza` reaches 1.25M draws/s on the RTX 4050 and 943k on the Intel UHD. GPU time
in `heavy`/`overdraw` is unchanged, so their wall time is still GPU-bound. These
are CPU translation-layer measurements, not game FPS.

**FPS overlay.** Every presented frame shows FPS, average frame time and the
slowest frame interval of the last half second. These are measured at actual
swapchain presentation. The text is rasterised on the CPU with a 5×7 font and
copied into the top-left corner after the frame blit. It needs no shaders or
render passes and costs one small buffer-to-image copy per frame. Text is
scaled with window height. The overlay is shown by default, **F3** toggles
it, and `RBREW_FPS_OVERLAY=0` starts it hidden. Captured presents used by image
tests omit it. `render_overlay` checks text, statistics and glyph
rasterisation. `render_overlay_present` presents through a real hidden Vulkan
window on each adapter and reads back the swapchain image
(`docs/fps-overlay-example.png`). All 47 tests passed on both adapters, render
cases also passed with serial recording, and the validated render cases
(including `overlay_present`) passed synchronization validation. The game was
not launched.
