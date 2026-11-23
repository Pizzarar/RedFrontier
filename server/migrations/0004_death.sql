-- fh_death (spec L4): one row per live death bag. Contents live in fh_inventory's `inventories` table under `id`
-- (a registered fh stash of type drop_bag). expires_at is unix seconds (os.time()), so no timezone conversion.
-- The row is written BEFORE any item moves and deleted only after fh_inventory deleted the stash.

CREATE TABLE IF NOT EXISTS `fh_death_drops` (
  `id` varchar(100) NOT NULL,
  `citizenid` varchar(50) NOT NULL,
  `x` double NOT NULL,
  `y` double NOT NULL,
  `z` double NOT NULL,
  `slots` int(11) NOT NULL,
  `max_weight` int(11) NOT NULL,
  `expires_at` bigint(20) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
