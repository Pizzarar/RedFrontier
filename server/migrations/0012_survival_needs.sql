-- fh_survival (plan survival-01): remaining seconds per need buff, saved on drop / resource stop and restored on
-- character load. `needs` is JSON { [need] = { remaining = seconds, magnitude = number } } (may be '{}'). A row, even an
-- empty one, means the character has played with needs before (no login grace). updated_at is unix seconds.

CREATE TABLE IF NOT EXISTS `fh_survival_needs` (
  `citizenid` varchar(50) NOT NULL,
  `needs` text NOT NULL,
  `updated_at` bigint(20) NOT NULL,
  PRIMARY KEY (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
