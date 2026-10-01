-- Treatment-pattern episodes: continuous-exposure runs by dosing-interval band.
-- One row per (subject, continuous episode). An episode is a MAXIMAL run of
-- consecutive administrations whose connecting gaps all fall in the SAME band,
-- so different regimens (e.g. 3-5 weeks vs 11-13 weeks) are never merged into
-- one continuous stretch. The dose at a band change is shared by both episodes.
--
-- Parameters (SqlRender):
--   @cohort_database_schema  schema holding the cohort tables
--   @drug_cohort_table       table with drug administrations (1 row per dose)
--   @arm_cohort_table        table with the arm cohort (index date per subject)
--   @target_cohort_id        arm cohort id (90210 denosumab / 90220 ZA)
--   @drug_cohort_id          administration cohort id (1771 denosumab / 1770 ZA)
--   @band{1,2,3}_lo/_hi/_label  up to three interval bands, in days
--                               (unused band: pass an impossible range)

WITH adm AS (
  -- distinct administration dates for the drug, on/after the arm index date
  SELECT DISTINCT d.subject_id, d.cohort_start_date AS adm_date
  FROM @cohort_database_schema.@drug_cohort_table d
  INNER JOIN @cohort_database_schema.@arm_cohort_table a
    ON  a.subject_id           = d.subject_id
    AND a.cohort_definition_id = @target_cohort_id
  WHERE d.cohort_definition_id = @drug_cohort_id
    AND d.cohort_start_date   >= a.cohort_start_date
),
lnk AS (
  -- each row = the "link" from one dose to the next
  SELECT
    subject_id,
    adm_date AS left_date,
    LEAD(adm_date) OVER (PARTITION BY subject_id ORDER BY adm_date) AS right_date
  FROM adm
),
banded AS (
  SELECT
    subject_id, left_date, right_date,
    DATEDIFF(DAY, left_date, right_date) AS gap_days,
    CASE
      WHEN DATEDIFF(DAY, left_date, right_date) BETWEEN @band1_lo AND @band1_hi THEN '@band1_label'
      WHEN DATEDIFF(DAY, left_date, right_date) BETWEEN @band2_lo AND @band2_hi THEN '@band2_label'
      WHEN DATEDIFF(DAY, left_date, right_date) BETWEEN @band3_lo AND @band3_hi THEN '@band3_label'
      ELSE 'break'
    END AS band
  FROM lnk
  WHERE right_date IS NOT NULL
),
flagged AS (
  -- start a new run whenever the band changes (a break also breaks the run)
  SELECT
    subject_id, left_date, right_date, band,
    CASE
      WHEN LAG(band) OVER (PARTITION BY subject_id ORDER BY left_date) IS NULL
        OR band <> LAG(band) OVER (PARTITION BY subject_id ORDER BY left_date)
      THEN 1 ELSE 0
    END AS new_run
  FROM banded
),
runs AS (
  SELECT
    subject_id, left_date, right_date, band,
    SUM(new_run) OVER (PARTITION BY subject_id ORDER BY left_date ROWS UNBOUNDED PRECEDING) AS run_id
  FROM flagged
)
SELECT
  @target_cohort_id                              AS cohort_definition_id,
  subject_id,
  band                                           AS regimen,
  run_id,
  COUNT(*) + 1                                   AS n_doses,
  MIN(left_date)                                 AS episode_start_date,
  MAX(right_date)                                AS episode_end_date,
  DATEDIFF(DAY, MIN(left_date), MAX(right_date)) AS length_days
FROM runs
WHERE band <> 'break'
GROUP BY subject_id, run_id, band
;
