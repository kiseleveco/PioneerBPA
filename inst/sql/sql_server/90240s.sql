-- ===== 90240s (SENSITIVITY): BPA arm = other BPA (not denosumab, not ZA, not AA) =====
-- bpa_type 'AllBPA' marks a first bone-targeting agent captured by the broad BPA
-- cohort but not by ZA / denosumab / AA.
INSERT INTO @cohort_database_schema.@cohortTableNew (cohort_definition_id, subject_id, cohort_start_date, cohort_end_date)
SELECT 90240, s.subject_id, s.allBPA_start_date, MAX(ct.cohort_end_date)
FROM #cohort_src s
LEFT JOIN @cohort_database_schema.@cohort_table ct
  ON  ct.subject_id           = s.subject_id
  AND ct.cohort_definition_id = @target_metastasis
WHERE s.bpa_type = 'AllBPA'
GROUP BY s.subject_id, s.allBPA_start_date;
