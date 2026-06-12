"use client";

import { useCallback, useState, type ReactNode } from "react";
import { cn } from "@/lib/utils";

type CopyCommandProps = {
  value: string;
  label?: string;
  className?: string;
  children?: ReactNode;
};

export function CopyCommand({
  value,
  label = "Copy command",
  className,
  children,
}: CopyCommandProps) {
  const [copied, setCopied] = useState(false);

  const copy = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(value);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1800);
    } catch {
      /* clipboard unavailable */
    }
  }, [value]);

  return (
    <button
      type="button"
      onClick={copy}
      aria-label={copied ? "Copied to clipboard" : label}
      className={cn(
        "group relative inline-flex items-center gap-3 text-left transition-colors",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/60 focus-visible:ring-offset-2 focus-visible:ring-offset-background",
        className,
      )}
    >
      {children}
      <span
        aria-hidden
        className={cn(
          "font-mono text-[10px] uppercase tracking-widest transition-all duration-200",
          copied
            ? "text-green-500"
            : "text-muted-foreground opacity-0 group-hover:opacity-100 group-focus-visible:opacity-100",
        )}
      >
        {copied ? "copied ✓" : "copy"}
      </span>
    </button>
  );
}
