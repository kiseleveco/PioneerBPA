-- ===== 90100: bone-metastasis index =====
INSERT INTO @cohort_database_schema.@cohortTableNew (cohort_definition_id, subject_id, cohort_start_date, cohort_end_date)
SELECT 90100, s.subject_id, s.bone_date, MAX(ct.cohort_end_date)
FROM #cohort_src s
LEFT JOIN @cohort_database_schema.@cohort_table ct
  ON  ct.subject_id           = s.subject_id
  AND ct.cohort_definition_id = @target_metastasis
WHERE s.bone_date IS NOT NULL
  AND s.bone_date >= DATEADD(DAY,-90,s.metastasis_date)
  AND s.bone_date <= DATEADD(DAY, 30,s.metastasis_date)
GROUP BY s.subject_id, s.bone_date;
