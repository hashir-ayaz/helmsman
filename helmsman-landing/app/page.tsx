import Image from "next/image";
import { CopyCommand } from "@/components/copy-command";
import { RevealOnView } from "@/components/reveal-on-view";
import {
  DevConsoleEasterEgg,
  ScrollProgress,
  TerminalPanel,
} from "@/components/site-delight";

const BACKEND_CMD = "cd helmsman-api && make run";
const CLONE_CMD = "git clone https://github.com/hashir-ayaz/helmsman";
const DMG_URL = "https://qkupugaejupbhwpobbdr.supabase.co/storage/v1/object/public/helmsman-dmg/Helmsman.dmg";
const BREW_TAP = "brew tap hashir-ayaz/helmsman";
const BREW_TRUST = "brew trust hashir-ayaz/helmsman";
const BREW_INSTALL = "brew install --cask helmsman";

export default function Home() {
  return (
    <div className="bold-grain flex min-h-screen flex-col bg-background text-foreground font-sans">
      <ScrollProgress />
      <DevConsoleEasterEgg />
      <Nav />
      <main className="flex-1">
        <Hero />
        <StatsBand />
        <WhySection />
        <FeaturesSection />
        <DownloadSection />
        <CtaBanner />
      </main>
      <Footer />
    </div>
  );
}

/* ─── Nav ─────────────────────────────────────────────────────────────── */

function Nav() {
  return (
    <header className="motion-nav fixed top-0 inset-x-0 z-50 border-b border-border/50 bg-background/80 backdrop-blur-md">
      <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4">
        <div className="motion-helm-hover flex items-center gap-2.5" title="Steer your cluster. No helm install required.">
          <HelmIcon />
          <span className="text-sm font-semibold tracking-widest uppercase text-foreground">
            Helmsman
          </span>
        </div>

        <nav className="hidden md:flex items-center gap-8 text-xs font-medium tracking-wider uppercase text-muted-foreground">
          <a href="#why" className="motion-link hover:text-foreground">Why</a>
          <a href="#features" className="motion-link hover:text-foreground">Features</a>
          <a href="#download" className="motion-link hover:text-foreground">Download</a>
          <a href="https://github.com/hashir-ayaz/helmsman" className="motion-link hover:text-foreground">GitHub</a>
        </nav>

        <a
          href="https://github.com/hashir-ayaz/helmsman"
          className="motion-btn bold-btn-primary rounded-sm border border-primary bg-primary px-4 py-2 text-xs font-bold tracking-widest uppercase text-primary-foreground hover:opacity-95"
        >
          View on GitHub
        </a>
      </div>
    </header>
  );
}

/* ─── Hero ────────────────────────────────────────────────────────────── */

