-- ===== Prerequisite: staging (once per session) =====
DROP TABLE IF EXISTS #cohort_src;
--HINT DISTRIBUTE_ON_KEY(subject_id)
SELECT
  t.subject_id,
  t.metastasis_date,
  t.bone_date,
  t.za_start_date,
  t.denosumab_start_date,
  t.bpa_type,
  t.aa_start_date,
  t.allBPA_start_date,
  t.adt_start_date,
  t.arpi_start_date,
  t.chemo_start_date,
  CASE WHEN t.adt_start_date   >= DATEADD(DAY,-30,t.metastasis_date)
        AND t.adt_start_date   <= DATEADD(DAY,180,t.metastasis_date) THEN 1 ELSE 0 END AS adt_in,
  CASE WHEN t.arpi_start_date  >= DATEADD(DAY,-30,t.metastasis_date)
        AND t.arpi_start_date  <= DATEADD(DAY,180,t.metastasis_date) THEN 1 ELSE 0 END AS arpi_in,
  CASE WHEN t.chemo_start_date >= DATEADD(DAY,-30,t.metastasis_date)
        AND t.chemo_start_date <= DATEADD(DAY,180,t.metastasis_date) THEN 1 ELSE 0 END AS chemo_in
INTO #cohort_src
FROM @cohort_database_schema.@target_table t;
