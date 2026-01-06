#!/usr/bin/env python3
"""Deploy validators to preview testnet"""

import json
import os
import sys
from pathlib import Path
from typing import Dict, Optional

from pycardano import (
    Address,
    BlockFrostChainContext,
    Network,
    PaymentSigningKey,
    PaymentVerificationKey,
    PlutusV3Script,
)
from pycardano.hash import ScriptHash


class Config:
    """Configuration management for preview testnet deployment"""

    # Network configuration
    NETWORK = "preview"  # preview testnet (magic 2)
    BLOCKFROST_API = "https://cardano-preview.blockfrost.io/api/"

    # Directory paths
    CREDENTIALS_DIR = Path(__file__).parent.parent / "credentials"
    BUILD_DIR = Path(__file__).parent.parent / "build" / \
        "packages" / "liquidity-manager"
    PLUTUS_FILE = Path(__file__).parent.parent / "plutus.json"

    # Config file path
    CONFIG_FILE = CREDENTIALS_DIR / "deployment.json"

    # Supported token policies (example cBTC)
    # For testing, we'll use a testnet token policy
    CBTC_POLICY = "d7d6e333126f7c6db3535cf2ea417261d53ecce45463c7ac919f4965"
    CBTC_ASSET_NAME = b"cBTC"

    @classmethod
    def ensure_credentials_dir(cls):
        """Ensure credentials directory exists"""
        cls.CREDENTIALS_DIR.mkdir(parents=True, exist_ok=True)

    @classmethod
    def save_deployment_config(cls, config_data: dict):
        """Save deployment configuration to file"""
        cls.ensure_credentials_dir()
        with open(cls.CONFIG_FILE, 'w') as f:
            json.dump(config_data, f, indent=2)

    @classmethod
    def load_deployment_config(cls) -> Optional[dict]:
        """Load deployment configuration from file"""
        if cls.CONFIG_FILE.exists():
            with open(cls.CONFIG_FILE, 'r') as f:
                return json.load(f)
        return None

    @classmethod
    def get_blockfrost_api_key(cls) -> str:
        """Get Blockfrost API key from environment"""
        api_key = os.getenv("BLOCKFROST_PROJECT_ID")
        if not api_key:
            raise ValueError(
                "BLOCKFROST_PROJECT_ID environment variable not set. "
                "Get a free key from https://blockfrost.io"
            )
        return api_key


def read_validator() -> dict:
    """Load Plutus v3 script from plutus.json"""
    with open(Config.PLUTUS_FILE, "r") as f:
        validator = json.load(f)

    # Get the spend validator (liquidity_manager.spend)
    spend_validator = None
    for v in validator["validators"]:
        if "spend" in v.get("title", ""):
            spend_validator = v
            break

    if not spend_validator:
        raise ValueError("Could not find spend validator in plutus.json")

    # Create PlutusV3Script from compiled code
    script_bytes = PlutusV3Script(
        bytes.fromhex(spend_validator["compiledCode"])
    )
    script_hash = ScriptHash(bytes.fromhex(spend_validator["hash"]))

    print(f"✓ Loaded Plutus v3 script")
    print(f"  Script Hash: {spend_validator['hash']}")
    print(
        f"  Compiled size: {len(spend_validator['compiledCode']) // 2} bytes")

    return {
        "type": "PlutusV3",
        "script_bytes": script_bytes,
        "script_hash": script_hash,
    }


def setup_operator_credentials() -> tuple:
    """Setup or load operator credentials"""
    Config.ensure_credentials_dir()

    sk_file = Config.CREDENTIALS_DIR / "operator.sk"
    addr_file = Config.CREDENTIALS_DIR / "operator.addr"

    if sk_file.exists() and addr_file.exists():
        print("✓ Operator credentials already exist")
        sk = PaymentSigningKey.load(str(sk_file))
        with open(addr_file, 'r') as f:
            addr = f.read().strip()
        pkh = sk.to_verification_key().hash().to_primitive().hex()
        return addr, pkh, sk

    # Generate new credentials
    print("→ Generating new operator credentials...")
    sk = PaymentSigningKey.generate()
    vk = sk.to_verification_key()
    addr = Address(payment_part=vk.hash(), network=Network.TESTNET)

    # Save credentials
    sk.save(str(sk_file))
    with open(addr_file, 'w') as f:
        f.write(str(addr))

    pkh = vk.hash().to_primitive().hex()

    print(f"✓ Generated operator credentials")
    print(f"  Address: {addr}")
    print(f"  PKH: {pkh}")
    print(f"  Saved to: {sk_file.parent}")

    return str(addr), pkh, sk