function Hero() {
  return (
    <section className="relative overflow-hidden pt-32 pb-24 md:pb-28">
      <div aria-hidden className="pointer-events-none absolute inset-0 bold-hero-glow-primary" />
      <div aria-hidden className="pointer-events-none absolute inset-0 bold-hero-glow-secondary" />

      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 flex items-start justify-center"
      >
        <div className="motion-glow h-[560px] w-[980px] rounded-full bg-primary/15 blur-[130px] -translate-y-1/3" />
      </div>

      <div className="relative mx-auto max-w-6xl px-6">
        <p className="motion-hero-item mb-6 font-mono text-xs font-medium tracking-[0.3em] uppercase text-primary">
          // Native macOS
        </p>

        <h1 className="motion-hero-item motion-hero-delay-1 max-w-4xl text-[clamp(2.75rem,8vw,6rem)] font-bold leading-[1.02] tracking-[-0.03em] text-foreground text-balance">
          Kubernetes at your
          <br />
          <span className="bold-headline-accent">fingertips.</span>
        </h1>

        <p className="motion-hero-item motion-hero-delay-2 mt-8 max-w-xl text-base leading-7 text-muted-foreground md:text-lg md:leading-8 text-pretty">
          A native macOS app for managing your Kubernetes clusters. Browse
          every resource type, stream live logs, edit YAML, scale workloads —
          all against your existing kubeconfig. No cloud account. No cluster
          agent.
        </p>

        <div className="motion-hero-item motion-hero-delay-3 mt-12 flex flex-wrap gap-4">
          <a
            href="#download"
            className="motion-btn bold-btn-primary inline-flex items-center gap-2 rounded-sm bg-primary px-7 py-3.5 text-sm font-bold tracking-wider uppercase text-primary-foreground hover:opacity-95"
          >
            <DownloadIcon />
            Download
          </a>
          <a
            href="https://github.com/hashir-ayaz/helmsman"
            className="motion-btn inline-flex items-center gap-2 rounded-sm border border-border px-7 py-3.5 text-sm font-bold tracking-wider uppercase text-foreground hover:border-primary/40 hover:bg-muted"
          >
            <GitHubIcon />
            View on GitHub
          </a>
        </div>

        <CopyCommand
          value={BACKEND_CMD}
          label="Copy backend start command"
          className="motion-hero-item motion-hero-delay-4 mt-10 rounded-sm border border-border bg-muted/40 px-5 py-3 hover:border-primary/30 hover:bg-muted/60"
        >
          <span className="font-mono text-xs tracking-widest text-muted-foreground"># BACKEND</span>
          <code className="font-mono text-sm text-foreground">{BACKEND_CMD}</code>
        </CopyCommand>

        <div className="motion-screenshot bold-screenshot-frame relative -mx-2 mt-20 overflow-hidden rounded-xl border border-primary/20 md:-mx-8 lg:-mx-14">
          <Image
            src="/app-screenshot.png"
            alt="Helmsman — native macOS Kubernetes manager showing pods view"
            width={1400}
            height={900}
            className="w-full h-auto"
            priority
          />
        </div>
      </div>
    </section>
  );
}

/* ─── Stats band ──────────────────────────────────────────────────────── */

function StatsBand() {
  const stats = [
    { value: "macOS 14+", label: "Native SwiftUI" },
    { value: "kubeconfig", label: "Zero setup" },
    { value: "0 agents", label: "Direct API" },
    { value: "Go + Swift", label: "No Electron" },
    { value: "CRD-aware", label: "Dynamic resolver" },
  ];

  return (
    <div className="border-y border-border bg-muted/30">
      <div className="mx-auto max-w-6xl px-6 py-2">
        <div className="flex flex-wrap justify-between divide-x divide-border">
          {stats.map(({ value, label }, index) => (
            <RevealOnView key={value} delay={index * 55} className="flex flex-1 min-w-[140px] justify-center">
              <div className="bold-stat-cell flex flex-col items-center px-6 py-8 gap-2 transition-colors hover:bg-primary/5">
                <span className="bold-stat-value font-mono font-bold text-primary">{value}</span>
                <span className="font-mono text-[10px] tracking-widest uppercase text-muted-foreground">{label}</span>
              </div>
            </RevealOnView>
          ))}
        </div>
      </div>
    </div>
  );
}

/* ─── Why section ─────────────────────────────────────────────────────── */

