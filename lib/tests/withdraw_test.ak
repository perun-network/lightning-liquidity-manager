use liquidity_manager/types.{State}
use liquidity_manager/validation.{validate_withdraw}
use tests/helpers.{
  assert_liquidity_decreased, default_validity_range, lm_pkh, make_basic_tx,
  make_operator_output, make_state_input, make_state_output,
  state_with_liquidity, test_config, user_pkh,
}

// Successful withdraw: state provides cBTC to operator
test withdraw_success() {
  let initial_state = state_with_liquidity(1000000, 500000)
  let withdraw_amount = 300000
  let new_state = state_with_liquidity(700000, 500000)

  let state_input = make_state_input(initial_state, 1000000, 0)
  // Operator output: receives the 300000 cBTC
  let operator_output = make_operator_output(300000)
  let state_output = make_state_output(new_state, 700000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [operator_output, state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  let result =
    validate_withdraw(test_config(), initial_state, withdraw_amount, tx)
  result && assert_liquidity_decreased(1000000, 700000, withdraw_amount) && new_state.reserved == initial_state.reserved
}

// Unauthorized operator fails
test withdraw_unauthorized_operator_fails() fail {
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

  validate_withdraw(test_config(), initial_state, withdraw_amount, tx)
}

// Insufficient available liquidity fails
test withdraw_insufficient_liquidity_fails() fail {
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

  validate_withdraw(test_config(), initial_state, withdraw_amount, tx)
}

// Operator doesn't receive full amount fails
test withdraw_incomplete_operator_cbtc_fails() fail {
  let initial_state = state_with_liquidity(1000000, 500000)
  let withdraw_amount = 300000
  let new_state = state_with_liquidity(700000, 500000)

  let state_input = make_state_input(initial_state, 1000000, 0)
  // Operator only receives 200000 instead of 300000
  let operator_output = make_operator_output(200000)
  let state_output = make_state_output(new_state, 700000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [operator_output, state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  validate_withdraw(test_config(), initial_state, withdraw_amount, tx)
}

// Negative amount fails
test withdraw_negative_amount_fails() fail {
  let initial_state = state_with_liquidity(1000000, 500000)
  let withdraw_amount = -300000
  let new_state = state_with_liquidity(1300000, 500000)

  let state_input = make_state_input(initial_state, 1000000, 0)
  let operator_output = make_operator_output(0)
  let state_output = make_state_output(new_state, 1300000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [operator_output, state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  validate_withdraw(test_config(), initial_state, withdraw_amount, tx)
}

// Zero amount fails
test withdraw_zero_amount_fails() fail {
  let initial_state = state_with_liquidity(1000000, 500000)
  let withdraw_amount = 0
  let new_state = state_with_liquidity(1000000, 500000)

  let state_input = make_state_input(initial_state, 1000000, 0)
  let operator_output = make_operator_output(0)
  let state_output = make_state_output(new_state, 1000000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [operator_output, state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  validate_withdraw(test_config(), initial_state, withdraw_amount, tx)
}

// Exact available liquidity
test withdraw_exact_available_liquidity_success() {
  let initial_state = state_with_liquidity(1000000, 500000)
  let withdraw_amount = 500000
  let new_state = state_with_liquidity(500000, 500000)

  let state_input = make_state_input(initial_state, 1000000, 0)
  let operator_output = make_operator_output(500000)
  let state_output = make_state_output(new_state, 500000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [operator_output, state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  let result =
    validate_withdraw(test_config(), initial_state, withdraw_amount, tx)
  result && assert_liquidity_decreased(1000000, 500000, withdraw_amount) && new_state.reserved == initial_state.reserved
}

// Multiple sequential withdrawals
test multiple_withdrawals_success() {
  let initial_state = state_with_liquidity(1000000, 400000)
  let first_withdraw = 300000
  let second_withdraw = 200000

  // First withdrawal
  let state_after_first = state_with_liquidity(700000, 400000)
  let first_state_input = make_state_input(initial_state, 1000000, 0)
  let first_op_output = make_operator_output(300000)
  let first_state_output = make_state_output(state_after_first, 700000)

  let first_tx =
    make_basic_tx(
      inputs: [first_state_input],
      outputs: [first_op_output, first_state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  let first_result =
    validate_withdraw(test_config(), initial_state, first_withdraw, first_tx)

  // Second withdrawal
  let state_after_second = state_with_liquidity(500000, 400000)
  let second_state_input = make_state_input(state_after_first, 700000, 1)
  let second_op_output = make_operator_output(200000)
  let second_state_output = make_state_output(state_after_second, 500000)

  let second_tx =
    make_basic_tx(
      inputs: [second_state_input],
      outputs: [second_op_output, second_state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  let second_result =
    validate_withdraw(
      test_config(),
      state_after_first,
      second_withdraw,
      second_tx,
    )

  first_result && second_result && assert_liquidity_decreased(
    1000000,
    500000,
    first_withdraw + second_withdraw,
  ) && state_after_second.reserved == initial_state.reserved
}
