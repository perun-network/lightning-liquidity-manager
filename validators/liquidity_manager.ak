use cardano/transaction.{OutputReference, Transaction}
use liquidity_manager/types.{
  Action, CancelInvoice, Config, CreateInvoice, Deposit, FulfillInvoice, State,
  Withdraw,
}
use liquidity_manager/validation.{
  validate_cancel_invoice, validate_create_invoice, validate_deposit,
  validate_fulfill_invoice, validate_withdraw,
}

use aiken/interval.{between, entirely_after}
use cardano/address.{Address, Credential}
use cardano/transaction.{NoDatum, Output}
use tests/helpers.{
  default_validity_range, lm_pkh, make_basic_tx, make_invoice,
  make_operator_input, make_operator_output, make_state_input, make_state_output,
  make_value, mock_output_ref, state_with_invoices, state_with_liquidity,
  test_config, user_pkh,
}

validator liquidity_manager(config: Config) {
  spend(
    datum: Option<State>,
    redeemer: Action,
    _utxo: OutputReference,
    self: Transaction,
  ) {
    expect Some(state) = datum
    when redeemer is {
      Deposit { amount } -> validate_deposit(config, state, amount, self)
      Withdraw { amount } -> validate_withdraw(config, state, amount, self)
      CreateInvoice { amount, owner, timestamp, expires_at } ->
        validate_create_invoice(
          config,
          state,
          amount,
          owner,
          timestamp,
          expires_at,
          self,
        )
      FulfillInvoice { invoice } ->
        validate_fulfill_invoice(config, state, invoice, self)
      CancelInvoice { invoice_id } ->
        validate_cancel_invoice(config, state, invoice_id, self)
    }
  }

  else(_) {
    fail
  }
}

// Helper to create mock TransactionId and OutputReference
fn mock_utxo() -> OutputReference {
  mock_output_ref(0)
}

