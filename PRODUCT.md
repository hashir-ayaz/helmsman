# Product

## Register

brand

## Users

Platform and DevOps engineers who manage Kubernetes clusters daily. They work across multiple kubeconfig contexts, switch between namespaces constantly, and already live in the terminal. Helmsman is the native macOS surface they reach for when browsing resources, tailing logs, editing YAML, or scaling workloads — faster than context-switching through kubectl, k9s, or a browser-based dashboard.

## Product Purpose

Helmsman is a native macOS Kubernetes cluster manager that reads the user's existing kubeconfig and talks directly to the Kubernetes API. No cloud account, no cluster agent, no Electron shell. Success means an engineer can install the app, point it at their clusters, and complete everyday cluster operations with less friction than their current toolchain — while trusting that nothing leaves their machine.

The landing page (`helmsman-landing/`) is the primary design surface for Impeccable: it communicates credibility, privacy, and technical capability to engineers evaluating whether to adopt a new tool. The SwiftUI app follows macOS system conventions and inherits brand identity through typography and color tone, but design decisions for marketing and product UI are anchored here first.

## Brand Personality

Technical, calm, trustworthy. Helmsman speaks like a senior platform engineer: precise, unhurried, confident without hype. It respects the user's intelligence and time. Visual tone is restrained warmth on a dark canvas — amber accents that feel like instrument panel lighting, not startup neon.

## Anti-references

- Generic SaaS landing pages: hero metric blocks, gradient text, identical icon-card grids, eyebrow kickers on every section, "01 / 02 / 03" scaffolding without semantic purpose
- Electron Kubernetes dashboards: heavy chrome, sluggish feel, enterprise purple gradients, bloated sidebars
- AI-generated dev tool aesthetics: cream/sand body backgrounds, decorative glassmorphism, uniform scroll-reveal animations on every section
- Kubernetes dashboard chaos: dense unreadable tables, status color noise, no visual hierarchy

## Design Principles

1. **Practice what you preach** — The landing page should feel as native and fast as the product it describes. No framework bloat visible in the experience.
2. **Show, don't tell** — Screenshots, terminal mockups, and real API paths carry credibility. Avoid abstract benefit claims without evidence.
3. **Expert confidence** — Assume the reader knows Kubernetes. Speak in their vocabulary (contexts, CRDs, server-side apply) without dumbing down or over-explaining.
4. **Privacy as default** — Local-first, kubeconfig-native, no agents. This is a structural truth, not a marketing bullet; it should shape layout and copy hierarchy.
5. **Restraint over spectacle** — One accent color, one mono voice for code, one hero moment. Rarity creates emphasis.

## Accessibility & Inclusion

WCAG 2.1 AA as baseline: body text ≥4.5:1 contrast against backgrounds, large text ≥3:1, placeholder and muted text held to the same standard. Keyboard-navigable interactive elements on the landing page. All motion respects `prefers-reduced-motion` with instant or crossfade alternatives. No information conveyed by color alone — status and emphasis use text or icons alongside hue.
