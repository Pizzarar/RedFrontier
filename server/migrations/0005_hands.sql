-- fh_hands (L9 hired hands): one row per hired hand. last_tick/hired_at are unix seconds (server clock);
-- offline catch-up is computed from last_tick. A hand that quits is deleted.

CREATE TABLE IF NOT EXISTS `fh_hands` (
  `citizenid` varchar(50) NOT NULL,
  `hand_kind` varchar(50) NOT NULL,
  `hired_at` bigint(20) NOT NULL,
  `last_tick` bigint(20) NOT NULL,
  `unpaid` int(11) NOT NULL DEFAULT 0,
  `status` varchar(16) NOT NULL DEFAULT 'working',
  PRIMARY KEY (`citizenid`, `hand_kind`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
