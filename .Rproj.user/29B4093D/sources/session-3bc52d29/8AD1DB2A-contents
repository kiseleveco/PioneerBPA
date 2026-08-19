DROP TABLE IF EXISTS @cohort_database_schema.@target_table;

SELECT
  m.subject_id,
  m.cohort_start_date AS metastasis_date,
  b.cohort_start_date AS bone_date
INTO @cohort_database_schema.@target_table
FROM @cohort_database_schema.@cohort_table m
INNER JOIN @cohort_database_schema.@cohort_table b
  ON m.subject_id = b.subject_id
WHERE m.cohort_definition_id = @target_metastasis
  AND b.cohort_definition_id = @target_bones
  AND b.cohort_start_date >= DATEADD(DAY, -90, m.cohort_start_date)
  AND b.cohort_start_date <= DATEADD(DAY,  30, m.cohort_start_date)
;
