-- fh_heat (spec L7): per-character per-faction heat, 0-100. One row per (citizenid, faction); a missing row means 0.
-- faction ids come from fh_core shared/regions.lua. updated_at is informational (decay is recomputed live).

CREATE TABLE IF NOT EXISTS `fh_heat` (
  `citizenid` varchar(50) NOT NULL,
  `faction` varchar(50) NOT NULL,
  `heat` double NOT NULL DEFAULT 0,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`citizenid`, `faction`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
