# Magpie iOS App

Native SwiftUI (iOS 15.0+) reverse-proxy client and local HTTP gateway (`127.0.0.1:3425`) supporting bidirectional translation across `/v1/chat/completions`, `/v1/responses`, `/v1/messages`, and `/v1beta/models/...`, alongside `/api/status`, `/api/config`, `/v1/models`, and `/api/logs`.

## Features
- Dark obsidian theme with custom amber/teal palette, custom geometric emblem & AppIcon, and custom non-plastic SwiftUI controls.
- Multi-profile reverse proxy manager with strict `http`/`https` URL validation, trailing-slash normalization, live connection status light, latency probe, and explicit failure diagnostics.
- Native `/v1/models` catalog, live gateway request logs, and bidirectional privacy masking engine.

## Build
Built via XcodeGen + `xcodebuild` on GitHub Actions (`xcode-27` runner, `iOS 15.0` deployment target) producing `Magpie-unsigned.ipa`.
