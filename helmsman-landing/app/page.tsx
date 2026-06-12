import Image from "next/image";
import { RevealOnView } from "@/components/reveal-on-view";

export default function Home() {
  return (
    <div className="flex flex-col min-h-screen bg-background text-foreground font-sans">
      <Nav />
      <main className="flex-1">
        <Hero />
        <StatsBand />
        <WhySection />
        <FeaturesSection />
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
        <div className="flex items-center gap-2.5">
          <HelmIcon />
          <span className="text-sm font-semibold tracking-widest uppercase text-foreground">
            Helmsman
          </span>
        </div>

        <nav className="hidden md:flex items-center gap-8 text-xs font-medium tracking-wider uppercase text-muted-foreground">
          <a href="#why" className="motion-link hover:text-foreground">Why</a>
          <a href="#features" className="motion-link hover:text-foreground">Features</a>
          <a href="https://github.com/hashir-ayaz/helmsman" className="motion-link hover:text-foreground">GitHub</a>
        </nav>

        <a
          href="https://github.com/hashir-ayaz/helmsman"
          className="motion-btn rounded-sm border border-primary bg-primary px-4 py-2 text-xs font-bold tracking-widest uppercase text-primary-foreground hover:opacity-90"
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
    <section className="relative overflow-hidden pt-32 pb-20">
      {/* Ambient glow */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 flex items-start justify-center"
      >
        <div className="motion-glow h-[500px] w-[900px] rounded-full bg-primary/10 blur-[120px] -translate-y-1/3" />
      </div>

      <div className="relative mx-auto max-w-6xl px-6">
        {/* Eyebrow */}
        <p className="motion-hero-item mb-6 font-mono text-xs font-medium tracking-[0.3em] uppercase text-primary">
          // Native macOS
        </p>

        {/* Headline */}
        <h1 className="motion-hero-item motion-hero-delay-1 max-w-3xl text-5xl font-bold leading-[1.1] tracking-tight text-foreground md:text-7xl text-balance">
          Kubernetes at your
          <br />
          fingertips.
        </h1>

        <p className="motion-hero-item motion-hero-delay-2 mt-6 max-w-xl text-base leading-7 text-muted-foreground md:text-lg text-pretty">
          A native macOS app for managing your Kubernetes clusters. Browse
          every resource type, stream live logs, edit YAML, scale workloads —
          all against your existing kubeconfig. No cloud account. No cluster
          agent.
        </p>

        {/* CTAs */}
        <div className="motion-hero-item motion-hero-delay-3 mt-10 flex flex-wrap gap-4">
          <a
            href="https://github.com/hashir-ayaz/helmsman"
            className="motion-btn inline-flex items-center gap-2 rounded-sm bg-primary px-6 py-3 text-sm font-bold tracking-wider uppercase text-primary-foreground hover:opacity-90"
          >
            <GitHubIcon />
            View on GitHub
          </a>
          <a
            href="#features"
            className="motion-btn inline-flex items-center rounded-sm border border-border px-6 py-3 text-sm font-bold tracking-wider uppercase text-foreground hover:bg-muted"
          >
            See Features
          </a>
        </div>

        {/* Install strip */}
        <div className="motion-hero-item motion-hero-delay-4 mt-8 inline-flex items-center gap-3 rounded-sm border border-border bg-muted/40 px-5 py-3">
          <span className="font-mono text-xs tracking-widest text-muted-foreground"># BACKEND</span>
          <code className="font-mono text-sm text-foreground">cd helmsman-api &amp;&amp; make run</code>
        </div>

        {/* App screenshot */}
        <div className="motion-screenshot mt-16 rounded-xl overflow-hidden border border-border/40 shadow-2xl shadow-black/40">
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
    <div className="border-y border-border bg-muted/20">
      <div className="mx-auto max-w-6xl px-6">
        <div className="flex flex-wrap justify-between divide-x divide-border">
          {stats.map(({ value, label }, index) => (
            <RevealOnView key={value} delay={index * 55} className="flex flex-1 min-w-[140px] justify-center">
              <div className="flex flex-col items-center px-8 py-6 gap-1">
                <span className="font-mono text-lg font-bold text-primary">{value}</span>
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
    <section id="why" className="py-24">
      <div className="mx-auto max-w-6xl px-6">
        <div className="grid gap-16 lg:grid-cols-2 lg:gap-24 items-center">
          {/* Text */}
          <div>
            <p className="mb-4 font-mono text-xs font-medium tracking-[0.3em] uppercase text-primary">
              // Private by default
            </p>
            <h2 className="text-4xl font-bold leading-tight tracking-tight text-foreground md:text-5xl text-balance">
              Your cluster.
              <br />
              Your config.
            </h2>
            <p className="mt-6 text-base leading-7 text-muted-foreground">
              Helmsman reads the same kubeconfig your terminal already uses.
              No sign-up, no cluster agent to deploy, no data leaving your
              machine. Open the app and start working.
            </p>

            <div className="mt-10 space-y-6">
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
                  <div className="mt-1 h-2 w-2 shrink-0 rounded-full bg-primary" />
                  <div>
                    <p className="text-sm font-semibold text-foreground">{title}</p>
                    <p className="mt-1 text-sm leading-6 text-muted-foreground">{body}</p>
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Terminal card */}
          <RevealOnView delay={120} className="rounded-lg border border-border bg-card overflow-hidden shadow-lg">
            <div className="flex items-center gap-2 border-b border-border px-4 py-3 bg-muted/20">
              <span className="h-2.5 w-2.5 rounded-full bg-red-500/60" />
              <span className="h-2.5 w-2.5 rounded-full bg-yellow-500/60" />
              <span className="h-2.5 w-2.5 rounded-full bg-green-500/60" />
              <span className="ml-3 font-mono text-[10px] text-muted-foreground">kubectl config get-contexts</span>
            </div>
            <div className="p-5 font-mono text-[11px] space-y-1">
              <p className="text-muted-foreground">CURRENT   NAME                  CLUSTER</p>
              <div className="mt-2 space-y-1.5">
                {[
                  { current: "*", name: "prod-cluster", cluster: "prod.k8s.internal" },
                  { current: "", name: "staging", cluster: "stg.k8s.internal" },
                  { current: "", name: "local-kind", cluster: "kind-local" },
                  { current: "", name: "docker-desktop", cluster: "docker-desktop" },
                ].map((ctx) => (
                  <p key={ctx.name} className={ctx.current ? "text-primary" : "text-foreground/60"}>
                    {ctx.current || " "}&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
                    {ctx.name.padEnd(22)}{ctx.cluster}
                  </p>
                ))}
              </div>
              <div className="mt-6 pt-4 border-t border-border space-y-1">
                <p className="text-muted-foreground"># Helmsman sees all of these, instantly.</p>
                <p className="text-primary">$ open helmsman</p>
                <p className="text-green-500 motion-cursor" aria-hidden="true">▊</p>
              </div>
            </div>
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
    <section id="features" className="py-24 bg-muted/10">
      <div className="mx-auto max-w-6xl px-6">
        <div className="mb-16">
          <p className="mb-4 font-mono text-xs font-medium tracking-[0.3em] uppercase text-primary">
            // Capabilities
          </p>
          <h2 className="text-4xl font-bold leading-tight tracking-tight text-foreground md:text-5xl text-balance">
            Everything you need.
            <br />
            Nothing you don&apos;t.
          </h2>
        </div>

        <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
          {features.map(({ tag, title, body, mono }, index) => (
            <RevealOnView key={tag} delay={index * 50}>
              <div className="motion-card group flex h-full flex-col gap-4 rounded-lg border border-border bg-card p-6 hover:border-primary/40 hover:bg-card/80">
                <p className="font-mono text-[10px] tracking-widest uppercase text-primary">{tag}</p>
                <h3 className="text-lg font-bold text-foreground leading-snug">{title}</h3>
                <p className="flex-1 text-sm leading-6 text-muted-foreground">{body}</p>
                <code className="rounded-sm bg-muted/60 px-3 py-2 font-mono text-[10px] text-muted-foreground leading-5 break-all">
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

/* ─── CTA banner ──────────────────────────────────────────────────────── */

function CtaBanner() {
  return (
    <section className="py-24">
      <div className="mx-auto max-w-6xl px-6">
        <RevealOnView>
          <div className="relative overflow-hidden rounded-lg border border-primary/30 bg-card p-12 text-center">
            <div
              aria-hidden
              className="pointer-events-none absolute inset-0 flex items-center justify-center"
            >
              <div className="motion-glow h-[300px] w-[600px] rounded-full bg-primary/10 blur-[80px]" />
            </div>
            <div className="relative">
              <p className="mb-4 font-mono text-xs font-medium tracking-[0.3em] uppercase text-primary">
                // Open source
              </p>
              <h2 className="text-4xl font-bold tracking-tight text-foreground md:text-5xl text-balance">
                Start managing your cluster.
              </h2>
              <p className="mx-auto mt-4 max-w-md text-base text-muted-foreground text-pretty">
                Clone the repo, run the Go backend, open the Xcode project. No
                dependencies outside your kubeconfig.
              </p>

              <div className="mt-10 flex flex-wrap justify-center gap-4">
                <a
                  href="https://github.com/hashir-ayaz/helmsman"
                  className="motion-btn inline-flex items-center gap-2 rounded-sm bg-primary px-7 py-3.5 text-sm font-bold tracking-wider uppercase text-primary-foreground hover:opacity-90"
                >
                  <GitHubIcon />
                  GitHub Repository
                </a>
              </div>

              <div className="mt-8 inline-flex flex-wrap items-center justify-center gap-4 rounded-sm border border-border bg-background/60 px-6 py-4 font-mono text-xs text-muted-foreground">
                <span><span className="text-primary">$</span> git clone https://github.com/hashir-ayaz/helmsman</span>
                <span className="hidden sm:inline text-border">|</span>
                <span><span className="text-primary">$</span> cd helmsman-api &amp;&amp; make run</span>
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
    <footer className="border-t border-border py-10">
      <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-4 px-6">
        <div className="flex items-center gap-2.5">
          <HelmIcon />
          <span className="font-mono text-xs tracking-widest uppercase text-muted-foreground">Helmsman</span>
        </div>
        <div className="flex gap-6 font-mono text-[10px] tracking-widest uppercase text-muted-foreground">
          <a href="https://github.com/hashir-ayaz/helmsman" className="motion-link hover:text-foreground">GitHub</a>
          <span>Go + Swift · macOS 14+</span>
        </div>
      </div>
    </footer>
  );
}

/* ─── Icons ───────────────────────────────────────────────────────────── */

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
          <line key={angle} x1={x1} y1={y1} x2={x2} y2={y2} stroke="currentColor" strokeWidth="1.5" className="text-primary" />
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
