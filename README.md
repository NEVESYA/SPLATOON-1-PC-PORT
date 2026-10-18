# Splatoon 1 PC Port

An unofficial native Windows port of **Splatoon (Wii U)**, made by statically recompiling the game's code into a Windows program, with a Vulkan renderer.

> **This project contains no Nintendo code, assets or game files.** You need your own copy of the game, dumped from your own Wii U. The setup builds the port on your PC from your files.

> ⚠️ **Work in progress.** Expect graphical glitches, missing effects, stutter and crashes. You need **strong hardware** (see below). If something goes wrong, please [open an issue](https://github.com/NEVESYA/SPLATOON-1-PC-PORT/issues). Include your PC specs and the text from the setup window or a screenshot.

---

## Requirements

- **Windows 10 or 11, 64-bit**
- **GPU with Vulkan 1.3** and an up-to-date driver (developed on an RTX 5060 Ti; a modern NVIDIA or AMD GPU is recommended)
- **CPU:** modern 6–8 cores or more · **RAM:** 16 GB minimum, 32 GB recommended (building the game uses a lot of memory)
- **Disk:** about 40 GB free during setup
- **Your own game dump:** Splatoon **EUR (AGMP01) with update v16**, with the folders `code`, `content` and `meta` (for example made with *Dumpling* on your Wii U). Other regions and versions are not supported yet.

## Installation (simple)

1. Click **Code → Download ZIP** on this page and extract it to a short path, for example `C:\SplatoonPort`.
2. Double-click **`Setup.bat`**.
   - If Visual Studio Build Tools, Python 3.12 or Git are missing, the setup offers to install them for you. Afterwards, close the window and run `Setup.bat` again.
3. When asked, select your **Splatoon dump folder** (the one containing `code`, `content` and `meta`). **The dump folder can have any name**; spaces and brackets such as `Splatoon [AGMP01]` are supported. Select the parent folder, rather than `code` or `content` inside it. Setup creates the Wii U folders automatically; there is no system-folder selection.
4. Wait. The first setup takes **30–90 minutes**: it builds the tools, recompiles your game and downloads the shader cache (about 820 MB).
5. Play: **`Game\Splatoon.exe`** (the setup can also create a desktop shortcut).

Setup creates the Wii U `mlc01` directory layout and the port's empty save folders automatically, like Cemu's initial setup. It uses existing local system fonts when available, or downloads Cemu's open-source Noto replacement fonts automatically (about 26 MB, with pinned checksums and their SIL OFL license). It never imports game saves, Mii save databases or console accounts. A fresh installation starts with no progress, and the game creates its save while you play.

Existing Mii graphics resources are detected automatically beside your game dump/repository, in `wiiu-system/mlc`, or in Cemu's default/configured MLC. These are optional to setup: missing resources produce a warning and may affect Mii graphics. Setup does not generate or download Nintendo's Mii graphics. Developers can optionally use `-Mlc "D:\My system dump"` to add a resource location; players are never prompted for it.

**Updating:** download the new version, then run `Setup.bat` again. Your save (`Game\save`) and shader cache are kept.

Options: `Setup.bat -SkipShaders` skips the shader download, `-Clean` rebuilds everything, and `-Output D:\Splatoon` picks a different game folder.

You can also pass folders directly, with quotes around paths that contain spaces:

```bat
Setup.bat -GameDump "D:\My Wii U games\Splatoon [AGMP01]"
```

## Controls

Controllers (Xbox, PlayStation or any SDL2 controller): buttons are mapped by position, like on the Wii U GamePad. The right stick controls the camera.

The tutorial keeps its original camera behavior, controlled with the **right stick or mouse**. Outside the tutorial, including the plaza, the port applies **motion controls off** and **neutral camera sensitivity (0)** automatically. It saves only those two preferences and the updated checksum; progress, character data, camera inversion and other settings are preserved. The first edited save is backed up as `save.dat.before-control-defaults`. A new save is still created by the game normally.

Keyboard and mouse:

| Input | Action |
|---|---|
| W A S D | Move |
| Mouse | Aim / camera |
| Left click | Shoot (ZR) |
| Right click | Squid form (ZL) |
| Space | Jump (B) |
| Q | Sub weapon |
| E | Special |
| F | Map (+) |
| G | Options (−) |
| Esc | Home |
| Tab | GamePad view (the mouse becomes the touch screen) |

## Why this project is legal

This project follows the same approach as other recompilation and decompilation projects:

- **No Nintendo material is in this repository.** There is no game code, no generated code, no textures, models, sounds, fonts, keys or firmware. It contains only original source code (the recompiler and the runtime) and open-source libraries under their own licenses (see `LICENSES/`).
- **You supply the game.** The port only works with a copy that you dumped yourself from a console and a game you own. The setup refuses unknown files.
- **The conversion happens on your own PC.** The recompiled code is created locally from your dump and is never uploaded or shared by this project.
- **Interoperability.** The runtime re-implements the Wii U system services (Cafe OS) in original code, so your game runs on Windows. This is the same kind of interoperability work that emulators like Cemu do.

Do not share your game files or the generated `build` folder. This explanation is not legal advice, and laws differ between countries. Only use games you legally own.

The optional shader cache download only speeds up the first play. It is hosted separately from this repository, and you can skip it with `-SkipShaders`; the game then builds its own.

## How the port works

1. **Static recompilation (RebrewU).** The recompiler loads `Gambit.rpx`, the game's PowerPC executable. It discovers functions using the RPX and the supported version's checked boundary-address profile in `profiles/`, builds control-flow graphs, and translates PowerPC instructions into equivalent C++. The profile contains addresses, not game code. Setup checks that the supported function table is complete before building. The result is about 200 C++ files that the Microsoft C++ compiler builds into a native x64 program. No emulator CPU runs at play time.
2. **Native Cafe OS runtime.** The game calls Wii U system libraries (coreinit, GX2, VPAD, sound and others). The runtime (`recompiler/port/os`) provides those functions natively: memory, threads, files (reading your `content` folder), saves, input through SDL2, and audio through miniaudio.
3. **GX2 → Vulkan renderer.** The game's GPU commands are replayed on a dedicated render thread. Latte (Wii U GPU) shaders are translated to GLSL by a decompiler adapted from Cemu, then compiled to SPIR-V with glslang. Textures are detiled and uploaded, and render targets map to Vulkan images.
4. **Performance work in this version:**
   - asynchronous render thread and display-list recording;
   - asynchronous shader and pipeline compilation with a persistent shader cache and boot warm-up;
   - texture, vertex, index and uniform caches that use OS write tracking instead of re-hashing every frame;
   - shader-key memoisation;
   - fixes for stale vertex layouts after level changes, 17-input vertex shaders, instance step rates, and out-of-bounds packed vertex attributes.
5. **Shader cache.** `Game\vulkan_cache` stores translated shaders so they don't have to be rebuilt during play.

## Credits and licenses

Built with RebrewU (static recompiler), a Latte shader decompiler adapted from [Cemu](https://github.com/cemu-project/Cemu) (MPL-2.0), SDL2, glslang, volk, Vulkan-Headers, zlib, curl, miniaudio and nlohmann/json. Automatic replacement fonts are Noto Sans JP/SC/KR/TC Medium by Adobe, distributed with Cemu under SIL OFL 1.1. License texts are in `LICENSES/` and next to their sources.

*Splatoon is a trademark of Nintendo. This project is not affiliated with or endorsed by Nintendo.*
