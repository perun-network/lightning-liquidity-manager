use aiken/interval.{between, entirely_after}
use liquidity_manager/types.{Offramp}
use liquidity_manager/validation.{
  validate_cancel_offramp, validate_create_offramp, validate_fulfill_offramp,
}
use tests/helpers.{
  default_validity_range, lm_pkh, make_basic_tx, make_offramp,
  make_operator_input, make_operator_output, make_state_input,
  make_state_output, state_with_liquidity, state_with_offramps, test_config,
  user_pkh, user_pkh_2,
}

// ─── Mock data ──────────────────────────────────────────────────────────────

const test_payment_hash: ByteArray =
  #"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

const test_payment_hash_2: ByteArray =
  #"cafebabecafebabecafebabecafebabecafebabecafebabecafebabecafebabe"

// ─── CreateOfframp Tests ────────────────────────────────────────────────────

test create_offramp_success() {
  let initial_state = state_with_liquidity(1000000, 0)
  let offramp =
    make_offramp(1, 200000, test_payment_hash, user_pkh, 1600000)

  let state_after =
    state_with_offramps(1000000, 0, 0, [], 1, [offramp])

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(state_after, 1000000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  validate_create_offramp(
    test_config(),
    initial_state,
    200000,
    test_payment_hash,
    user_pkh,
    1600000,
    tx,
  )
}

test create_offramp_unauthorized_fails() fail {
  let initial_state = state_with_liquidity(1000000, 0)
  let offramp =
    make_offramp(1, 200000, test_payment_hash, user_pkh, 1600000)

  let state_after =
    state_with_offramps(1000000, 0, 0, [], 1, [offramp])

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(state_after, 1000000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output],
      validity_range: default_validity_range(),
      signatories: [user_pkh],
    )

  validate_create_offramp(
    test_config(),
    initial_state,
    200000,
    test_payment_hash,
    user_pkh,
    1600000,
    tx,
  )
}

test create_offramp_zero_amount_fails() fail {
  let initial_state = state_with_liquidity(1000000, 0)

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(initial_state, 1000000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  validate_create_offramp(
    test_config(),
    initial_state,
    0,
    test_payment_hash,
    user_pkh,
    1600000,
    tx,
  )
}

test create_offramp_already_expired_fails() fail {
  let initial_state = state_with_liquidity(1000000, 0)

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(initial_state, 1000000)

  // expires_at=1200000 but validity range starts at 1000000 and we use entirely_after
  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output],
      validity_range: entirely_after(1300000),
      signatories: [lm_pkh],
    )

  validate_create_offramp(
    test_config(),
    initial_state,
    200000,
    test_payment_hash,
    user_pkh,
    1200000,
    tx,
  )
}

// ─── FulfillOfframp Tests ───────────────────────────────────────────────────

test fulfill_offramp_success() {
  let offramp =
    make_offramp(1, 200000, test_payment_hash, user_pkh, 1600000)
  let initial_state =
    state_with_offramps(1000000, 0, 0, [], 1, [offramp])
  let state_after =
    state_with_offramps(1200000, 0, 0, [], 1, [])

  let operator_input = make_operator_input(200000, 0)
  let state_input = make_state_input(initial_state, 1000000, 1)
  let operator_output = make_operator_output(0)
  let state_output = make_state_output(state_after, 1200000)

  let tx =
    make_basic_tx(
      inputs: [operator_input, state_input],
      outputs: [operator_output, state_output],
      validity_range: between(1200000, 1500000),
      signatories: [lm_pkh],
    )

  validate_fulfill_offramp(test_config(), initial_state, offramp, tx)
}

test fulfill_offramp_unauthorized_fails() fail {
  let offramp =
    make_offramp(1, 200000, test_payment_hash, user_pkh, 1600000)
  let initial_state =
    state_with_offramps(1000000, 0, 0, [], 1, [offramp])
  let state_after =
    state_with_offramps(1200000, 0, 0, [], 1, [])

  let operator_input = make_operator_input(200000, 0)
  let state_input = make_state_input(initial_state, 1000000, 1)
  let operator_output = make_operator_output(0)
  let state_output = make_state_output(state_after, 1200000)

  let tx =
    make_basic_tx(
      inputs: [operator_input, state_input],
      outputs: [operator_output, state_output],
      validity_range: between(1200000, 1500000),
      signatories: [user_pkh],
    )

  validate_fulfill_offramp(test_config(), initial_state, offramp, tx)
}

