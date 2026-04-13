#!/usr/bin/env python3
"""Initialize the liquidity manager contract with parameterized validator"""

import json
import sys
import subprocess
from pathlib import Path
from dataclasses import dataclass

from pycardano import (
    Address,

    Network,
    PaymentSigningKey,
    PlutusData,
    PlutusV3Script,
    TransactionBuilder,
    TransactionOutput,
    Value,
    MultiAsset,
    Asset,
    AssetName,
)
from pycardano.hash import ScriptHash
from pycardano.serialization import IndefiniteList

from config import Config


@dataclass
class State(PlutusData):
    """Contract state datum"""
    CONSTR_ID = 0
    total_liquidity: int
    reserved: int
    last_invoice_id: int
    invoices: IndefiniteList
    last_offramp_id: int
    offramps: IndefiniteList


@dataclass
class ConfigParam(PlutusData):
    """Config parameter for the validator - simplified (no script_address)"""
    CONSTR_ID = 0
    lm_pkh: bytes
    cbtc_policy: bytes
    cbtc_name: bytes


def apply_validator_parameters(config_data: dict) -> str:
    """Apply parameters to validator using Aiken CLI"""

    operator_pkh = bytes.fromhex(config_data["operator"]["pkh"])
    cbtc_policy = bytes.fromhex(config_data["token"]["cbtc_policy"])
    cbtc_asset_name = bytes.fromhex(config_data["token"]["cbtc_asset_name"])

    print(f"→ Creating Config parameter...")
    print(f"  Operator PKH:    {config_data['operator']['pkh']}")
    print(f"  cBTC Policy:     {config_data['token']['cbtc_policy']}")
    print(f"  cBTC Asset:      {config_data['token']['cbtc_asset_name']}")

    # Simplified Config - no script_address needed!
    config_param = ConfigParam(
        lm_pkh=operator_pkh,
        cbtc_policy=cbtc_policy,
        cbtc_name=cbtc_asset_name,
    )

    # Get CBOR hex
    cbor_hex = config_param.to_cbor_hex()
    if cbor_hex.startswith('0x'):
        cbor_hex = cbor_hex[2:]

    print(f"  Config CBOR length: {len(cbor_hex)} chars")
    print(f"  Config CBOR (hex): {cbor_hex}")

    output_file = str(Path(__file__).resolve().parent.parent / "plutus-applied.json")
    input_file = str(Config.PLUTUS_FILE)

    # Run aiken blueprint apply
    cmd = [
        "aiken",
        "blueprint", "apply",
        "-i", input_file,
        "-o", output_file,
        "-m", "liquidity_manager",
        "-v", "liquidity_manager",
        cbor_hex
    ]

    print(f"\n→ Running aiken blueprint apply...")
    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print(f"✗ Command failed!")
        print(f"STDOUT: {result.stdout}")
        print(f"STDERR: {result.stderr}")
        raise Exception("Failed to apply parameters")

    print(f"✓ Parameters applied successfully")
    print(f"  Output: {output_file}")

    return output_file


def read_parameterized_validator(plutus_file: str) -> dict:
    """Load the parameterized validator"""
    with open(plutus_file, "r") as f:
        validator = json.load(f)

    spend_validator = None
    for v in validator["validators"]:
        if "spend" in v.get("title", ""):
            spend_validator = v
            break

    if not spend_validator:
        raise ValueError("Spend validator not found")

    script_hex = spend_validator["compiledCode"]
    script = PlutusV3Script(bytes.fromhex(script_hex))
    script_hash = ScriptHash(bytes.fromhex(spend_validator["hash"]))

    return {
        "script": script,
        "script_hash": script_hash,
    }


def init_contract(initial_cbtc: int = 10_000_000) -> int:
    """Initialize contract with parameterized validator"""
    print("=" * 70)
    print("Initializing Liquidity Manager Contract (Parameterized)")
    print("=" * 70)

    try:
        # Load config
        config_data = Config.load_deployment_config()
        if not config_data:
            print("✗ Config not found. Run 'uv run scripts/deploy.py' first")
            return 1

        operator_addr = config_data['operator']['address']
        sk_file = config_data['operator']['sk_file']
        cbtc_policy = config_data['token']['cbtc_policy']
        cbtc_asset_name = bytes.fromhex(
            config_data['token']['cbtc_asset_name'])

        # Step 1: Apply parameters to validator
        print(f"\n[1/5] Applying parameters to validator...")
        applied_plutus_file = apply_validator_parameters(config_data)

        # Step 2: Load the parameterized validator
        print(f"\n[2/5] Loading parameterized validator...")
        validator = read_parameterized_validator(applied_plutus_file)

        script_address = Address(
            payment_part=validator["script_hash"],
            network=Network.TESTNET,
        )

        print(f"  ✓ Validator loaded")
        print(f"  Script hash: {validator['script_hash']}")
        print(f"  Script address: {script_address}")

        # Update config with parameterized address
        config_data['validator']['parameterized_script_hash'] = str(
            validator["script_hash"])
        config_data['validator']['parameterized_script_address'] = str(
            script_address)
        Config.save_deployment_config(config_data)

        # Step 3: Connect to chain
        print(f"\n[3/5] Connecting to {Config.NETWORK} network...")
        context = Config.get_chain_context()

        # Load keys
        signing_key = PaymentSigningKey.load(sk_file)
        address = Address.from_primitive(operator_addr)

        # Step 4: Build transaction
        print(f"\n[4/5] Building transaction...")
        print(f"  Initial cBTC: {initial_cbtc:,}")

        # Create initial state
        initial_state = State(
            total_liquidity=initial_cbtc,
            reserved=0,
            last_invoice_id=0,
            invoices=IndefiniteList([]),
            last_offramp_id=0,
            offramps=IndefiniteList([]),
        )

        # Create value with cBTC tokens
        asset_name = AssetName(cbtc_asset_name)
        my_asset = Asset({asset_name: initial_cbtc})
        multi_asset = MultiAsset(
            {ScriptHash.from_primitive(cbtc_policy): my_asset})

        # Build transaction
        builder = TransactionBuilder(context)
        builder.add_input_address(address)

        # Add output to script address with datum
        builder.add_output(
            TransactionOutput(
                address=script_address,
                amount=Value(coin=2_000_000, multi_asset=multi_asset),
                datum=initial_state,
            )
        )

        # Step 5: Sign and submit
        print(f"\n[5/5] Signing and submitting...")
        signed_tx = builder.build_and_sign(
            signing_keys=[signing_key],
            change_address=address,
        )

        context.submit_tx(signed_tx)
        tx_hash = signed_tx.id

        print(f"\n" + "=" * 70)
        print(f"✓ CONTRACT INITIALIZED SUCCESSFULLY")
        print(f"=" * 70)
        print(f"TX Hash:           {tx_hash}")
        print(f"Script Address:    {script_address}")
        print(f"Initial Liquidity: {initial_cbtc:,} cBTC")
        print(
            f"Explorer:          {Config.get_explorer_url(str(tx_hash))}")
        print(f"\n⏳ Wait 30-60 seconds, then test:")
        print(f"   uv run scripts/test_deposit.py {tx_hash} 100000")
        print(f"=" * 70)

        return 0

    except Exception as e:
        print(f"\n✗ Initialization failed: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    initial_amount = int(sys.argv[1]) if len(sys.argv) > 1 else 10_000_000
    sys.exit(init_contract(initial_amount))
