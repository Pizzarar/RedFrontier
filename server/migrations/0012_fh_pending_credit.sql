-- core-04 E2 (idea-700): fh_economy.credit for characters that are offline. Queued credits wait here and are paid
-- on the character's next load by an atomic claim (claimed_by = a per-claim token, set only WHERE claimed_by IS NULL),
-- then deleted. Never a write to players.money: rsg-core saves a loaded player's in-memory money over it.
-- A row with claimed_by set at server start is from an earlier run: audit it by hand (it may already be paid).
-- Idempotent (IF NOT EXISTS), like 0003/0005; the enum widening only adds values (existing rows untouched).

ALTER TABLE `fh_ledger` MODIFY `kind` enum('pay','rep','charge','credit','credit_pending') NOT NULL;

CREATE TABLE IF NOT EXISTS `fh_pending_credit` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `citizenid` varchar(50) NOT NULL,
  `amount` int(10) unsigned NOT NULL,
  `reason` varchar(128) NOT NULL,
  `region_id` varchar(50) NOT NULL,
  `claimed_by` varchar(100) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `citizenid_claimed` (`citizenid`, `claimed_by`),
  KEY `claimed_by` (`claimed_by`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