function WhySection() {
  return (
    <section id="why" className="py-28 md:py-32">
      <div className="mx-auto max-w-6xl px-6">
        <div className="grid gap-16 lg:grid-cols-[1.15fr_0.85fr] lg:gap-20 items-center">
          <div>
            <div className="bold-section-rule mb-8" aria-hidden />
            <h2 className="text-[clamp(2.25rem,5vw,3.25rem)] font-bold leading-[1.05] tracking-tight text-foreground text-balance">
              Your cluster.
              <br />
              Your config.
            </h2>
            <p className="mt-8 max-w-lg text-base leading-7 text-muted-foreground md:text-lg text-pretty">
              Helmsman reads the same kubeconfig your terminal already uses.
              No sign-up, no cluster agent to deploy, no data leaving your
              machine. Open the app and start working.
            </p>

            <div className="mt-12 space-y-7">
              {[
                {
                  title: "Reads your existing kubeconfig",
                  body: "Honors KUBECONFIG env var and multi-context merge rules. Every context you have in kubectl is available in Helmsman.",
                },
                {
                  title: "No cluster agents required",
                  body: "All core operations talk directly to the Kubernetes API server. Nothing runs inside your cluster.",
                },
                {
                  title: "No cloud account",
                  body: "Install, open, and manage clusters without signing up for anything.",
                },
                {
                  title: "Native performance",
                  body: "Go backend + SwiftUI frontend. No Electron, no browser runtime. The app stays out of your way.",
                },
              ].map(({ title, body }) => (
                <div key={title} className="flex gap-4">
                  <div className="mt-1.5 h-2.5 w-2.5 shrink-0 rounded-full bg-primary shadow-[0_0_10px_oklch(0.7049_0.1867_47.6044/0.6)]" />
                  <div>
                    <p className="text-sm font-semibold text-foreground md:text-base">{title}</p>
                    <p className="mt-1.5 text-sm leading-6 text-muted-foreground">{body}</p>
                  </div>
                </div>
              ))}
            </div>
          </div>

          <RevealOnView delay={120}>
            <TerminalPanel />
          </RevealOnView>
        </div>
      </div>
    </section>
  );
}

/* ─── Features ────────────────────────────────────────────────────────── */

function FeaturesSection() {
  const features = [
    {
      tag: "01 / BROWSE",
      title: "Every resource. Every CRD.",
      body: "The backend uses Kubernetes server-side Table format and a dynamic RESTMapper — any built-in resource or custom CRD shows up automatically, including kubectl-identical columns. No per-resource code needed.",
      mono: "pods • deployments.apps • virtualservices.networking.istio.io",
    },
    {
      tag: "02 / LOGS",
      title: "Live log streaming.",
      body: "Pod logs stream over Server-Sent Events directly to the UI. Filter by container, toggle follow mode, and keep a 5,000-line scrollback buffer. Works exactly like kubectl logs -f.",
      mono: "GET /api/v1/contexts/{ctx}/namespaces/{ns}/pods/{name}/log",
    },
    {
      tag: "03 / YAML",
      title: "Edit and apply YAML.",
      body: "Fetch any resource as YAML, edit it in the built-in editor, and apply with server-side apply in one keystroke. The backend strips managed fields so you can round-trip fetched objects directly.",
      mono: "POST /api/v1/contexts/{ctx}/resources  (server-side apply)",
    },
    {
      tag: "04 / ACTIONS",
      title: "Scale and restart workloads.",
      body: "Scale deployments via the scale subresource. Trigger rolling restarts using the same pod-template annotation as kubectl rollout restart — no downtime, no guesswork.",
      mono: 'PATCH spec.replicas • annotation restartedAt="<RFC3339>"',
    },
    {
      tag: "05 / INSPECT",
      title: "JSON tree + overview.",
      body: "Every resource opens a detail panel with a structured overview, a collapsible JSON tree for the full object, and a raw YAML tab. Labels, owner refs, status conditions — all readable at a glance.",
      mono: "Overview → Object → YAML",
    },
    {
      tag: "06 / CONTEXTS",
      title: "Multi-context switching.",
      body: "Switch between any kubeconfig context from the sidebar picker. Client bundles are built lazily and cached — switching contexts is instant after the first load.",
      mono: "GET /api/v1/contexts  →  _current sentinel",
    },
  ];

  return (
    <section id="features" className="py-28 md:py-32 bg-muted/10">
      <div className="mx-auto max-w-6xl px-6">
        <div className="mb-20 max-w-3xl">
          <div className="bold-section-rule mb-8" aria-hidden />
          <h2 className="text-[clamp(2.25rem,5vw,3.25rem)] font-bold leading-[1.05] tracking-tight text-foreground text-balance">
            Everything you need.
            <br />
            Nothing you don&apos;t.
          </h2>
        </div>

        <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
          {features.map(({ tag, title, body, mono }, index) => (
            <RevealOnView key={tag} delay={index * 50}>
              <div className="motion-card group flex h-full flex-col gap-4 rounded-lg border border-border bg-card p-6 hover:border-primary/50 hover:bg-card/90">
                <p className="font-mono text-[10px] tracking-widest uppercase text-primary">{tag}</p>
                <h3 className="text-xl font-bold text-foreground leading-snug">{title}</h3>
                <p className="flex-1 text-sm leading-6 text-muted-foreground">{body}</p>
                <code className="bold-feature-code rounded-sm border border-transparent bg-muted/60 px-3 py-2 font-mono text-[10px] text-muted-foreground leading-5 break-all">
                  {mono}
                </code>
              </div>
            </RevealOnView>
          ))}
        </div>
      </div>
    </section>
  );
}

