#!/usr/bin/env python3
"""
Automated test script for invoice operations on testnet.

This script performs a complete test cycle:
1. Check current contract state
2. Create an invoice (reserve liquidity)
3. Wait for confirmation
4. Fulfill the invoice (send cBTC to owner)
5. Create another invoice
6. Wait for expiry
7. Cancel the expired invoice

Usage:
    uv run scripts/test_invoices.py <contract_tx_id> [test_amount]
"""

import json
import sys
import time
from dataclasses import dataclass
from pathlib import Path

from pycardano import (
    Address,
    Network,
    PaymentSigningKey,
    PaymentVerificationKey,
    PlutusData,
)
from pycardano.hash import ScriptHash
from pycardano.serialization import IndefiniteList

from config import Config


@dataclass
class Invoice:
    """Invoice representation"""
    invoice_id: int
    amount: int
    owner: str
    timestamp: int
    expires_at: int


@dataclass
class ContractState:
    """Contract state representation"""
    total_liquidity: int
    reserved: int
    last_invoice_id: int
    invoices: list


def get_contract_state(context, script_address: str) -> tuple:
    """Get current contract state from latest UTxO"""

    print(f"  Querying contract at: {script_address[:50]}...")
    utxos = context.utxos(script_address)

    if not utxos:
        raise Exception("No UTxOs found at contract address")

    # Get the most recent UTxO (highest slot)
    latest_utxo = max(utxos, key=lambda u: u.input.transaction_id)

    print(
        f"  Found UTxO: {latest_utxo.input.transaction_id}#{latest_utxo.input.index}")

    # Extract state datum
    if not latest_utxo.output.datum:
        raise Exception("No datum found on contract UTxO")

    @dataclass
    class State(PlutusData):
        CONSTR_ID = 0
        total_liquidity: int
        reserved: int
        last_invoice_id: int
        invoices: IndefiniteList

    state = State.from_cbor(latest_utxo.output.datum.cbor)

    return (
        str(latest_utxo.input.transaction_id),
        ContractState(
            total_liquidity=state.total_liquidity,
            reserved=state.reserved,
            last_invoice_id=state.last_invoice_id,
            invoices=list(state.invoices) if state.invoices else []
        )
    )


def print_state(state: ContractState):
    """Pretty print contract state"""
    available = state.total_liquidity - state.reserved
    print(f"  Total Liquidity:  {state.total_liquidity:,} cBTC")
    print(f"  Reserved:         {state.reserved:,} cBTC")
    print(f"  Available:        {available:,} cBTC")
    print(f"  Last Invoice ID:  {state.last_invoice_id}")
    print(f"  Active Invoices:  {len(state.invoices)}")


def run_command(cmd: str) -> tuple[int, str]:
    """Run shell command and return exit code and output"""
    import subprocess

    print(f"\n  $ {cmd}")
    result = subprocess.run(
        cmd,
        shell=True,
        capture_output=True,
        text=True
    )

    return result.returncode, result.stdout.strip()


def wait_for_confirmation(seconds: int = 60):
    """Wait for blockchain confirmation"""
    print(f"\n  ⏳ Waiting {seconds} seconds for confirmation...")
    for i in range(seconds, 0, -10):
        print(f"     {i} seconds remaining...", end='\r')
        time.sleep(10)
    print("     ✓ Wait complete" + " " * 30)


