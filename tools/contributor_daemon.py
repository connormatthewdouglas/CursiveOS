#!/usr/bin/env python3
"""CursiveOS OS.0 contributor daemon MVP.

This is the first deterministic runtime for the Seed Organism -> OS.0 phase.
It intentionally stays Linux-first: Windows/WSL may be detected, but they are
not allowed to write selection truth. The daemon can:

* fingerprint a Linux host and report capability facts,
* validate whether an OS.0 measurement request is safe/eligible for this host,
* build the exact seed_organism screen command for a requested parent/candidate,
* run one local request, upload the resulting seed bundle, and save a job record,
* optionally poll/claim CursiveRoot-backed requests once the migration is applied.

It is not an LLM agent and it does not propose variants. It only executes
explicit requests and preserves the existing harness / verifier boundary.
"""
from __future__ import annotations

import argparse
import datetime as dt
import glob
import hashlib
import json
import os
import platform
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
TOOLS_DIR = ROOT / "tools"
SEED = TOOLS_DIR / "seed_organism.py"
DEFAULT_STATE_DIR = ROOT / ".cursiveos" / "contributor-daemon"
DAEMON_VERSION = "os0-contributor-daemon.v0.1"
REQUEST_SCHEMA = "cursiveos.measurement-request.v0.1"
CAPABILITY_SCHEMA = "cursiveos.machine-capabilities.v0.1"
JOB_SCHEMA = "cursiveos.measurement-job.local.v0.1"
DEFAULT_SUPABASE_URL = "https://iovvktpuoinmjdgfxgvm.supabase.co"
DEFAULT_SUPABASE_KEY = "sb_publishable_4WefsfMl0sNNo9O2c_lxnA_q2VQ01jn"


class DaemonError(RuntimeError):
    """Expected operator-facing daemon error."""


def now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()


