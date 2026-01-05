use aiken/interval.{between, entirely_after}
use cardano/address.{Address, Credential}
use cardano/transaction.{NoDatum, Output}
use liquidity_manager/types.{Invoice}
use liquidity_manager/validation.{
  validate_cancel_invoice, validate_create_invoice, validate_fulfill_invoice,
}
use tests/helpers.{
  default_invoice, default_validity_range, lm_pkh, make_basic_tx, make_invoice,
  make_state_input, make_state_output, make_value, state_with_invoices,
  state_with_liquidity, test_config, user_pkh, user_pkh_2, user_pkh_3,
}

test default_invoice_payload() {
  let invoice = default_invoice()
  invoice.invoice_id == 1 && invoice.amount == 100000 && invoice.owner == user_pkh && invoice.timestamp == 1000000 && invoice.expires_at == 1500000
}

test make_invoice_payload() {
  let invoice =
    make_invoice(
      id: 1,
      amount: 100000,
      owner: user_pkh,
      timestamp: 1000000,
      expires_at: 1500000,
    )
  and {
    invoice.invoice_id == 1,
    invoice.amount == 100000,
    invoice.owner == user_pkh,
    invoice.timestamp == 1000000,
    invoice.expires_at == 1500000,
  }
}

// Create Invoice
test create_invoice_success() {
  let initial_state = state_with_liquidity(1000000, 0)
  let invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)

  let state_after_invoice = state_with_invoices(1000000, 200000, 1, [invoice])

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(state_after_invoice, 1000000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  let result =
    validate_create_invoice(
      test_config(),
      initial_state,
      invoice.amount,
      invoice.owner,
      invoice.timestamp,
      invoice.expires_at,
      tx,
    )
  result && state_after_invoice.reserved == initial_state.reserved + invoice.amount && state_after_invoice.last_invoice_id == initial_state.last_invoice_id + 1
}

test create_invoice_insufficient_liquidity_fails() fail {
  let initial_state = state_with_liquidity(100000, 0)
  let invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)

  let state_input = make_state_input(initial_state, 100000, 0)
  let state_output = make_state_output(initial_state, 100000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  validate_create_invoice(
    test_config(),
    initial_state,
    invoice.amount,
    invoice.owner,
    invoice.timestamp,
    invoice.expires_at,
    tx,
  )
}

test create_invoice_unauthorized_operator_fails() fail {
  let initial_state = state_with_liquidity(1000000, 0)
  let invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(initial_state, 1000000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output],
      validity_range: default_validity_range(),
      signatories: [user_pkh],
    )

  validate_create_invoice(
    test_config(),
    initial_state,
    invoice.amount,
    invoice.owner,
    invoice.timestamp,
    invoice.expires_at,
    tx,
  )
}

