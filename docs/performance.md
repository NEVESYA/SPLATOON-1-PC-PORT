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
