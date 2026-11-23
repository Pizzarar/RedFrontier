-- B7: fh_economy.charge writes ledger rows with kind='charge' (amount = the positive sum debited).
-- Widens the enum only; existing rows are untouched. fh_ledger stays append-only.
ALTER TABLE `fh_ledger` MODIFY `kind` enum('pay','rep','charge') NOT NULL;
