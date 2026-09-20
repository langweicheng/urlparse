# URL Parser

<img src="assets/AppIcon.png" width="96" alt="URL Parser icon">

English | [简体中文](README.md)

A native macOS URL parameter editor for development and debugging. Edit a URL on the left or its decoded query JSON on the right; both stay in sync. Built with Swift and AppKit, with no third-party dependencies or WebView. All processing happens locally, with no network requests.

## Features

- **Two-way editing**: paste a URL to see formatted JSON; edit the JSON to update the URL. Incomplete or invalid JSON shows an error and keeps the last valid URL.
- **Quick key/value actions**: click a key to select its name and highlight the matching key/value pair. Right-click to copy or delete a key or value. Deleting a key removes the parameter; deleting a value replaces it with an empty string.
- **Native editing shortcuts**: copy, paste, cut, select all, undo, and redo. Undo and redo restore both editors together.
- **Split view and colors**: starts at 50:50 and remembers your divider position. JSON uses IDEA Light colors.
- **Offline QR codes**: generate a QR code for the current URL with one click. URLs exceeding QR capacity show an error.
- **Parameter preservation**: supports custom URL schemes, repeated parameters, empty values, and parameters without an equals sign. Unchanged parameters retain their original encoding and order.

Values remain strings to preserve large integers, leading zeros, and boolean text. Repeated parameters use arrays; parameters without an equals sign use `null`:

```json
{
  "city": "北京",
  "id": "00123",
  "tag": ["a", "b"],
  "empty": "",
  "flag": null
}
```

Here, `tag` represents `tag=a&tag=b`, `empty` represents `empty=`, and `flag` represents a bare `flag`. Percent encoding is decoded once, `+` remains a plus sign, and embedded JSON stays a string. URL content is kept only for the current session; copy anything you need before quitting.

## Performance

- The v1.0.0 universal download is approximately **1.46 MiB**, including Apple Silicon and Intel binaries and the app icon.
- Parsing and formatting **1,000 parameters took approximately 3 ms** in a local debug build, excluding text rendering.
- Uses native text components and delta-based undo records, keeping up to 100 undo groups. QR codes are generated on demand, and related resources are released when closed.

The following measurements were taken during memory optimization on an Apple Silicon Mac running macOS 26.5.2, using Release builds. Each scenario was sampled after 2 seconds, across two independent process runs.

| Scenario | Before optimization | After optimization |
| --- | ---: | ---: |
| Empty launch | 25.1–25.7 MiB | 31.4–31.7 MiB |
| 1,000 parameters | 148.3–156.3 MiB | 41.4–42.5 MiB |
| Followed by 100 edits | 167.8–169.8 MiB | 46.0–47.0 MiB |
| Switch to a short URL and open QR code | 53.1–53.7 MiB | 50.7–50.8 MiB |

These figures use `TASK_VM_INFO.phys_footprint`, not RSS, and are not memory limits. Physical memory fell by about 73% in the long-document scenario; empty-launch memory did not decrease. Usage varies with input, window size, and system caches. These measurements document the optimization work, rather than a full benchmark of the final release package.

[Raw results before optimization](docs/memory-before.txt) · [Raw results after optimization](docs/memory-after.txt). Run `./scripts/measure-memory.sh` to repeat the measurements.

## Installation

1. Download `URL-Parser-1.0.0-macOS-universal.zip` from [GitHub Releases](https://github.com/langweicheng/urlparse/releases/latest).
2. Unzip it and drag `URL Parser.app` into **Applications**.
3. Open URL Parser from Applications.

Requires **macOS 13 or later**. The same package supports Apple Silicon and Intel. The Intel build has been compiled but has not been tested on Intel hardware.

The app is ad-hoc signed and has no Apple Developer ID signature or notarization. If macOS blocks the first launch, verify the source, then choose **Open Anyway** in **System Settings → Privacy & Security**. The release page includes a SHA-256 checksum; compare it with the output of `shasum -a 256 <path-to-downloaded-zip>`.

### Build from source

Install Xcode or command line tools that include Swift, then run these commands from the project root:

```sh
./scripts/build-app.sh
open 'dist/URL Parser.app'
```

The default build targets your Mac’s architecture. Run `./scripts/package-release.sh` to create the universal app, ZIP, and checksum file, or `swift test` to run the tests. You can also open `Package.swift` in Xcode.
