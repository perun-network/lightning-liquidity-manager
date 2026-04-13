from pathlib import Path
#!/usr/bin/env python3
"""Test deposit transaction - parameterized validator version"""

import json
import sys
from dataclasses import dataclass

from pycardano import (
    Address,
    Network,
    PaymentSigningKey,
    PaymentVerificationKey,
    PlutusData,
    PlutusV3Script,
    Redeemer,
    TransactionBuilder,
    TransactionOutput,
    UTxO,
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
class DepositRedeemer(PlutusData):
    """Deposit redeemer (Action::Deposit)"""
    CONSTR_ID = 0
    amount: int


def read_parameterized_validator() -> dict:
    """Load parameterized validator from plutus-applied.json"""
    applied_file = str(Path(__file__).resolve().parent.parent / "plutus-applied.json")

    try:
        with open(applied_file, "r") as f:
            validator = json.load(f)
    except FileNotFoundError:
        raise SystemExit(f"ERROR: {applied_file} not found. Run init_contract.py first.")
    except json.JSONDecodeError as e:
        raise SystemExit(f"ERROR: {applied_file} is not valid JSON: {e}")

    spend_validator = None
    for v in validator.get("validators", []):
        if "spend" in v.get("title", ""):
            spend_validator = v
            break

    if not spend_validator:
        raise SystemExit("ERROR: spend validator not found in plutus-applied.json")

    script_hex = spend_validator.get("compiledCode", "")
    if not script_hex or len(script_hex) % 2 != 0:
        raise SystemExit(f"ERROR: invalid compiledCode in plutus-applied.json (length: {len(script_hex)})")

    try:
        script = PlutusV3Script(bytes.fromhex(script_hex))
    except ValueError as e:
        raise SystemExit(f"ERROR: invalid hex in compiledCode: {e}")

    hash_hex = spend_validator.get("hash", "")
    try:
        script_hash = ScriptHash(bytes.fromhex(hash_hex))
    except ValueError as e:
        raise SystemExit(f"ERROR: invalid hex in script hash: {e}")

    return {
        "script": script,
        "script_hash": script_hash,
    }


def get_contract_utxo(context, tx_id: str, script_address: Address) -> UTxO:
    """Find the contract UTxO by transaction ID"""
    print(f"  Searching for UTxO with TX ID: {tx_id[:16]}...")
    utxos = context.utxos(str(script_address))

    for utxo in utxos:
        if str(utxo.input.transaction_id) == tx_id:
            return utxo

    # If not found, list available UTxOs
    print(f"\n  Available UTxOs at script address:")
    for utxo in utxos:
        print(f"    - {utxo.input.transaction_id}#{utxo.input.index}")

    raise Exception(f"Contract UTxO not found for transaction {tx_id}")


def save_transaction_log(tx_type: str, tx_hash: str, amount: int, new_liquidity: int):
    """Save transaction to log file"""
    log_file = Config.CREDENTIALS_DIR / "transactions.json"

    if log_file.exists():
        with open(log_file, 'r') as f:
            log = json.load(f)
    else:
        log = {"deposits": [], "withdrawals": []}

    tx_entry = {
        "tx_hash": str(tx_hash),
        "amount": amount,
        "new_liquidity": new_liquidity,
        "network": Config.NETWORK,
        "explorer_url": Config.get_explorer_url(str(tx_hash)),
    }

    if tx_type == "deposit":
        log["deposits"].append(tx_entry)

    with open(log_file, 'w') as f:
        json.dump(log, f, indent=2)


def test_deposit(contract_tx_id: str, deposit_amount: int):
    """Test deposit operation"""
    print("=" * 70)
    print("Lightning Liquidity Manager - Deposit Test (Parameterized)")
    print("=" * 70)

    try:
        # Load config
        config_data = Config.load_deployment_config()
        if not config_data:
            print("✗ Config not found")
            return 1

        operator_addr = config_data['operator']['address']
        sk_file = config_data['operator']['sk_file']
        cbtc_policy = config_data['token']['cbtc_policy']
        cbtc_asset_name = bytes.fromhex(
            config_data['token']['cbtc_asset_name'])

        # Use parameterized script address
        script_address_str = config_data['validator'].get(
            'parameterized_script_address')
        if not script_address_str:
            print(
                "✗ No parameterized_script_address in config. Run init_contract_parameterized.py first")
            return 1

        print(f"\n[Configuration]")
        print(f"  Network:         {Config.NETWORK}")
        print(f"  Operator:        {operator_addr}")
        print(f"  Deposit Amount:  {deposit_amount:,} cBTC")
        print(f"  Contract TX:     {contract_tx_id[:32]}...")

        # Connect to chain
        context = Config.get_chain_context()

        # Load keys and validator
        signing_key = PaymentSigningKey.load(sk_file)
        vkey = PaymentVerificationKey.from_signing_key(signing_key)
        address = Address.from_primitive(operator_addr)

        print(f"\n[1/6] Loading parameterized validator...")
        validator = read_parameterized_validator()

        script_address = Address(
            payment_part=validator["script_hash"],
            network=Network.TESTNET,
        )
        print(f"  ✓ Loaded from plutus-applied.json")
        print(f"  Script hash: {validator['script_hash']}")

        print(f"\n[2/6] Finding contract UTxO...")
        contract_utxo = get_contract_utxo(
            context, contract_tx_id, script_address)
        print(f"  ✓ Found UTxO at index {contract_utxo.input.index}")

        # Extract current state
        print(f"\n[3/6] Reading current state...")
        datum_cbor = contract_utxo.output.datum
        if datum_cbor is None:
            raise Exception("No datum found on contract UTxO")

        current_state = State.from_cbor(datum_cbor.cbor)

        print(f"  Total Liquidity:  {current_state.total_liquidity:,}")
        print(f"  Reserved:         {current_state.reserved:,}")
        print(
            f"  Available:        {current_state.total_liquidity - current_state.reserved:,}")

        # Get current cBTC
        current_cbtc = 0
        if contract_utxo.output.amount.multi_asset:
            script_hash_key = ScriptHash.from_primitive(cbtc_policy)
            asset_name = AssetName(cbtc_asset_name)
            if script_hash_key in contract_utxo.output.amount.multi_asset:
                if asset_name in contract_utxo.output.amount.multi_asset[script_hash_key]:
                    current_cbtc = contract_utxo.output.amount.multi_asset[script_hash_key][asset_name]

        print(f"  Current cBTC:     {current_cbtc:,}")

        # Calculate new state
        print(f"\n[4/6] Calculating new state...")
        new_state = State(
            total_liquidity=current_state.total_liquidity + deposit_amount,
            reserved=current_state.reserved,
            last_invoice_id=current_state.last_invoice_id,
            invoices=current_state.invoices,
            last_offramp_id=current_state.last_offramp_id,
            offramps=current_state.offramps,
        )

        new_cbtc_amount = current_cbtc + deposit_amount
        print(
            f"  New Liquidity:    {new_state.total_liquidity:,} (+{deposit_amount:,})")
        print(f"  New cBTC:         {new_cbtc_amount:,}")

        # Create redeemer
        redeemer = Redeemer(DepositRedeemer(amount=deposit_amount))

        # Prepare output value
        asset_name = AssetName(cbtc_asset_name)
        my_asset = Asset({asset_name: new_cbtc_amount})
        multi_asset = MultiAsset(
            {ScriptHash.from_primitive(cbtc_policy): my_asset})

        # Build transaction
        print(f"\n[5/6] Building transaction...")
        builder = TransactionBuilder(context)

        builder.add_script_input(
            utxo=contract_utxo,
            script=validator["script"],
            redeemer=redeemer,
        )

        builder.add_input_address(address)

        builder.add_output(
            TransactionOutput(
                address=script_address,
                amount=Value(coin=contract_utxo.output.amount.coin,
                             multi_asset=multi_asset),
                datum=new_state,
            )
        )

        builder.required_signers = [vkey.hash()]
        print(f"  ✓ Transaction built")

        # Sign and submit
        print(f"\n[6/6] Signing and submitting...")
        signed_tx = builder.build_and_sign(
            signing_keys=[signing_key],
            change_address=address,
        )

        context.submit_tx(signed_tx)
        tx_hash = signed_tx.id

        # Save to log
        save_transaction_log("deposit", tx_hash,
                             deposit_amount, new_state.total_liquidity)

        print("\n" + "=" * 70)
        print("✓ DEPOSIT SUCCESSFUL")
        print("=" * 70)
        print(f"TX Hash:       {tx_hash}")
        print(f"Deposited:     {deposit_amount:,} cBTC")
        print(f"New Liquidity: {new_state.total_liquidity:,} cBTC")
        print(
            f"Explorer:      {Config.get_explorer_url(str(tx_hash))}")
        print(f"\n⏳ Wait 30-60 seconds, then run:")
        print(
            f"   uv run scripts/test_withdraw_parameterized.py {tx_hash} 50000")
        print("=" * 70)

        return 0

    except Exception as e:
        print(f"\n✗ Deposit failed: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(
            "Usage: uv run scripts/test_deposit.py <contract_tx_id> <amount>")
        print("\nExample:")
        print("  uv run scripts/test_deposit.py abc123...def 100000")
        sys.exit(1)

    contract_tx = sys.argv[1]
    amount = int(sys.argv[2])
    sys.exit(test_deposit(contract_tx, amount))
