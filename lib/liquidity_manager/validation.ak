use aiken/collection/list
use aiken/crypto.{VerificationKeyHash}
use cardano/transaction.{InlineDatum, Output, Transaction}
use liquidity_manager/types.{Config, Invoice, State}
use liquidity_manager/utils.{
  cbtc_of, find_invoice, operator_input_cbtc, operator_output_cbtc,
  remove_invoice, submitted_after_expiry, verify_owner_output,
}

/// Validate deposit action
/// 1. Only authorized operator can deposit
/// 2. cBTC must be added to the pool
/// 3. State UTxO updated with new liquidity amount
/// 4. No double-spending or unauthorized modifications
pub fn validate_deposit(
  config: Config,
  datum: State,
  amount: Int,
  self: Transaction,
) -> Bool {
  // Extract transaction
  let tx = self

  // Check amount is positive
  expect amount > 0

  // Verify operator signature (only LM can deposit)
  expect list.has(tx.extra_signatories, config.lm_pkh)

  // Find unique state input from this script
  let state_inputs =
    list.filter(
      tx.inputs,
      fn(input) { input.output.address == config.script_address },
    )
  expect [state_input] = state_inputs

  // Find the unique state output back to this script
  let state_outputs =
    list.filter(
      tx.outputs,
      fn(output: Output) { output.address == config.script_address },
    )

  // Must be exactly one state output
  expect [state_output] = state_outputs

  // Extract new datum
  expect InlineDatum(new_datum_raw) = state_output.datum
  expect new_datum: State = new_datum_raw

  // Verify state transition: liquidity increased, reserved + invoice_id unchanged
  let expected_new_liquidity = datum.total_liquidity + amount

  expect new_datum.total_liquidity == expected_new_liquidity
  expect new_datum.reserved == datum.reserved
  expect new_datum.last_invoice_id == datum.last_invoice_id

  // Verify cBTC added to the pool
  let input_cbtc = cbtc_of(state_input.output.value, config)
  let output_cbtc = cbtc_of(state_output.value, config)
  expect output_cbtc == input_cbtc + amount

  // Calculate operator's cBTC change: (operator_outputs - operator_inputs)
  let operator_in_cbtc =
    operator_input_cbtc(tx.inputs, config.script_address, config)
  let operator_out_cbtc =
    operator_output_cbtc(tx.outputs, config.script_address, config)
  // Operator should have spent at least 'amount' cBTC more than they received back
  // operator_in_cbtc - operator_out_cbtc >= amount
  expect operator_in_cbtc >= operator_out_cbtc + amount

  True
}

/// Validate withdrawal action
/// 1. Only authorized operator can withdraw
/// 2. Cannot withdraw reserved liquidity
/// 3. Withdrawal amount ≤ available liquidity
/// 4. State UTxO updated correctly
pub fn validate_withdraw(
  config: Config,
  datum: State,
  amount: Int,
  self: Transaction,
) -> Bool {
  let tx = self

  expect amount > 0

  // Only authorized operator can withdraw
  expect list.has(tx.extra_signatories, config.lm_pkh)

  // Ensure sufficient available liquidity
  let available_liquidity = datum.total_liquidity - datum.reserved
  expect available_liquidity >= amount

  // Find unique state input from this script
  let state_inputs =
    list.filter(
      tx.inputs,
      fn(input) { input.output.address == config.script_address },
    )
  expect [state_input] = state_inputs

  // Find the unique state output back to this script
  let state_outputs =
    list.filter(
      tx.outputs,
      fn(output: Output) { output.address == config.script_address },
    )

  expect [state_output] = state_outputs

  // Extract new datum
  expect InlineDatum(new_datum_raw) = state_output.datum
  expect new_datum: State = new_datum_raw

  // Verify state transition: liquidity decreased, reserved + invoice_id unchanged
  let expected_new_liquidity = datum.total_liquidity - amount
  expect new_datum.total_liquidity == expected_new_liquidity
  expect new_datum.reserved == datum.reserved
  expect new_datum.last_invoice_id == datum.last_invoice_id

  // Verify cBTC removed from the pool
  let input_cbtc = cbtc_of(state_input.output.value, config)
  let output_cbtc = cbtc_of(state_output.value, config)
  expect output_cbtc == input_cbtc - amount

  // Operator should receive at least 'amount' more cBTC than they spent
  // operator_out_cbtc - operator_in_cbtc >= amount
  let operator_in_cbtc =
    operator_input_cbtc(tx.inputs, config.script_address, config)
  let operator_out_cbtc =
    operator_output_cbtc(tx.outputs, config.script_address, config)
  expect operator_out_cbtc >= operator_in_cbtc + amount

  True
}

