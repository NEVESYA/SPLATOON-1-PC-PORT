# Vulkan GPU memory

The renderer uses the memory heaps and types advertised by the selected Vulkan
driver. `DEVICE_LOCAL` means efficient GPU access; it does not mean dedicated
VRAM. Integrated GPUs can expose system RAM as a single device-local heap.
Discrete GPUs can expose additional GPU-accessible system-memory types, including
types that the CPU cannot map. Physical heap sizes describe capacity, not current
residency or a guarantee that every allocation will succeed.

## Allocation policy

- Every allocation respects the resource's `memoryTypeBits`. GPU-only images and
  buffers prefer device-local types, then try other compatible types if allocation
  fails. No staging requirement or host-visibility requirement excludes an otherwise
  compatible system-memory type.
- Direct CPU uploads require host visibility, prefer device-local access, and
  prefer host coherence among otherwise equivalent types. There is no BAR/heap-size
  cutoff. A small host-visible local heap can fall back to another compatible type
  when the driver refuses an allocation.
- Readbacks require host visibility and prefer CPU-cached types, with coherence
  preferred among equivalent types. Non-coherent cached memory is supported.
- Lazy, protected and AMD device-coherent types are excluded because the renderer
  does not enable the resource/device features required to use them.
- GPU-only allocations are not mapped. Mapped and unmapped pools are separate;
  linear buffers and optimal-tiled images remain in separate blocks to satisfy
  `bufferImageGranularity`.
- Existing suballocation blocks are reused first within each preferred type.
  If a new block fails, the allocator tries the resource's exact size in that
  type before falling back to slower memory. Mapping failures also permit
  fallback; unrelated failures such as device loss terminate the attempt.
- Buffer/image requirements are queried with the Vulkan 1.1 requirements API.
  Driver-required or preferred dedicated allocations carry the associated
  buffer/image in `VkMemoryDedicatedAllocateInfo`.

Memory placement remains a driver-supported choice. The port does not invent a
shared-memory heap, reserve a fraction of installed RAM, force healthy GPU-local
allocations into system memory, or control the driver's paging/residency policy.
No cache capacity, upload chunk size, dedicated threshold, eviction policy,
resolution or graphical setting was reduced by this change.

## Transfers and synchronization

Geometry, indices and uniforms retain their direct mapped-buffer paths and cached
uploads. No extra staging copy or duplicate GPU resource was introduced. Texture
uploads retain optimal-tiled images and buffer-to-image transfers; host visibility
alone does not make an optimal-tiled image a linear CPU-writable texture.

Non-coherent suballocations and ring spans are isolated to
`nonCoherentAtomSize` boundaries so flushing one cannot race a neighbouring
in-flight allocation. Ring writes are collected and adjacent ranges merged, then
flushed together before submission. Direct buffer writes flush after writing.
GPU readbacks invalidate after the existing GPU-to-host barrier and completion
wait. Coherent types avoid flush/invalidate driver calls entirely. No per-frame
GPU wait, memory-budget query, resource migration or cache sweep was added.

`memory_usage()` counts application allocations by memory properties. Local
allocations include UMA RAM and host-visible local memory; they are not a report
of dedicated VRAM usage or driver residency.

## Verification

Configure `-DRBREW_BUILD_TESTS=ON`, build the Release test targets, and run CTest.
`gambit_memory_tests` adds policy, allocator and transfer checks, including serial
command recording. Tests use synthetic resources without loading the game or its
saves. Fault injection rejects allocations rather than exhausting the system.

Verified locally on 20 October 2026:

- NVIDIA GeForce RTX 4050 Laptop GPU: two heaps, five types. Injected failures of
  both local types recover onto the driver's non-mappable system-memory type.
  An optimal image allocated there passes binding, GPU clear and exact readback.
  All three mapped types pass byte-for-byte buffer transfers. Subsequent normal
  image allocation still selects device-local memory.
- Intel UHD Graphics: one shared 8,043 MiB heap, three device-local types, no
  dedicated VRAM heap. Both mapped types pass exact buffer transfers. Optimal
  images and repeated ring-to-texture uploads pass exact readback checks.
- Synthetic policies cover a single UMA type, a small mapped local heap, resource
  compatibility masks, non-local/non-mappable fallback and non-coherent types.
  Injected allocator tests cover failed blocks, exact-size recovery, failed maps,
  all-types failure, accounting and device-loss handling. Captured flush/invalidate
  calls verify atom alignment, dedicated tails and the coherent fast path.
- All 15 pre-existing tests passed before the change. The expanded 19-test suite
  passes on both GPUs, including display-resolution rendering, texture reuse,
  upload residency and split/serial recording.

Neither installed driver exposes non-coherent host-visible memory; those paths
are checked through synthetic policies and captured synchronization calls.
Khronos validation layers are unavailable locally. These automated tests do not
establish gameplay FPS, frame-time distributions or behavior on every driver.

Local evidence: `build/shared-memory-baseline-tests.log`,
`build/shared-memory-nvidia-tests.log`, `build/shared-memory-intel-tests.log`.

The policy follows the [Khronos memory allocation guide](https://docs.vulkan.org/guide/latest/memory_allocation.html),
[mapped-memory flush requirements](https://docs.vulkan.org/refpages/latest/refpages/source/vkFlushMappedMemoryRanges.html)
and [dedicated allocation requirements](https://docs.vulkan.org/refpages/latest/refpages/source/VkMemoryDedicatedRequirements.html).