/* ─── Download ────────────────────────────────────────────────────────── */

function DownloadSection() {
  return (
    <section id="download" className="py-28 md:py-32 bg-muted/10">
      <div className="mx-auto max-w-6xl px-6">
        <div className="mb-16">
          <div className="bold-section-rule mb-8" aria-hidden />
          <h2 className="text-[clamp(2.25rem,5vw,3.25rem)] font-bold leading-[1.05] tracking-tight text-foreground text-balance">
            Get Helmsman.
          </h2>
        </div>

        <div className="grid gap-6 md:grid-cols-2">
          <RevealOnView delay={0}>
            <div className="motion-card flex h-full flex-col gap-6 rounded-lg border border-border bg-card p-8 hover:border-primary/50 hover:bg-card/90">
              <div>
                <p className="font-mono text-[10px] tracking-widest uppercase text-primary mb-3">01 / Direct</p>
                <h3 className="text-xl font-bold text-foreground">Download the .dmg</h3>
                <p className="mt-2 text-sm leading-6 text-muted-foreground">
                  Download the disk image, open it, and drag Helmsman to Applications.
                </p>
              </div>
              <a
                href={DMG_URL}
                className="motion-btn bold-btn-primary inline-flex items-center gap-2.5 self-start rounded-sm bg-primary px-6 py-3.5 text-sm font-bold tracking-wider uppercase text-primary-foreground hover:opacity-95"
              >
                <DownloadIcon />
                Download .dmg
              </a>
              <code className="bold-feature-code rounded-sm border border-transparent bg-muted/60 px-3 py-2 font-mono text-[10px] text-muted-foreground leading-5">
                macOS 14+ Sonoma · Free · MIT
              </code>
            </div>
          </RevealOnView>

          <RevealOnView delay={80}>
            <div className="motion-card flex h-full flex-col gap-6 rounded-lg border border-border bg-card p-8 hover:border-primary/50 hover:bg-card/90">
              <div>
                <p className="font-mono text-[10px] tracking-widest uppercase text-primary mb-3">02 / Homebrew</p>
                <h3 className="text-xl font-bold text-foreground">Install with Homebrew</h3>
                <p className="mt-2 text-sm leading-6 text-muted-foreground">
                  Tap the cask, then install. Updates with <code className="font-mono text-xs text-foreground">brew upgrade</code>.
                </p>
              </div>
              <div className="flex flex-col gap-2">
                {[BREW_TAP, BREW_TRUST, BREW_INSTALL].map((cmd) => (
                  <CopyCommand
                    key={cmd}
                    value={cmd}
                    label={`Copy: ${cmd}`}
                    className="rounded-sm border border-border bg-muted/40 px-4 py-2.5 hover:border-primary/30 hover:bg-muted/60"
                  >
                    <code className="font-mono text-xs text-foreground">
                      <span className="text-primary">$</span> {cmd}
                    </code>
                  </CopyCommand>
                ))}
              </div>
              <code className="bold-feature-code rounded-sm border border-transparent bg-muted/60 px-3 py-2 font-mono text-[10px] text-muted-foreground leading-5">
                requires homebrew · brew.sh
              </code>
            </div>
          </RevealOnView>
        </div>
      </div>
    </section>
  );
}

/* ─── CTA banner ──────────────────────────────────────────────────────── */

