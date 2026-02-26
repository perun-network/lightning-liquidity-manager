#!/usr/bin/env python3
"""Test create invoice transaction - parameterized validator version"""

import json
import sys
import time
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
from pycardano.hash import ScriptHash, VerificationKeyHash
from pycardano.serialization import IndefiniteList, ByteString

from config import Config


@dataclass
class Invoice(PlutusData):
    """Invoice datum"""
    CONSTR_ID = 0
    invoice_id: int
    amount: int
    owner: bytes  # Changed from VerificationKeyHash to bytes
    timestamp: int
    expires_at: int


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
class CreateInvoiceRedeemer(PlutusData):
    """CreateInvoice redeemer (Action::CreateInvoice)"""
    CONSTR_ID = 2
    amount: int
    owner: bytes  # Changed from VerificationKeyHash to bytes
    timestamp: int
    expires_at: int


def read_parameterized_validator() -> dict:
    """Load parameterized validator from plutus-applied.json"""
    applied_file = "plutus-applied.json"

    with open(applied_file, "r") as f:
        validator = json.load(f)

    spend_validator = None
    for v in validator["validators"]:
        if "spend" in v.get("title", ""):
            spend_validator = v
            break

    if not spend_validator:
        raise ValueError("Spend validator not found in plutus-applied.json")

    script_hex = spend_validator["compiledCode"]
    script = PlutusV3Script(bytes.fromhex(script_hex))
    script_hash = ScriptHash(bytes.fromhex(spend_validator["hash"]))

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


def save_invoice_log(invoice_id: int, amount: int, owner: str, timestamp: int, expires_at: int, tx_hash: str, status: str = "created"):
    """Save invoice to log file"""
    log_file = Config.CREDENTIALS_DIR / "invoices.json"

    if log_file.exists():
        with open(log_file, 'r') as f:
            log = json.load(f)
    else:
        log = {"invoices": []}

    invoice_entry = {
        "invoice_id": invoice_id,
        "amount": amount,
        "owner": owner,
        "timestamp": timestamp,
        "expires_at": expires_at,
        "status": status,
        "tx_hash": str(tx_hash),
        "network": Config.NETWORK,
        "explorer_url": Config.get_explorer_url(str(tx_hash)),
    }

    log["invoices"].append(invoice_entry)

    with open(log_file, 'w') as f:
        json.dump(log, f, indent=2)


