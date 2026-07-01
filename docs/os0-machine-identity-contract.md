# OS.0 machine identity contract

Last audited: 2026-07-01.

## Contract

The canonical CursiveRoot machine key is the full-test hardware fingerprint:

```text
machine_id = sha256(HW_ID_TUPLE + "\n").hexdigest()[:16]
fingerprint_version = 2
```

`HW_ID_TUPLE` is:

```text
CPU_MODEL|BOARD_VENDOR|BOARD_NAME|GPU_PCI_IDS
```

The newline is intentional. `cursiveos-full-test-v1.4.sh` computes the value with:

```bash
echo "$HW_ID_TUPLE" | sha256sum | cut -c1-16
```

`tools/contributor_daemon.py` must mirror that byte contract through `full_test_fingerprint(text)` so daemon heartbeats/jobs join to wrapper-generated runs and seed bundles.

## Canonical founder-fleet ids

| physical machine | canonical machine_id | evidence |
| --- | --- | --- |
| Elizabeth Lenovo laptop / Linux Mint bare-metal test host | `42e7c7257af11f46` | daemon v2 capability row + wrapper v2 runs |
| Stardust Ryzen/Arc Linux rig | `3e6b165ddf112a75` | wrapper v2 machine row + historical aliases |

## Live alias rows verified

These aliases currently exist in CursiveRoot and are safe to collapse onto their canonical machine:

| alias | canonical machine_id | alias_kind | source / reason |
| --- | --- | --- | --- |
| `7ba4f665a3bb4fb8` | `42e7c7257af11f46` | `daemon_pre_b52df82_no_newline_fingerprint` | contributor daemon hash bug fixed by `b52df82`; no-newline daemon hash |
| `7be9d01858b242a2` | `42e7c7257af11f46` | `rebuild_fingerprint` | curated rebuild-era laptop fingerprint |
| `1c63d2a53cfb98d0` | `42e7c7257af11f46` | `legacy_fingerprint_v1` | wrapper legacy v1 fingerprint |
| `11th-gen-intelr-coretm-i5-11300h--310ghz-elizabe` | `42e7c7257af11f46` | `legacy_slug` | early slug-style laptop id |
| `bda4bd63b3564822` | `3e6b165ddf112a75` | `rebuild_fingerprint` | curated Stardust rebuild fingerprint |
| `768a2e818376d96b` | `3e6b165ddf112a75` | `legacy_fingerprint_v1` | wrapper legacy v1 fingerprint |
| `amd-ryzen-7-5700-vega` | `3e6b165ddf112a75` | `legacy_slug` | early slug-style Stardust Ryzen/Arc id |

## Explicit non-backfill

`amd-fxtm-8350-eight-core-processor-stardust` remains a standalone historical AMD FX host id for now.

Reason: the live audit found one machine row and 28 run rows for that id, but no verified fingerprint-v2 canonical target. Do **not** collapse it into the current Stardust Ryzen/Arc id without evidence that it is the same physical host. It is safer to preserve it as a separate historical machine until a raw artifact, operator note, or fresh v2 fingerprint proves a target.

## Regression coverage

`tests/test_identity_contract.py` locks the Sprint 1 contract:

- wrapper and daemon both hash `HW_ID_TUPLE + "\n"`
- the Lenovo tuple resolves to `42e7c7257af11f46`
- the old daemon no-newline hash does not become canonical
- dashboard alias logic maps old ids to canonical ids
- dashboard physical-machine count excludes alias rows
- daemon capability heartbeats collapse by canonical machine
- only `claimed` and `running` jobs count as active queue work
