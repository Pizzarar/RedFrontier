-- fh_wagons (roads-04 R16, fh_cargo): wagons a character OWNS (bought with fh_economy:charge). One row per owned tier;
-- the primary key (citizenid, tier) is the DB-level guard against a double buy: fh_cargo inserts with INSERT IGNORE
-- AFTER the charge succeeded (1 row = new, 0 = already owned -> the charge is refunded via fh_economy:credit).
-- tier = fh_cargo tier key ('t1' cart / 't2' wagon / 't3' freight). The wagon's cargo is NOT here: it lives in the
-- fh_inventory stash 'fh:wagon:<citizenid>:<tier>' (deterministic per owner + tier), so it survives stow / call.
CREATE TABLE IF NOT EXISTS `fh_wagons` (
  `citizenid` varchar(50) NOT NULL,
  `tier` varchar(8) NOT NULL,
  `bought_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`citizenid`, `tier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
