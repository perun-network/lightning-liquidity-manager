#!/usr/bin/env python3
"""Mint test cBTC tokens for testing"""

import json
import sys
from pathlib import Path

from pycardano import (
    Address,
    AlonzoMetadata,
    Asset,
    AssetName,
    AuxiliaryData,

    InvalidHereAfter,
    Metadata,
    MultiAsset,
    Network,
    PaymentKeyPair,
    PaymentSigningKey,
    PaymentVerificationKey,
    ScriptAll,
    ScriptPubkey,
    TransactionBuilder,
    TransactionOutput,
    Value,
    min_lovelace,
)

from config import Config


def load_or_create_policy_key(key_dir: Path, base_name: str):
    """Load or create policy key pair"""
    skey_path = key_dir / f"{base_name}.skey"
    vkey_path = key_dir / f"{base_name}.vkey"

    if skey_path.exists():
        skey = PaymentSigningKey.load(str(skey_path))
        vkey = PaymentVerificationKey.from_signing_key(skey)
    else:
        key_pair = PaymentKeyPair.generate()
        key_pair.signing_key.save(str(skey_path))
        key_pair.verification_key.save(str(vkey_path))
        skey = key_pair.signing_key
        vkey = key_pair.verification_key
    return skey, vkey


def mint_tokens(
    amount: int,
    token_name: str = "cBTC"
) -> int:
    """Mint cBTC test tokens"""
    print("=" * 60)
    print("Minting Test cBTC Tokens")
    print("=" * 60)

    try:
        # Load config
        config_data = Config.load_deployment_config()
        if not config_data:
            print("✗ Deployment config not found. Run 'python scripts/deploy.py' first")
            return 1

        operator_addr = config_data['operator']['address']
        sk_file = config_data['operator']['sk_file']

        # Connect to chain
        context = Config.get_chain_context()

        # Load payment signing key
        payment_skey = PaymentSigningKey.load(sk_file)
        payment_vkey = PaymentVerificationKey.from_signing_key(payment_skey)
        address = Address.from_primitive(operator_addr)

        print(f"\n→ Setting up minting policy")
        print(f"  Operator address: {operator_addr}")

        # Generate or load policy keys
        Config.ensure_credentials_dir()
        policy_skey, policy_vkey = load_or_create_policy_key(
            Config.CREDENTIALS_DIR, "policy"
        )

        # Create policy that requires signature from policy key
        pub_key_policy = ScriptPubkey(policy_vkey.hash())

        # Add time lock - tokens can only be minted before this slot
        must_before_slot = InvalidHereAfter(context.last_block_slot + 10000)

        # Combine policies
        policy = ScriptAll([pub_key_policy, must_before_slot])

        # Calculate policy ID
        policy_id = policy.hash()

        print(f"  Policy ID: {policy_id}")

        # Save policy ID
        with open(Config.CREDENTIALS_DIR / "policy.id", "w") as f:
            f.write(str(policy_id))

        # Create asset
        asset_name = AssetName(token_name.encode())
        my_asset = Asset()
        my_asset[asset_name] = amount

        # Create MultiAsset
        my_nft = MultiAsset()
        my_nft[policy_id] = my_asset

        # Native scripts to attach to transaction
        native_scripts = [policy]

        # Create metadata for the token
        metadata = {
            721: {
                policy_id.payload.hex(): {
                    token_name: {
                        "description": "Test cBTC token for Lightning Liquidity Manager",
                        "name": f"Test {token_name}",
                        "decimals": 8,
                        "ticker": token_name,
                    }
                }
            }
        }

        auxiliary_data = AuxiliaryData(
            AlonzoMetadata(metadata=Metadata(metadata)))

        print(f"\n→ Building transaction")
        print(f"  Minting {amount} {token_name} tokens")

        # Build transaction
        builder = TransactionBuilder(context)
        builder.add_input_address(address)
        builder.ttl = must_before_slot.after
        builder.mint = my_nft
        builder.native_scripts = native_scripts
        builder.auxiliary_data = auxiliary_data

        # Calculate minimum lovelace needed to hold the token
        min_val = min_lovelace(
            context, output=TransactionOutput(address, Value(0, my_nft))
        )

        # Send tokens to operator address
        builder.add_output(TransactionOutput(address, Value(min_val, my_nft)))

        # Sign transaction with both payment key and policy key
        print("→ Signing transaction...")
        signed_tx = builder.build_and_sign(
            [payment_skey, policy_skey],
            change_address=address
        )

        # Submit transaction
        print("→ Submitting transaction...")
        context.submit_tx(signed_tx)
        tx_hash = signed_tx.id

        print(f"\n✓ Tokens minted successfully!")
        print(f"  TX Hash: {tx_hash}")
        print(f"  Policy ID: {policy_id}")
        print(f"  Asset Name: {token_name}")
        print(f"  Amount: {amount}")
        print(
            f"\n  Check: {Config.get_explorer_url(str(tx_hash))}")

        # Update config with token info
        config_data['token']['cbtc_policy'] = str(policy_id)
        config_data['token']['cbtc_asset_name'] = token_name.encode().hex()
        Config.save_deployment_config(config_data)

        print(f"\n✓ Updated deployment config with token info")
        print(f"\n⏳ Wait 30-60 seconds for confirmation, then run:")
        print(f"   uv run scripts/init_contract.py {amount}")

        return 0

    except Exception as e:
        print(f"\n✗ Minting failed: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    amount = int(sys.argv[1]) if len(
        sys.argv) > 1 else 10_000_000_000  # 100 cBTC
    token_name = sys.argv[2] if len(sys.argv) > 2 else "cBTC"
    sys.exit(mint_tokens(amount, token_name))
