use liquidity_manager/validation.{validate_deposit}
use tests/helpers.{
  assert_liquidity_increased, default_validity_range, lm_pkh, make_basic_tx,
  make_operator_input, make_operator_output, make_state_input, make_state_output,
  state_with_liquidity, test_config, user_pkh,
}

// Successful deposit: operator provides cBTC to state
test deposit_success() {
  let initial_state = state_with_liquidity(1000000, 500000)
  let deposit_amount = 250000
  let new_state = state_with_liquidity(1000000 + deposit_amount, 500000)

  // Operator input: 250000 cBTC to deposit
  let operator_input = make_operator_input(250000, 0)
  let state_input = make_state_input(initial_state, 1000000, 1)
  // Operator output: no change (cBTC sent to state)
  let operator_output = make_operator_output(0)
  let state_output = make_state_output(new_state, 1250000)

  let tx =
    make_basic_tx(
      inputs: [operator_input, state_input],
      outputs: [operator_output, state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  let result =
    validate_deposit(test_config(), initial_state, deposit_amount, tx)

  result && assert_liquidity_increased(1000000, 1250000, deposit_amount) && new_state.reserved == initial_state.reserved
}

// Deposit with change: operator has remaining cBTC
test deposit_with_operator_change() {
  let initial_state = state_with_liquidity(1000000, 500000)
  let deposit_amount = 250000

  let operator_input = make_operator_input(350000, 0)
  let state_input = make_state_input(initial_state, 1000000, 1)
  let operator_output = make_operator_output(100000)
  let state_output =
    make_state_output(state_with_liquidity(1250000, 500000), 1250000)

  let tx =
    make_basic_tx(
      inputs: [operator_input, state_input],
      outputs: [operator_output, state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  validate_deposit(test_config(), initial_state, deposit_amount, tx)
}

// Unauthorized operator fails
test deposit_unauthorized_operator_fails() fail {
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

  validate_deposit(test_config(), initial_state, deposit_amount, tx)
}

// Insufficient cBTC from operator fails
test deposit_insufficient_operator_cbtc_fails() fail {
  let initial_state = state_with_liquidity(1000000, 500000)
  let deposit_amount = 250000
  let new_state = state_with_liquidity(1250000, 500000)

  // Operator only provides 100000, but deposit requires 250000
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

  validate_deposit(test_config(), initial_state, deposit_amount, tx)
}

// Zero amount fails
test deposit_zero_amount_fails() fail {
  let initial_state = state_with_liquidity(1000000, 500000)
  let deposit_amount = 0
  let new_state = state_with_liquidity(1000000, 500000)

  let operator_input = make_operator_input(0, 0)
  let state_input = make_state_input(initial_state, 1000000, 1)
  let operator_output = make_operator_output(0)
  let state_output = make_state_output(new_state, 1000000)

  let tx =
    make_basic_tx(
      inputs: [operator_input, state_input],
      outputs: [operator_output, state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  validate_deposit(test_config(), initial_state, deposit_amount, tx)
}

// Negative amount fails
test deposit_negative_amount_fails() fail {
  let initial_state = state_with_liquidity(1000000, 500000)
  let deposit_amount = -100000
  let new_state = state_with_liquidity(900000, 500000)

  let operator_input = make_operator_input(0, 0)
  let state_input = make_state_input(initial_state, 1000000, 1)
  let operator_output = make_operator_output(100000)
  let state_output = make_state_output(new_state, 900000)

  let tx =
    make_basic_tx(
      inputs: [operator_input, state_input],
      outputs: [operator_output, state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  validate_deposit(test_config(), initial_state, deposit_amount, tx)
}

// Multiple sequential deposits
test multiple_deposits_accumulate() {
  let initial_state = state_with_liquidity(500000, 200000)
  let first_deposit = 300000
  let second_deposit = 400000

  // First deposit
  let state_after_first = state_with_liquidity(800000, 200000)
  let first_op_input = make_operator_input(300000, 0)
  let first_state_input = make_state_input(initial_state, 500000, 1)
  let first_op_output = make_operator_output(0)
  let first_state_output = make_state_output(state_after_first, 800000)

  let first_tx =
    make_basic_tx(
      inputs: [first_op_input, first_state_input],
      outputs: [first_op_output, first_state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  let first_result =
    validate_deposit(test_config(), initial_state, first_deposit, first_tx)

  // Second deposit
  let state_after_second = state_with_liquidity(1200000, 200000)
  let second_op_input = make_operator_input(400000, 2)
  let second_state_input = make_state_input(state_after_first, 800000, 3)
  let second_op_output = make_operator_output(0)
  let second_state_output = make_state_output(state_after_second, 1200000)

  let second_tx =
    make_basic_tx(
      inputs: [second_op_input, second_state_input],
      outputs: [second_op_output, second_state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  let second_result =
    validate_deposit(
      test_config(),
      state_after_first,
      second_deposit,
      second_tx,
    )

  first_result && second_result && assert_liquidity_increased(
    500000,
    1200000,
    first_deposit + second_deposit,
  ) && state_after_second.reserved == initial_state.reserved
}
