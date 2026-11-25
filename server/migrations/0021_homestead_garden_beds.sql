-- fh_homestead H19 (plan homestead-04): planted garden beds. One row per planted bed; no row = empty bed.
-- Idempotent (IF NOT EXISTS), like 0003/0005/0011.
--   bed        = 1..FhHomesteadConfig.garden.beds
--   crop       = the seed item key in FhHomesteadConfig.garden.crops (e.g. 'seedcarrot')
--   planted_at = server unix time in seconds (os.time() on the server), so a crop grows while its owner is offline
--                and across restarts; no TIMESTAMP, so no DB/server time-zone conversion touches it.
-- Rows vanish with the plot (unclaim: FK cascade; fh_homestead also deletes them explicitly on a force unclaim).

CREATE TABLE IF NOT EXISTS `fh_plot_beds` (
  `plot_id` varchar(50) NOT NULL,
  `bed` tinyint(3) unsigned NOT NULL,
  `crop` varchar(50) NOT NULL,
  `planted_at` bigint(20) unsigned NOT NULL,
  PRIMARY KEY (`plot_id`, `bed`),
  CONSTRAINT `fh_plot_beds_plot` FOREIGN KEY (`plot_id`) REFERENCES `fh_plots` (`plot_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