def test_create_invoice(contract_tx_id: str, amount: int, owner_address: str, expiry_minutes: int):
    """Test create invoice operation"""
    print("=" * 70)
    print("Lightning Liquidity Manager - Create Invoice Test")
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
        print(f"  Invoice Amount:  {amount:,} cBTC")
        print(f"  Owner:           {owner_address}")
        print(f"  Expiry:          {expiry_minutes} minutes")
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

        available_liquidity = current_state.total_liquidity - current_state.reserved
        print(f"  Total Liquidity:  {current_state.total_liquidity:,}")
        print(f"  Reserved:         {current_state.reserved:,}")
        print(f"  Available:        {available_liquidity:,}")
        print(f"  Last Invoice ID:  {current_state.last_invoice_id}")

        # Validate sufficient liquidity
        if amount > available_liquidity:
            print(f"\n✗ INSUFFICIENT AVAILABLE LIQUIDITY")
            print(f"  Requested:  {amount:,}")
            print(f"  Available:  {available_liquidity:,}")
            return 1

        # Calculate timestamps
        print(f"\n[4/6] Calculating invoice parameters...")
        current_time = int(time.time() * 1000)  # milliseconds
        expires_at = current_time + (expiry_minutes * 60 * 1000)

        # Extract owner verification key hash as bytes
        owner_addr = Address.from_primitive(owner_address)
        if not hasattr(owner_addr.payment_part, 'payload'):
            raise Exception("Owner address must be a payment key hash address")

        # Get the raw bytes from the payment credential
        owner_pkh_raw = owner_addr.payment_part.payload

        # Convert to bytes if it's a VerificationKeyHash object
        if isinstance(owner_pkh_raw, VerificationKeyHash):
            owner_pkh_bytes = owner_pkh_raw.payload
        elif isinstance(owner_pkh_raw, bytes):
            owner_pkh_bytes = owner_pkh_raw
        else:
            raise Exception(
                f"Unexpected owner PKH type: {type(owner_pkh_raw)}")

        new_invoice_id = current_state.last_invoice_id + 1

        print(f"  Invoice ID:       {new_invoice_id}")
        print(f"  Timestamp:        {current_time}")
        print(f"  Expires At:       {expires_at}")
        print(f"  Owner PKH:        {owner_pkh_bytes.hex()[:16]}...")

        # Calculate new state
        new_invoice = Invoice(
            invoice_id=new_invoice_id,
            amount=amount,
            owner=owner_pkh_bytes,
            timestamp=current_time,
            expires_at=expires_at,
        )

        new_invoices = IndefiniteList(
            [new_invoice] + list(current_state.invoices))

        new_state = State(
            total_liquidity=current_state.total_liquidity,
            reserved=current_state.reserved + amount,
            last_invoice_id=new_invoice_id,
            invoices=new_invoices,
            last_offramp_id=current_state.last_offramp_id,
            offramps=current_state.offramps,
        )

        print(f"  New Reserved:     {new_state.reserved:,} (+{amount:,})")

        # Create redeemer
        redeemer = Redeemer(CreateInvoiceRedeemer(
            amount=amount,
            owner=owner_pkh_bytes,
            timestamp=current_time,
            expires_at=expires_at,
        ))

        # Get current cBTC amount
        current_cbtc = 0
        if contract_utxo.output.amount.multi_asset:
            script_hash_key = ScriptHash.from_primitive(cbtc_policy)
            asset_name = AssetName(cbtc_asset_name)
            if script_hash_key in contract_utxo.output.amount.multi_asset:
                if asset_name in contract_utxo.output.amount.multi_asset[script_hash_key]:
                    current_cbtc = contract_utxo.output.amount.multi_asset[script_hash_key][asset_name]

        # Prepare output value (cBTC amount unchanged)
        asset_name = AssetName(cbtc_asset_name)
        my_asset = Asset({asset_name: current_cbtc})
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
        save_invoice_log(new_invoice_id, amount, owner_address,
                         current_time, expires_at, tx_hash, "created")

        print("\n" + "=" * 70)
        print("✓ INVOICE CREATED SUCCESSFULLY")
        print("=" * 70)
        print(f"TX Hash:        {tx_hash}")
        print(f"Invoice ID:     {new_invoice_id}")
        print(f"Amount:         {amount:,} cBTC")
        print(f"Reserved:       {new_state.reserved:,} cBTC")
        print(f"Expires:        {expiry_minutes} minutes from now")
        print(
            f"Explorer:       {Config.get_explorer_url(str(tx_hash))}")
        print(f"\n⏳ Wait 30-60 seconds, then run:")
        print(
            f"   uv run scripts/test_fulfill_invoice.py {tx_hash} {new_invoice_id}")
        print("=" * 70)

        return 0

    except Exception as e:
        print(f"\n✗ Create invoice failed: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    if len(sys.argv) < 5:
        print("Usage: uv run scripts/test_create_invoice.py <contract_tx_id> <amount> <owner_address> <expiry_minutes>")
        print("\nExample:")
        print(
            "  uv run scripts/test_create_invoice.py abc123...def 100000 addr_test1qz... 60")
        sys.exit(1)

    contract_tx = sys.argv[1]
    amount = int(sys.argv[2])
    owner_addr = sys.argv[3]
    expiry_min = int(sys.argv[4])

    sys.exit(test_create_invoice(contract_tx, amount, owner_addr, expiry_min))
