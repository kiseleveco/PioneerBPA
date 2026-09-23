-- ===== 90300: no BPA; start = earliest of ADT/ARPI/chemo (tie order ADT>ARPI>chemo) =====
INSERT INTO @cohort_database_schema.@cohortTableNew (cohort_definition_id, subject_id, cohort_start_date, cohort_end_date)
SELECT 90400, m.subject_id, m.cohort_start_date, MAX(ct.cohort_end_date)
FROM (
  SELECT subject_id, cohort_start_date
  FROM (
    SELECT u.subject_id, u.line_start AS cohort_start_date,
           ROW_NUMBER() OVER (PARTITION BY u.subject_id ORDER BY u.line_start, u.priority) AS rn
    FROM (
      SELECT subject_id, adt_start_date   AS line_start, 1 AS priority
        FROM #cohort_src WHERE za_start_date IS NULL AND denosumab_start_date IS NULL AND aa_start_date IS NULL AND allBPA_start_date IS NULL AND adt_start_date   IS NOT NULL
      UNION ALL
      SELECT subject_id, arpi_start_date,  2
        FROM #cohort_src WHERE za_start_date IS NULL AND denosumab_start_date IS NULL AND aa_start_date IS NULL AND allBPA_start_date IS NULL AND arpi_start_date  IS NOT NULL
      UNION ALL
      SELECT subject_id, chemo_start_date, 3
        FROM #cohort_src WHERE za_start_date IS NULL AND denosumab_start_date IS NULL AND aa_start_date IS NULL AND allBPA_start_date IS NULL AND chemo_start_date IS NOT NULL
    ) u
  ) z
  WHERE rn = 1
) m
LEFT JOIN @cohort_database_schema.@cohort_table ct
  ON  ct.subject_id           = m.subject_id
  AND ct.cohort_definition_id = @target_metastasis
GROUP BY m.subject_id, m.cohort_start_date;
