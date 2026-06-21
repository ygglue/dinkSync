---
name: dinksync-ui
description: Use when building, styling, or restyling any Flutter UI in the dinkSync app — new screens, widgets, theme edits, or matching a Stitch mockup. Covers the court-green "Rounded" design system: color tokens (light + dark), Plus Jakarta Sans + Inter fonts, 24px rounded shape language, and component recipes (pill toggle, filled/outlined buttons, tonal inputs, stat chips, info/RLS cards).
---

# dinkSync UI

## Overview

dinkSync uses one design system — **"Clean & Minimal, Rounded"**: court-green
(`#2E7D32`) as a *sparing* accent on soft, near-white (or near-black) surfaces,
**Plus Jakarta Sans** headlines + **Inter** body, generous whitespace, and a
**24px rounded** shape language. Color carries meaning; layout carries the rest.

Source of truth: the Stitch project `dinkSync` (screens "… - Rounded" and their
dark variants) and the shipped theme in [theme.dart](../../../app/lib/app/theme.dart).

**The golden rule for Flutter: drive every color from `Theme.of(context).colorScheme`,
not hardcoded hex.** Both light and dark are generated from the single seed
`#2E7D32`, so colorScheme-based widgets adapt to dark mode for free. The token
tables below are ground truth for *what the scheme resolves to* — use them to
verify, not to hardcode.

## When to use

- Building a new screen or reusable widget (Phase 1 owner/staff/admin/player screens)
- Restyling an existing screen, or translating a Stitch mockup into Flutter
- Editing `theme.dart` or any color/font/radius/spacing decision
- Anytime you're tempted to pick a color, radius, or font by feel

## Color tokens (ground truth)

Verify your `colorScheme` output against these; don't paste hex into widgets.

| Role | Light | Dark | colorScheme getter |
|---|---|---|---|
| Background / surface | `#F9FAFB` | `#131313` | `surface` |
| Tonal input fill | `#F1F5F9` | `#1C1B1B` | `surfaceContainerLow`* |
| Track / secondary fill | `#E2E8F0`–`#F1F5F9` | `#2A2A2A` | `surfaceContainerHigh` |
| Hover / card fill | — | `#353534` | `surfaceContainerHighest` |
| Border / divider | `#E2E8F0` | `#40493D` | `outlineVariant` |
| Body text | `#0F172A` | `#E5E2E1` | `onSurface` |
| Muted text / idle icon | `#64748B` | `#BFCABA` | `onSurfaceVariant` |
| **Accent** (links, focus, key icons, headline) | `#2E7D32` | `#88D982` | `primary` |
| **Brand button fill** (see note) | `#2E7D32` | `#2E7D32` | `kBrandGreen` constant |
| Error | M3 error | `#FFB4AB` | `error` |

\* Flutter's default filled-input fill is `surfaceContainerHighest`; set
`fillColor` explicitly if you want the lighter `surfaceContainerLow` look.

**The one deliberate exception — primary buttons stay deep green in BOTH modes.**
In dark mode `colorScheme.primary` is the *pale* green `#88D982`; a pale filled
button looks wrong. Stitch's dark variant fills the primary button with the deep
`#2E7D32` (= `primaryContainer`) + white text. So: filled CTAs and the selected
toggle segment use a fixed `kBrandGreen = Color(0xFF2E7D32)` with white text,
not `colorScheme.primary`. Everything else uses the scheme.

## Typography

- **Headlines/titles:** Plus Jakarta Sans, w600–w700, letter-spacing ~`-0.2`.
- **Body/labels:** Inter, w400–w600.
- Applied centrally via `google_fonts` in [theme.dart](../../../app/lib/app/theme.dart)
  (`_textTheme`). Use `theme.textTheme.*` styles — don't call `GoogleFonts` in screens.
- Hierarchy comes from size/weight, not color.
- (A stray Stitch dark export used Lexend; ignore it — Plus Jakarta Sans is canonical.)

