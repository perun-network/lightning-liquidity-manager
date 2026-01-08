# Lightning Liquidity Manager

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Aiken](https://img.shields.io/badge/Aiken-v1.1.19-blueviolet)](https://aiken-lang.org)
[![Network](https://img.shields.io/badge/Network-Cardano_Preprod-green)](https://preprod.cardanoscan.io)

A Plutus smart contract for managing Bitcoin Lightning Network liquidity on Cardano. Part of the Perun Bitcoin-Lightning integration enabling atomic cross-chain swaps between Cardano and Bitcoin Lightning.

## Overview

The Lightning Liquidity Manager (LM) is a parameterized Plutus V3 smart contract that:
- Manages a liquidity pool of wrapped Bitcoin (cBTC tokens)
- Enables deposits and withdrawals by authorized operators
- Creates time-bound invoices for Lightning payment channels
- Tracks reserved liquidity for pending Lightning HTLCs
- Provides invoice payload endpoints for Connector integration

## Deployment (Preprod Testnet)

### Deployed Contract Information

| Parameter             | Value                                                                                                                      |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| **Network**           | Cardano Preprod Testnet                                                                                                    |
| **Script Hash**       | `48d8b56897a96e38e3cc39f9af97ae4143a8ead0720ec6d61795e95d`                                                                 |
| **Script Address**    | `addr_test1wzgelm2s9057n4rlculv0zmh84aggkd3wqylvk5dgx37vjcwfammz`                                                          |
| **Deployment TX**     | [View on Explorer](https://preprod.cardanoscan.io/address/addr_test1wzgelm2s9057n4rlculv0zmh84aggkd3wqylvk5dgx37vjcwfammz) |
| **cBTC Policy**       | `c6684a9c15e50d4937a31075538e1a40e96e638fdfb86b4b0f659979`                                                                 |
| **Initial Liquidity** | 1,100,000 cBTC                                                                                                             |

### Acceptance Test Results (v0.1.0)

**Test Execution Date:** January 8, 2026

#### Deposits (5 transactions)

| #   | Amount       | TX Hash       | Explorer                                                                                                            |
| --- | ------------ | ------------- | ------------------------------------------------------------------------------------------------------------------- |
| 1   | 100,000 cBTC | `24f31498...` | [View](https://preprod.cardanoscan.io/transaction/24f314988df4c0d8608c2321d8ecd6c77199b045b162630c46dda68175f9791e) |
| 2   | 150,000 cBTC | `89772250...` | [View](https://preprod.cardanoscan.io/transaction/897722508f7c22e3a706165d10e4804827d9b599b92c8ee7573e6519acf3aa45) |
| 3   | 200,000 cBTC | `e0161d5e...` | [View](https://preprod.cardanoscan.io/transaction/e0161d5e08671a8d96e9f8d1ffa3176592e59c2b9c0b62ec60967156d31d779f) |
| 4   | 250,000 cBTC | `6ab51998...` | [View](https://preprod.cardanoscan.io/transaction/6ab519980a6c639a160d3b8a57af85a3f23cd3d0c591fddb0571ca26872bf41a) |
| 5   | 300,000 cBTC | `f709bebf...` | [View](https://preprod.cardanoscan.io/transaction/f709bebff822058ae4307558268dd67f40abd976cd3465a954c4d774ff998678) |

**Total Deposited:** 1,000,000 cBTC

#### Withdrawals (5 transactions)

| #   | Amount       | TX Hash       | Explorer                                                                                                            |
| --- | ------------ | ------------- | ------------------------------------------------------------------------------------------------------------------- |
| 1   | 80,000 cBTC  | `24fd7476...` | [View](https://preprod.cardanoscan.io/transaction/24fd74762ec3eef51bc2a997aac592e00baaa52a0b42f0230ac9b9afcc2731b7) |
| 2   | 100,000 cBTC | `e04f60b7...` | [View](https://preprod.cardanoscan.io/transaction/e04f60b713c883cb310c85d7e02c23f05145934659ae60dd7d29d91a441c3caf) |
| 3   | 120,000 cBTC | `fe8af78e...` | [View](https://preprod.cardanoscan.io/transaction/fe8af78e41d6f6066cdc8fb865f786153bffffa77a6ab9f7dde0a174f6587925) |
| 4   | 150,000 cBTC | `08ffb9b3...` | [View](https://preprod.cardanoscan.io/transaction/08ffb9b317eed04cabfe3bea0ec9f363f6fa5385a83aa40ecd02c8a2426ff64c) |
| 5   | 180,000 cBTC | `4876cd5d...` | [View](https://preprod.cardanoscan.io/transaction/4876cd5dde8bf321627713d31172a927c9567cf308196cf0b1f9be6d74d64e8a) |

**Total Withdrawn:** 630,000 cBTC

#### Final State
- **Total Liquidity:** 1,470,000 cBTC
- **Reserved:** 0 cBTC
- **Available:** 1,470,000 cBTC
- **Net Change:** +370,000 cBTC

**Full Results:** [`credentials/acceptance_test_results.json`](credentials/acceptance_test_results.json)

## Architecture

### Contract Parameters

The validator is parameterized with:
```haskell
Config {
  lm_pkh: VerificationKeyHash,      -- Authorized operator
  cbtc_policy: PolicyId,              -- Wrapped BTC token policy
  cbtc_name: AssetName                -- Token asset name
}
````
### State Datum:

```haskell
State {
  total_liquidity: Int,     -- Total cBTC in pool
  reserved: Int,            -- cBTC reserved for pending invoices
  last_invoice_id: Int,     -- Counter for invoice IDs
  invoices: List<Invoice>   -- Active invoice list
}
```

### Redeemer Endpoints
1. **Deposit** - Add liquidity to pool
2. **Withdraw** - Remove available liquidity
3. **CreateInvoice** - Reserve liquidity for Lightning HTLC
4. **FulfillInvoice** - Release cBTC to invoice owner
5. **CancelInvoice** - Unreserve liquidity after expiry

### Invoice 


```haskell
Invoice {
  invoice_id: Int,
  amount: Int,
  owner: VerificationKeyHash,  -- Payment destination
  timestamp: Int,              -- Creation time (ms)
  expires_at: Int              -- Expiry time (ms)
}
```

## Development Setup
Prerequisites:
- [Aiken]((https://aiken-lang.org)) v1.1.19+
- [Pycardano](https://github.com/Python-Cardano/pycardano) with Python 3.9+ and `uv` package manager (see [Installation](https://aiken-lang.org/example--hello-world/end-to-end/pycardano))
- [Blockfrost API](https://blockfrost.io) for Cardano Test Deployment.

Installation
```sh
# Clone repository
git clone https://github.com/perun-network/lightning-liquidity-manager.git
cd lightning-liquidity-manager

# Install Aiken (if not installed)
curl -sSf https://install.aiken-lang.org | bash

# Install Python dependencies
uv sync
```

Environment Setup
```sh
# Set Blockfrost API key
export BLOCKFROST_PROJECT_ID="your_project_id"

# Generate operator keys (first time only)
uv run scripts/config.py
```

Build Contract
```sh
# Run unit tests
aiken check

# Compile Aiken validator
aiken build
```

## Preview Testnet Deployment
1. Create operator keys and fund with [Cardano Faucet](https://docs.cardano.org/cardano-testnets/tools/faucet)
```
uv run scripts/config.py
```

2. Mint Test cBTC
```bash
# Mint 5,000,000 test cBTC tokens
uv run scripts/mint_cbtc.py 5000000
```
3. Deploy contract
```bash
# Initialize with 1M cBTC liquidity
uv run scripts/init_contract.py 1000000
```

4. Verify Deployment:
```bash
# Check contract state
uv run scripts/config.py

# View on explorer
https://preview.cardanoscan.io/address/<SCRIPT_ADDRESS>
```


## Testing
### Unit Test
```sh
# Run all Aiken tests
aiken check
```
Test coverage includes:
- Deposit validation (authorized, insufficient funds)
-  Withdrawal validation (liquidity checks, authorization)
- Invoice creation (liquidity reservation, expiry)
-  Invoice fulfillment (payment to owner, state updates)
- Invoice cancellation (expiry enforcement)
### Integration Test
```sh
# Get latest contract TX ID from deployment.json
CONTRACT_TX=$(cat credentials/deployment.json | jq -r '.validator.deployment_tx')

# Test deposit
uv run scripts/test_deposit.py <LATEST_TX_HASH> 100000

# Test withdrawal
uv run scripts/test_withdraw.py <LATEST_TX_HASH> 50000

# Test invoice operations
uv run scripts/test_invoices.py <LATEST_TX_HASH>
```
### Acceptance Tests
```sh
# Get latest contract TX ID from deployment.json
CONTRACT_TX=$(cat credentials/deployment.json | jq -r '.validator.deployment_tx')

# Test deposit
uv run scripts/test_deposit.py <LATEST_TX_HASH> 100000

# Test withdrawal
uv run scripts/test_withdraw.py <LATEST_TX_HASH> 50000

# Test invoice operations
uv run scripts/acceptance_test.py <LATEST_TX_HASH>
```

Output: [credentials/acceptance_test_results](credentials/acceptance_test_results.json)


## API Endpoints
All endpoints interact with the deployed smart contract on Cardano Preprod testnet. Each operation requires the latest contract UTxO transaction hash.

### Deposit
Add cBTC tokens to the liquidity pool.

Parameters:
- `amount` - Amount of cBTC to deposit (integer, no decimals)

Authorization: Requires operator signature

Try: 
```sh
uv run scripts/test_deposit.py <contract_tx_id> <amount>
```

### Withdraw
Remove available cBTC tokens from the liquidity pool.
Parameters:
- `amount` - Amount of cBTC to deposit (integer, no decimals)

Authorization: Requires operator signature

Validation:

- Amount cannot exceed `total_liquidity - reserved`
- Cannot withdraw reserved liquidity

Try: 
```sh
uv run scripts/test_withdraw.py <contract_tx_id> <amount>
```

### Create Invoice
Reserve liquidity and create a time-bound invoice for Lightning payment.

Parameters:

- `amount` - Amount of cBTC to reserve for this invoice
- `owner_address` - Cardano address that will receive - cBTC upon fulfillment
- `timestamp` - Invoice creation time in POSIX ms
- `expiry_at` - Invoice validity period in POSIX ms

Authorization: Requires operator signature

Validation:

- Amount must be ≤ available liquidity
- Expiry time must be in the future

Try:

```sh
uv run scripts/test_create_invoice.py <contract_tx_id> <amount> <owner_address> <expiry_minutes>

```

Invoice Payload example (saved to **credentials/invoices.json**)
```json
{
  "invoice_id": 1,
  "amount": 200000,
  "owner": "addr_test1vrr94v04tjjfqqsusezwmmkmqguuskc45plen04uj6vrefqsueu63",
  "timestamp": 1767863315385,
  "expires_at": 1767867315385,
  "status": "created",
  "tx_hash": "c6859c86f79d668f35884d7ce791b935...",
  "network": "preprod",
  "explorer_url": "https://preprod.cardanoscan.io/transaction/c6859c86..."
}
```

### Fulfill Invoice
Complete a Lightning payment by sending reserved cBTC to the invoice owner.

Parameters:

- `invoice` - The invoice to fulfill

Validation:

- Invoice must exist on-chain and be in active status
- Current time must be before expiry
- Exact amount of cBTC sent to owner's address

Try:

```bash
uv run scripts/test_fulfill_invoice.py <contract_tx_id> <invoice_id>
```

### Cancel Invoice
Cancel an expired invoice and release reserved liquidity back to the pool.

Parameters:

- `invoice_id` - Unique ID of the invoice to fulfill

Validation:

- Invoice must exist
- Current time must be after expiry

Try:

```bash
uv run scripts/test_cancel_invoice.py <contract_tx_id> <invoice_id>
```


## License
This project is licensed under the **Apache License 2.0** - see the [LICENSE](LICENSE) file for details.