-- fh_economy ledger (spec 4.6). fh_ledger is append-only: never UPDATE or DELETE rows.

CREATE TABLE IF NOT EXISTS `fh_ledger` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `citizenid` varchar(50) NOT NULL,
  `kind` enum('pay','rep') NOT NULL,
  `amount` double NOT NULL,
  `reason` varchar(100) NOT NULL,
  `region_id` varchar(50) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `citizenid` (`citizenid`),
  KEY `region_id` (`region_id`),
  KEY `created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `fh_rep` (
  `citizenid` varchar(50) NOT NULL,
  `region_id` varchar(50) NOT NULL,
  `value` double NOT NULL DEFAULT 0,
  PRIMARY KEY (`citizenid`, `region_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
