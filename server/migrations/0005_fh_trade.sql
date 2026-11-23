-- fh_trade (spec L6): persisted regional price state, one row per (region, trade good). `shortage` (0..1) and
-- `saturation` (0..1) are the values as of `updated_at` (unix seconds, os.time()); fh_trade decays them to "now" on
-- load, so a restart neither resets nor freezes the market. Rows for goods/regions no longer configured are ignored.

CREATE TABLE IF NOT EXISTS `fh_trade_prices` (
  `region_id` varchar(50) NOT NULL,
  `item` varchar(100) NOT NULL,
  `shortage` double NOT NULL DEFAULT 0,
  `saturation` double NOT NULL DEFAULT 0,
  `updated_at` bigint(20) NOT NULL,
  PRIMARY KEY (`region_id`, `item`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
