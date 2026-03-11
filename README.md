# AmorphousDiskMark
A macOS storage benchmark tool that measures read/write performance in MB/s and IOPS. Inspired by [CrystalDiskMark](http://crystalmark.info/) for Windows.

[![Download on the Mac App Store](https://developer.apple.com/app-store/marketing/guidelines/images/badge-download-on-the-mac-app-store.svg)](https://apps.apple.com/app/amorphousdiskmark/id1168254295)

## Features
- **Sequential benchmarks:** 1 MiB block reads/writes, single-queue (QD=1) and multi-queue (QD up to 1024)
- **Random benchmarks:** 4 KiB block reads/writes, single-queue and multi-queue (QD up to 1024)
- **Flexible test parameters:** configurable iteration count, test data (random/zero), measurement size (16 MiB–64 GiB), interval (0 s–10 min), and duration limit
- **Dual units:** view results in MB/s or IOPS; tooltips show both
- **Copy-pasteable results:** export measurements as formatted plain text

## Example Output
```
Sequential Read 1MiB (QD=    8) :   832.04 MB/s [    793.5 IOPS]
Sequential Write 1MiB (QD=   8) :   773.81 MB/s [    738.0 IOPS]
    Sequential Read 1MiB (QD=1) :   667.96 MB/s [    637.0 IOPS]
   Sequential Write 1MiB (QD=1) :   576.30 MB/s [    549.6 IOPS]
     Random Read 4KiB (QD=  64) :   524.28 MB/s [ 127998.7 IOPS]
    Random Write 4KiB (QD=  64) :   192.25 MB/s [  46935.0 IOPS]
        Random Read 4KiB (QD=1) :    31.70 MB/s [   7738.3 IOPS]
       Random Write 4KiB (QD=1) :   200.17 MB/s [  48868.8 IOPS]
```

## Requirements
- macOS 10.9.5 or later
- Xcode (to build from source)

## Building
Open `AmorphousDiskMark/AmorphousDiskMark.xcodeproj` in Xcode and build the scheme. The app is sandboxed and requests user-selected file read/write access for target volume selection.

## Architecture
The codebase is Objective-C, structured around a few key components:

| File | Role |
|---|---|
| `AppDelegate` | Main UI controller — handles toolbar actions, volume selection, test orchestration |
| `DiskMark` | Core benchmark engine — manages threaded I/O with configurable block size, queue depth, and duration |
| `DiskUtil` | Volume enumeration via DiskArbitration framework, mount/unmount observation, filesystem metadata |
| `DMTextView` | Custom text view with logarithmic bar graph rendering (matching CrystalDiskMark's visual style) |
| `DMButton` / `DMButtonCell` | Custom button with dark mode support |
| `DMMediaIcon` | Resolves storage device icons from IOKit kernel extension bundles |
| `LinkTextField` | Clickable URL text field |

### How benchmarking works
AmorphousDiskMark spawns threads to perform I/O against a temporary file on the target volume. The design mirrors CrystalDiskMark's use of Microsoft's `diskspd` parameters — block size, queue depth, thread count, duration, and warmup — adapted for macOS. Queue depth is implemented via concurrent threads (up to the macOS per-task limit of 2048) rather than POSIX AIO, which only supports 16 queues on macOS.

## Usage
1. Select a target volume from the dropdown.
2. Click **All** (or an individual test button).
3. When finished, press ⌘S to save a screenshot, or copy the plain-text results.

> **Note:** Avoid running write benchmarks more than necessary — repeated writes can reduce the lifespan of flash storage.

## License
MIT License. See [LICENSE](LICENSE) for details.

UI design used with permission from the author of CrystalDiskMark.

## Links
- [Katsura Shareware](https://katsurashareware.com/)
- [CrystalDiskMark](http://crystalmark.info/)