test validator_deposit_success() {
  let config = test_config()
  let initial_state = state_with_liquidity(1000000, 500000)
  let deposit_amount = 250000
  let new_state = state_with_liquidity(1250000, 500000)

  let operator_input = make_operator_input(250000, 0)
  let state_input = make_state_input(initial_state, 1000000, 1)
  let operator_output = make_operator_output(0)
  let state_output = make_state_output(new_state, 1250000)

  let tx =
    make_basic_tx(
      inputs: [operator_input, state_input],
      outputs: [operator_output, state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  let redeemer = Deposit { amount: deposit_amount }
  let utxo = mock_utxo()
  liquidity_manager.spend(config, Some(initial_state), redeemer, utxo, tx)
}

test validator_deposit_unauthorized_fails() fail {
  let config = test_config()
  let initial_state = state_with_liquidity(1000000, 500000)
  let deposit_amount = 250000
  let new_state = state_with_liquidity(1250000, 500000)

  let operator_input = make_operator_input(250000, 0)
  let state_input = make_state_input(initial_state, 1000000, 1)
  let operator_output = make_operator_output(0)
  let state_output = make_state_output(new_state, 1250000)

  let tx =
    make_basic_tx(
      inputs: [operator_input, state_input],
      outputs: [operator_output, state_output],
      validity_range: default_validity_range(),
      signatories: [user_pkh],
    )

  let redeemer = Deposit { amount: deposit_amount }
  let utxo = mock_utxo()
  liquidity_manager.spend(config, Some(initial_state), redeemer, utxo, tx)
}

test validator_deposit_insufficient_cbtc_fails() fail {
  let config = test_config()
  let initial_state = state_with_liquidity(1000000, 500000)
  let deposit_amount = 250000
  let new_state = state_with_liquidity(1250000, 500000)

  // Operator only provides 100000 instead of 250000
  let operator_input = make_operator_input(100000, 0)
  let state_input = make_state_input(initial_state, 1000000, 1)
  let operator_output = make_operator_output(0)
  let state_output = make_state_output(new_state, 1250000)

  let tx =
    make_basic_tx(
      inputs: [operator_input, state_input],
      outputs: [operator_output, state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  let redeemer = Deposit { amount: deposit_amount }
  let utxo = mock_utxo()
  liquidity_manager.spend(config, Some(initial_state), redeemer, utxo, tx)
}

// Withdraw Tests

test validator_withdraw_success() {
  let config = test_config()
  let initial_state = state_with_liquidity(1000000, 500000)
  let withdraw_amount = 300000
  let new_state = state_with_liquidity(700000, 500000)

  let state_input = make_state_input(initial_state, 1000000, 0)
  let operator_output = make_operator_output(300000)
  let state_output = make_state_output(new_state, 700000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [operator_output, state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  let redeemer = Withdraw { amount: withdraw_amount }
  let utxo = mock_utxo()
  liquidity_manager.spend(config, Some(initial_state), redeemer, utxo, tx)
}

test validator_withdraw_unauthorized_fails() fail {
  let config = test_config()
  let initial_state = state_with_liquidity(1000000, 500000)
  let withdraw_amount = 300000
  let new_state = state_with_liquidity(700000, 500000)

  let state_input = make_state_input(initial_state, 1000000, 0)
  let operator_output = make_operator_output(300000)
  let state_output = make_state_output(new_state, 700000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [operator_output, state_output],
      validity_range: default_validity_range(),
      signatories: [user_pkh],
    )

  let redeemer = Withdraw { amount: withdraw_amount }
  let utxo = mock_utxo()
  liquidity_manager.spend(config, Some(initial_state), redeemer, utxo, tx)
}

test validator_withdraw_insufficient_liquidity_fails() fail {
  let config = test_config()
  let initial_state = state_with_liquidity(1000000, 800000)
  let withdraw_amount = 300000
  let new_state = state_with_liquidity(700000, 800000)

  let state_input = make_state_input(initial_state, 1000000, 0)
  let operator_output = make_operator_output(300000)
  let state_output = make_state_output(new_state, 700000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [operator_output, state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  let redeemer = Withdraw { amount: withdraw_amount }
  let utxo = mock_utxo()
  liquidity_manager.spend(config, Some(initial_state), redeemer, utxo, tx)
}

// Create Invoice Tests

test validator_create_invoice_success() {
  let config = test_config()
  let initial_state = state_with_liquidity(1000000, 0)
  let invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)
  let state_after_create = state_with_invoices(1000000, 200000, 1, [invoice])

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(state_after_create, 1000000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  let redeemer =
    CreateInvoice {
      amount: invoice.amount,
      owner: invoice.owner,
      timestamp: invoice.timestamp,
      expires_at: invoice.expires_at,
    }
  let utxo = mock_utxo()
  liquidity_manager.spend(config, Some(initial_state), redeemer, utxo, tx)
}

test validator_create_invoice_unauthorized_fails() fail {
  let config = test_config()
  let initial_state = state_with_liquidity(1000000, 0)
  let invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)
  let state_after_create = state_with_invoices(1000000, 200000, 1, [invoice])

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(state_after_create, 1000000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output],
      validity_range: default_validity_range(),
      signatories: [user_pkh],
    )

  let redeemer =
    CreateInvoice {
      amount: invoice.amount,
      owner: invoice.owner,
      timestamp: invoice.timestamp,
      expires_at: invoice.expires_at,
    }
  let utxo = mock_utxo()
  liquidity_manager.spend(config, Some(initial_state), redeemer, utxo, tx)
}

test validator_create_invoice_insufficient_liquidity_fails() fail {
  let config = test_config()
  let initial_state = state_with_liquidity(100000, 0)
  let invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)
  let state_after_create = state_with_invoices(100000, 200000, 1, [invoice])

  let state_input = make_state_input(initial_state, 100000, 0)
  let state_output = make_state_output(state_after_create, 100000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  let redeemer =
    CreateInvoice {
      amount: invoice.amount,
      owner: invoice.owner,
      timestamp: invoice.timestamp,
      expires_at: invoice.expires_at,
    }
  let utxo = mock_utxo()
  liquidity_manager.spend(config, Some(initial_state), redeemer, utxo, tx)
}

// Fulfill Invoice Tests

test validator_fulfill_invoice_success() {
  let config = test_config()
  let invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)
  let initial_state = state_with_invoices(1000000, 200000, 1, [invoice])
  let state_after_fulfill = state_with_invoices(800000, 0, 1, [])

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(state_after_fulfill, 800000)

  let owner_address =
    Address {
      payment_credential: Credential.VerificationKey(invoice.owner),
      stake_credential: None,
    }
  let owner_output =
    Output {
      address: owner_address,
      value: make_value(2_000_000, 200_000),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output, owner_output],
      validity_range: between(1200000, 1500000),
      signatories: [lm_pkh],
    )

  let redeemer = FulfillInvoice { invoice }
  let utxo = mock_utxo()
  liquidity_manager.spend(config, Some(initial_state), redeemer, utxo, tx)
}

test validator_fulfill_invoice_unauthorized_fails() fail {
  let config = test_config()
  let invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)
  let initial_state = state_with_invoices(1000000, 200000, 1, [invoice])
  let state_after_fulfill = state_with_invoices(800000, 0, 1, [])

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(state_after_fulfill, 800000)

  let owner_address =
    Address {
      payment_credential: Credential.VerificationKey(invoice.owner),
      stake_credential: None,
    }
  let owner_output =
    Output {
      address: owner_address,
      value: make_value(2_000_000, 200_000),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output, owner_output],
      validity_range: between(1200000, 1500000),
      signatories: [user_pkh],
    )

  let redeemer = FulfillInvoice { invoice }
  let utxo = mock_utxo()
  liquidity_manager.spend(config, Some(initial_state), redeemer, utxo, tx)
}

test validator_fulfill_invoice_insufficient_cbtc_fails() fail {
  let config = test_config()
  let invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)
  let initial_state = state_with_invoices(1000000, 200000, 1, [invoice])
  let state_after_fulfill = state_with_invoices(800000, 0, 1, [])

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(state_after_fulfill, 800000)

  let owner_address =
    Address {
      payment_credential: Credential.VerificationKey(invoice.owner),
      stake_credential: None,
    }
  // Owner receives only 150000 instead of 200000
  let owner_output =
    Output {
      address: owner_address,
      value: make_value(2_000_000, 150_000),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output, owner_output],
      validity_range: between(1200000, 1500000),
      signatories: [lm_pkh],
    )

  let redeemer = FulfillInvoice { invoice }
  let utxo = mock_utxo()
  liquidity_manager.spend(config, Some(initial_state), redeemer, utxo, tx)
}

