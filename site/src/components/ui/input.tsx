import type { InputHTMLAttributes, ReactNode, SelectHTMLAttributes, TextareaHTMLAttributes } from "react";
import { cn } from "@/lib/cn";

const field =
  "h-11 w-full rounded-md border border-border bg-bg-elevated px-3 text-sm text-fg placeholder:text-subtle";

export function Input({ className, ...props }: InputHTMLAttributes<HTMLInputElement>) {
  return <input className={cn(field, className)} {...props} />;
}

export function Textarea({ className, ...props }: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return (
    <textarea
      className={cn(
        "min-h-24 w-full rounded-md border border-border bg-bg-elevated px-3 py-2 text-sm text-fg placeholder:text-subtle",
        className,
      )}
      {...props}
    />
  );
}

export function Select({ className, ...props }: SelectHTMLAttributes<HTMLSelectElement>) {
  return <select className={cn(field, className)} {...props} />;
}

export function Label({
  className,
  children,
  htmlFor,
}: {
  className?: string;
  children: ReactNode;
  htmlFor?: string;
}) {
  return (
    <label htmlFor={htmlFor} className={cn("mb-1.5 block text-xs font-medium text-muted", className)}>
      {children}
    </label>
  );
}