test create_invoice_with_expired_timestamp_fails() fail {
  let initial_state = state_with_liquidity(1000000, 0)
  let invoice = make_invoice(1, 200000, user_pkh, 1100000, 1050000)

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(initial_state, 1000000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  validate_create_invoice(
    test_config(),
    initial_state,
    invoice.amount,
    invoice.owner,
    invoice.timestamp,
    invoice.expires_at,
    tx,
  )
}

test create_invoice_negative_amount_fails() fail {
  let initial_state = state_with_liquidity(1000000, 0)
  let invoice = make_invoice(1, -200000, user_pkh, 1100000, 1600000)

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(initial_state, 1000000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  validate_create_invoice(
    test_config(),
    initial_state,
    invoice.amount,
    invoice.owner,
    invoice.timestamp,
    invoice.expires_at,
    tx,
  )
}

test create_invoice_zero_amount_fails() fail {
  let initial_state = state_with_liquidity(1000000, 0)
  let invoice = make_invoice(1, 0, user_pkh, 1100000, 1600000)

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(initial_state, 1000000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  validate_create_invoice(
    test_config(),
    initial_state,
    invoice.amount,
    invoice.owner,
    invoice.timestamp,
    invoice.expires_at,
    tx,
  )
}

test create_invoice_submitted_after_expiry_fails() fail {
  let initial_state = state_with_liquidity(1000000, 0)
  let invoice = make_invoice(1, 200000, user_pkh, 1100000, 1200000)

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(initial_state, 1000000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output],
      validity_range: entirely_after(1300000),
      signatories: [lm_pkh],
    )

  validate_create_invoice(
    test_config(),
    initial_state,
    invoice.amount,
    invoice.owner,
    invoice.timestamp,
    invoice.expires_at,
    tx,
  )
}

test create_invoice_multiple_sequential() {
  // First invoice
  let initial_state = state_with_liquidity(1000000, 0)
  let first_invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)

  let state_after_first =
    state_with_invoices(1000000, 200000, 1, [first_invoice])

  let first_input = make_state_input(initial_state, 1000000, 0)
  let first_output = make_state_output(state_after_first, 1000000)

  let first_tx =
    make_basic_tx(
      inputs: [first_input],
      outputs: [first_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  let first_result =
    validate_create_invoice(
      test_config(),
      initial_state,
      first_invoice.amount,
      first_invoice.owner,
      first_invoice.timestamp,
      first_invoice.expires_at,
      first_tx,
    )

  // Second invoice
  let second_invoice = make_invoice(2, 300000, user_pkh_2, 1200000, 1700000)

  let state_after_second =
    state_with_invoices(1000000, 500000, 2, [second_invoice, first_invoice])

  let second_input = make_state_input(state_after_first, 1000000, 1)
  let second_output = make_state_output(state_after_second, 1000000)

  let second_tx =
    make_basic_tx(
      inputs: [second_input],
      outputs: [second_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  let second_result =
    validate_create_invoice(
      test_config(),
      state_after_first,
      second_invoice.amount,
      second_invoice.owner,
      second_invoice.timestamp,
      second_invoice.expires_at,
      second_tx,
    )

  first_result && second_result && state_after_second.reserved == initial_state.reserved + first_invoice.amount + second_invoice.amount && state_after_second.last_invoice_id == initial_state.last_invoice_id + 2
}

// Fulfill Invoice Tests
test fulfill_invoice_success() {
  let initial_invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)
  let initial_state = state_with_invoices(1000000, 200000, 1, [initial_invoice])
  let state_after_fulfill = state_with_invoices(800000, 0, 1, [])

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(state_after_fulfill, 800000)

  // Create output to owner with the cBTC
  let owner_address =
    Address {
      payment_credential: Credential.VerificationKey(initial_invoice.owner),
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
  let result =
    validate_fulfill_invoice(test_config(), initial_state, initial_invoice, tx)
  result && state_after_fulfill.reserved == initial_state.reserved - initial_invoice.amount && state_after_fulfill.last_invoice_id == initial_state.last_invoice_id && state_after_fulfill.invoices == [] && state_after_fulfill.total_liquidity == initial_state.total_liquidity - initial_invoice.amount
}

test fulfill_invoice_insufficient_cbtc_to_owner_fails() fail {
  // Owner receives less than invoice amount
  let initial_invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)
  let initial_state = state_with_invoices(1000000, 200000, 1, [initial_invoice])
  let state_after_fulfill = state_with_invoices(800000, 0, 1, [])

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(state_after_fulfill, 800000)

  let owner_address =
    Address {
      payment_credential: Credential.VerificationKey(initial_invoice.owner),
      stake_credential: None,
    }
  // Owner only receives 150000 instead of 200000
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

  validate_fulfill_invoice(test_config(), initial_state, initial_invoice, tx)
}

test fulfill_invoice_unauthorized_operator_fails() fail {
  let initial_invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)
  let initial_state = state_with_invoices(1000000, 200000, 1, [initial_invoice])
  let state_after_fulfill = state_with_invoices(800000, 0, 1, [])

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(state_after_fulfill, 800000)

  let owner_address =
    Address {
      payment_credential: Credential.VerificationKey(initial_invoice.owner),
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

  validate_fulfill_invoice(test_config(), initial_state, initial_invoice, tx)
}

test fulfill_invoice_expired_fails() fail {
  let initial_invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)
  let initial_state = state_with_invoices(1000000, 200000, 1, [initial_invoice])
  let state_after_fulfill = state_with_invoices(800000, 0, 1, [])

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(state_after_fulfill, 800000)

  let owner_address =
    Address {
      payment_credential: Credential.VerificationKey(initial_invoice.owner),
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

  validate_fulfill_invoice(test_config(), initial_state, initial_invoice, tx)
}

test fulfill_invoice_no_owner_output_fails() fail {
  // No output to owner address
  let initial_invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)
  let initial_state = state_with_invoices(1000000, 200000, 1, [initial_invoice])
  let state_after_fulfill = state_with_invoices(800000, 0, 1, [])

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(state_after_fulfill, 800000)

  // No owner output provided
  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output],
      validity_range: between(1200000, 1500000),
      signatories: [lm_pkh],
    )

  validate_fulfill_invoice(test_config(), initial_state, initial_invoice, tx)
}

test fulfill_invoice_wrong_owner_address_fails() fail {
  // cBTC goes to wrong owner address
  let initial_invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)
  let initial_state = state_with_invoices(1000000, 200000, 1, [initial_invoice])
  let state_after_fulfill = state_with_invoices(800000, 0, 1, [])

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(state_after_fulfill, 800000)

  // Send to wrong owner (user_pkh_2 instead of user_pkh)
  let wrong_owner_address =
    Address {
      payment_credential: Credential.VerificationKey(user_pkh_2),
      stake_credential: None,
    }
  let owner_output =
    Output {
      address: wrong_owner_address,
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

  validate_fulfill_invoice(test_config(), initial_state, initial_invoice, tx)
}

test fulfill_invoice_wrong_invoice_id_fails() fail {
  // Mismatch between invoice passed and state's actual invoice
  let on_chain_invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)
  let wrong_invoice = make_invoice(2, 200000, user_pkh, 1100000, 1600000)
  let initial_state =
    state_with_invoices(1000000, 200000, 1, [on_chain_invoice])
  let state_after_fulfill = state_with_invoices(800000, 0, 1, [])

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(state_after_fulfill, 800000)

  let owner_address =
    Address {
      payment_credential: Credential.VerificationKey(on_chain_invoice.owner),
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

  validate_fulfill_invoice(test_config(), initial_state, wrong_invoice, tx)
}

test fulfill_invoice_different_owners() {
  // Test fulfilling invoice for different owner addresses
  let first_invoice = make_invoice(1, 150000, user_pkh_2, 1100000, 1600000)
  let second_invoice = make_invoice(2, 250000, user_pkh_3, 1150000, 1650000)
  let initial_state =
    state_with_invoices(1000000, 400000, 2, [second_invoice, first_invoice])

  // Fulfill first invoice
  let state_after_first =
    state_with_invoices(850000, 250000, 2, [second_invoice])
  let state_input_1 = make_state_input(initial_state, 1000000, 0)
  let state_output_1 = make_state_output(state_after_first, 850000)

  let owner_address_1 =
    Address {
      payment_credential: Credential.VerificationKey(first_invoice.owner),
      stake_credential: None,
    }
  let owner_output_1 =
    Output {
      address: owner_address_1,
      value: make_value(2_000_000, 150_000),
      datum: NoDatum,
      reference_script: None,
    }

  let tx_1 =
    make_basic_tx(
      inputs: [state_input_1],
      outputs: [state_output_1, owner_output_1],
      validity_range: between(1200000, 1500000),
      signatories: [lm_pkh],
    )

  let result_1 =
    validate_fulfill_invoice(test_config(), initial_state, first_invoice, tx_1)

  // Fulfill second invoice
  let state_after_second = state_with_invoices(600000, 0, 2, [])
  let state_input_2 = make_state_input(state_after_first, 850000, 1)
  let state_output_2 = make_state_output(state_after_second, 600000)

  let owner_address_2 =
    Address {
      payment_credential: Credential.VerificationKey(second_invoice.owner),
      stake_credential: None,
    }
  let owner_output_2 =
    Output {
      address: owner_address_2,
      value: make_value(2_000_000, 250_000),
      datum: NoDatum,
      reference_script: None,
    }

  let tx_2 =
    make_basic_tx(
      inputs: [state_input_2],
      outputs: [state_output_2, owner_output_2],
      validity_range: between(1200000, 1550000),
      signatories: [lm_pkh],
    )

  let result_2 =
    validate_fulfill_invoice(
      test_config(),
      state_after_first,
      second_invoice,
      tx_2,
    )

  result_1 && result_2 && state_after_second.reserved == 0 && state_after_second.total_liquidity == 600000
}

test fulfill_invoice_owner_receives_multiple_outputs() {
  // Owner receives cBTC across multiple outputs
  let initial_invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)
  let initial_state = state_with_invoices(1000000, 200000, 1, [initial_invoice])
  let state_after_fulfill = state_with_invoices(800000, 0, 1, [])

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(state_after_fulfill, 800000)

  let owner_address =
    Address {
      payment_credential: Credential.VerificationKey(initial_invoice.owner),
      stake_credential: None,
    }
  // Split cBTC across two outputs
  let owner_output_1 =
    Output {
      address: owner_address,
      value: make_value(2_000_000, 120_000),
      datum: NoDatum,
      reference_script: None,
    }
  let owner_output_2 =
    Output {
      address: owner_address,
      value: make_value(1_000_000, 80_000),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output, owner_output_1, owner_output_2],
      validity_range: between(1200000, 1500000),
      signatories: [lm_pkh],
    )
  let result =
    validate_fulfill_invoice(test_config(), initial_state, initial_invoice, tx)
  result && state_after_fulfill.total_liquidity == 800000
}