function CtaBanner() {
  return (
    <section className="py-28 md:py-32">
      <div className="mx-auto max-w-6xl px-6">
        <RevealOnView>
          <div className="bold-cta-panel relative overflow-hidden rounded-lg border border-primary/40 bg-card p-12 text-center md:p-16">
            <div
              aria-hidden
              className="pointer-events-none absolute inset-0 flex items-center justify-center"
            >
              <div className="motion-glow h-[360px] w-[720px] rounded-full bg-primary/15 blur-[90px]" />
            </div>
            <div className="relative">
              <h2 className="text-[clamp(2.25rem,5vw,3.25rem)] font-bold tracking-tight text-foreground text-balance">
                Start managing your cluster.
              </h2>
              <p className="mx-auto mt-5 max-w-md text-base text-muted-foreground md:text-lg text-pretty">
                Clone the repo, run the Go backend, open the Xcode project. No
                dependencies outside your kubeconfig.
              </p>

              <div className="mt-12 flex flex-wrap justify-center gap-4">
                <a
                  href="https://github.com/hashir-ayaz/helmsman"
                  className="motion-btn bold-btn-primary inline-flex items-center gap-2 rounded-sm bg-primary px-8 py-4 text-sm font-bold tracking-wider uppercase text-primary-foreground hover:opacity-95"
                >
                  <GitHubIcon />
                  GitHub Repository
                </a>
              </div>

              <div className="mt-10 flex flex-wrap items-center justify-center gap-3">
                <CopyCommand
                  value={CLONE_CMD}
                  label="Copy git clone command"
                  className="rounded-sm border border-border bg-background/60 px-5 py-3 font-mono text-xs text-muted-foreground hover:border-primary/30"
                >
                  <span><span className="text-primary">$</span> {CLONE_CMD}</span>
                </CopyCommand>
                <CopyCommand
                  value={BACKEND_CMD}
                  label="Copy backend start command"
                  className="rounded-sm border border-border bg-background/60 px-5 py-3 font-mono text-xs text-muted-foreground hover:border-primary/30"
                >
                  <span><span className="text-primary">$</span> {BACKEND_CMD}</span>
                </CopyCommand>
              </div>
            </div>
          </div>
        </RevealOnView>
      </div>
    </section>
  );
}

/* ─── Footer ──────────────────────────────────────────────────────────── */

function Footer() {
  return (
    <footer className="border-t border-border py-12">
      <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-4 px-6">
        <div className="motion-helm-hover flex items-center gap-2.5">
          <HelmIcon />
          <span className="font-mono text-xs tracking-widest uppercase text-muted-foreground">Helmsman</span>
        </div>
        <div className="flex gap-6 font-mono text-[10px] tracking-widest uppercase text-muted-foreground">
          <a href="https://github.com/hashir-ayaz/helmsman" className="motion-link hover:text-foreground">GitHub</a>
          <span>Go + Swift · macOS 14+ · MIT</span>
        </div>
      </div>
    </footer>
  );
}

/* ─── Icons ───────────────────────────────────────────────────────────── */

function DownloadIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
      <polyline points="7 10 12 15 17 10" />
      <line x1="12" y1="15" x2="12" y2="3" />
    </svg>
  );
}

function HelmIcon() {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <circle cx="12" cy="12" r="3" fill="currentColor" className="text-primary" />
      <circle
        cx="12"
        cy="12"
        r="9"
        stroke="currentColor"
        strokeWidth="1.5"
        className="motion-helm-orbit text-primary"
        strokeDasharray="3 2"
      />
      {[0, 60, 120, 180, 240, 300].map((angle) => {
        const rad = (angle * Math.PI) / 180;
        const x1 = 12 + 3 * Math.cos(rad);
        const y1 = 12 + 3 * Math.sin(rad);
        const x2 = 12 + 9 * Math.cos(rad);
        const y2 = 12 + 9 * Math.sin(rad);
        return (
          <line
            key={angle}
            x1={x1}
            y1={y1}
            x2={x2}
            y2={y2}
            stroke="currentColor"
            strokeWidth="1.5"
            className="text-primary opacity-80 transition-opacity duration-200"
          />
        );
      })}
    </svg>
  );
}

function GitHubIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0112 6.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0022 12.017C22 6.484 17.522 2 12 2z" />
    </svg>
  );
}
