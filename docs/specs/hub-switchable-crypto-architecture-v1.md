# Hub Switchable Crypto Architecture v1

Date: 2026-04-03
Owner: Copper Sage

Goal: build MVP in internal credits now, but make it easy to flip to real crypto rails later.

## Principle
Separate "economic decision engine" from "payment rail execution".

- Engine (already built): determines who earns/loses what.
- Rail (switchable): how value moves (internal credits now, on-chain later).

## Rail modes
1) internal_credits (current)
- source of truth: l5_credit_ledger
- no on-chain transfer

2) crypto_testnet (next)
- ledger still source of truth
- payout events enqueue transfer intents
- signer executes testnet transfers
- tx hash stored back in DB

3) crypto_mainnet (later)
- same flow as testnet with stricter controls

## Required table extension (next pass)
Add payout transfer tracking table:
- payout_id
- ledger_event_id
- rail_mode
- destination_wallet
- amount
- chain
- tx_status (queued/submitted/confirmed/failed)
- tx_hash
- retries
- last_error
- created_at/updated_at

## MVP decision
Do not block Hub MVP on chain integration.
Ship with internal_credits rail but keep interfaces compatible with testnet/mainnet.

## Security controls for future crypto flip
- signing key never in browser
- transfer worker runs server-side only
- per-cycle max payout cap
- manual emergency pause switch
- full audit trail in l5_admin_actions + transfer logs

## User experience requirement
Hub should always show:
- reward earned (engine output)
- payout status (queued/confirmed)
- rail mode badge (internal / testnet / mainnet)

This keeps trust while transitioning rails.
