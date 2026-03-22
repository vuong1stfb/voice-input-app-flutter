# Design System — Voice Input

## Product Context
- **What this is:** A Windows-first tray utility that lets people hold a hotkey, speak, and type directly into the currently focused text field.
- **Who it's for:** Mainstream Windows users who type often, especially chat-heavy and AI-heavy users who care about speed and staying in flow.
- **Space/industry:** Desktop productivity utility, dictation input, lightweight paid software.
- **Project type:** Windows desktop app with a settings surface, tray behavior, and trust-first utility UX.

## Aesthetic Direction
- **Direction:** Warm Utility
- **Decoration level:** Intentional
- **Mood:** Calm, capable, and premium in a small-software way. It should feel like a well-made writing instrument, not a dashboard, dev console, or enterprise settings portal.
- **Reference sites:** Internal product framing from office-hours and implementation spec. No external visual research was used for this first pass.

## Visual Thesis
This app wins when it disappears into the user's workflow. The UI should therefore feel:
- trustworthy, not flashy
- fast, not busy
- warm, not sterile
- specific, not interchangeable

The core visual move is to replace “SaaS dashboard” language with “desktop instrument” language:
- paper-warm surfaces instead of pure white app chrome
- ink-dark typography instead of generic gray UI
- one brass accent for action and identity
- monospaced hotkey chips and diagnostics for precision
- fewer rounded blobs, more deliberate geometry

## Typography
- **Display/Hero:** `Fraunces` — used sparingly for the main app title, onboarding headline, and occasional trust copy. It gives the product a face without turning the app into editorial theater.
- **Body:** `Instrument Sans` — the main workhorse for labels, descriptions, toggles, and form controls. It is readable, modern, and less generic than common SaaS defaults.
- **UI/Labels:** `Instrument Sans` semi-bold — settings labels, section titles, inline hints.
- **Data/Tables:** `IBM Plex Mono` — hotkey chips, diagnostics, transcript metadata, technical values. Use tabular figures when available.
- **Code:** `IBM Plex Mono`
- **Loading:** Prefer self-hosted font assets for the app. Google Fonts is acceptable for the preview page only.
- **Scale:**
  - Display XL: 40px / 1.05 / 700
  - Display L: 30px / 1.1 / 650
  - Heading 1: 24px / 1.2 / 700
  - Heading 2: 20px / 1.25 / 700
  - Heading 3: 16px / 1.3 / 700
  - Body L: 16px / 1.5 / 450
  - Body M: 14px / 1.45 / 450
  - Label: 13px / 1.3 / 600
  - Micro: 12px / 1.3 / 500

## Color
- **Approach:** Restrained with one distinctive accent
- **Primary:** `#C7772B` — brass orange; used for key actions, active highlights, and small brand moments
- **Secondary:** `#245C4E` — deep green; used for healthy, ready, and calm states
- **Neutrals:**
  - `#FCFAF6` — paper
  - `#F3EEE5` — warm canvas
  - `#E2D8C8` — soft border
  - `#B4A897` — muted divider
  - `#6B6A63` — secondary copy
  - `#20211E` — ink
- **Semantic:**
  - success `#2F6B59`
  - warning `#B86A1F`
  - error `#9B3E2C`
  - info `#2F5D7C`
- **Dark mode:** In dark mode, shift surfaces to ink-charcoal rather than pure black, reduce accent saturation by 10-15%, and preserve the warm paper/brass relationship with darker neutrals.

## Spacing
- **Base unit:** 4px
- **Density:** Comfortable-compact
- **Scale:** 2xs(4) xs(8) sm(12) md(16) lg(24) xl(32) 2xl(48) 3xl(64)

## Layout
- **Approach:** Grid-disciplined with one expressive header zone
- **Grid:** Single-column flow for the current settings window, but with internal two-column groups for related settings on wide screens
- **Max content width:** 920px inside the app shell
- **Border radius:**
  - sm: 8px
  - md: 12px
  - lg: 18px
  - xl: 24px
  - pill: 999px