## Shape & spacing

- **Rounded = 24px** (`rounded-3xl`) on inputs, buttons, cards, logo tile, toggle.
  Use a single constant: `const kRadius = 24.0;`.
- **Pills are fully round:** segmented toggle, stat chips, avatar (`StadiumBorder` /
  `BorderRadius.circular(999)` / `CircleBorder`).
- Controls are tall: inputs ~56px, primary/secondary buttons ≥48px, full-width.
- Vertical rhythm: ~24–28px between sections, ~14px between stacked fields.

## Component recipes

Reuse the implementations already in the codebase rather than reinventing:

| Component | Recipe / where it lives |
|---|---|
| **Scaffold** | `scaffoldBackgroundColor: colorScheme.surface`; flat `AppBar` with transparent surfaceTint, title in `primary` bold. See [theme.dart](../../../app/lib/app/theme.dart). |
| **Brand header** | Paddle `Icon` in a `primary`-at-10% rounded-24 tile → "dinkSync" `headlineMedium` bold `primary` → tagline `bodyMedium` `onSurfaceVariant`. See [auth_screen.dart](../../../app/lib/features/auth/auth_screen.dart). |
| **Pill toggle** | `_PillToggle` in [auth_screen.dart](../../../app/lib/features/auth/auth_screen.dart): neutral track, selected segment filled `kBrandGreen` + white, `AnimatedContainer`. |
| **Tonal input** | `InputDecoration` filled, leading icon, floating label, rounded-24, no border in light / `outlineVariant` border in dark, `primary` focus. Themed once in `inputDecorationTheme`. |
| **Primary button** | `FilledButton`, full-width, ≥48px, rounded-24, `kBrandGreen` bg + white, Plus Jakarta w600. |
| **Secondary button** | `OutlinedButton`(`.icon`), full-width, `outlineVariant` border, `onSurface` text. Used for "Continue with Google" / "Sign out". |
| **Google button** | `OutlinedButton.icon` with `_GoogleLogo` ("G" in `#4285F4`) in [auth_screen.dart](../../../app/lib/features/auth/auth_screen.dart). |
| **OR divider** | `_OrDivider` in [auth_screen.dart](../../../app/lib/features/auth/auth_screen.dart). |
| **Stat / role chip** | `_StatChip` in [profile_screen.dart](../../../app/lib/features/profile/profile_screen.dart): fully-round pill, green-tinted or neutral, icon + label. |
| **Avatar** | Circle `primary`-at-10%, initial in `primary`, optional green edit badge. See [profile_screen.dart](../../../app/lib/features/profile/profile_screen.dart). |
| **Info / RLS card** | Tonal `surfaceContainerHighest` fill, rounded-24, small icon tile + uppercase label + `bodySmall` body. See [profile_screen.dart](../../../app/lib/features/profile/profile_screen.dart). |

## Common mistakes

- **Hardcoding hex in a widget.** Use `colorScheme.*` so dark mode works. The
  only literal color allowed is `kBrandGreen` for filled CTAs / selected segments.
- **Using `colorScheme.primary` for a filled button.** It goes pale in dark —
  use `kBrandGreen` + white text instead.
- **`withOpacity` (deprecated).** Use `color.withValues(alpha: 0.1)`.
- **Wrong radius.** Rounded system = 24px for boxes; chips/avatar/toggle = fully round.
- **Flooding green.** It's an accent — buttons, active states, key icons only;
  never large background fills.
- **Calling `GoogleFonts` in a screen.** Fonts are set once in the theme.
- **Dropping `kDebugMode` gating** when copying the auth screen's dev-login panel.

## After any UI change

Run `flutter analyze` (clean) and `flutter test` (green) before claiming done.
If you can, have the human run `flutter run -d chrome` and check overflow,
contrast, and dark mode — you can't see rendered pixels; they can.
