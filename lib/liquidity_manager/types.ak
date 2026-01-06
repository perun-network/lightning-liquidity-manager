use aiken/crypto.{VerificationKeyHash}

pub type Config {
  // Liquidity Manager operator's PKH
  lm_pkh: VerificationKeyHash,
  // cBTC asset policy ID
  cbtc_policy: ByteArray,
  // cBTC asset name
  cbtc_name: ByteArray,
}

pub type State {
  total_liquidity: Int,
  reserved: Int,
  last_invoice_id: Int,
  invoices: List<Invoice>,
}

/// Invoice/Payload structure for Lightning → Cardano coordination
pub type Invoice {
  // Unique invoice identifier (from last_invoice_id)
  invoice_id: Int,
  // Amount in satoshis (8 decimal places)
  amount: Int,
  // Cardano address receiving the wrapped cBTC
  owner: VerificationKeyHash,
  // POSIX ms when created
  timestamp: Int,
  // POSIX ms when it expires
  expires_at: Int,
}

/// Redeemer actions for the Liquidity Manager contract
pub type Action {
  // Add cBTC to the liquidity pool
  Deposit { amount: Int }

  // Remove cBTC from the pool (LM rebalancing)
  Withdraw { amount: Int }

  // Generate signed invoice payload for Lightning connector
  CreateInvoice {
    amount: Int,
    owner: VerificationKeyHash,
    timestamp: Int,
    expires_at: Int,
  }

  // Release wrapped cBTC when Lightning payment received
  FulfillInvoice { invoice: Invoice }

  // Cancel pending invoice if payment expires.
  CancelInvoice { invoice_id: Int }
}