// Cancel Invoice
test cancel_invoice_success() {
  let initial_invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)
  let initial_state = state_with_invoices(1000000, 200000, 1, [initial_invoice])

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

  let result =
    validate_cancel_invoice(
      test_config(),
      initial_state,
      initial_invoice.invoice_id,
      tx,
    )
  result && state_after_cancel.reserved == initial_state.reserved - initial_invoice.amount && state_after_cancel.last_invoice_id == initial_state.last_invoice_id && state_after_cancel.invoices == [] && state_after_cancel.total_liquidity == initial_state.total_liquidity
}

test cancel_invoice_unauthorized_operator_fails() fail {
  let initial_invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)
  let initial_state = state_with_invoices(1000000, 200000, 1, [initial_invoice])

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(initial_state, 1000000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output],
      validity_range: entirely_after(1600000),
      signatories: [user_pkh],
    )

  validate_cancel_invoice(
    test_config(),
    initial_state,
    initial_invoice.invoice_id,
    tx,
  )
}

test cancel_invoice_fails_before_expiry() fail {
  let initial_invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)
  let initial_state = state_with_invoices(1000000, 200000, 1, [initial_invoice])

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(initial_state, 1000000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  validate_cancel_invoice(
    test_config(),
    initial_state,
    initial_invoice.invoice_id,
    tx,
  )
}

