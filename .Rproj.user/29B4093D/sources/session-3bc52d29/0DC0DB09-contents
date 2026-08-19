-- ===== 90200: any BPA; start = earliest of ZA/denosumab (tie -> ZA) =====
INSERT INTO @cohort_database_schema.@cohortTableNew (cohort_definition_id, subject_id, cohort_start_date, cohort_end_date)
SELECT 90200, m.subject_id, m.cohort_start_date, MAX(ct.cohort_end_date)
FROM (
  SELECT subject_id,
         CASE WHEN denosumab_start_date IS NULL          THEN za_start_date
              WHEN za_start_date IS NULL                 THEN denosumab_start_date
              WHEN za_start_date <= denosumab_start_date THEN za_start_date
              ELSE denosumab_start_date END AS cohort_start_date
  FROM #cohort_src
  WHERE za_start_date IS NOT NULL OR denosumab_start_date IS NOT NULL
) m
LEFT JOIN @cohort_database_schema.@cohort_table ct
  ON  ct.subject_id           = m.subject_id
  AND ct.cohort_definition_id = @target_metastasis
GROUP BY m.subject_id, m.cohort_start_date;
