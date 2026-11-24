-- fh_homestead (homestead-02 H6): plot class. A character may now hold one plot PER CLASS ('claim' = homestead claim,
-- 'town_lot' = bought town lot), so the one-plot-per-character UNIQUE(citizenid) from 0003 becomes UNIQUE(citizenid, class).
-- plot_id stays the PK (one owner per plot). Existing rows get the default 'claim', which is what they all are.
-- Idempotent (IF [NOT] EXISTS guards, MariaDB), like 0003/0005: safe to re-run. The new key is added before the old one is
-- dropped, so the table is never without a per-character uniqueness constraint.

ALTER TABLE `fh_plots` ADD COLUMN IF NOT EXISTS `class` varchar(16) NOT NULL DEFAULT 'claim' AFTER `citizenid`;

ALTER TABLE `fh_plots` ADD UNIQUE KEY IF NOT EXISTS `citizenid_class` (`citizenid`, `class`);

ALTER TABLE `fh_plots` DROP INDEX IF EXISTS `citizenid`;