test validator_fulfill_invoice_expired_fails() fail {
  let config = test_config()
  let invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)
  let initial_state = state_with_invoices(1000000, 200000, 1, [invoice])
  let state_after_fulfill = state_with_invoices(800000, 0, 1, [])

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(state_after_fulfill, 800000)

  let owner_address =
    Address {
      payment_credential: Credential.VerificationKey(invoice.owner),
      stake_credential: None,
    }
  let owner_output =
    Output {
      address: owner_address,
      value: make_value(2_000_000, 200_000),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output, owner_output],
      validity_range: entirely_after(1700000),
      signatories: [lm_pkh],
    )

  let redeemer = FulfillInvoice { invoice }
  let utxo = mock_utxo()
  liquidity_manager.spend(config, Some(initial_state), redeemer, utxo, tx)
}

// Cancel Invoice Tests

test validator_cancel_invoice_success() {
  let config = test_config()
  let invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)
  let initial_state = state_with_invoices(1000000, 200000, 1, [invoice])
  let state_after_cancel = state_with_invoices(1000000, 0, 1, [])

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(state_after_cancel, 1000000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output],
      validity_range: entirely_after(1600000),
      signatories: [lm_pkh],
    )

  let redeemer = CancelInvoice { invoice_id: invoice.invoice_id }
  let utxo = mock_utxo()
  liquidity_manager.spend(config, Some(initial_state), redeemer, utxo, tx)
}

test validator_cancel_invoice_unauthorized_fails() fail {
  let config = test_config()
  let invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)
  let initial_state = state_with_invoices(1000000, 200000, 1, [invoice])
  let state_after_cancel = state_with_invoices(1000000, 0, 1, [])

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(state_after_cancel, 1000000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output],
      validity_range: entirely_after(1600000),
      signatories: [user_pkh],
    )

  let redeemer = CancelInvoice { invoice_id: invoice.invoice_id }
  let utxo = mock_utxo()
  liquidity_manager.spend(config, Some(initial_state), redeemer, utxo, tx)
}

test validator_cancel_invoice_before_expiry_fails() fail {
  let config = test_config()
  let invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)
  let initial_state = state_with_invoices(1000000, 200000, 1, [invoice])
  let state_after_cancel = state_with_invoices(1000000, 0, 1, [])

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(state_after_cancel, 1000000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  let redeemer = CancelInvoice { invoice_id: invoice.invoice_id }
  let utxo = mock_utxo()
  liquidity_manager.spend(config, Some(initial_state), redeemer, utxo, tx)
}

test validator_cancel_nonexistent_invoice_fails() fail {
  let config = test_config()
  let invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)
  let initial_state = state_with_invoices(1000000, 200000, 1, [invoice])
  let state_after_cancel = state_with_invoices(1000000, 0, 1, [])

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(state_after_cancel, 1000000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output],
      validity_range: entirely_after(1600000),
      signatories: [lm_pkh],
    )

  let redeemer = CancelInvoice { invoice_id: 999 }
  let utxo = mock_utxo()
  liquidity_manager.spend(config, Some(initial_state), redeemer, utxo, tx)
}