### Shell Structure
- Top banner: large product heading, short promise, and a compact status panel
- Main body: stacked sections with strong hierarchy and breathing room
- Advanced: collapsed by default and visually separated from the main surface
- Diagnostics: monospaced, flatter, more technical, clearly secondary

## Motion
- **Approach:** Minimal-functional
- **Easing:** enter(`easeOutCubic`) exit(`easeInCubic`) move(`easeInOutCubic`)
- **Duration:** micro(80ms) short(160ms) medium(220ms) long(320ms)

Use motion only to:
- soften state transitions
- reveal and collapse advanced sections
- confirm user actions

Avoid:
- floating cards
- elastic overshoot
- decorative shimmer
- “AI app” glows

## Component Guidance

### Window Shell
- Use a warm canvas background with one darker side rail or top strip for anchoring.
- The window should look intentional at desktop size, not like a stretched mobile settings page.

### Status Banner
- Treat status as a calm product banner, not a system alert by default.
- Use tone shifts only when the app truly needs attention.
- Keep copy outcome-oriented: `Ready to type`, `Listening`, `Turning speech into text`, `Needs attention`.

### Section Cards
- Cards should be flatter, more architectural, and less bubbly than the current UI.
- Prefer soft borders plus subtle tonal contrast over obvious elevation.
- Section titles should feel editorially strong, but the controls inside should stay plain.

### Form Controls
- Inputs should feel compact and deliberate.
- Avoid giant rounded text boxes.
- Use hotkey chips and dropdowns that visually resemble hardware keycaps.

### Advanced Surface
- Make it look intentionally more technical:
  - mono accents
  - tighter spacing
  - calmer contrast
- Users should immediately understand that this is optional and diagnostic.

## Safe Choices
- Strong readable sans-serif body typography. Users expect clarity from a utility.
- Grid-disciplined settings layout. A desktop settings app should feel easy to scan.
- Restrained palette with obvious semantic status colors. This supports trust and supportability.

## Risks
- **Warm paper surfaces instead of clean white SaaS chrome**
  - Why it works: it makes the app feel like a personal tool, not a B2B console.
  - Gain: stronger identity and more emotional trust.
  - Cost: if overdone, it can drift into “retro” instead of “modern utility.”
- **Fraunces as a limited display accent**
  - Why it works: the app needs one memorable note so it does not feel generic.
  - Gain: better brand feel without cluttering the working UI.
  - Cost: misuse would make the app theatrical. Keep it at the top layer only.
- **Monospaced hotkey and diagnostics language**
  - Why it works: it gives precision where the product actually behaves like an instrument.
  - Gain: clearer separation between user utility and power-user detail.
  - Cost: if overused, it drifts back toward dev-tool aesthetics.

## Implementation Notes For Flutter
- Replace `ColorScheme.fromSeed` with explicit brand tokens.
- Stop relying on one universal large radius value for all containers.
- Add a theme extension or token file for surface, border, semantic, and mono styles.
- Use headline/body typography intentionally instead of default Material scales.
- Keep `Advanced` visually subordinate but still polished.

## First UI Pass To Make
1. Rebuild the app shell and header first.
2. Restyle status banner and section cards with the new color/radius system.
3. Replace current default form styling with compact utility controls.
4. Restyle hotkey controls as keycaps.
5. Restyle `Advanced` as a distinct diagnostics surface.

## Decisions Log
| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-03-23 | Warm Utility aesthetic | The app is a paid desktop instrument, not a dashboard |
| 2026-03-23 | Fraunces + Instrument Sans + IBM Plex Mono | Gives the UI identity, clarity, and precision without feeling generic |
| 2026-03-23 | Restrained warm palette with brass accent | Feels trustworthy and distinct while keeping states understandable |
