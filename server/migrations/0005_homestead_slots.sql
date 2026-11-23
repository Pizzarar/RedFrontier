-- fh_homestead H1: built tier per plot slot. Slot ids/tiers come from fh_homestead/config.lua; tier 0 = no row.
-- Idempotent (IF NOT EXISTS), like 0003.

CREATE TABLE IF NOT EXISTS `fh_plot_slots` (
  `plot_id` varchar(50) NOT NULL,
  `slot_id` varchar(50) NOT NULL,
  `tier` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `built_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`plot_id`, `slot_id`),
  CONSTRAINT `fh_plot_slots_plot` FOREIGN KEY (`plot_id`) REFERENCES `fh_plots` (`plot_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
