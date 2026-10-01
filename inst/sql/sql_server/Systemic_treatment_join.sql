DROP TABLE IF EXISTS #treatment_join;
SELECT
  t.*,
  adt.adt_start_date,
  arpi.arpi_start_date,
  chemo.chemo_start_date
INTO #treatment_join
FROM @cohort_database_schema.@target_table t
LEFT JOIN (
  SELECT c.subject_id, MIN(c.cohort_start_date) AS adt_start_date
  FROM @cohort_database_schema.@cohort_table c
  INNER JOIN @cohort_database_schema.@target_table tt
    ON tt.subject_id = c.subject_id
  WHERE c.cohort_definition_id = @cohort_adt
    AND c.cohort_start_date >= DATEADD(DAY, -30, tt.metastasis_date)
    AND c.cohort_start_date <= DATEADD(DAY, 180, tt.metastasis_date)
  GROUP BY c.subject_id
) adt ON adt.subject_id = t.subject_id
LEFT JOIN (
  SELECT c.subject_id, MIN(c.cohort_start_date) AS arpi_start_date
  FROM @cohort_database_schema.@cohort_table c
  INNER JOIN @cohort_database_schema.@target_table tt
    ON tt.subject_id = c.subject_id
  WHERE c.cohort_definition_id = @cohort_arpi
    AND c.cohort_start_date >= DATEADD(DAY, -30, tt.metastasis_date)
    AND c.cohort_start_date <= DATEADD(DAY, 180, tt.metastasis_date)
  GROUP BY c.subject_id
) arpi ON arpi.subject_id = t.subject_id
LEFT JOIN (
  SELECT c.subject_id, MIN(c.cohort_start_date) AS chemo_start_date
  FROM @cohort_database_schema.@cohort_table c
  INNER JOIN @cohort_database_schema.@target_table tt
    ON tt.subject_id = c.subject_id
  WHERE c.cohort_definition_id = @cohort_chemo
    AND c.cohort_start_date >= DATEADD(DAY, -30, tt.metastasis_date)
    AND c.cohort_start_date <= DATEADD(DAY, 180, tt.metastasis_date)
  GROUP BY c.subject_id
) chemo ON chemo.subject_id = t.subject_id;
DROP TABLE IF EXISTS @cohort_database_schema.@target_table;
SELECT * INTO @cohort_database_schema.@target_table FROM #treatment_join;
DROP TABLE IF EXISTS #treatment_join;
