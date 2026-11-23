-- fh_hunting legendary hunt chain (spec L8 H4): one row per character per chain, keyed (citizenid, chain_id).
-- `step` is the next clue to find: 1 rumour -> 2 track -> 3 carcass -> 4 spawned -> 5 complete.
-- `spawn_request` is the fh_core requestSpawn id once the bear was requested (0 = not yet).
-- `spawned` = the spawn was adopted (the bear exists); `completed` = the pelt was skinned (the chain is done).
-- Idempotent (IF NOT EXISTS), like the other fh migrations. The single row per (citizenid, chain_id) is the
-- "one spawn per chain per character" backstop.

CREATE TABLE IF NOT EXISTS `fh_hunting_chains` (
  `citizenid` varchar(50) NOT NULL,
  `chain_id` varchar(50) NOT NULL,
  `step` tinyint(3) unsigned NOT NULL DEFAULT 1,
  `spawn_request` int(11) NOT NULL DEFAULT 0,
  `spawned` tinyint(1) NOT NULL DEFAULT 0,
  `completed` tinyint(1) NOT NULL DEFAULT 0,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`citizenid`, `chain_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