test cancel_nonexistent_invoice_fails() fail {
  let initial_invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)
  let initial_state = state_with_invoices(1000000, 200000, 1, [initial_invoice])

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(initial_state, 1000000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output],
      validity_range: entirely_after(1600000),
      signatories: [lm_pkh],
    )

  validate_cancel_invoice(
    test_config(),
    initial_state,
    999,
    // Non-existent invoice ID
    tx,
  )
}

test cancel_invoice_multiple_sequential() {
  // Initial state with two invoices
  let first_invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)
  let second_invoice = make_invoice(2, 300000, user_pkh_2, 1200000, 1700000)

  let initial_state =
    state_with_invoices(1000000, 500000, 2, [second_invoice, first_invoice])

  // Cancel first invoice
  let state_after_first_cancel =
    state_with_invoices(1000000, 300000, 2, [second_invoice])

  let first_input = make_state_input(initial_state, 1000000, 0)
  let first_output = make_state_output(state_after_first_cancel, 1000000)

  let first_tx =
    make_basic_tx(
      inputs: [first_input],
      outputs: [first_output],
      validity_range: entirely_after(1600000),
      signatories: [lm_pkh],
    )

  let first_result =
    validate_cancel_invoice(
      test_config(),
      initial_state,
      first_invoice.invoice_id,
      first_tx,
    )

  // Cancel second invoice
  let state_after_second_cancel = state_with_invoices(1000000, 0, 2, [])

  let second_input = make_state_input(state_after_first_cancel, 1000000, 1)
  let second_output = make_state_output(state_after_second_cancel, 1000000)

  let second_tx =
    make_basic_tx(
      inputs: [second_input],
      outputs: [second_output],
      validity_range: entirely_after(1700000),
      signatories: [lm_pkh],
    )

  let second_result =
    validate_cancel_invoice(
      test_config(),
      state_after_first_cancel,
      second_invoice.invoice_id,
      second_tx,
    )

  first_result && second_result && state_after_second_cancel.reserved == initial_state.reserved - first_invoice.amount - second_invoice.amount && state_after_second_cancel.last_invoice_id == initial_state.last_invoice_id && state_after_second_cancel.invoices == [] && state_after_second_cancel.total_liquidity == initial_state.total_liquidity
}

