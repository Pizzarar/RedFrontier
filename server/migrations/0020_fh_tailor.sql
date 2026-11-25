-- fh_tailor (progression-03 T1): clothing ownership is a list of catalog ids per character, not inventory items
-- (clothes take no bag weight). One row per owned catalog entry; the primary key makes every grant idempotent
-- (INSERT IGNORE: 1 row = new, 0 = already owned) and is the DB-level guard against a double grant.
-- `source` = how it was acquired: 'buy', 'starter', or the grant caller's tag (e.g. 'hunting:legendary_bear').
CREATE TABLE IF NOT EXISTS `fh_tailor_owned` (
  `citizenid` varchar(50) NOT NULL,
  `entry_id` varchar(64) NOT NULL,
  `source` varchar(32) NOT NULL,
  `acquired_at` bigint(20) NOT NULL,
  PRIMARY KEY (`citizenid`, `entry_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- Per-character tailor state: starter_at is set once the starter set was granted (never cleared, so the starter
-- grant runs once); worn_outfit / worn_items = the active look (an owned outfit id + up to N owned single item
-- ids, comma-separated). NULL worn_outfit = nothing chosen yet.
CREATE TABLE IF NOT EXISTS `fh_tailor_state` (
  `citizenid` varchar(50) NOT NULL,
  `starter_at` bigint(20) DEFAULT NULL,
  `worn_outfit` varchar(64) DEFAULT NULL,
  `worn_items` varchar(512) NOT NULL DEFAULT '',
  PRIMARY KEY (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- Saved outfits (wardrobe slots 1..Config.maxSavedOutfits): one owned outfit id + up to Config.maxItems owned single
-- item ids (comma-separated). Ownership is re-checked whenever a saved outfit is worn.
CREATE TABLE IF NOT EXISTS `fh_tailor_outfits` (
  `citizenid` varchar(50) NOT NULL,
  `slot` tinyint(3) unsigned NOT NULL,
  `label` varchar(32) NOT NULL DEFAULT '',
  `outfit_id` varchar(64) NOT NULL,
  `items` varchar(512) NOT NULL DEFAULT '',
  PRIMARY KEY (`citizenid`, `slot`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