test fulfill_offramp_expired_fails() fail {
  let offramp =
    make_offramp(1, 200000, test_payment_hash, user_pkh, 1600000)
  let initial_state =
    state_with_offramps(1000000, 0, 0, [], 1, [offramp])
  let state_after =
    state_with_offramps(1200000, 0, 0, [], 1, [])

  let operator_input = make_operator_input(200000, 0)
  let state_input = make_state_input(initial_state, 1000000, 1)
  let operator_output = make_operator_output(0)
  let state_output = make_state_output(state_after, 1200000)

  let tx =
    make_basic_tx(
      inputs: [operator_input, state_input],
      outputs: [operator_output, state_output],
      validity_range: entirely_after(1700000),
      signatories: [lm_pkh],
    )

  validate_fulfill_offramp(test_config(), initial_state, offramp, tx)
}

test fulfill_offramp_wrong_id_fails() fail {
  let on_chain_offramp =
    make_offramp(1, 200000, test_payment_hash, user_pkh, 1600000)
  let wrong_offramp =
    make_offramp(2, 200000, test_payment_hash, user_pkh, 1600000)
  let initial_state =
    state_with_offramps(1000000, 0, 0, [], 1, [on_chain_offramp])
  let state_after =
    state_with_offramps(1200000, 0, 0, [], 1, [])

  let operator_input = make_operator_input(200000, 0)
  let state_input = make_state_input(initial_state, 1000000, 1)
  let operator_output = make_operator_output(0)
  let state_output = make_state_output(state_after, 1200000)

  let tx =
    make_basic_tx(
      inputs: [operator_input, state_input],
      outputs: [operator_output, state_output],
      validity_range: between(1200000, 1500000),
      signatories: [lm_pkh],
    )

  validate_fulfill_offramp(test_config(), initial_state, wrong_offramp, tx)
}

test fulfill_offramp_insufficient_cbtc_fails() fail {
  let offramp =
    make_offramp(1, 200000, test_payment_hash, user_pkh, 1600000)
  let initial_state =
    state_with_offramps(1000000, 0, 0, [], 1, [offramp])
  let state_after =
    state_with_offramps(1200000, 0, 0, [], 1, [])

  // Operator only provides 100000 instead of 200000
  let operator_input = make_operator_input(100000, 0)
  let state_input = make_state_input(initial_state, 1000000, 1)
  let operator_output = make_operator_output(0)
  let state_output = make_state_output(state_after, 1200000)

  let tx =
    make_basic_tx(
      inputs: [operator_input, state_input],
      outputs: [operator_output, state_output],
      validity_range: between(1200000, 1500000),
      signatories: [lm_pkh],
    )

  validate_fulfill_offramp(test_config(), initial_state, offramp, tx)
}

// ─── CancelOfframp Tests ───────────────────────────────────────────────────

test cancel_offramp_success() {
  let offramp =
    make_offramp(1, 200000, test_payment_hash, user_pkh, 1600000)
  let initial_state =
    state_with_offramps(1000000, 0, 0, [], 1, [offramp])
  let state_after =
    state_with_offramps(1000000, 0, 0, [], 1, [])

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(state_after, 1000000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output],
      validity_range: entirely_after(1600000),
      signatories: [lm_pkh],
    )

  validate_cancel_offramp(
    test_config(),
    initial_state,
    offramp.offramp_id,
    tx,
  )
}

