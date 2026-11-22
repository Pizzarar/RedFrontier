-- fh_homestead (spec L138-139): fixed plots. One plot per character (citizenid UNIQUE), one owner per plot (plot_id PK).
-- Plot ids come from fh_homestead/config.lua. Chest contents live in fh_inventory's stash table, keyed by stash_id.

CREATE TABLE IF NOT EXISTS `fh_plots` (
  `plot_id` varchar(50) NOT NULL,
  `citizenid` varchar(50) NOT NULL,
  `claimed_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`plot_id`),
  UNIQUE KEY `citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `fh_plot_chests` (
  `plot_id` varchar(50) NOT NULL,
  `chest_id` int(11) NOT NULL DEFAULT 1,
  `stash_id` varchar(100) NOT NULL,
  PRIMARY KEY (`plot_id`, `chest_id`),
  KEY `stash_id` (`stash_id`),
  CONSTRAINT `fh_plot_chests_plot` FOREIGN KEY (`plot_id`) REFERENCES `fh_plots` (`plot_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
