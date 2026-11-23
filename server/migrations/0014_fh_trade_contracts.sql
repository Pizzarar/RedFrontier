-- fh_trade freight contracts (roads R4): one row per ACTIVE contract so timeouts and wagon-loss checks survive a
-- restart. Rows are deleted on delivery, failure and abandon (the payout record is fh_quests + the fh_ledger).
-- Number is provisional; renumbered at merge.

CREATE TABLE IF NOT EXISTS `fh_trade_contracts` (
  `citizenid` varchar(50) NOT NULL,
  `ckey` varchar(52) NOT NULL,
  `wagon` varchar(100) NOT NULL,
  `from_region` varchar(50) NOT NULL,
  `to_region` varchar(50) NOT NULL,
  `item` varchar(100) NOT NULL,
  `qty` int(11) NOT NULL,
  `reward` int(11) NOT NULL,
  `accepted_at` bigint(20) NOT NULL,
  `deadline` bigint(20) NOT NULL,
  PRIMARY KEY (`citizenid`, `ckey`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