test cancel_offramp_unauthorized_fails() fail {
  let offramp =
    make_offramp(1, 200000, test_payment_hash, user_pkh, 1600000)
  let initial_state =
    state_with_offramps(1000000, 0, 0, [], 1, [offramp])
  let state_after =
    state_with_offramps(1000000, 0, 0, [], 1, [])

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(state_after, 1000000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output],
      validity_range: entirely_after(1600000),
      signatories: [user_pkh],
    )

  validate_cancel_offramp(
    test_config(),
    initial_state,
    offramp.offramp_id,
    tx,
  )
}

test cancel_offramp_before_expiry_fails() fail {
  let offramp =
    make_offramp(1, 200000, test_payment_hash, user_pkh, 1600000)
  let initial_state =
    state_with_offramps(1000000, 0, 0, [], 1, [offramp])
  let state_after =
    state_with_offramps(1000000, 0, 0, [], 1, [])

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(state_after, 1000000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output],
      validity_range: default_validity_range(),
      signatories: [lm_pkh],
    )

  validate_cancel_offramp(
    test_config(),
    initial_state,
    offramp.offramp_id,
    tx,
  )
}

test cancel_offramp_nonexistent_id_fails() fail {
  let offramp =
    make_offramp(1, 200000, test_payment_hash, user_pkh, 1600000)
  let initial_state =
    state_with_offramps(1000000, 0, 0, [], 1, [offramp])
  let state_after =
    state_with_offramps(1000000, 0, 0, [], 1, [])

  let state_input = make_state_input(initial_state, 1000000, 0)
  let state_output = make_state_output(state_after, 1000000)

  let tx =
    make_basic_tx(
      inputs: [state_input],
      outputs: [state_output],
      validity_range: entirely_after(1600000),
      signatories: [lm_pkh],
    )

  validate_cancel_offramp(
    test_config(),
    initial_state,
    999,
    tx,
  )
}

// ─── Workflow Tests ─────────────────────────────────────────────────────────

test create_and_fulfill_offramp() {
  // Step 1: Create offramp
  let initial_state = state_with_liquidity(1000000, 0)
  let offramp =
    make_offramp(1, 200000, test_payment_hash, user_pkh, 1600000)
  let state_after_create =
    state_with_offramps(1000000, 0, 0, [], 1, [offramp])

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
    validate_create_offramp(
      test_config(),
      initial_state,
      200000,
      test_payment_hash,
      user_pkh,
      1600000,
      create_tx,
    )

  // Step 2: Fulfill offramp (deposit cBTC to pool)
  let state_after_fulfill =
    state_with_offramps(1200000, 0, 0, [], 1, [])

  let operator_input = make_operator_input(200000, 0)
  let state_input_2 = make_state_input(state_after_create, 1000000, 1)
  let operator_output = make_operator_output(0)
  let state_output_2 = make_state_output(state_after_fulfill, 1200000)

  let fulfill_tx =
    make_basic_tx(
      inputs: [operator_input, state_input_2],
      outputs: [operator_output, state_output_2],
      validity_range: between(1200000, 1500000),
      signatories: [lm_pkh],
    )

  let fulfill_result =
    validate_fulfill_offramp(
      test_config(),
      state_after_create,
      offramp,
      fulfill_tx,
    )

  create_result && fulfill_result && state_after_fulfill.total_liquidity == 1200000 && state_after_fulfill.offramps == []
}

test create_and_cancel_offramp() {
  // Step 1: Create offramp
  let initial_state = state_with_liquidity(1000000, 0)
  let offramp =
    make_offramp(1, 200000, test_payment_hash, user_pkh, 1600000)
  let state_after_create =
    state_with_offramps(1000000, 0, 0, [], 1, [offramp])

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
    validate_create_offramp(
      test_config(),
      initial_state,
      200000,
      test_payment_hash,
      user_pkh,
      1600000,
      create_tx,
    )

  // Step 2: Cancel offramp after expiry
  let state_after_cancel =
    state_with_offramps(1000000, 0, 0, [], 1, [])

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
    validate_cancel_offramp(
      test_config(),
      state_after_create,
      offramp.offramp_id,
      cancel_tx,
    )

  create_result && cancel_result && state_after_cancel.total_liquidity == 1000000 && state_after_cancel.offramps == []
}