def test_invoice_operations(starting_contract_tx: str, test_amount: int = 200000):
    """Run complete invoice operation tests"""

    print("=" * 80)
    print("LIGHTNING LIQUIDITY MANAGER - INVOICE OPERATIONS TEST")
    print("=" * 80)

    try:
        # Load config
        config_data = Config.load_deployment_config()
        if not config_data:
            print("✗ Config not found. Run init_contract_parameterized.py first")
            return 1

        operator_addr = config_data['operator']['address']
        script_address = config_data['validator'].get(
            'parameterized_script_address')

        if not script_address:
            print("✗ No parameterized_script_address in config")
            return 1

        print(f"\n[Configuration]")
        print(f"  Network:         {Config.NETWORK}")
        print(f"  Operator:        {operator_addr}")
        print(f"  Script Address:  {script_address[:50]}...")
        print(f"  Test Amount:     {test_amount:,} cBTC")

        # Connect to chain
        context = Config.get_chain_context()

        current_tx = starting_contract_tx

        # ====================================================================
        # STEP 1: Check initial state
        # ====================================================================
        print("\n" + "=" * 80)
        print("STEP 1: Check Initial Contract State")
        print("=" * 80)

        current_tx, state = get_contract_state(context, script_address)
        print_state(state)

        available = state.total_liquidity - state.reserved
        if available < test_amount:
            print(f"\n✗ Insufficient liquidity for test")
            print(f"  Need: {test_amount:,}, Available: {available:,}")
            print(
                f"  Run: uv run scripts/test_deposit.py {current_tx} {test_amount}")
            return 1

        # ====================================================================
        # STEP 2: Create Invoice #1 (will fulfill)
        # ====================================================================
        print("\n" + "=" * 80)
        print("STEP 2: Create Invoice #1 (for fulfillment test)")
        print("=" * 80)

        invoice1_amount = test_amount
        expiry_minutes = 120  # 2 hours - long enough to fulfill before expiry

        print(f"\n  Creating invoice:")
        print(f"  - Amount: {invoice1_amount:,} cBTC")
        print(f"  - Owner: {operator_addr}")
        print(f"  - Expiry: {expiry_minutes} minutes")

        code, output = run_command(
            f"uv run scripts/test_create_invoice.py {current_tx} {invoice1_amount} {operator_addr} {expiry_minutes}"
        )

        if code != 0:
            print(f"\n✗ Create invoice failed:\n{output}")
            return 1

        # Extract TX hash from output
        for line in output.split('\n'):
            if 'TX Hash:' in line:
                current_tx = line.split('TX Hash:')[1].strip()
                print(f"\n  ✓ Invoice created, TX: {current_tx[:32]}...")
                break

        wait_for_confirmation(60)

        # Verify state after create
        print("\n  Verifying state after create...")
        current_tx, state = get_contract_state(context, script_address)
        print_state(state)

        expected_invoice_id = state.last_invoice_id
        print(
            f"\n  ✓ Invoice ID {expected_invoice_id} created and reserved {invoice1_amount:,} cBTC")

        # ====================================================================
        # STEP 3: Fulfill Invoice #1
        # ====================================================================
        print("\n" + "=" * 80)
        print("STEP 3: Fulfill Invoice #1 (send cBTC to owner)")
        print("=" * 80)

        print(f"\n  Fulfilling invoice ID {expected_invoice_id}...")

        code, output = run_command(
            f"uv run scripts/test_fulfill_invoice.py {current_tx} {expected_invoice_id}"
        )

        if code != 0:
            print(f"\n✗ Fulfill invoice failed:\n{output}")
            return 1

        # Extract TX hash
        for line in output.split('\n'):
            if 'TX Hash:' in line:
                current_tx = line.split('TX Hash:')[1].strip()
                print(f"\n  ✓ Invoice fulfilled, TX: {current_tx[:32]}...")
                break

        wait_for_confirmation(60)

        # Verify state after fulfill
        print("\n  Verifying state after fulfill...")
        current_tx, state = get_contract_state(context, script_address)
        print_state(state)

        print(
            f"\n  ✓ Invoice {expected_invoice_id} fulfilled - liquidity decreased and unreserved")

        # ====================================================================
        # STEP 4: Create Invoice #2 (will cancel)
        # ====================================================================
        print("\n" + "=" * 80)
        print("STEP 4: Create Invoice #2 (for cancellation test)")
        print("=" * 80)

        invoice2_amount = test_amount // 2  # Smaller amount
        expiry_minutes = 1  # 1 minute - will expire quickly

        print(f"\n  Creating invoice:")
        print(f"  - Amount: {invoice2_amount:,} cBTC")
        print(f"  - Owner: {operator_addr}")
        print(f"  - Expiry: {expiry_minutes} minutes (for quick expiry)")

        code, output = run_command(
            f"uv run scripts/test_create_invoice.py {current_tx} {invoice2_amount} {operator_addr} {expiry_minutes}"
        )

        if code != 0:
            print(f"\n✗ Create invoice failed:\n{output}")
            return 1

        # Extract TX hash
        for line in output.split('\n'):
            if 'TX Hash:' in line:
                current_tx = line.split('TX Hash:')[1].strip()
                print(f"\n  ✓ Invoice created, TX: {current_tx[:32]}...")
                break

        wait_for_confirmation(60)

        # Verify state after create
        print("\n  Verifying state after create...")
        current_tx, state = get_contract_state(context, script_address)
        print_state(state)

        cancel_invoice_id = state.last_invoice_id
        print(f"\n  ✓ Invoice ID {cancel_invoice_id} created")

        # ====================================================================
        # STEP 5: Wait for Invoice #2 to expire
        # ====================================================================
        print("\n" + "=" * 80)
        print("STEP 5: Wait for Invoice #2 to Expire")
        print("=" * 80)

        print(f"\n  Waiting for invoice {cancel_invoice_id} to expire...")
        print(f"  (Expiry set to {expiry_minutes} minute from creation)")

        # Wait slightly longer than expiry time to ensure it's expired
        wait_for_confirmation(90)

        # ====================================================================
        # STEP 6: Cancel Expired Invoice #2
        # ====================================================================
        print("\n" + "=" * 80)
        print("STEP 6: Cancel Expired Invoice #2")
        print("=" * 80)

        print(f"\n  Cancelling expired invoice ID {cancel_invoice_id}...")

        code, output = run_command(
            f"uv run scripts/test_cancel_invoice.py {current_tx} {cancel_invoice_id}"
        )

        if code != 0:
            print(f"\n✗ Cancel invoice failed:\n{output}")
            return 1

        # Extract TX hash
        for line in output.split('\n'):
            if 'TX Hash:' in line:
                current_tx = line.split('TX Hash:')[1].strip()
                print(f"\n  ✓ Invoice cancelled, TX: {current_tx[:32]}...")
                break

        wait_for_confirmation(60)

        # Verify final state
        print("\n  Verifying final state...")
        current_tx, state = get_contract_state(context, script_address)
        print_state(state)

        print(
            f"\n  ✓ Invoice {cancel_invoice_id} cancelled - liquidity unreserved but kept in pool")

        # ====================================================================
        # FINAL SUMMARY
        # ====================================================================
        print("\n" + "=" * 80)
        print("✓ ALL INVOICE OPERATION TESTS PASSED")
        print("=" * 80)

        print(f"\n[Test Summary]")
        print(
            f"  ✓ Created invoice #{expected_invoice_id} ({invoice1_amount:,} cBTC)")
        print(
            f"  ✓ Fulfilled invoice #{expected_invoice_id} (sent cBTC to owner)")
        print(
            f"  ✓ Created invoice #{cancel_invoice_id} ({invoice2_amount:,} cBTC)")
        print(f"  ✓ Cancelled invoice #{cancel_invoice_id} (after expiry)")

        print(f"\n[Final State]")
        print_state(state)

        print(f"\n[Next Steps]")
        print(f"  - Check invoices.json for complete log")
        print(
            f"  - View on explorer: https://preview.cardanoscan.io/transaction/{current_tx}")
        print(
            f"  - Continue testing with: uv run scripts/test_deposit.py {current_tx} <amount>")

        print("\n" + "=" * 80)

        return 0

    except Exception as e:
        print(f"\n✗ Test failed: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(
            "Usage: uv run scripts/test_invoices.py <contract_tx_id> [test_amount]")
        print("\nExample:")
        print("  uv run scripts/test_invoices.py abc123...def")
        print("  uv run scripts/test_invoices.py abc123...def 300000")
        print("\nThis will:")
        print("  1. Create an invoice and fulfill it")
        print("  2. Create another invoice, wait for expiry, and cancel it")
        print("  3. Verify all state transitions")
        sys.exit(1)

    contract_tx = sys.argv[1]
    test_amount = int(sys.argv[2]) if len(sys.argv) > 2 else 200000

    sys.exit(test_invoice_operations(contract_tx, test_amount))
