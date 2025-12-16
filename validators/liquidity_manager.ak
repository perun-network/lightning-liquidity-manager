use cardano/transaction.{OutputReference, Transaction}
use liquidity_manager/types.{
  Action, CancelInvoice, Config, CreateInvoice, Deposit, FulfillInvoice, State,
  Withdraw,
}
use liquidity_manager/validation.{
  validate_cancel_invoice, validate_create_invoice, validate_deposit,
  validate_fulfill_invoice, validate_withdraw,
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
        validate_create_invoice(config, state, amount, owner, timestamp, expires_at, self)
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
