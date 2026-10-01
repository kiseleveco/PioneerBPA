-- Switch detection: arm members with an administration of the OTHER agent
-- starting at least @grace_days after their arm index date.
-- One row per switcher (first qualifying administration of the other drug).
--
-- Parameters (SqlRender):
--   @cohort_database_schema  schema holding the cohort tables
--   @drug_cohort_table       table with drug administrations (1 row per dose)
--   @arm_cohort_table        table with the arm cohort (index date per subject)
--   @target_cohort_id        arm cohort id (90210 denosumab / 90220 ZA)
--   @switch_drug_cohort_id   administration cohort id of the OTHER agent
--   @grace_days              days after index before an other-agent dose counts

SELECT
  @target_cohort_id                                            AS cohort_definition_id,
  a.subject_id,
  a.cohort_start_date                                          AS arm_start_date,
  MIN(s.cohort_start_date)                                     AS first_switch_date,
  DATEDIFF(DAY, a.cohort_start_date, MIN(s.cohort_start_date)) AS days_to_switch
FROM @cohort_database_schema.@arm_cohort_table a
INNER JOIN @cohort_database_schema.@drug_cohort_table s
  ON  s.subject_id           = a.subject_id
  AND s.cohort_definition_id = @switch_drug_cohort_id
  AND s.cohort_start_date   >= DATEADD(DAY, @grace_days, a.cohort_start_date)
WHERE a.cohort_definition_id = @target_cohort_id
GROUP BY a.subject_id, a.cohort_start_date
;
