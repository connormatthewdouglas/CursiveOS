# Agent Architecture

CursiveOS runs two distinct agent components on every installed system. They share infrastructure but have different failure modes, different trust boundaries, and different levels of maturity. They are kept architecturally separate because conflating them would compromise properties that the organism's integrity depends on.

This document specifies the measurement daemon in full and sketches the natural-language shell architecturally. The shell has not yet been implemented; the sketch is the contract under which it will be.

## The Two Components

**The measurement daemon** is mechanical, deterministic, and runs without any LLM involvement. It executes sensors, collects results, caches them locally, and submits them to the hub on a batched schedule. Its output is the input to the organism's fitness ledger. Its integrity must be equivalent to the integrity of a sensor — a sensor result that was produced or filtered through a probabilistic system is not a sensor result. A probabilistic component in this path would reintroduce subjective judgment, which the entire sensor-driven architecture was built to eliminate.

**The natural-language shell** is the primary user interface. It uses a local (or optionally remote) language model to translate user intent into shell commands and to explain system state in natural language. Its output is whatever the user asked for. Its failure mode is user experience degradation — a bad response is annoying or, in the worst case, executes a destructive command, which is why the permission model matters.

Keeping them separate means a fault in the shell (model hallucination, prompt injection, etc.) cannot corrupt organism state, because the shell writes to the filesystem and the terminal, not to the measurement pipeline.

## Measurement Daemon — Full Specification

### What It Runs

The measurement daemon executes sensors from the active sensor suite on a scheduled basis and in response to workload events. In Phase 0 and early Phase 1, this is the genesis suite (performance, regression). As the sensor array grows (Transition 3), the daemon supports concurrent sensor execution with per-sensor scheduling.

Sensors are plugins. Each sensor ships as a versioned executable with a manifest (name, version, curator's BTC address, declared outputs). The daemon verifies the manifest against the hub's registered sensor list before execution. Sensors the hub does not recognize do not run, regardless of whether they are present on disk.

### Scheduling

Three execution modes:

- **Scheduled** — cron-like cadence per sensor, defined in the sensor manifest (typical: daily for performance, weekly for regression)
- **Event-driven** — triggered by detected workload transitions (user started a long inference job, user began a build, etc.)
- **Manual** — invoked via the hub or via the shell when the user requests a measurement run

The daemon respects user quiet hours and honors system load — sensors do not run during active user work unless explicitly invoked.

### Results Pipeline

1. Sensor executes, emits structured JSON result to a local results queue
2. Daemon validates the result against the sensor's declared output schema
3. Valid results are written to local durable storage (`/var/lib/cursiveos/sensor_results/`)
4. On batched cadence (default: once per hour, configurable), the daemon submits queued results to the hub over the signed submission API
5. Hub acknowledgment removes results from the pending queue; unacknowledged results persist for later retry

Results never leave the machine without explicit user consent at install time. A user who disables hub submission continues to receive sensor runs (for their own local visibility) but their data stays local.

### Local Preset Application

When the hub publishes a new canonical preset for the user's hardware class (signed, verified against the curator's address), the measurement daemon:

