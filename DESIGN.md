---
name: Helmsman
description: Native macOS Kubernetes cluster manager — solar-dusk marketing surface
colors:
  canvas: "oklch(0.2161 0.0061 56.0434)"
  ink: "oklch(0.9699 0.0013 106.4238)"
  primary: "oklch(0.7049 0.1867 47.6044)"
  primary-light: "oklch(0.5553 0.1455 48.9975)"
  muted: "oklch(0.2330 0.0073 67.4563)"
  muted-foreground: "oklch(0.7161 0.0091 56.2590)"
  card: "oklch(0.2685 0.0063 34.2976)"
  border: "oklch(0.3741 0.0087 67.5582)"
  accent-blue: "oklch(0.3598 0.0497 229.3202)"
  destructive: "oklch(0.5771 0.2152 27.3250)"
typography:
  display:
    fontFamily: "Oxanium, sans-serif"
    fontSize: "clamp(3rem, 8vw, 4.5rem)"
    fontWeight: 700
    lineHeight: 1.1
    letterSpacing: "-0.025em"
  headline:
    fontFamily: "Oxanium, sans-serif"
    fontSize: "clamp(2.25rem, 5vw, 3rem)"
    fontWeight: 700
    lineHeight: 1.15
    letterSpacing: "-0.025em"
  body:
    fontFamily: "Oxanium, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.75
    letterSpacing: "0em"
  label:
    fontFamily: "Fira Code, monospace"
    fontSize: "0.75rem"
    fontWeight: 500
    lineHeight: 1.4
    letterSpacing: "0.3em"
  mono:
    fontFamily: "Fira Code, monospace"
    fontSize: "0.875rem"
    fontWeight: 400
    lineHeight: 1.5
    letterSpacing: "0em"
rounded:
  sm: "calc(0.3rem * 0.6)"
  md: "calc(0.3rem * 0.8)"
  lg: "0.3rem"
  xl: "calc(0.3rem * 1.4)"
spacing:
  section: "6rem"
  container: "1.5rem"
  stack: "1rem"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.ink}"
    rounded: "{rounded.sm}"
    padding: "12px 24px"
  button-secondary:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    rounded: "{rounded.sm}"
    padding: "12px 24px"
  nav-bar:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    height: "64px"
  feature-card:
    backgroundColor: "{colors.card}"
    textColor: "{colors.ink}"
    rounded: "{rounded.lg}"
    padding: "24px"
---

# Design System: Helmsman

## 1. Overview

**Creative North Star: "The Instrument Panel"**

Helmsman’s landing page reads like a well-lit control surface at dusk: dark canvas, warm amber indicators, monospace telemetry for anything technical. The aesthetic serves platform engineers who evaluate tools by whether they feel precise and trustworthy, not flashy. Density is moderate — generous section rhythm, but code paths, API routes, and terminal mockups carry real information.

The system explicitly rejects generic SaaS landing tropes: no hero-metric grids, no gradient text, no decorative glass cards, no eyebrow kickers on every section. Warmth comes from the amber primary on dark neutrals, not from cream body backgrounds.

**Key Characteristics:**

- Dark-first (`html.dark` by default in `helmsman-landing/app/layout.tsx`)
- OKLCH color tokens in `helmsman-landing/app/globals.css`
- Oxanium for UI/display, Fira Code for code/labels, Merriweather available for serif accents
- Restrained border radius (0.3rem base)
- Technical credibility via terminal mockups, install commands, and real API path strings

## 2. Colors

Warm amber primary on a near-neutral dark canvas. Accent blue appears sparingly in dark-mode secondary surfaces.

### Primary

- **Solar Amber** (`oklch(0.7049 0.1867 47.6044)`): CTAs, active context lines, stat values, section kickers (`// Native macOS`). The instrument-panel light.
- **Amber Deep** (`oklch(0.5553 0.1455 48.9975)`): Light-mode primary (available but not default); ring/focus color reference.

### Neutral

- **Canvas** (`oklch(0.2161 0.0061 56.0434)`): Page background. Near-black with minimal warm chroma.
- **Ink** (`oklch(0.9699 0.0013 106.4238)`): Primary text, headings.
- **Muted Surface** (`oklch(0.2330 0.0073 67.4563)`): Subtle section backgrounds, install strips.
- **Muted Text** (`oklch(0.7161 0.0091 56.2590)`): Body secondary, nav links at rest. Must stay ≥4.5:1 on canvas.
- **Card** (`oklch(0.2685 0.0063 34.2976)`): Terminal cards, elevated panels.
- **Border** (`oklch(0.3741 0.0087 67.5582)`): Dividers, card outlines, input borders.

