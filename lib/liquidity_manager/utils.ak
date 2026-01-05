use aiken/collection/list
use aiken/crypto.{VerificationKeyHash}
use aiken/interval
use cardano/address.{Address, Credential}
use cardano/assets.{Value, quantity_of}
use cardano/transaction.{Input, Output, Transaction}
use liquidity_manager/types.{Config, Invoice}

pub fn cbtc_of(value: Value, config: Config) -> Int {
  quantity_of(value, config.cbtc_policy, config.cbtc_name)
}

pub fn find_invoice(invoices: List<Invoice>, id: Int) -> Option<Invoice> {
  list.find(invoices, fn(i) { i.invoice_id == id })
}

pub fn remove_invoice(invoices: List<Invoice>, id: Int) -> List<Invoice> {
  list.filter(invoices, fn(i) { i.invoice_id != id })
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

/// Calculate total cBTC in operator's inputs (excluding script inputs)
pub fn operator_input_cbtc(
  inputs: List<Input>,
  script_address: Address,
  config: Config,
) -> Int {
  let operator_inputs =
    list.filter(inputs, fn(input) { input.output.address != script_address })

  list.foldr(
    operator_inputs,
    0,
    fn(input, acc) { acc + cbtc_of(input.output.value, config) },
  )
}

/// Calculate total cBTC in operator's outputs (excluding script outputs)
pub fn operator_output_cbtc(
  outputs: List<Output>,
  script_address: Address,
  config: Config,
) -> Int {
  let operator_outputs =
    list.filter(outputs, fn(output) { output.address != script_address })

  list.foldr(
    operator_outputs,
    0,
    fn(output, acc) { acc + cbtc_of(output.value, config) },
  )
}
