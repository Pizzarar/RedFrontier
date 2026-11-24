-- fh_tutorial (guide-02): per-character skip/auto-start flag for the intro tutorial quest (fh_quests kind='tutorial').
-- A row means the character has been through the tutorial auto-start at least once; `skipped` is whether they opted
-- out. No row = never started (auto-starts on the next load). The quest's own done/step state lives in fh_quest_state
-- (quest id `tutorial_intro`), owned by fh_quests. Idempotent (IF NOT EXISTS). updated_at is unix seconds.

CREATE TABLE IF NOT EXISTS `fh_tutorial_state` (
  `citizenid` varchar(50) NOT NULL,
  `skipped` tinyint(1) NOT NULL DEFAULT 0,
  `updated_at` bigint(20) NOT NULL,
  PRIMARY KEY (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
