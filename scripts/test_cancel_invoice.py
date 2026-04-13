from pathlib import Path
#!/usr/bin/env python3
"""Test cancel invoice transaction - parameterized validator version"""

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
from pycardano.hash import ScriptHash, VerificationKeyHash
from pycardano.serialization import IndefiniteList

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
class CancelInvoiceRedeemer(PlutusData):
    """CancelInvoice redeemer (Action::CancelInvoice)"""
    CONSTR_ID = 4
    invoice_id: int


def read_parameterized_validator() -> dict:
    """Load parameterized validator from plutus-applied.json"""
    applied_file = str(Path(__file__).resolve().parent.parent / "plutus-applied.json")

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


def update_invoice_log(invoice_id: int, tx_hash: str, status: str):
    """Update invoice status in log file"""
    log_file = Config.CREDENTIALS_DIR / "invoices.json"

    if not log_file.exists():
        print("  Warning: invoices.json not found")
        return

    with open(log_file, 'r') as f:
        log = json.load(f)

    for invoice in log["invoices"]:
        if invoice["invoice_id"] == invoice_id:
            invoice["status"] = status
            invoice[f"{status}_tx_hash"] = str(tx_hash)
            invoice[f"{status}_explorer_url"] = Config.get_explorer_url(str(tx_hash))
            break

    with open(log_file, 'w') as f:
        json.dump(log, f, indent=2)


def test_cancel_invoice(contract_tx_id: str, invoice_id: int):
    """Test cancel invoice operation"""
    print("=" * 70)
    print("Lightning Liquidity Manager - Cancel Invoice Test")
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
            print("✗ No parameterized_script_address in config")
            return 1

        print(f"\n[Configuration]")
        print(f"  Network:         {Config.NETWORK}")
        print(f"  Operator:        {operator_addr}")
        print(f"  Invoice ID:      {invoice_id}")
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

        print(f"\n[2/6] Finding contract UTxO...")
        contract_utxo = get_contract_utxo(
            context, contract_tx_id, script_address)
        print(f"  ✓ Found UTxO at index {contract_utxo.input.index}")

        # Extract current state
        print(f"\n[3/6] Reading current state and finding invoice...")
        datum_cbor = contract_utxo.output.datum
        if datum_cbor is None:
            raise Exception("No datum found on contract UTxO")

        current_state = State.from_cbor(datum_cbor.cbor)

        print(f"  Total Liquidity:  {current_state.total_liquidity:,}")
        print(f"  Reserved:         {current_state.reserved:,}")
        print(f"  Active Invoices:  {len(list(current_state.invoices))}")

        # Deserialize invoices from raw CBOR to Invoice objects
        invoices_list = []
        for raw_inv in current_state.invoices:
            if isinstance(raw_inv, Invoice):
                invoices_list.append(raw_inv)
            else:
                try:
                    inv = Invoice.from_primitive(raw_inv)
                    invoices_list.append(inv)
                except:
                    inv = Invoice(
                        invoice_id=raw_inv[0],
                        amount=raw_inv[1],
                        owner=raw_inv[2],
                        timestamp=raw_inv[3],
                        expires_at=raw_inv[4]
                    )
                    invoices_list.append(inv)

        # Find the invoice
        target_invoice = None
        for inv in invoices_list:
            if inv.invoice_id == invoice_id:
                target_invoice = inv
                break

        if not target_invoice:
            print(f"\n✗ Invoice {invoice_id} not found in state")
            print(
                f"  Available invoice IDs: {[inv.invoice_id for inv in invoices_list]}")
            return 1

        print(f"\n  Found Invoice:")
        print(f"  - ID: {target_invoice.invoice_id}")
        print(f"  - Amount: {target_invoice.amount:,} cBTC")
        print(f"  - Expires At: {target_invoice.expires_at}")

        # Calculate new state
        print(f"\n[4/6] Calculating new state...")

        # Remove cancelled invoice from list - keep raw invoices except the target
        new_invoices_raw = []
        for raw_inv in current_state.invoices:
            if isinstance(raw_inv, Invoice):
                inv = raw_inv
            else:
                try:
                    inv = Invoice.from_primitive(raw_inv)
                except:
                    inv = Invoice(
                        invoice_id=raw_inv[0],
                        amount=raw_inv[1],
                        owner=raw_inv[2],
                        timestamp=raw_inv[3],
                        expires_at=raw_inv[4]
                    )

            if inv.invoice_id != invoice_id:
                new_invoices_raw.append(raw_inv)

        new_invoices = IndefiniteList(new_invoices_raw)

        new_state = State(
            total_liquidity=current_state.total_liquidity,
            reserved=current_state.reserved - target_invoice.amount,
            last_invoice_id=current_state.last_invoice_id,
            invoices=new_invoices,
            last_offramp_id=current_state.last_offramp_id,
            offramps=current_state.offramps,
        )

        print(f"  New Liquidity:    {new_state.total_liquidity:,} (unchanged)")
        print(
            f"  New Reserved:     {new_state.reserved:,} (-{target_invoice.amount:,})")

        # Create redeemer
        redeemer = Redeemer(CancelInvoiceRedeemer(invoice_id=invoice_id))

        # Get current cBTC amount (unchanged)
        current_cbtc = 0
        if contract_utxo.output.amount.multi_asset:
            script_hash_key = ScriptHash.from_primitive(cbtc_policy)
            asset_name = AssetName(cbtc_asset_name)
            if script_hash_key in contract_utxo.output.amount.multi_asset:
                if asset_name in contract_utxo.output.amount.multi_asset[script_hash_key]:
                    current_cbtc = contract_utxo.output.amount.multi_asset[script_hash_key][asset_name]

        # Prepare output value (cBTC unchanged)
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

        # Set validity range to after expiry
        builder.validity_start = context.last_block_slot
        builder.ttl = builder.validity_start + 1000

        builder.required_signers = [vkey.hash()]
        print(f"  ✓ Transaction built")
        print(f"  Validity range: {builder.validity_start} - {builder.ttl}")

        # Sign and submit
        print(f"\n[6/6] Signing and submitting...")
        signed_tx = builder.build_and_sign(
            signing_keys=[signing_key],
            change_address=address,
        )

        context.submit_tx(signed_tx)
        tx_hash = signed_tx.id

        # Update log
        update_invoice_log(invoice_id, tx_hash, "cancelled")

        print("\n" + "=" * 70)
        print("✓ INVOICE CANCELLED SUCCESSFULLY")
        print("=" * 70)
        print(f"TX Hash:        {tx_hash}")
        print(f"Invoice ID:     {invoice_id}")
        print(f"Amount:         {target_invoice.amount:,} cBTC")
        print(f"Unreserved:     {target_invoice.amount:,} cBTC")
        print(f"New Reserved:   {new_state.reserved:,} cBTC")
        print(
            f"Explorer:       {Config.get_explorer_url(str(tx_hash))}")
        print(f"\n⏳ Wait 30-60 seconds for confirmation")
        print("=" * 70)

        return 0

    except Exception as e:
        print(f"\n✗ Cancel invoice failed: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: uv run scripts/test_cancel_invoice.py <contract_tx_id> <invoice_id>")
        print("\nExample:")
        print("  uv run scripts/test_cancel_invoice.py abc123...def 2")
        sys.exit(1)

    contract_tx = sys.argv[1]
    inv_id = int(sys.argv[2])

    sys.exit(test_cancel_invoice(contract_tx, inv_id))
