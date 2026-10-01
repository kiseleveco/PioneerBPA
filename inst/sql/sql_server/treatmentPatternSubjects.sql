-- Per-subject rollup for the arm, used for the ALL and NO_REGIMEN summary rows.
-- One row per arm member: index date, last administration, dose count, and the
-- start -> last-dose span (in days).
--
-- Parameters (SqlRender):
--   @cohort_database_schema  schema holding the cohort tables
--   @drug_cohort_table       table with drug administrations (1 row per dose)
--   @arm_cohort_table        table with the arm cohort (index date per subject)
--   @target_cohort_id        arm cohort id (90210 denosumab / 90220 ZA)
--   @drug_cohort_id          administration cohort id (1771 denosumab / 1770 ZA)

WITH adm AS (
  SELECT DISTINCT d.subject_id, d.cohort_start_date AS adm_date
  FROM @cohort_database_schema.@drug_cohort_table d
  INNER JOIN @cohort_database_schema.@arm_cohort_table a
    ON  a.subject_id           = d.subject_id
    AND a.cohort_definition_id = @target_cohort_id
  WHERE d.cohort_definition_id = @drug_cohort_id
    AND d.cohort_start_date   >= a.cohort_start_date
)
SELECT
  @target_cohort_id                                     AS cohort_definition_id,
  a.subject_id,
  a.cohort_start_date                                   AS arm_start_date,
  MAX(adm.adm_date)                                     AS last_dose_date,
  COUNT(adm.adm_date)                                   AS n_doses,
  DATEDIFF(DAY, a.cohort_start_date, MAX(adm.adm_date)) AS days_start_to_last
FROM @cohort_database_schema.@arm_cohort_table a
INNER JOIN adm ON adm.subject_id = a.subject_id
WHERE a.cohort_definition_id = @target_cohort_id
GROUP BY a.subject_id, a.cohort_start_date
;