/// Validate invoice creation
/// 1. Amount must be positive
/// 2. Amount ≤ available liquidity
/// 3. Only operator can create invoices
/// 4. Reserved liquidity increases
/// 5. Invoice ID increments
pub fn validate_create_invoice(
  config: Config,
  datum: State,
  amount: Int,
  owner: VerificationKeyHash,
  timestamp: Int,
  expires_at: Int,
  self: Transaction,
) -> Bool {
  let tx = self

  expect amount > 0
  expect timestamp > 0
  expect expires_at > timestamp

  expect !submitted_after_expiry(expires_at, tx)

  // Only authorized operator can create invoices
  expect list.has(tx.extra_signatories, config.lm_pkh)

  // Ensure sufficient available liquidity
  let available_liquidity = datum.total_liquidity - datum.reserved
  expect available_liquidity >= amount

  let state_inputs =
    list.filter(
      tx.inputs,
      fn(input) { input.output.address == config.script_address },
    )
  expect [_state_input] = state_inputs

  // Find unique state output back to this script
  let state_outputs =
    list.filter(
      tx.outputs,
      fn(output: Output) { output.address == config.script_address },
    )
  expect [state_output] = state_outputs

  // Extract new datum
  expect InlineDatum(new_datum_raw) = state_output.datum
  expect new_datum: State = new_datum_raw

  let new_id = datum.last_invoice_id + 1
  let new_invoice =
    Invoice { invoice_id: new_id, amount, owner, timestamp, expires_at }
  let expected_invoices = [new_invoice, ..datum.invoices]

  // Verify state transition: reserved increased, liquidity unchanged, invoice_id incremented
  let expected_new_reserved = datum.reserved + amount
  expect new_datum.total_liquidity == datum.total_liquidity
  expect new_datum.reserved == expected_new_reserved
  expect new_datum.last_invoice_id == new_id
  expect new_datum.invoices == expected_invoices

  True
}

/// Validate invoice fulfillment
/// 1. Invoice must be valid and pending
/// 2. Wrapped cBTC must be minted to owner's address
/// 3. Reserved liquidity decreases
/// 4. Invoice removed from state
/// 5. Total liquidity decreases accordingly
pub fn validate_fulfill_invoice(
  config: Config,
  datum: State,
  invoice: Invoice,
  self: Transaction,
) -> Bool {
  let tx = self

  let invoice_id = invoice.invoice_id
  expect invoice_id > 0
  expect invoice_id <= datum.last_invoice_id

  expect invoice.amount > 0

  // Check on-chain invoices
  expect Some(on_chain_inv) = find_invoice(datum.invoices, invoice.invoice_id)
  expect on_chain_inv == invoice

  expect !submitted_after_expiry(on_chain_inv.expires_at, tx)

  // Verify operator signature (only LM can fulfill)
  expect list.has(tx.extra_signatories, config.lm_pkh)

  // Find unique state input from this script
  let state_inputs =
    list.filter(
      tx.inputs,
      fn(input) { input.output.address == config.script_address },
    )
  expect [state_input] = state_inputs

  // Find unique state output back to this script
  let state_outputs =
    list.filter(
      tx.outputs,
      fn(output: Output) { output.address == config.script_address },
    )
  expect [state_output] = state_outputs

  // Extract new datum
  expect InlineDatum(new_datum_raw) = state_output.datum
  expect new_datum: State = new_datum_raw

  // Verify state transition: reserved decreased, liquidity unchanged, invoice_id unchanged
  let expected_new_reserved = datum.reserved - invoice.amount
  let expected_new_liquidity = datum.total_liquidity - invoice.amount
  expect expected_new_liquidity >= 0
  expect expected_new_reserved >= 0

  expect new_datum.total_liquidity == expected_new_liquidity
  expect new_datum.reserved == expected_new_reserved
  expect new_datum.last_invoice_id == datum.last_invoice_id

  // Remove fulfilled invoice from state
  let updated_invoices = remove_invoice(datum.invoices, invoice.invoice_id)
  expect new_datum.invoices == updated_invoices

  // Verify cBTC removed from the pool
  let input_cbtc = cbtc_of(state_input.output.value, config)
  let output_cbtc = cbtc_of(state_output.value, config)
  expect output_cbtc == input_cbtc - invoice.amount

  // Verify wrapped cBTC transferred to owner's address
  expect verify_owner_output(tx.outputs, invoice.owner, invoice.amount, config)
  True
}

/// Validate invoice cancellation
/// 1. Invoice must exist and is pending
/// 2. Only LM can cancel
/// 3. Cancellation only allowed after expiry
/// 4. Reserved decreases by invoice.amount
/// 5. Invoice status updated to Cancelled in state
pub fn validate_cancel_invoice(
  config: Config,
  datum: State,
  invoice_id: Int,
  self: Transaction,
) -> Bool {
  let tx = self

  expect invoice_id > 0
  expect invoice_id <= datum.last_invoice_id

  // Only authorized operator can cancel invoices
  expect list.has(tx.extra_signatories, config.lm_pkh)

  // Check on-chain invoices
  expect Some(on_chain_inv) = find_invoice(datum.invoices, invoice_id)
  expect submitted_after_expiry(on_chain_inv.expires_at, tx)

  // Find unique state output back to this script
  let state_outputs =
    list.filter(
      tx.outputs,
      fn(output: Output) { output.address == config.script_address },
    )
  expect [state_output] = state_outputs

  // Extract new datum
  expect InlineDatum(new_datum_raw) = state_output.datum
  expect new_datum: State = new_datum_raw

  // Verify state transition: reserved decreased, liquidity unchanged, invoice_id unchanged
  let expected_new_reserved = datum.reserved - on_chain_inv.amount
  expect expected_new_reserved >= 0

  expect new_datum.total_liquidity == datum.total_liquidity
  expect new_datum.reserved == expected_new_reserved
  expect new_datum.last_invoice_id == datum.last_invoice_id

  // Remove cancelled invoice from state
  let updated_invoices = remove_invoice(datum.invoices, invoice_id)
  expect new_datum.invoices == updated_invoices

  True
}
