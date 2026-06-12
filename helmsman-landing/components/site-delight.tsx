"use client";

import { useEffect, useState } from "react";

const CONTEXTS = [
  { name: "prod-cluster", cluster: "prod.k8s.internal" },
  { name: "staging", cluster: "stg.k8s.internal" },
  { name: "local-kind", cluster: "kind-local" },
  { name: "docker-desktop", cluster: "docker-desktop" },
] as const;

export function TerminalPanel() {
  const [active, setActive] = useState(0);
  const [bootLine, setBootLine] = useState("$ open helmsman");

  useEffect(() => {
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduced) return;

    const line = "$ open helmsman";
    setBootLine("");
    let i = 0;
    const id = window.setInterval(() => {
      i += 1;
      setBootLine(line.slice(0, i));
      if (i >= line.length) window.clearInterval(id);
    }, 42);
    return () => window.clearInterval(id);
  }, []);

  return (
    <div className="rounded-lg border border-border bg-card overflow-hidden shadow-lg bold-terminal-glow">
      <div className="flex items-center gap-2 border-b border-border px-4 py-3 bg-muted/20">
        <span className="h-2.5 w-2.5 rounded-full bg-red-500/60" />
        <span className="h-2.5 w-2.5 rounded-full bg-yellow-500/60" />
        <span className="h-2.5 w-2.5 rounded-full bg-green-500/60" />
        <span className="ml-3 font-mono text-[10px] text-muted-foreground">
          kubectl config get-contexts
        </span>
      </div>
      <div className="p-5 font-mono text-[11px] space-y-1">
        <p className="text-muted-foreground">CURRENT   NAME                  CLUSTER</p>
        <div className="mt-2 space-y-1.5">
          {CONTEXTS.map((ctx, index) => {
            const isActive = index === active;
            return (
              <button
                key={ctx.name}
                type="button"
                onClick={() => setActive(index)}
                className="group block w-full rounded px-1 py-0.5 text-left transition-colors hover:bg-primary/10 focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-primary/50"
              >
                <span className={isActive ? "text-primary" : "text-foreground/60 group-hover:text-foreground/80"}>
                  {isActive ? "*" : " "}&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
                  {ctx.name.padEnd(22)}
                  {ctx.cluster}
                </span>
              </button>
            );
          })}
        </div>
        <div className="mt-6 pt-4 border-t border-border space-y-1">
          <p className="text-muted-foreground">
            # click a context — Helmsman switches instantly.
          </p>
          <p className="text-primary min-h-[1.25em]">
            {bootLine}
            <span className="text-green-500 motion-cursor" aria-hidden="true">
              ▊
            </span>
          </p>
        </div>
      </div>
    </div>
  );
}

export function ScrollProgress() {
  const [progress, setProgress] = useState(0);
  const [enabled, setEnabled] = useState(true);

  useEffect(() => {
    setEnabled(!window.matchMedia("(prefers-reduced-motion: reduce)").matches);
  }, []);

  useEffect(() => {
    if (!enabled) return;

    const onScroll = () => {
      const doc = document.documentElement;
      const max = doc.scrollHeight - doc.clientHeight;
      setProgress(max > 0 ? doc.scrollTop / max : 0);
    };

    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, [enabled]);

  if (!enabled) return null;

  return (
    <div
      aria-hidden
      className="pointer-events-none fixed inset-x-0 top-0 z-[60] h-[2px] bg-border/40"
    >
      <div
        className="h-full origin-left bg-primary shadow-[0_0_12px_oklch(0.7049_0.1867_47.6044/0.8)] transition-transform duration-150 ease-out"
        style={{ transform: `scaleX(${progress})` }}
      />
    </div>
  );
}

export function DevConsoleEasterEgg() {
  useEffect(() => {
    const art = [
      "Helmsman // native macOS Kubernetes manager",
      "Like what you see? github.com/hashir-ayaz/helmsman",
      "Tip: your kubeconfig already works. No agents. No signup.",
    ];
    console.info(art.join("\n"));
  }, []);

  return null;
}
