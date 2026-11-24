-- fh_tutorial (guide-02 reorder): one-time migration of in-flight tutorial progress from a step INDEX to a stable
-- step id. fh_quest_state.step is a 1-based index, so the reordered tutorial would otherwise move a character to a
-- different step; fh_quests now also persists progress.step_id and resolves the current step by it. This maps every
-- active row's old index to the same logical step in the new order (and stores its id, so future reorders are a
-- config-only change). Idempotent by effect: a row that already carries step_id is left alone.
--
-- Old order: 1 inventory, 2 trade_post, 3 claim_plot, 4 jobs, 5 hunt, 6 family, 7 eat_drink.
-- New order: 1 greeting, 2 inventory, 3 eat_drink, 4 claim_plot, 5 trade_post, 6 hunt, 7 jobs, 8 family.
-- MySQL/MariaDB evaluate SET assignments left to right, so progress (reads the old step) must come before step.

UPDATE `fh_quest_state`
SET
  `progress` = JSON_SET(`progress`, '$.step_id', CASE `step`
      WHEN 1 THEN 'inventory'
      WHEN 2 THEN 'trade_post'
      WHEN 3 THEN 'claim_plot'
      WHEN 4 THEN 'jobs'
      WHEN 5 THEN 'hunt'
      WHEN 6 THEN 'family'
      WHEN 7 THEN 'eat_drink'
  END),
  `step` = CASE `step`
      WHEN 1 THEN 2
      WHEN 2 THEN 5
      WHEN 3 THEN 4
      WHEN 4 THEN 7
      WHEN 5 THEN 6
      WHEN 6 THEN 8
      WHEN 7 THEN 3
  END
WHERE `quest_id` = 'tutorial_intro'
  AND `status` = 'active'
  AND `step` BETWEEN 1 AND 7
  AND LOCATE('"step_id"', `progress`) = 0;