### Accent

- **Signal Blue** (`oklch(0.3598 0.0497 229.3202)`): Dark-mode accent for sidebar/highlight surfaces. Use sparingly; amber remains the brand voice.

### Named Rules

**The Amber Rarity Rule.** Primary amber appears on CTAs, one kicker per section maximum, stat highlights, and terminal cursor/active lines. It should not flood backgrounds or body text.

## 3. Typography

**Display Font:** Oxanium (Google Fonts, `--font-sans`)
**Body Font:** Oxanium (same family, weight differentiation)
**Label/Mono Font:** Fira Code (`--font-mono`)
**Serif (optional):** Merriweather (`--font-serif`) — loaded but rarely used on landing; reserve for editorial moments.

**Character:** Geometric sans with a technical edge; monospace for anything that should feel like terminal output or API documentation.

### Hierarchy

- **Display** (700, up to 4.5rem clamp, 1.1 lh): Hero headline only. Max one per page above the fold.
- **Headline** (700, 2.25–3rem, 1.15 lh): Section titles (`Your cluster. Your config.`)
- **Body** (400, 1rem/1.125rem, 1.75 lh): Prose blocks. Cap line length at ~65ch.
- **Label** (500, 0.75rem, uppercase, 0.3em tracking): Mono kickers (`// Private by default`). One per section, not every heading.
- **Mono inline** (400, 0.875rem): Install commands, API paths, feature `mono` strings.

### Named Rules

**The Mono Credibility Rule.** Fira Code is reserved for code, commands, API routes, and stat labels — never for marketing prose paragraphs.

## 4. Elevation

Hybrid: mostly flat dark surfaces with tonal layering (`canvas` → `muted/20` → `card`). Shadows are structural, not decorative — screenshot frames and terminal cards use `shadow-lg` / `shadow-2xl` with low-opacity black. Nav uses `backdrop-blur-md` with semi-transparent background; this is functional (sticky header), not glassmorphism decoration.

### Shadow Vocabulary

- **Screenshot frame** (`shadow-2xl shadow-black/40`): App screenshot hero only.
- **Terminal card** (`shadow-lg`): Elevated mock terminal in Why section.
- **Default stack** (from CSS vars): Subtle 2–3px offsets for cards at rest.

### Named Rules

**The Flat-By-Default Rule.** Sections sit on canvas or muted/20 bands. Elevation appears only on screenshots, terminal mockups, and sticky nav — not on every content block.

## 5. Components

### Navigation

Fixed top bar, `border-b border-border/50`, `bg-background/80 backdrop-blur-md`. Logo + uppercase wordmark (tracking-widest). Links: uppercase, xs, muted → foreground on hover. Primary CTA: filled amber button, uppercase, bold.

### Buttons

- **Primary:** `bg-primary text-primary-foreground`, uppercase, bold, `rounded-sm`, hover via opacity (not color shift).
- **Secondary:** `border border-border`, hover `bg-muted`. Same typographic treatment as primary.

### Stats Band

Horizontal strip with `border-y`, divided cells. Value in mono bold primary; label in mono 10px uppercase muted. Avoid hero-metric cliché — these are factual specs (macOS 14+, kubeconfig, 0 agents), not vanity numbers.

### Feature Sections

Two-column on large screens where appropriate. Feature tags use mono uppercase (`01 / BROWSE`) — acceptable here because they label a real ordered capability list, not generic section scaffolding. Body + mono API string below.

### Terminal Mock

Card with traffic-light dots, mono 11px content, primary for active context, green cursor blink (respect reduced motion). Border + card background.

## 6. Do's and Don'ts

**Do**

- Lead with product screenshots and real terminal/API content
- Keep dark canvas as default; test all muted text for WCAG AA contrast
- Use amber primary for emphasis sparingly
- Write copy for engineers who already know Kubernetes
- Respect `prefers-reduced-motion` on any animation (cursor blink, hover transitions)

**Don't**

- Add gradient text, side-stripe borders, or glass card grids
- Put uppercase tracked eyebrows above every section
- Use hero-metric templates (big number + small label grids for vanity stats)
- Lighten muted-foreground for "elegance" — bump toward ink if contrast is borderline
- Introduce cream/sand body backgrounds or warm-tinted near-white canvases
