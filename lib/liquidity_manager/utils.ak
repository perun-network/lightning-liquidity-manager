use aiken/collection/list
use aiken/interval
use cardano/transaction.{Transaction}
use cardano/assets.{Value, quantity_of}
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