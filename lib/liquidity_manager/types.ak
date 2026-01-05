use aiken/crypto.{VerificationKeyHash}
use cardano/address.{ Address }


pub type Config {
  lm_pkh: VerificationKeyHash, // Liquidity Manager operator's PKH
  cbtc_policy: ByteArray,  // cBTC asset policy ID
  cbtc_name: ByteArray, // cBTC asset name
  script_address: Address,  // Liquidity Manager script address
}


pub type State {
  total_liquidity: Int,
  reserved: Int,
  last_invoice_id: Int,
  invoices: List<Invoice>,  // active invoices
}

/// Invoice/Payload structure for Lightning → Cardano coordination
pub type Invoice {
  invoice_id: Int, // Unique invoice identifier (from last_invoice_id)
  amount: Int,  // Amount in satoshis (8 decimal places)
  owner: VerificationKeyHash,// Cardano address receiving the wrapped cBTC
  timestamp: Int, // POSIX ms when created
  expires_at: Int, // POSIX ms when it expires
}

/// Redeemer actions for the Liquidity Manager contract
pub type Action {
  Deposit { amount: Int } // Add cBTC to the liquidity pool
  Withdraw { amount: Int } // Remove cBTC from the pool (LM rebalancing)
  CreateInvoice { amount: Int, owner: VerificationKeyHash, timestamp: Int, expires_at: Int } // Generate signed invoice payload for Lightning connector
  FulfillInvoice { invoice: Invoice } // Release wrapped cBTC when Lightning payment received
  CancelInvoice { invoice_id: Int } // Cancel pending invoice if payment expires.
}
