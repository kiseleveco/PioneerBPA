-- Time from the bone-metastasis date to the first BPA administration.
-- One row per subject:
--   days_to_first_bpa : days from the bone-metastasis index date (cohort
--                       @bone_cohort_id start) to the first BPA start date
--                       (cohort @bpa_cohort_id start). Can be negative: the BPA
--                       window opens 30 days BEFORE the bone-metastasis date.
--   first_agent       : agent of the first BPA ('Denosumab' / 'ZA'), taken from
--                       the first-agent arm cohorts; 'Other' if in neither arm.
--
-- MIN() per subject guarantees one row per subject even if a cohort has more
-- than one row for the same person.
--
-- Parameters (SqlRender):
--   @cohort_database_schema  schema holding the derived cohort table
--   @arm_cohort_table        derived cohort table (90100 / 90200 / 90210 / 90220)
--   @bone_cohort_id          bone-metastasis index cohort id (90100)
--   @bpa_cohort_id           any-BPA cohort id (90200)
--   @deno_cohort_id          denosumab-first arm cohort id (90210)
--   @za_cohort_id            ZA-first arm cohort id (90220)

SELECT
  b.subject_id,
  DATEDIFF(DAY, b.bone_date, a.bpa_date) AS days_to_first_bpa,
  CASE
    WHEN d.subject_id IS NOT NULL THEN 'Denosumab'
    WHEN z.subject_id IS NOT NULL THEN 'ZA'
    ELSE 'Other'
  END AS first_agent
FROM (
  SELECT subject_id, MIN(cohort_start_date) AS bone_date
  FROM @cohort_database_schema.@arm_cohort_table
  WHERE cohort_definition_id = @bone_cohort_id
  GROUP BY subject_id
) b
INNER JOIN (
  SELECT subject_id, MIN(cohort_start_date) AS bpa_date
  FROM @cohort_database_schema.@arm_cohort_table
  WHERE cohort_definition_id = @bpa_cohort_id
  GROUP BY subject_id
) a ON a.subject_id = b.subject_id
LEFT JOIN (
  SELECT DISTINCT subject_id
  FROM @cohort_database_schema.@arm_cohort_table
  WHERE cohort_definition_id = @deno_cohort_id
) d ON d.subject_id = b.subject_id
LEFT JOIN (
  SELECT DISTINCT subject_id
  FROM @cohort_database_schema.@arm_cohort_table
  WHERE cohort_definition_id = @za_cohort_id
) z ON z.subject_id = b.subject_id
;
