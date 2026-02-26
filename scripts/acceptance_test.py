#!/usr/bin/env python3
"""
Acceptance Test: Execute ≥5 deposits and ≥5 withdrawals
This script performs the v0.1.0 acceptance criteria for transaction testing.

Usage:
    uv run scripts/acceptance_test_transactions.py <initial_contract_tx_id>
"""

import json
import sys
import time
from pathlib import Path

from pycardano import (
    Address,
)

from config import Config


def run_command(cmd: str) -> tuple[int, str]:
    """Run shell command and return exit code and output"""
    import subprocess

    print(f"\n$ {cmd}")
    result = subprocess.run(
        cmd,
        shell=True,
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        print(f"ERROR: {result.stderr}")

    return result.returncode, result.stdout.strip()


def extract_tx_hash(output: str) -> str:
    """Extract transaction hash from script output"""
    for line in output.split('\n'):
        if 'TX Hash:' in line:
            return line.split('TX Hash:')[1].strip()
    return None


def get_contract_state(context, script_address: str) -> dict:
    """Query current contract state"""
    from pycardano import PlutusData
    from pycardano.serialization import IndefiniteList
    from dataclasses import dataclass

    @dataclass
    class State(PlutusData):
        CONSTR_ID = 0
        total_liquidity: int
        reserved: int
        last_invoice_id: int
        invoices: IndefiniteList
        last_offramp_id: int
        offramps: IndefiniteList

    utxos = context.utxos(script_address)
    if not utxos:
        raise Exception("No UTxOs found at contract address")

    latest_utxo = max(utxos, key=lambda u: u.input.transaction_id)

    if not latest_utxo.output.datum:
        raise Exception("No datum found on contract UTxO")

    state = State.from_cbor(latest_utxo.output.datum.cbor)

    return {
        "tx_id": str(latest_utxo.input.transaction_id),
        "total_liquidity": state.total_liquidity,
        "reserved": state.reserved,
        "available": state.total_liquidity - state.reserved,
        "last_invoice_id": state.last_invoice_id,
        "active_invoices": len(list(state.invoices))
    }


def wait_for_confirmation(seconds: int = 90):
    """Wait for blockchain confirmation"""
    print(f"\n⏳ Waiting {seconds} seconds for confirmation...")
    for i in range(seconds, 0, -10):
        print(f"   {i} seconds remaining...", end='\r')
        time.sleep(10)
    print("   ✓ Confirmed" + " " * 30)


def run_acceptance_test(starting_tx_id: str):
    """Run acceptance test for ≥5 deposits and ≥5 withdrawals"""

    print("=" * 80)
    print("ACCEPTANCE TEST: ≥5 DEPOSITS AND ≥5 WITHDRAWALS")
    print("=" * 80)

    # Load config
    config_data = Config.load_deployment_config()
    if not config_data:
        print("✗ Config not found")
        return 1

    script_address = config_data['validator'].get(
        'parameterized_script_address')
    if not script_address:
        print("✗ No parameterized_script_address in config")
        return 1

    print(f"\nNetwork:        {Config.NETWORK}")
    print(f"Script Address: {script_address}")
    print(f"Starting TX:    {starting_tx_id}\n")

    # Connect to chain
    context = Config.get_chain_context()

    # Track all transactions
    results = {
        "deposits": [],
        "withdrawals": [],
        "states": []
    }

    current_tx = starting_tx_id

    # Define test amounts
    deposit_amounts = [100000, 150000, 200000, 250000, 300000]  # 5 deposits
    withdrawal_amounts = [80000, 100000,
                          120000, 150000, 180000]  # 5 withdrawals

    # ========================================================================
    # PHASE 1: EXECUTE 5 DEPOSITS
    # ========================================================================
    print("=" * 80)
    print("PHASE 1: EXECUTE 5 DEPOSITS")
    print("=" * 80)

    for i, amount in enumerate(deposit_amounts, 1):
        print(f"\n{'─' * 80}")
        print(f"DEPOSIT #{i}: {amount:,} cBTC")
        print(f"{'─' * 80}")

        # Get state before
        state_before = get_contract_state(context, script_address)
        print(f"\nBefore Deposit #{i}:")
        print(f"  Total Liquidity: {state_before['total_liquidity']:,} cBTC")
        print(f"  Reserved:        {state_before['reserved']:,} cBTC")
        print(f"  Available:       {state_before['available']:,} cBTC")

        # Execute deposit
        cmd = f"uv run scripts/test_deposit.py {current_tx} {amount}"
        code, output = run_command(cmd)

        if code != 0:
            print(f"\n✗ Deposit #{i} failed")
            print(output)
            return 1

        # Extract TX hash
        tx_hash = extract_tx_hash(output)
        if not tx_hash:
            print(f"\n✗ Could not extract TX hash from deposit #{i}")
            return 1

        print(f"\n✓ Deposit #{i} succeeded")
        print(f"  TX Hash: {tx_hash}")
        print(
            f"  Explorer: {Config.get_explorer_url(str(tx_hash))}")

        current_tx = tx_hash

        # Wait for confirmation
        wait_for_confirmation(90)

        # Get state after
        state_after = get_contract_state(context, script_address)
        print(f"\nAfter Deposit #{i}:")
        print(f"  Total Liquidity: {state_after['total_liquidity']:,} cBTC")
        print(f"  Reserved:        {state_after['reserved']:,} cBTC")
        print(f"  Available:       {state_after['available']:,} cBTC")
        print(f"  Change:          +{amount:,} cBTC")

        # Verify balance increased correctly
        expected_liquidity = state_before['total_liquidity'] + amount
        if state_after['total_liquidity'] != expected_liquidity:
            print(
                f"\n✗ Balance mismatch! Expected {expected_liquidity:,}, got {state_after['total_liquidity']:,}")
            return 1

        # Record result
        results["deposits"].append({
            "number": i,
            "amount": amount,
            "tx_hash": tx_hash,
            "explorer_url": Config.get_explorer_url(str(tx_hash)),
            "before_liquidity": state_before['total_liquidity'],
            "after_liquidity": state_after['total_liquidity']
        })

        print(f"\n✓ Balance updated correctly")

    # ========================================================================
    # PHASE 2: EXECUTE 5 WITHDRAWALS
    # ========================================================================
    print("\n" + "=" * 80)
    print("PHASE 2: EXECUTE 5 WITHDRAWALS")
    print("=" * 80)

    for i, amount in enumerate(withdrawal_amounts, 1):
        print(f"\n{'─' * 80}")
        print(f"WITHDRAWAL #{i}: {amount:,} cBTC")
        print(f"{'─' * 80}")

        # Get state before
        state_before = get_contract_state(context, script_address)
        print(f"\nBefore Withdrawal #{i}:")
        print(f"  Total Liquidity: {state_before['total_liquidity']:,} cBTC")
        print(f"  Reserved:        {state_before['reserved']:,} cBTC")
        print(f"  Available:       {state_before['available']:,} cBTC")

        # Check sufficient available liquidity
        if amount > state_before['available']:
            print(f"\n✗ Insufficient available liquidity for withdrawal #{i}")
            print(
                f"  Requested: {amount:,}, Available: {state_before['available']:,}")
            return 1

        # Execute withdrawal
        cmd = f"uv run scripts/test_withdraw.py {current_tx} {amount}"
        code, output = run_command(cmd)

        if code != 0:
            print(f"\n✗ Withdrawal #{i} failed")
            print(output)
            return 1

        # Extract TX hash
        tx_hash = extract_tx_hash(output)
        if not tx_hash:
            print(f"\n✗ Could not extract TX hash from withdrawal #{i}")
            return 1

        print(f"\n✓ Withdrawal #{i} succeeded")
        print(f"  TX Hash: {tx_hash}")
        print(
            f"  Explorer: {Config.get_explorer_url(str(tx_hash))}")

        current_tx = tx_hash

        # Wait for confirmation
        wait_for_confirmation(90)

        # Get state after
        state_after = get_contract_state(context, script_address)
        print(f"\nAfter Withdrawal #{i}:")
        print(f"  Total Liquidity: {state_after['total_liquidity']:,} cBTC")
        print(f"  Reserved:        {state_after['reserved']:,} cBTC")
        print(f"  Available:       {state_after['available']:,} cBTC")
        print(f"  Change:          -{amount:,} cBTC")

        # Verify balance decreased correctly
        expected_liquidity = state_before['total_liquidity'] - amount
        if state_after['total_liquidity'] != expected_liquidity:
            print(
                f"\n✗ Balance mismatch! Expected {expected_liquidity:,}, got {state_after['total_liquidity']:,}")
            return 1

        # Record result
        results["withdrawals"].append({
            "number": i,
            "amount": amount,
            "tx_hash": tx_hash,
            "explorer_url": Config.get_explorer_url(str(tx_hash)),
            "before_liquidity": state_before['total_liquidity'],
            "after_liquidity": state_after['total_liquidity']
        })

        print(f"\n✓ Balance updated correctly")

    # ========================================================================
    # FINAL SUMMARY
    # ========================================================================
    print("\n" + "=" * 80)
    print("✓ ACCEPTANCE TEST PASSED")
    print("=" * 80)

    print(f"\n[DEPOSITS - {len(results['deposits'])} transactions]")
    total_deposited = 0
    for d in results["deposits"]:
        total_deposited += d['amount']
        print(f"  #{d['number']}: {d['amount']:,} cBTC")
        print(f"         TX: {d['tx_hash']}")
        print(f"         URL: {d['explorer_url']}")

    print(f"\n  Total Deposited: {total_deposited:,} cBTC")

    print(f"\n[WITHDRAWALS - {len(results['withdrawals'])} transactions]")
    total_withdrawn = 0
    for w in results["withdrawals"]:
        total_withdrawn += w['amount']
        print(f"  #{w['number']}: {w['amount']:,} cBTC")
        print(f"         TX: {w['tx_hash']}")
        print(f"         URL: {w['explorer_url']}")

    print(f"\n  Total Withdrawn: {total_withdrawn:,} cBTC")

    # Get final state
    final_state = get_contract_state(context, script_address)
    print(f"\n[FINAL CONTRACT STATE]")
    print(f"  Total Liquidity: {final_state['total_liquidity']:,} cBTC")
    print(f"  Reserved:        {final_state['reserved']:,} cBTC")
    print(f"  Available:       {final_state['available']:,} cBTC")
    print(f"  Net Change:      {total_deposited - total_withdrawn:+,} cBTC")

    # Save results to file
    results_file = Config.CREDENTIALS_DIR / "acceptance_test_results.json"
    with open(results_file, 'w') as f:
        json.dump({
            "test_date": time.strftime("%Y-%m-%d %H:%M:%S UTC", time.gmtime()),
            "network": Config.NETWORK,
            "script_address": script_address,
            "summary": {
                "deposits_count": len(results['deposits']),
                "withdrawals_count": len(results['withdrawals']),
                "total_deposited": total_deposited,
                "total_withdrawn": total_withdrawn,
                "net_change": total_deposited - total_withdrawn
            },
            "deposits": results['deposits'],
            "withdrawals": results['withdrawals'],
            "final_state": final_state
        }, f, indent=2)

    print(f"\n[RESULTS SAVED]")
    print(f"  File: {results_file}")

    print("\n" + "=" * 80)
    print("✓ All requirements met:")
    print(f"  ✓ {len(results['deposits'])} deposits executed successfully")
    print(
        f"  ✓ {len(results['withdrawals'])} withdrawals executed successfully")
    print("  ✓ All balances updated correctly")
    print("  ✓ All TX hashes recorded")
    print("=" * 80 + "\n")

    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(
            "Usage: uv run scripts/acceptance_test_transactions.py <initial_contract_tx_id>")
        print("\nExample:")
        print("  uv run scripts/acceptance_test_transactions.py abc123...def")
        print("\nThis will execute:")
        print("  - 5 deposits (100K, 150K, 200K, 250K, 300K cBTC)")
        print("  - 5 withdrawals (80K, 100K, 120K, 150K, 180K cBTC)")
        print("  - Verify all balance changes")
        print("  - Save results to acceptance_test_results.json")
        sys.exit(1)

    starting_tx = sys.argv[1]
    sys.exit(run_acceptance_test(starting_tx))