def create_deployment_config(
    validator: dict,
    operator_address: str,
    operator_pkh: str
) -> Dict:
    """Create deployment configuration"""
    # Calculate script address from script hash
    script_address = Address(
        payment_part=validator["script_hash"],
        network=Network.TESTNET,
    )

    config = {
        "network": Config.NETWORK,
        "operator": {
            "address": operator_address,
            "pkh": operator_pkh,
            "sk_file": str(Config.CREDENTIALS_DIR / "operator.sk"),
        },
        "validator": {
            "script_hash": validator["script_hash"].to_primitive().hex(),
            "script_address": str(script_address),
            "plutus_file": str(Config.PLUTUS_FILE),
        },
        "token": {
            "cbtc_policy": Config.CBTC_POLICY,
            "cbtc_asset_name": Config.CBTC_ASSET_NAME.hex(),
        },
    }

    return config


def check_operator_balance(
    operator_addr: str,
    context: BlockFrostChainContext
):
    """Check operator's balance on testnet"""
    print(f"\n→ Checking operator balance...")

    try:
        addr = Address.from_primitive(operator_addr)
        utxos = context.utxos(str(addr))

        if not utxos:
            print(f"⚠ Operator has no UTxOs!")
            print(f"  Please send ADA to: {operator_addr}")
            print(f"  Faucet: https://faucet.preview.world.dev.cardano.org/basic-faucet")
            return False

        total_lovelace = 0
        for utxo in utxos:
            total_lovelace += utxo.output.amount.coin

        ada_amount = total_lovelace / 1_000_000
        print(
            f"✓ Operator balance: {ada_amount:.2f} ADA ({total_lovelace} lovelace)")

        return total_lovelace >= 2_000_000  # Minimum 2 ADA for transactions
    except Exception as e:
        print(f"⚠ Could not check balance: {e}")
        print(f"  This is normal if the address has not been funded yet")
        print(f"  Please send ADA to: {operator_addr}")
        print(f"  Faucet: https://faucet.preview.world.dev.cardano.org/basic-faucet")
        return False


def deploy():
    """Main deployment function"""
    print("=" * 60)
    print("Lightning Liquidity Manager - Validator Deployment")
    print(f"Network: {Config.NETWORK.upper()}")
    print("=" * 60)

    try:
        # 1. Load validator script
        print("\n[1/5] Loading validator script...")
        validator = read_validator()

        # 2. Setup operator credentials
        print("\n[2/5] Setting up operator...")
        operator_addr, operator_pkh, signing_key = setup_operator_credentials()

        # 3. Create deployment config
        print("\n[3/5] Creating deployment configuration...")
        config = create_deployment_config(
            validator, operator_addr, operator_pkh)
        Config.save_deployment_config(config)
        print(f"✓ Deployment config saved to {Config.CONFIG_FILE}")

        # 4. Connect to chain
        print("\n[4/5] Connecting to preview testnet...")
        context = BlockFrostChainContext(
            project_id=Config.get_blockfrost_api_key(),
            base_url="https://cardano-preview.blockfrost.io/api/",
        )
        print(f"✓ Connected to {Config.NETWORK} testnet")

        # 5. Check operator balance
        print("\n[5/5] Validating operator setup...")
        balance_ok = check_operator_balance(operator_addr, context)

        # Print summary
        print("\n" + "=" * 60)
        print("Deployment Summary")
        print("=" * 60)
        print(f"Network:          {Config.NETWORK}")
        print(f"Operator Address: {operator_addr}")
        print(f"Operator PKH:     {operator_pkh}")
        print(f"Script Hash:      {config['validator']['script_hash']}")
        print(f"Script Address:   {config['validator']['script_address']}")
        print(f"Config File:      {Config.CONFIG_FILE}")

        if balance_ok:
            print("\n✓ Deployment ready! Next steps:")
            print("  1. Run: python scripts/init_contract.py")
            print("  2. Run: python scripts/test_deposit.py <tx_id>")
            print("  3. Run: python scripts/test_withdraw.py <tx_id>")
        else:
            print("\n⚠ Funding required:")
            print(f"  Send ADA to: {operator_addr}")
            print(f"  Faucet: https://faucet.preview.world.dev.cardano.org/basic-faucet")
            print("  Then run this script again")

        return 0

    except Exception as e:
        print(f"\n✗ Deployment failed: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(deploy())
