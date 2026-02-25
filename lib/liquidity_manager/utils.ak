use aiken/collection/list
use aiken/crypto.{VerificationKeyHash}
use aiken/interval
use cardano/address.{Address, Credential}
use cardano/assets.{Value, quantity_of}
use cardano/transaction.{Datum, InlineDatum, Input, Output, Transaction}
use liquidity_manager/types.{Config, Invoice, Offramp, State}

pub fn cbtc_of(value: Value, config: Config) -> Int {
  quantity_of(value, config.cbtc_policy, config.cbtc_name)
}

/// Check if a datum is a State datum (identifies script UTxOs)
pub fn has_state_datum(datum: Datum) -> Bool {
  when datum is {
    InlineDatum(data) -> {
      // Try to deserialize as State - if it works, it's a state UTXO
      expect _state: State = data
      True
    }
    _ -> False
  }
}

pub fn find_invoice(invoices: List<Invoice>, id: Int) -> Option<Invoice> {
  list.find(invoices, fn(i) { i.invoice_id == id })
}

pub fn remove_invoice(invoices: List<Invoice>, id: Int) -> List<Invoice> {
  list.filter(invoices, fn(i) { i.invoice_id != id })
}

pub fn find_offramp(offramps: List<Offramp>, id: Int) -> Option<Offramp> {
  list.find(offramps, fn(o) { o.offramp_id == id })
}

pub fn remove_offramp(offramps: List<Offramp>, id: Int) -> List<Offramp> {
  list.filter(offramps, fn(o) { o.offramp_id != id })
}

pub fn submitted_after_expiry(expires_at: Int, tx: Transaction) -> Bool {
  let vr = tx.validity_range

  interval.is_entirely_after(vr, expires_at)
}

pub fn verify_owner_output(
  outputs: List<Output>,
  owner_credential: VerificationKeyHash,
  required_cbtc: Int,
  config: Config,
) -> Bool {
  let owner_outputs =
    list.filter(
      outputs,
      fn(output: Output) {
        // Check if output goes to owner (by checking payment credential)
        when output.address.payment_credential is {
          Credential.VerificationKey(pkh) -> pkh == owner_credential
          _ -> False
        }
      },
    )

  // Should have at least one output to owner
  let has_owner_output = list.length(owner_outputs) > 0

  if has_owner_output {
    // Verify owner received the correct cBTC amount
    let received_cbtc =
      list.foldr(
        owner_outputs,
        0,
        fn(output, acc) { acc + cbtc_of(output.value, config) },
      )
    received_cbtc >= required_cbtc
  } else {
    False
  }
}

/// Calculate total cBTC in operator's inputs (excluding state inputs)
pub fn operator_input_cbtc(inputs: List<Input>, config: Config) -> Int {
  let operator_inputs =
    list.filter(inputs, fn(input) { !has_state_datum(input.output.datum) })

  list.foldr(
    operator_inputs,
    0,
    fn(input, acc) { acc + cbtc_of(input.output.value, config) },
  )
}

/// Calculate total cBTC in operator's outputs (excluding state outputs)
pub fn operator_output_cbtc(outputs: List<Output>, config: Config) -> Int {
  let operator_outputs =
    list.filter(outputs, fn(output) { !has_state_datum(output.datum) })

  list.foldr(
    operator_outputs,
    0,
    fn(output, acc) { acc + cbtc_of(output.value, config) },
  )
}
