# Operator Onboarding Draft — Frosty (Pilot)

Operator profile
- Name/handle: Frosty
- Machine: gaming PC
- Contact: cmdouglas84@gmail.com

Purpose
- Validate that onboarding is clear for a real operator.
- Run one controlled pilot cycle with clean logging.

---

## Message draft (email-ready)

Subject: CursiveOS Pilot Invite — 15 Minute Setup (Frosty)

Hey Frosty —

You’re invited to a small controlled CursiveOS pilot.

What this does:
- Runs safe benchmark tests
- Uses reversible settings
- Sends performance results (not personal files) to CursiveRoot

Time needed:
- ~15 minutes first run

Step 1) Clone and run

```bash
git clone https://github.com/connormatthewdouglas/CursiveOS.git 2>/dev/null; git -C ~/CursiveOS pull --ff-only 2>/dev/null || echo "Local changes detected"; chmod +x ~/CursiveOS/cursiveos-full-test-v1.4.sh; cd ~/CursiveOS && bash cursiveos-full-test-v1.4.sh
```

Step 2) Confirm completion
- You should see benchmark output and run summary.
- Reply with: "Run complete" + screenshot of final summary section.

Step 3) Safety check
- Optional immediate rollback test:

```bash
cd ~/CursiveOS && bash presets/cursiveos-presets-v0.7.sh --undo
```

What to report back:
1) Did run complete? (yes/no)
2) Any warnings/errors shown?
3) Did machine feel stable after run?
4) Would you run again? (yes/no)

Thanks — this is a controlled pilot and your feedback directly improves safety + clarity.

---

## Internal checklist (Copper)
- [ ] Send invite
- [ ] Receive completion confirmation
- [ ] Record operator status in contributor ledger
- [ ] Schedule next run window (repeat behavior test)
