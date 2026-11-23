-- fh_quests Q2 (plan quests-01): one row per character and quest (README "Persistence"). Idempotent (IF NOT EXISTS).
-- Provisional number: the lead renumbers at merge (0006/0007 are taken on other lanes' branches).
-- progress is JSON { count, completions, reward_pending?, reward_paid? = { [part] = true }, reward_inflight? = { key, at } }.
-- Times are unix seconds (os.time()), so no timezone conversion. Completed one-time quests stay as status 'done'.

CREATE TABLE IF NOT EXISTS `fh_quest_state` (
  `citizenid` varchar(50) NOT NULL,
  `quest_id` varchar(64) NOT NULL,
  `status` varchar(16) NOT NULL,
  `step` int(11) NOT NULL DEFAULT 1,
  `progress` longtext NOT NULL,
  `cooldown_until` bigint(20) DEFAULT NULL,
  `updated_at` bigint(20) NOT NULL,
  PRIMARY KEY (`citizenid`, `quest_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
