-- core M3: fh_economy.credit takes whole-cent amounts (shop refunds / sell payouts like $1.13), so the offline queue
-- must hold cents exactly. fh_pending_credit.amount goes from int(10) unsigned to decimal(12,2) unsigned: exact
-- fixed-point (no float drift; fh_ledger.amount is a double already), existing whole-dollar rows convert exactly
-- (5 -> 5.00), one column so no backfill and no old/new column split, and still no negatives. 12,2 holds far more
-- than maxCredit (100000). The claim reads it as a number or a string and pays exact cents (FhLedgerLogic.toCents).
-- Idempotent: MODIFY to the same type again is a no-op, like 0015's enum MODIFY.

ALTER TABLE `fh_pending_credit` MODIFY `amount` decimal(12,2) unsigned NOT NULL;
