-- fh_homestead H20b (plan homestead-04): trough refill cooldown. One row per plot that has ever refilled a horse.
-- Placeholder number 0099: renumbered to main's highest + 1 at the merge slot. Idempotent (IF NOT EXISTS).
--   last_refill_at = server unix time in seconds (os.time() on the server), no TIMESTAMP, so no time-zone conversion.
-- The row vanishes with the plot (unclaim: FK cascade; the server also deletes it on unclaim as a backstop).

CREATE TABLE IF NOT EXISTS `fh_plot_trough` (
  `plot_id` varchar(50) NOT NULL,
  `last_refill_at` bigint(20) unsigned NOT NULL,
  PRIMARY KEY (`plot_id`),
  CONSTRAINT `fh_plot_trough_plot` FOREIGN KEY (`plot_id`) REFERENCES `fh_plots` (`plot_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
