-- core-10 I2 (idea-923): rsg-character starter items are granted from this table, not an in-memory map, so a server
-- or resource restart between character creation and first spawn still grants them, exactly once.
-- createCharacter writes a pending row (granted = 0; ON DUPLICATE KEY resets it, since rsg-core can reuse a deleted
-- character's citizenid). The first spawn claims it with an atomic
--   UPDATE ... SET granted = 1 WHERE citizenid = ? AND granted = 0
-- and only the claim with affectedRows = 1 grants. No row = a character from before this table (already got its kit
-- at creation): never granted. A grant that fails after the claim is logged, not retried (no double grant).
-- rsg-core's DeleteCharacter removes the row with the character's other tables. Idempotent (IF NOT EXISTS).

CREATE TABLE IF NOT EXISTS `fh_starter_granted` (
  `citizenid` varchar(50) NOT NULL,
  `granted` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `granted_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
