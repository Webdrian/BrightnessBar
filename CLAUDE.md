# BrightnessBar

Projektanweisungen für Claude Code. Darüber gilt `~/Webdrian - Projekte/CLAUDE.md`.

## Eckdaten

| | |
|---|---|
| Typ | macOS-Menüleisten-App (`LSUIElement`), Open Source |
| Ziel | macOS 14+, Apple Silicon (`-target arm64-apple-macos14.0`) |
| Bau | `./build.sh` mit `swiftc`, ohne Xcode-Projekt |
| Repository | https://github.com/Webdrian/BrightnessBar (öffentlich) |
| Server | keiner — kein Deployment |

Öffentliches Repository: keine Pfade, Namen oder Zugangsdaten aus anderen
Projekten in Code, Commits oder Screenshots.

## BAMA (seit 18.11.2026)

Das Plugin `bama` ist für dieses Projekt eingeschaltet (`.claude/settings.json`).
Allgemeine Regeln im Wiki: `content/wikinext/06-werkzeugwahl/04-mac-apps-mit-bama.mdx`.
Für BrightnessBar gilt dazu:

- **Ziel bleibt macOS 14.** BAMA rechnet mit macOS 26 und Swift 6.2. Liquid
  Glass und neuere APIs nur hinter `if #available(macOS 26, *)` mit Rückfall,
  `LSMinimumSystemVersion` und `-target` nicht nebenbei anheben.
- **`build.sh` bleibt.** Nicht auf das Swift-Paket aus `new-mac-app` umbauen —
  die feste Signatur in `build.sh` hält die Bedienungshilfen-Freigabe über
  Neubauten hinweg.
- **Kein `agent-cli`.** Die App steuert Monitore über DDC; ein Socket, über den
  andere Prozesse das auslösen, wäre Angriffsfläche ohne Nutzen.
- Brauchbar hier: `os-integrations` (Hotkeys, Menüleiste, Rechte),
  `mac-design`, `ux-design`, `swift-swiftui`, `performance`, `app-icon`.