// WORKFLOW Tests
test create_and_fulfill_basic() {
  // Step 1: Create invoice
  let initial_state = state_with_liquidity(1000000, 0)
  let invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)
  let state_after_create = state_with_invoices(1000000, 200000, 1, [invoice])

  let state_input_1 = make_state_input(initial_state, 1000000, 0)
  let state_output_1 = make_state_output(state_after_create, 1000000)

  let create_tx =
    make_basic_tx(
      inputs: [state_input_1],
      outputs: [state_output_1],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  let create_result =
    validate_create_invoice(
      test_config(),
      initial_state,
      invoice.amount,
      invoice.owner,
      invoice.timestamp,
      invoice.expires_at,
      create_tx,
    )

  // Step 2: Fulfill the invoice
  let state_after_fulfill = state_with_invoices(800000, 0, 1, [])

  let state_input_2 = make_state_input(state_after_create, 1000000, 1)
  let state_output_2 = make_state_output(state_after_fulfill, 800000)

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

  let fulfill_tx =
    make_basic_tx(
      inputs: [state_input_2],
      outputs: [state_output_2, owner_output],
      validity_range: between(1200000, 1500000),
      signatories: [lm_pkh],
    )

  let fulfill_result =
    validate_fulfill_invoice(
      test_config(),
      state_after_create,
      invoice,
      fulfill_tx,
    )

  create_result && fulfill_result && state_after_fulfill.reserved == 0 && state_after_fulfill.total_liquidity == 800000
}

test create_and_cancel_basic() {
  // Step 1: Create invoice
  let initial_state = state_with_liquidity(1000000, 0)
  let invoice = make_invoice(1, 200000, user_pkh, 1100000, 1600000)
  let state_after_create = state_with_invoices(1000000, 200000, 1, [invoice])

  let state_input_1 = make_state_input(initial_state, 1000000, 0)
  let state_output_1 = make_state_output(state_after_create, 1000000)

  let create_tx =
    make_basic_tx(
      inputs: [state_input_1],
      outputs: [state_output_1],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  let create_result =
    validate_create_invoice(
      test_config(),
      initial_state,
      invoice.amount,
      invoice.owner,
      invoice.timestamp,
      invoice.expires_at,
      create_tx,
    )

  // Step 2: Cancel invoice after expiry
  let state_after_cancel = state_with_invoices(1000000, 0, 1, [])

  let state_input_2 = make_state_input(state_after_create, 1000000, 1)
  let state_output_2 = make_state_output(state_after_cancel, 1000000)

  let cancel_tx =
    make_basic_tx(
      inputs: [state_input_2],
      outputs: [state_output_2],
      validity_range: entirely_after(1600000),
      signatories: [lm_pkh],
    )

  let cancel_result =
    validate_cancel_invoice(
      test_config(),
      state_after_create,
      invoice.invoice_id,
      cancel_tx,
    )

  create_result && cancel_result && state_after_cancel.reserved == 0 && state_after_cancel.total_liquidity == 1000000
}
