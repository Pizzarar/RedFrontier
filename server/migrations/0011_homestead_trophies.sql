-- fh_homestead H4: trophies placed on a plot's trophy wall (points are comfort, set by the feeding resource).
-- Idempotent (IF NOT EXISTS), like 0003/0005. Rows vanish with the plot (unclaim).

CREATE TABLE IF NOT EXISTS `fh_plot_trophies` (
  `plot_id` varchar(50) NOT NULL,
  `trophy_id` varchar(64) NOT NULL,
  `points` int(10) unsigned NOT NULL DEFAULT 0,
  `placed_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`plot_id`, `trophy_id`),
  CONSTRAINT `fh_plot_trophies_plot` FOREIGN KEY (`plot_id`) REFERENCES `fh_plots` (`plot_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
