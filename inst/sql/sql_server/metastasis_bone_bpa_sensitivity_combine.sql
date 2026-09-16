DROP TABLE IF EXISTS #bpa_join;

--HINT DISTRIBUTE_ON_KEY(subject_id)
SELECT
  t.*,
  za.cohort_start_date        AS za_start_date,
  za.cohort_end_date          AS za_end_date,
  denosumab.cohort_start_date AS denosumab_start_date,
  denosumab.cohort_end_date   AS denosumab_end_date,
  aa.cohort_start_date        AS aa_start_date,
  allBPA.cohort_start_date    AS allBPA_start_date,
  CASE
  WHEN za.cohort_start_date IS NOT NULL
   AND (denosumab.cohort_start_date IS NULL OR za.cohort_start_date <= denosumab.cohort_start_date)
   AND (aa.cohort_start_date        IS NULL OR za.cohort_start_date <= aa.cohort_start_date)
    THEN 'ZA'
  WHEN denosumab.cohort_start_date IS NOT NULL
   AND (za.cohort_start_date IS NULL OR denosumab.cohort_start_date <  za.cohort_start_date)
   AND (aa.cohort_start_date IS NULL OR denosumab.cohort_start_date <= aa.cohort_start_date)
    THEN 'Denosumab'
  WHEN aa.cohort_start_date IS NOT NULL
   AND (za.cohort_start_date        IS NULL OR aa.cohort_start_date < za.cohort_start_date)
   AND (denosumab.cohort_start_date IS NULL OR aa.cohort_start_date < denosumab.cohort_start_date)
    THEN 'AA'
  WHEN allBPA.cohort_start_date IS NOT NULL
   AND za.cohort_start_date        IS NULL
   AND denosumab.cohort_start_date IS NULL
   AND aa.cohort_start_date        IS NULL
    THEN 'AllBPA'
END AS bpa_type
INTO #bpa_join
FROM @cohort_database_schema.@target_table t
LEFT JOIN (
  SELECT subject_id, cohort_start_date, cohort_end_date
  FROM (
    SELECT c.subject_id, c.cohort_start_date, c.cohort_end_date,
           ROW_NUMBER() OVER (PARTITION BY c.subject_id ORDER BY c.cohort_start_date) AS rn
    FROM @cohort_database_schema.@cohort_table c
    INNER JOIN (SELECT DISTINCT subject_id, bone_date FROM @cohort_database_schema.@target_table) tt
      ON tt.subject_id = c.subject_id
    WHERE c.cohort_definition_id = @bpa_za
      AND c.cohort_start_date >= DATEADD(DAY, -30, tt.bone_date)
  ) x
  WHERE rn = 1
) za ON za.subject_id = t.subject_id
LEFT JOIN (
  SELECT subject_id, cohort_start_date, cohort_end_date
  FROM (
    SELECT c.subject_id, c.cohort_start_date, c.cohort_end_date,
           ROW_NUMBER() OVER (PARTITION BY c.subject_id ORDER BY c.cohort_start_date) AS rn
    FROM @cohort_database_schema.@cohort_table c
    INNER JOIN (SELECT DISTINCT subject_id, bone_date FROM @cohort_database_schema.@target_table) tt
      ON tt.subject_id = c.subject_id
    WHERE c.cohort_definition_id = @bpa_denosumab
      AND c.cohort_start_date >= DATEADD(DAY, -30, tt.bone_date)
  ) x
  WHERE rn = 1
) denosumab ON denosumab.subject_id = t.subject_id
LEFT JOIN (
  SELECT subject_id, cohort_start_date, cohort_end_date
  FROM (
    SELECT c.subject_id, c.cohort_start_date, c.cohort_end_date,
           ROW_NUMBER() OVER (PARTITION BY c.subject_id ORDER BY c.cohort_start_date) AS rn
    FROM @cohort_database_schema.@cohort_table c
    INNER JOIN (SELECT DISTINCT subject_id, bone_date FROM @cohort_database_schema.@target_table) tt
      ON tt.subject_id = c.subject_id
    WHERE c.cohort_definition_id = @bpa_aa
      AND c.cohort_start_date >= DATEADD(DAY, -30, tt.bone_date)
  ) x
  WHERE rn = 1
) aa ON aa.subject_id = t.subject_id
LEFT JOIN (
  SELECT subject_id, cohort_start_date, cohort_end_date
  FROM (
    SELECT c.subject_id, c.cohort_start_date, c.cohort_end_date,
           ROW_NUMBER() OVER (PARTITION BY c.subject_id ORDER BY c.cohort_start_date) AS rn
    FROM @cohort_database_schema.@cohort_table c
    INNER JOIN (SELECT DISTINCT subject_id, bone_date FROM @cohort_database_schema.@target_table) tt
      ON tt.subject_id = c.subject_id
    WHERE c.cohort_definition_id = @bpa_all
      AND c.cohort_start_date >= DATEADD(DAY, -30, tt.bone_date)
  ) x
  WHERE rn = 1
) allBPA ON allBPA.subject_id = t.subject_id;

DROP TABLE IF EXISTS @cohort_database_schema.@target_table;

--HINT DISTRIBUTE_ON_KEY(subject_id)
SELECT *
INTO @cohort_database_schema.@target_table
FROM #bpa_join;

DROP TABLE IF EXISTS #bpa_join;