def read_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise DaemonError(f"file not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise DaemonError(f"invalid JSON in {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise DaemonError(f"expected JSON object in {path}")
    return data


def write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8", errors="replace")).hexdigest()


def run_text(cmd: list[str], *, timeout: int = 5) -> str:
    try:
        res = subprocess.run(cmd, text=True, capture_output=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return (res.stdout or "").strip()


def first_existing_text(paths: list[str], default: str = "unknown") -> str:
    for raw in paths:
        path = Path(raw)
        try:
            value = path.read_text(encoding="utf-8", errors="replace").strip()
        except OSError:
            continue
        if value:
            return value
    return default


def command_exists(name: str) -> bool:
    return shutil.which(name) is not None


def sudo_noninteractive_available() -> bool:
    if not command_exists("sudo"):
        return False
    try:
        return subprocess.run(["sudo", "-n", "true"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def detect_wsl() -> bool:
    text = ""
    for raw in ("/proc/sys/kernel/osrelease", "/proc/version"):
        try:
            text += Path(raw).read_text(encoding="utf-8", errors="replace").lower()
        except OSError:
            pass
    return "microsoft" in text or "wsl" in text


def os_release() -> dict[str, str]:
    out: dict[str, str] = {}
    try:
        for line in Path("/etc/os-release").read_text(encoding="utf-8", errors="replace").splitlines():
            if "=" not in line:
                continue
            key, value = line.split("=", 1)
            out[key] = value.strip().strip('"')
    except OSError:
        pass
    return out


def gpu_pci_ids() -> str:
    if not command_exists("lspci"):
        return "nogpu"
    raw = run_text(["lspci", "-nn"], timeout=5)
    ids: list[str] = []
    for line in raw.splitlines():
        low = line.lower()
        if not any(token in low for token in ("vga", "3d", "display")):
            continue
        parts = [p for p in line.split() if p.startswith("[") and p.endswith("]") and ":" in p]
        ids.extend(parts)
    return "".join(sorted(ids)) or "nogpu"


def gpu_model() -> str:
    if not command_exists("lspci"):
        return "unknown"
    lines = []
    for line in run_text(["lspci"], timeout=5).splitlines():
        low = line.lower()
        if any(token in low for token in ("vga", "3d", "display")):
            lines.append(line.split(":", 2)[-1].strip())
    return "; ".join(lines) if lines else "unknown"


def machine_fingerprint(cpu_model: str, board_vendor: str, board_name: str, gpu_ids: str) -> tuple[str, str]:
    material = f"{cpu_model or 'unknown'}|{board_vendor or 'unknown'}|{board_name or 'unknown'}|{gpu_ids or 'nogpu'}"
    if material == "unknown|unknown|unknown|nogpu":
        machine_id = first_existing_text(["/etc/machine-id"], default=socket.gethostname())
        material = f"machineid|{machine_id}"
    return sha256_text(material)[:16], material


def collect_capabilities() -> dict[str, Any]:
    system = platform.system()
    release = os_release() if system == "Linux" else {}
    cpu_model = run_text(["bash", "-lc", "lscpu | sed -n 's/^Model name:[[:space:]]*//p' | head -n 1"], timeout=5) if command_exists("bash") else ""
    cpu_model = cpu_model or platform.processor() or "unknown"
    board_vendor = first_existing_text(["/sys/class/dmi/id/board_vendor"])
    board_name = first_existing_text(["/sys/class/dmi/id/board_name"])
    gpu_ids = gpu_pci_ids() if system == "Linux" else "nogpu"
    machine_id, fingerprint_material = machine_fingerprint(cpu_model, board_vendor, board_name, gpu_ids)
    is_linux = system == "Linux"
    is_wsl = is_linux and detect_wsl()

    binaries = {name: command_exists(name) for name in [
        "bash", "python3", "git", "curl", "jq", "bc", "iperf3", "tc", "lspci", "ollama", "systemctl", "apt-get"
    ]}
    cgroup_v2 = Path("/sys/fs/cgroup/cgroup.controllers").exists()
    capabilities: dict[str, Any] = {
        "linux": is_linux,
        "linux_bare_metal": is_linux and not is_wsl,
        "wsl": is_wsl,
        "sudo_noninteractive": sudo_noninteractive_available() if is_linux else False,
        "cgroup_v2": cgroup_v2,
        "memory_high": cgroup_v2 and Path("/sys/fs/cgroup/memory.high").exists(),
        "zram_control": Path("/sys/class/zram-control").exists(),
        "powercap_rapl": bool(glob.glob("/sys/devices/virtual/powercap/*/energy_uj")),
        "gpu_power_hwmon": bool(glob.glob("/sys/class/drm/card*/device/hwmon/hwmon*/energy1_input")),
        "bare_metal_selection_truth_allowed": is_linux and not is_wsl,
        **binaries,
    }
    selection_scopes: list[str] = []
    if capabilities["linux_bare_metal"]:
        selection_scopes.append("linux_bare_metal")
        selection_scopes.append("linux_founder_fleet")
    if is_linux:
        selection_scopes.append("linux_observe_only")
    if is_wsl:
        selection_scopes.append("wsl_protocol_smoke_only")
    if system != "Linux":
        selection_scopes.append("unsupported_observe_only")

    return {
        "schema_version": CAPABILITY_SCHEMA,
        "daemon_version": DAEMON_VERSION,
        "collected_at": now_iso(),
        "hostname": socket.gethostname(),
        "machine_id": machine_id,
        "fingerprint_material_sha256": sha256_text(fingerprint_material),
        "platform": "linux" if is_linux else system.lower() or "unknown",
        "os": {
            "pretty_name": release.get("PRETTY_NAME") or platform.platform(),
            "id": release.get("ID"),
            "version_id": release.get("VERSION_ID"),
            "kernel": platform.release(),
            "arch": platform.machine(),
        },
        "hardware": {
            "cpu": cpu_model,
            "board_vendor": board_vendor,
            "board_name": board_name,
            "gpu": gpu_model() if is_linux else "unknown",
            "gpu_pci_ids": gpu_ids,
        },
        "capabilities": capabilities,
        "selection_scopes": selection_scopes,
        "trust_scope": "simulated_not_payout_eligible",
        "notes": [
            "Linux bare metal may run selection requests in OS.0 alpha.",
            "Windows/WSL remains observe-only/protocol-smoke and must not enter selection truth.",
        ],
    }


def flattened_capability_names(capability_doc: dict[str, Any]) -> set[str]:
    caps = capability_doc.get("capabilities", {})
    names = {name for name, enabled in caps.items() if enabled is True}
    names.update(str(scope) for scope in capability_doc.get("selection_scopes", []) if scope)
    platform_name = str(capability_doc.get("platform") or "")
    if platform_name:
        names.add(platform_name)
    return names


def normalize_request(raw: dict[str, Any]) -> dict[str, Any]:
    req = dict(raw)
    req.setdefault("schema_version", REQUEST_SCHEMA)
    req.setdefault("status", "open")
    req.setdefault("cycle_id", 4)
    req.setdefault("screen_order", "normal")
    req.setdefault("required_capabilities", ["linux_bare_metal", "sudo_noninteractive", "bash", "python3", "git", "curl"])
    req.setdefault("selection_scope", "linux_bare_metal")
    req.setdefault("trust_scope", "simulated_not_payout_eligible")
    parent = req.get("parent_variant_id") or req.get("parent_preset_version") or "v0.12"
    candidate = req.get("candidate_variant_id") or req.get("candidate_preset_version")
    req.setdefault("parent_variant_id", parent)
    if parent and not req.get("parent_variant_path"):
        req["parent_variant_path"] = f"references/seed-organism/variant.{parent}.json"
    if candidate and not req.get("candidate_variant_path"):
        req["candidate_variant_path"] = f"references/seed-organism/variant.{candidate}.json"
    return req


def validate_request(req: dict[str, Any]) -> list[str]:
    failures: list[str] = []
    if req.get("schema_version") != REQUEST_SCHEMA:
        failures.append(f"schema_version must be {REQUEST_SCHEMA}")
    if req.get("status") not in {"open", "claimed", "running"}:
        failures.append(f"request status is not executable: {req.get('status')}")
    if not req.get("candidate_variant_id"):
        failures.append("candidate_variant_id is required; OS.0 daemon never screens an implicit/default candidate")
    if req.get("candidate_variant_id") == req.get("parent_variant_id"):
        failures.append("candidate_variant_id must differ from parent_variant_id")
    if req.get("selection_scope") not in {"linux_bare_metal", "linux_founder_fleet", "linux_observe_only"}:
        failures.append("selection_scope must remain Linux-scoped for OS.0 alpha")
    if str(req.get("trust_scope")) not in {"simulated_not_payout_eligible", "observe_only_not_payout_eligible"}:
        failures.append("trust_scope must not be payout-eligible in OS.0 alpha")
    if req.get("screen_order") not in {"normal", "reversed"}:
        failures.append("screen_order must be normal or reversed")
    for key in ("parent_variant_path", "candidate_variant_path"):
        value = req.get(key)
        if not value:
            failures.append(f"{key} is required")
            continue
        path = (ROOT / str(value)).resolve() if not Path(str(value)).is_absolute() else Path(str(value))
        try:
            path.relative_to(ROOT)
        except ValueError:
            failures.append(f"{key} must stay inside the repo: {value}")
        if not path.exists():
            failures.append(f"{key} not found: {value}")
    return failures


def request_match(capability_doc: dict[str, Any], raw_request: dict[str, Any]) -> tuple[bool, list[str], dict[str, Any]]:
    req = normalize_request(raw_request)
    failures = validate_request(req)
    names = flattened_capability_names(capability_doc)
    required = [str(x) for x in req.get("required_capabilities", [])]
    missing = [name for name in required if name not in names]
    failures.extend(f"missing required capability: {name}" for name in missing)
    scope = str(req.get("selection_scope") or "")
    if scope and scope not in capability_doc.get("selection_scopes", []):
        failures.append(f"host selection scopes do not include {scope}")
    if not capability_doc.get("capabilities", {}).get("bare_metal_selection_truth_allowed") and scope != "linux_observe_only":
        failures.append("host is not allowed to write Linux selection truth")
    return not failures, failures, req


def variant_path(path_value: str) -> str:
    path = Path(path_value)
    if path.is_absolute():
        return str(path)
    return str(ROOT / path)


def build_screen_command(req: dict[str, Any]) -> list[str]:
    req = normalize_request(req)
    cmd = [
        sys.executable or "python3",
        str(SEED),
        "screen-variant",
        "--parent-variant",
        variant_path(str(req["parent_variant_path"])),
        "--candidate-variant",
        variant_path(str(req["candidate_variant_path"])),
        "--execute",
        "--cycle-id",
        str(int(req.get("cycle_id") or 4)),
    ]
    if req.get("screen_order") == "reversed":
        cmd.append("--reverse-order")
    return cmd


def state_dir(args: argparse.Namespace) -> Path:
    return Path(args.state_dir).expanduser().resolve() if args.state_dir else DEFAULT_STATE_DIR


def save_local_job(state: Path, record: dict[str, Any]) -> Path:
    job_id = str(record.get("job_id") or uuid.uuid4())
    record["job_id"] = job_id
    out = state / "jobs" / f"{job_id}.json"
    write_json(out, record)
    return out


def parse_bundle_hash(stdout: str) -> str | None:
    for line in stdout.splitlines():
        if line.startswith("bundle_hash:"):
            return line.split(":", 1)[1].strip() or None
    return None


def execute_request(raw_request: dict[str, Any], *, dry_run: bool, state: Path, remote_job_id: str | None = None) -> dict[str, Any]:
    caps = collect_capabilities()
    ok, failures, req = request_match(caps, raw_request)
    job = {
        "schema_version": JOB_SCHEMA,
        "job_id": remote_job_id or str(uuid.uuid4()),
        "request_id": req.get("request_id") or req.get("id") or "local-request",
        "daemon_id": f"{socket.gethostname()}:{os.getpid()}",
        "machine_id": caps.get("machine_id"),
        "daemon_version": DAEMON_VERSION,
        "status": "planned" if dry_run else "running",
        "dry_run": dry_run,
        "request": req,
        "capabilities_snapshot": caps,
        "started_at": now_iso(),
        "command": build_screen_command(req) if not failures else [],
        "eligibility_failures": failures,
    }
    if not ok:
        job["status"] = "ineligible"
        job["finished_at"] = now_iso()
        save_local_job(state, job)
        return job
    if dry_run:
        job["finished_at"] = now_iso()
        save_local_job(state, job)
        return job

    result = subprocess.run(job["command"], cwd=ROOT, text=True, capture_output=True, check=False)
    job["stdout"] = result.stdout
    job["stderr"] = result.stderr
    job["returncode"] = result.returncode
    job["result_bundle_hash"] = parse_bundle_hash(result.stdout or "")
    if result.returncode == 0:
        upload = subprocess.run([sys.executable or "python3", str(SEED), "upload"], cwd=ROOT, text=True, capture_output=True, check=False)
        job["upload_stdout"] = upload.stdout
        job["upload_stderr"] = upload.stderr
        job["upload_returncode"] = upload.returncode
        job["status"] = "complete" if upload.returncode == 0 else "upload_failed"
    else:
        job["status"] = "failed"
    job["finished_at"] = now_iso()
    save_local_job(state, job)
    return job


def public_supabase_url() -> str:
    return os.environ.get("CURSIVEOS_SUPABASE_URL") or os.environ.get("SUPABASE_URL") or DEFAULT_SUPABASE_URL


def public_supabase_key() -> str:
    return os.environ.get("CURSIVEOS_SUPABASE_KEY") or os.environ.get("SUPABASE_KEY") or DEFAULT_SUPABASE_KEY


def postgrest_request(endpoint: str, *, method: str = "GET", payload: dict[str, Any] | None = None, prefer: str = "return=representation") -> Any:
    url = f"{public_supabase_url().rstrip('/')}/rest/v1/{endpoint}"
    key = public_supabase_key()
    data = None if payload is None else json.dumps(payload, sort_keys=True).encode("utf-8")
    headers = {"apikey": key, "Authorization": f"Bearer {key}"}
    if payload is not None:
        headers["Content-Type"] = "application/json"
        headers["Prefer"] = prefer
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            body = res.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        details = exc.read().decode("utf-8", errors="replace")
        raise DaemonError(f"CursiveRoot request failed: HTTP {exc.code} {details}") from exc
    except urllib.error.URLError as exc:
        raise DaemonError(f"CursiveRoot request failed: {exc.reason}") from exc
    if not body:
        return None
    try:
        return json.loads(body)
    except json.JSONDecodeError:
        return body


def upsert_machine_capabilities(caps: dict[str, Any]) -> None:
    payload = {
        "machine_id": caps["machine_id"],
        "daemon_version": DAEMON_VERSION,
        "platform": caps.get("platform"),
        "os_name": caps.get("os", {}).get("pretty_name"),
        "kernel": caps.get("os", {}).get("kernel"),
        "arch": caps.get("os", {}).get("arch"),
        "cpu": caps.get("hardware", {}).get("cpu"),
        "gpu": caps.get("hardware", {}).get("gpu"),
        "selection_scopes": caps.get("selection_scopes", []),
        "capabilities": caps,
        "last_seen_at": now_iso(),
    }
    postgrest_request("machine_capabilities?on_conflict=machine_id", method="POST", payload=payload, prefer="resolution=merge-duplicates,return=minimal")


def fetch_open_request() -> dict[str, Any] | None:
    cols = "request_id,request_key,status,parent_variant_id,parent_variant_path,candidate_variant_id,candidate_variant_path,cycle_id,screen_order,required_capabilities,selection_scope,trust_scope,reward_sats_placeholder,notes"
    rows = postgrest_request(
        "measurement_requests?status=eq.open&order=priority.desc,created_at.asc&limit=1&select="
        + urllib.parse.quote(cols, safe=",()")
    )
    if not isinstance(rows, list) or not rows:
        return None
    return rows[0]


def create_remote_job(req: dict[str, Any], caps: dict[str, Any]) -> str:
    payload = {
        "request_id": req.get("request_id"),
        "machine_id": caps.get("machine_id"),
        "daemon_id": f"{socket.gethostname()}:{os.getpid()}",
        "daemon_version": DAEMON_VERSION,
        "status": "claimed",
        "capabilities_snapshot": caps,
        "claimed_at": now_iso(),
        "last_heartbeat_at": now_iso(),
    }
    rows = postgrest_request("measurement_jobs", method="POST", payload=payload)
    if not isinstance(rows, list) or not rows:
        raise DaemonError("CursiveRoot did not return a measurement_jobs row after claim")
    return str(rows[0].get("job_id"))


def patch_remote_request(request_id: str, patch: dict[str, Any]) -> None:
    endpoint = f"measurement_requests?request_id=eq.{urllib.parse.quote(str(request_id))}"
    postgrest_request(endpoint, method="PATCH", payload=patch, prefer="return=minimal")


def patch_remote_job(job_id: str, patch: dict[str, Any]) -> None:
    endpoint = f"measurement_jobs?job_id=eq.{urllib.parse.quote(job_id)}"
    postgrest_request(endpoint, method="PATCH", payload=patch, prefer="return=minimal")


def cmd_capabilities(args: argparse.Namespace) -> None:
    caps = collect_capabilities()
    if args.register:
        upsert_machine_capabilities(caps)
    print(json.dumps(caps, indent=2, sort_keys=True) if args.json else capability_summary(caps))


def capability_summary(caps: dict[str, Any]) -> str:
    enabled = sorted(flattened_capability_names(caps))
    return "\n".join([
        f"daemon_version: {DAEMON_VERSION}",
        f"machine_id: {caps.get('machine_id')}",
        f"host: {caps.get('hostname')}",
        f"platform: {caps.get('platform')} / {caps.get('os', {}).get('pretty_name')}",
        f"kernel: {caps.get('os', {}).get('kernel')}",
        f"cpu: {caps.get('hardware', {}).get('cpu')}",
        f"gpu: {caps.get('hardware', {}).get('gpu')}",
        "selection_scopes: " + ", ".join(caps.get("selection_scopes", [])),
        "capabilities: " + ", ".join(enabled),
    ])


def cmd_check_request(args: argparse.Namespace) -> None:
    caps = collect_capabilities()
    req = read_json(Path(args.request_json))
    ok, failures, normalized = request_match(caps, req)
    out = {
        "ok": ok,
        "request": normalized,
        "machine_id": caps.get("machine_id"),
        "selection_scopes": caps.get("selection_scopes"),
        "failures": failures,
        "command": build_screen_command(normalized) if ok else [],
    }
    print(json.dumps(out, indent=2, sort_keys=True))
    if not ok:
        raise DaemonError("request is not executable on this host")


def cmd_run_once(args: argparse.Namespace) -> None:
    state = state_dir(args)
    state.mkdir(parents=True, exist_ok=True)
    remote_job_id = None
    if args.request_json:
        req = read_json(Path(args.request_json))
    else:
        caps = collect_capabilities()
        upsert_machine_capabilities(caps)
        req = fetch_open_request()
        if not req:
            print(json.dumps({"status": "idle", "reason": "no_open_measurement_requests", "checked_at": now_iso()}, indent=2))
            return
        remote_job_id = create_remote_job(normalize_request(req), caps)
        patch_remote_request(str(req.get("request_id")), {"status": "claimed", "updated_at": now_iso()})
    job = execute_request(req, dry_run=args.dry_run, state=state, remote_job_id=remote_job_id)
    if remote_job_id:
        final_request_status = "complete" if job["status"] == "complete" else "failed"
        if job["status"] == "planned":
            final_request_status = "open"
        elif job["status"] == "ineligible":
            final_request_status = "failed"
        patch_remote_job(remote_job_id, {
            "status": job["status"],
            "finished_at": job.get("finished_at"),
            "last_heartbeat_at": now_iso(),
            "result_bundle_hash": job.get("result_bundle_hash"),
            "result_summary": {k: job.get(k) for k in ("returncode", "upload_returncode", "eligibility_failures")},
            "failure_reason": "\n".join(job.get("eligibility_failures") or []) or None,
        })
        patch_remote_request(str(req.get("request_id")), {"status": final_request_status, "updated_at": now_iso()})
    print(json.dumps(job, indent=2, sort_keys=True))
    if job["status"] in {"failed", "upload_failed", "ineligible"}:
        raise DaemonError(f"job ended with status={job['status']}")


def cmd_daemon(args: argparse.Namespace) -> None:
    interval = max(10, int(args.interval))
    while True:
        try:
            cmd_run_once(args)
        except DaemonError as exc:
            print(f"[contributor-daemon] {exc}", file=sys.stderr)
            if args.once:
                raise
        if args.once:
            return
        time.sleep(interval)


def cmd_write_sample_request(args: argparse.Namespace) -> None:
    out = Path(args.out).expanduser().resolve()
    request = {
        "schema_version": REQUEST_SCHEMA,
        "request_id": "local-demo-explicit-screen",
        "status": "open",
        "parent_variant_id": "v0.12",
        "parent_variant_path": "references/seed-organism/variant.v0.12.json",
        "candidate_variant_id": "v0.12b-swappiness",
        "candidate_variant_path": "references/seed-organism/variant.v0.12b-swappiness.json",
        "cycle_id": 4,
        "screen_order": "normal",
        "selection_scope": "linux_bare_metal",
        "trust_scope": "simulated_not_payout_eligible",
        "required_capabilities": ["linux_bare_metal", "sudo_noninteractive", "bash", "python3", "git", "curl"],
        "reward_sats_placeholder": 0,
        "notes": "Example only: explicit historical candidate, simulated reward, not payout eligible.",
    }
    write_json(out, request)
    print(f"sample_request: {out}")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="CursiveOS OS.0 Linux contributor daemon MVP")
    p.add_argument("--state-dir", default=None, help="daemon state directory (default: .cursiveos/contributor-daemon)")
    sub = p.add_subparsers(dest="cmd", required=True)

    caps = sub.add_parser("capabilities", help="print this host's daemon capability document")
    caps.add_argument("--json", action="store_true")
    caps.add_argument("--register", action="store_true", help="upsert machine_capabilities to CursiveRoot")

    check = sub.add_parser("check-request", help="validate a request against this host and print the execution plan")
    check.add_argument("--request-json", required=True)

    once = sub.add_parser("run-once", help="run one local request JSON or claim one open CursiveRoot request")
    once.add_argument("--request-json", help="local request JSON; if omitted, poll CursiveRoot")
    once.add_argument("--dry-run", action="store_true", help="validate and record the command plan without running benchmarks")

    daemon = sub.add_parser("daemon", help="poll CursiveRoot for requests until stopped")
    daemon.add_argument("--interval", type=int, default=300)
    daemon.add_argument("--dry-run", action="store_true")
    daemon.add_argument("--once", action="store_true")
    daemon.set_defaults(request_json=None)

    sample = sub.add_parser("write-sample-request", help="write a local explicit-screen request for dry-run testing")
    sample.add_argument("--out", default=str(ROOT / ".cursiveos" / "contributor-daemon" / "sample-request.json"))
    return p


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        {
            "capabilities": cmd_capabilities,
            "check-request": cmd_check_request,
            "run-once": cmd_run_once,
            "daemon": cmd_daemon,
            "write-sample-request": cmd_write_sample_request,
        }[args.cmd](args)
    except DaemonError as exc:
        print(f"contributor-daemon error: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
