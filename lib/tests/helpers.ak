use aiken/collection/dict
use aiken/crypto.{VerificationKeyHash}
use aiken/interval.{Finite, Interval, IntervalBound}
use cardano/address.{Address, Credential}
use cardano/assets.{from_asset, from_lovelace, merge, zero}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
  TransactionId,
}
use liquidity_manager/types.{Config, Invoice, State}

pub const lm_pkh: VerificationKeyHash =
  #"aabbccdd00112233445566778899aabbccddeeff00112233445566778899aabb"

pub const user_pkh: VerificationKeyHash =
  #"1122334455667788990011223344556677889900112233445566778899001122"

pub const user_pkh_2: VerificationKeyHash =
  #"2233445566778899001122334455667788990011223344556677889900112233"

pub const user_pkh_3: VerificationKeyHash =
  #"3344556677889900112233445566778899001122334455667788990011223344"

pub const cbtc_policy: ByteArray =
  #"cafebabe00112233445566778899aabbccddeeff00112233445566778899aabb"

pub const cbtc_name: ByteArray = #"63425443"

pub const script_hash: ByteArray =
  #"deadbeef00112233445566778899aabbccddeeff00112233445566778899aabb"

pub fn mock_script_address() -> Address {
  Address {
    payment_credential: Credential.Script(script_hash),
    stake_credential: None,
  }
}

pub fn mock_operator_address() -> Address {
  Address {
    payment_credential: Credential.VerificationKey(lm_pkh),
    stake_credential: None,
  }
}

pub fn test_config() -> Config {
  Config { lm_pkh, cbtc_policy, cbtc_name }
}

pub fn mock_tx_id() -> TransactionId {
  #"ffeeddcc00112233445566778899aabbccddeeff00112233445566778899aabb"
}

pub fn mock_output_ref(index: Int) -> OutputReference {
  OutputReference { transaction_id: mock_tx_id(), output_index: index }
}

pub fn make_value(lovelace: Int, cbtc_amount: Int) -> assets.Value {
  let ada_value = from_lovelace(lovelace)
  if cbtc_amount > 0 {
    let cbtc_value = from_asset(cbtc_policy, cbtc_name, cbtc_amount)
    merge(ada_value, cbtc_value)
  } else {
    ada_value
  }
}

pub fn make_state_output(state: State, cbtc_amount: Int) -> Output {
  Output {
    address: mock_script_address(),
    value: make_value(2_000_000, cbtc_amount),
    datum: InlineDatum(state),
    reference_script: None,
  }
}

pub fn make_state_input(state: State, cbtc_amount: Int, index: Int) -> Input {
  Input {
    output_reference: mock_output_ref(index),
    output: make_state_output(state, cbtc_amount),
  }
}

pub fn make_operator_output(cbtc_amount: Int) -> Output {
  Output {
    address: mock_operator_address(),
    value: make_value(5_000_000, cbtc_amount),
    datum: NoDatum,
    reference_script: None,
  }
}

pub fn make_operator_input(cbtc_amount: Int, index: Int) -> Input {
  Input {
    output_reference: mock_output_ref(index),
    output: make_operator_output(cbtc_amount),
  }
}

pub fn make_basic_tx(
  inputs: List<Input>,
  outputs: List<Output>,
  signatories: List<VerificationKeyHash>,
  validity_range: Interval,
) -> Transaction {
  Transaction {
    inputs,
    reference_inputs: [],
    outputs,
    fee: 500_000,
    mint: zero,
    certificates: [],
    withdrawals: [],
    validity_range,
    extra_signatories: signatories,
    redeemers: [],
    datums: dict.empty,
    id: mock_tx_id(),
    votes: [],
    proposal_procedures: [],
    current_treasury_amount: None,
    treasury_donation: None,
  }
}

pub fn default_validity_range() -> Interval {
  Interval {
    lower_bound: IntervalBound {
      bound_type: Finite(1000000),
      is_inclusive: True,
    },
    upper_bound: IntervalBound {
      bound_type: Finite(2000000),
      is_inclusive: True,
    },
  }
}

pub fn late_validity_range(expiry: Int) -> Interval {
  Interval {
    lower_bound: IntervalBound {
      bound_type: Finite(expiry + 100000),
      is_inclusive: True,
    },
    upper_bound: IntervalBound {
      bound_type: Finite(expiry + 500000),
      is_inclusive: True,
    },
  }
}

pub fn empty_state() -> State {
  State { total_liquidity: 0, reserved: 0, last_invoice_id: 0, invoices: [] }
}

pub fn state_with_liquidity(total: Int, reserved: Int) -> State {
  State { total_liquidity: total, reserved, last_invoice_id: 0, invoices: [] }
}

pub fn state_with_invoices(
  total: Int,
  reserved: Int,
  last_invoice_id: Int,
  invoices: List<Invoice>,
) -> State {
  State { total_liquidity: total, reserved, last_invoice_id, invoices }
}

pub fn make_invoice(
  id: Int,
  amount: Int,
  owner: VerificationKeyHash,
  timestamp: Int,
  expires_at: Int,
) -> Invoice {
  Invoice { invoice_id: id, amount, owner, timestamp, expires_at }
}

pub fn default_invoice() -> Invoice {
  Invoice {
    invoice_id: 1,
    amount: 100000,
    owner: user_pkh,
    timestamp: 1000000,
    expires_at: 1500000,
  }
}

pub fn assert_liquidity_increased(
  initial_liquidity: Int,
  final_liquidity: Int,
  deposit_amount: Int,
) -> Bool {
  final_liquidity == initial_liquidity + deposit_amount
}

pub fn assert_liquidity_decreased(
  initial_liquidity: Int,
  final_liquidity: Int,
  withdraw_amount: Int,
) -> Bool {
  final_liquidity == initial_liquidity - withdraw_amount
}

pub fn assert_reserved_increased(
  initial_reserved: Int,
  final_reserved: Int,
  invoice_amount: Int,
) -> Bool {
  final_reserved == initial_reserved + invoice_amount
}

pub fn assert_reserved_decreased(
  initial_reserved: Int,
  final_reserved: Int,
  invoice_amount: Int,
) -> Bool {
  final_reserved == initial_reserved - invoice_amount
}

pub fn assert_cbtc_balance_correct(
  input_cbtc: Int,
  output_cbtc: Int,
  expected_change: Int,
) -> Bool {
  output_cbtc == input_cbtc + expected_change
}

pub fn assert_operator_cbtc_transfer(
  operator_in_cbtc: Int,
  operator_out_cbtc: Int,
  expected_transfer: Int,
) -> Bool {
  operator_in_cbtc - operator_out_cbtc == expected_transfer
}
