# Localization Brief — Catty Package

This document is a handoff to whichever agent picks up Catty's localization. The parent app (Local AI Chat) is going through localization Phase 2; Catty is in scope but explicitly out of the parent app's team scope because Catty is a separate package with its own ownership.

## Approach (decided upstream)

Keep Catty as a **self-contained, externally-localized SPM package**. Translations live inside this repo, ship as a package resource, and resolve via `Bundle.module` automatically when SPM consumes the package. The parent app gets translated Catty UI for free — no parent-app code changes needed.

## Mechanics

1. Add `defaultLocalization: "en"` to `Package.swift` (top of the `Package(...)` init).
2. Configure the `Catty` library target to ship resources:
   ```swift
   .target(
       name: "Catty",
       dependencies: [...],
       resources: [.process("Resources")]
   )
   ```
3. Create `Sources/Catty/Resources/Localizable.xcstrings` (use Xcode 15+ String Catalog format).
4. Enable Xcode auto-extraction by ensuring the build setting `SWIFT_EMIT_LOC_STRINGS = YES` is on for the package target (already on for parent app; verify here).
5. Build the package once in Xcode → auto-extraction populates the String Catalog with the ~15 existing `Text("...")` literals.
6. Translate per the locale list below.

## Target locales

Match parent app (Local AI Chat). 10 total + English source:

| Locale | Code | Notes |
|---|---|---|
| Spanish (Spain) | es-ES | |
| Spanish (Latin America) | es-419 | |
| Portuguese (Portugal) | pt-PT | |
| Portuguese (Brazil) | pt-BR | |
| French | fr | |
| German | de | |
| Italian | it | |
| Dutch | nl | |
| Simplified Chinese | zh-Hans | |
| Japanese | ja | |

## Translation method

Use Apple's automatic translation in Xcode 16+ as the first pass, then human review. Parent app is taking the same approach (driven by a team of agents). Fastest path; quality is good enough for a first ship.

## DNT (Don't Translate) strings

Per the parent app's Phase 1 audit, the following Catty-internal strings stay English in every locale. Mark them as **Don't Translate** in the String Catalog:

- "Catty 3D" — the product name (renamed from "Catty" — the App Store
  record was taken; "Catty 3D" is the public name. Treat any remaining
  bare "Catty" string as DNT too — the Swift package, target, and
  source comments still use it.)
- "Maxwell" — the cat character (internet-meme reference)
- "Ratty" — inspirational tool name (homage)
- "SSH" — protocol acronym

Other strings inside Catty (~15 total) are translatable:
- "No sessions yet"
- "Open a local terminal or connect via SSH to get started."
- "Inspired by Ratty" — translatable preamble; "Ratty" itself stays English
- "Layout %@ not yet implemented — showing active session only" — preserve the `%@` interpolation slot

## TRANSCREATE candidates

The "Inspired by Ratty" attribution block is light marketing copy — translators should adapt for tone rather than translate literally.

## Anti-patterns audit (from parent app review)

Quick scan of Catty source: nothing blocking. Existing `Text("...")` calls are clean, no `String`-typed view-helper params, no enum-rawValue rendered as Text. The package is in good shape for direct String Catalog auto-extraction.

The debug overlays (`OrbitDebugSliders.swift`, `OrbitDebugMinimap.swift`)
are also in scope and should be auto-extracted. Strings to translate:
"Radius", "Speed", "Maxwell phase", "Maxwell spin", "Maxwell scale",
"Rat scale", "Terminal alpha", "Terminal". The Maxwell-prefixed ones
preserve "Maxwell" as DNT — translate only the trailing word
("phase" → translated, "Maxwell" stays English). Same rule for
"Rat scale" — "Rat" is part of the Ratty homage and stays English.

## Validation

After adding the String Catalog and translating, build the parent app (Local AI Chat) against this branch and verify:
- Catty UI surfaces (Terminal3D scene view, session history, multi-session view) render translated copy in each target locale
- DNT items (Catty, Maxwell, Ratty, SSH) remain English in every locale
- The `%@` interpolation slot in the "Layout not yet implemented" string still works

## Related context

- Parent app Phase 1 report (annotated source + decisions): `/Users/timapple/Documents/Github/Local-AI-Chat/.claude/worktrees/i18n-context-comments/LOCALIZATION_PHASE1_REPORT.md`
- Parent app SPEC (Phase 1 annotation conventions): `/Users/timapple/Documents/Github/Local-AI-Chat/.claude/worktrees/i18n-context-comments/SPEC.md`

---

Created: 2026-05-15
