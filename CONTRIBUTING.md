# Contributing

This project is early. Small, focused changes are easiest to review.

Before opening a pull request, run:

```sh
swift build
swift test
swift run jocalhost-checks
```

Keep changes native and dependency-light:

- Prefer Swift standard library, Foundation, AppKit, and SwiftUI before adding dependencies.
- Keep UI changes consistent with the existing menu bar app.
- Do not commit generated build artifacts from `.build`, `dist`, or `dist.noindex`.
- Do not commit local config files or LAN tokens.
