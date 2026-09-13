<p align="center">
  <img src="docs/logo.png" width="128" height="128" alt="Opossum Desktop logo">
</p>

# Opossum Desktop

A lightweight, native macOS GUI for [opossum](https://github.com/suruseas/opossum) — the
Docker-Compose-like orchestrator for Apple's `container` runtime. Think "Docker Desktop, but only
the parts that matter, and none of the always-on VM."

Menu bar + a normal window. No daemon of its own: it shells out to `container` and `opossum`,
reads their JSON output, and shows you what's running.

## Requirements

- macOS 26+ on Apple silicon
- [`container`](https://github.com/apple/container) and [`opossum`](https://github.com/suruseas/opossum) installed (e.g. via Homebrew)
- Xcode 26+ (Swift 6.2 toolchain) to build from source
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) to generate the Xcode project

## Building

```bash
make build   # regenerates OpossumDesktop.xcodeproj and builds Debug
make run     # build + launch
make test    # run the OpossumKit unit test suite (no Xcode project needed)
```

`OpossumDesktop.xcodeproj` is generated from [`project.yml`](project.yml) and is not checked in —
run `make gen` (or just open the project once `make build` has generated it) after editing
`project.yml`.

## Layout

- **`OpossumKit/`** — a plain SwiftPM package with all the logic: typed wrappers over the
  `container`/`opossum` CLIs, the polling `RuntimeStore`, stats sampling, log streaming, the
  project registry, secret masking, etc. Fully unit-tested (`OpossumKit/Tests`) against fixture
  JSON and a fake CLI shim — no real runtime needed to run `make test`.
- **`OpossumDesktop/`** — the SwiftUI app target: menu bar, main window, and all views.

## What it does (v1)

- **Menu bar**: runtime status, per-project quick start/stop, jump to the main window.
- **Projects**: register a folder with a compose file; up/down/restart/destroy with live streamed
  output and `[OPSM-NNN]` diagnostics called out; resolved config viewer.
- **Containers**: grouped by project, with logs (follow + boot log), inspect (env vars masked by
  default), live CPU/memory/network/disk charts, mounts, and exec-into-Terminal.
- **Images / Volumes / Networks**: list, delete, prune, pull.
- **Builder**: status, resize (cpus/memory).
- **Runtime**: start/stop the container system, disk usage, `opossum doctor` with fixes, system
  logs, launch-at-login, update check (against GitHub Releases — the app is unsigned, so updates
  go through Homebrew, not an in-app installer).

Deliberately left out (Docker Desktop has it; this doesn't need it): sign-in, extensions
marketplace, an AI assistant, Kubernetes, Testcontainers Cloud, and anything backed by an
always-running VM.

## How it talks to the runtime

Everything is read via `container ls -a --format json` / `image ls` / `volume ls` / `network ls`
on a poller (2s while a window is open, 10s in the background), sped up by an FSEvents watcher on
`~/Library/Application Support/com.apple.container` (container/volume/network create or destroy)
and a `launchctl list` diff (container start/stop of something that already exists — Apple's
runtime has no events API). Actions (`up`, `down`, `logs --follow`, …) run as subprocesses and
stream their output straight into the UI.

`opossum` itself only has `--format json` on `ls`/`volumes`/`doctor` today; `ps`/`stats`/`images`
are table-only, so the app derives that data from `container`'s JSON output plus the
`opossum.project` label instead. Adding those flags upstream is tracked as follow-up work.

## Security notes

- Container environment variables (which can contain real secrets) are masked by default anywhere
  they're shown, keyed off both variable name and value shape — see `OpossumKit/Sources/OpossumKit/Secrets/Masker.swift`.
- The app is unsigned and not sandboxed (it needs to spawn Homebrew binaries and open Terminal),
  distributed via a Homebrew cask rather than a notarized DMG for now.

## License

MIT — see [LICENSE](LICENSE).