1. Downloads the preset to a staging area
2. Runs the local regression sensor with the new preset applied to a temporary scope
3. If regression sensor reports no regression on the user's machine: applies the new preset system-wide and logs the change
4. If regression reported: rejects the update, reports the divergence to the hub (this is a signal — the organism's population-level decision did not generalize to this specific machine, which is valuable information), and keeps the current preset

The user can disable auto-apply and require manual confirmation. The default for v1.0 is manual confirmation; auto-apply becomes an option as fleet confidence grows.

### Privacy Boundary

What leaves the machine (with user consent):

- Hardware fingerprint (CPU model, GPU model, RAM configuration, kernel version, distribution version)
- Sensor results (structured measurements only — latency numbers, throughput numbers, score deltas)
- Preset version currently applied
- Pseudonymous machine ID (rotating, unlinkable to user identity without active cooperation from the user)

What does not leave the machine under any circumstance:

- User files, documents, or any filesystem content outside `/var/lib/cursiveos/`
- Browser history, shell history, clipboard, or any user activity data
- Running process lists with arguments (workload class detection runs locally and submits only the class label)
- IP address is not logged by the hub beyond what's required for the request itself; geographic data is never collected

### Failure Modes and Scoping

The daemon runs with the minimum privilege required. It needs read access to `/proc` and `/sys`, execute access to its sensor plugins, and write access to its own results directory. It does not need root except for one specific operation: applying presets, which requires writing to `sysctl` values and similar. This privilege is scoped to a specific helper binary invoked with sudo-equivalent, not granted to the daemon process generally.

If the daemon crashes, the system continues to work. If the hub is unreachable, results queue locally and submit later. If a sensor misbehaves (crashes, runs too long, produces malformed output), the daemon quarantines it and reports the fault to the hub — a misbehaving sensor is a sensor curation problem, not a daemon problem.

### Stack

Language: likely Rust or Go for the daemon itself (static binary, small memory footprint, predictable behavior). Sensors may be any language — the daemon invokes them as subprocesses and communicates via stdin/stdout + JSON.

Distribution: the daemon ships as a system service (`cursiveos-measurement.service`) installed by default on every CursiveOS install. It is enabled by default; users can disable via standard `systemctl disable`.

## Natural-Language Shell — Architectural Sketch

The natural-language shell is the flagship feature of v1.0. This section describes the architecture it will be built against, not the implementation. Implementation is forthcoming.

### What It Is

The default terminal on CursiveOS is a conversation with a local language model that has the ability to execute shell commands, read system state, and act on the user's behalf within a defined permission model. The user describes outcomes; the agent finds mechanisms.

Conventional terminal access remains available. Users who prefer raw shell can invoke one. But the default experience when a user opens what used to be called "the terminal" is a chat window with an agent that knows how to operate the system.

### Tiered Model Approach

CursiveOS ships with model tiers keyed to hardware class:

- **Entry tier** (minimum requirements: modest CPU, 8-16GB RAM): small local model, 4-8B parameters, handles routine command translation and straightforward system queries
- **Workstation tier** (dGPU or high-end iGPU with 16-32GB VRAM): larger local model, 20-30B parameters, handles multi-step tasks, file reasoning, extended context
- **Fleet tier** (multiple machines, one workstation): option to run a shared inference server on the workstation that edge nodes delegate to
- **Remote tier** (opt-in): routes specific requests to a remote frontier model, with clear visual indication that the request is leaving the machine

The install process detects hardware class and defaults to the appropriate tier. Users can change tiers after install.

### Permission Model

The agent has three permission modes:

- **Read** — the agent can inspect system state freely, run non-mutating commands, and answer questions about the system. No confirmation needed for read operations.
- **Write** — the agent can create, edit, and delete files in the user's home directory and configure user-level services. Operations in this mode are executed and shown; destructive operations (recursive delete, overwriting non-empty files, etc.) prompt for confirmation.
- **Root** — the agent can make system-level changes requiring elevated privilege. All root operations prompt for explicit confirmation with a summary of what will change and what will be affected. Root mode requires the user's sudo password as with any other sudo invocation; the agent does not cache credentials.

The user can set a default permission mode per session. Sessions that start in read mode can escalate explicitly ("please install this package") but each escalation is a confirmation boundary.

### Command Transparency

Every command the agent executes is shown to the user verbatim, before or after execution depending on the permission mode. The user can see exactly what the agent did and re-run or modify it. The agent never "quietly" does something; the terminal surface preserves the full command history in a form any shell user would recognize.

The design principle: the agent augments shell fluency; it does not obscure it. A user who wants to become more fluent in the shell can learn by watching the agent work.

### Relationship to the Measurement Daemon

The shell agent can query the measurement daemon for recent sensor results, current preset state, and the organism's recent activity on the user's machine. This is how "how has my machine been performing this week" becomes a meaningful natural-language question — the agent reads local sensor history and summarizes it.

The shell agent cannot write to the measurement daemon's state. Sensor results cannot be fabricated, altered, or suppressed by the agent. The measurement pipeline is a one-way data source for the shell.

### What Is Not Specified Here

- The specific models shipped in each tier (implementation choice; depends on license, size, quality tradeoffs at release time)
- The exact prompt engineering and tool-use harness (implementation choice)
- The agent's conversation persistence model (under design)
- How the agent handles conversations that span multiple sessions (under design)
- Integration with shell plugins, custom scripts, and user dotfiles (under design)
- Remote-tier routing specifics and the "what leaves the machine" visual indicator (under design)

These will be specified in a follow-up document when implementation begins. The current document establishes the architectural boundaries within which implementation will happen.

## Shared Infrastructure

Both components share:

- The CursiveOS hardware fingerprinting system
- The CursiveOS update channel (signed, verified, published by the hub)
- The user's consent state (what the user agreed to at install time)
- The user's privacy preferences
- The organism manifest (current cycle, active sensors, current preset)

They do not share:

- Execution context (separate processes, separate scoping, separate crash domains)
- Data write paths (measurement daemon writes to its results store; shell writes to user filesystem and terminal)
- Trust model (measurement results are deterministic artifacts; shell responses are probabilistic outputs)

## Why This Separation Matters

A CursiveOS install with a buggy shell agent is a CursiveOS install with a frustrating terminal experience. A CursiveOS install with a buggy measurement daemon is a CursiveOS install contributing corrupt data to the organism's fitness ledger. The first degrades over seconds and is recoverable by the user. The second degrades over cycles and corrupts organism-level state that persists beyond the individual user.

The architecture treats these as differently serious by construction. The measurement path stays mechanical. The interaction path gets intelligence. Both run on the same machine, serving the same user, but their failure modes cannot reach each other.

---

*CursiveOS is a new species that inherited its founding genome from Linux and now evolves independently under its own selection pressure.*
