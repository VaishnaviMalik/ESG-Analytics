USE ESG_Project;
SELECT TOP 10 * FROM dbo.esg_wide_raw;

-- how many countries, indicatoes are there?
SELECT COUNT(*) AS total_records,
	COUNT(DISTINCT Country_Name) AS total_countries,
	COUNT(DISTINCT Indicator_Name) AS total_indicators
FROM dbo.esg_wide_raw;

-- null values per year
SELECT 
  '1960' AS year, COUNT(CASE WHEN "[1960]" IS NULL THEN 1 END) AS null_count, COUNT(*) AS total
FROM esg_wide_raw
UNION ALL
SELECT '1970', COUNT(CASE WHEN "[1970]" IS NULL THEN 1 END), COUNT(*) FROM esg_wide_raw
UNION ALL
SELECT '1980', COUNT(CASE WHEN "[1980]" IS NULL THEN 1 END), COUNT(*) FROM esg_wide_raw
UNION ALL
SELECT '1990', COUNT(CASE WHEN "[1990]" IS NULL THEN 1 END), COUNT(*) FROM esg_wide_raw
UNION ALL
SELECT '2000', COUNT(CASE WHEN "[2000]" IS NULL THEN 1 END), COUNT(*) FROM esg_wide_raw
UNION ALL
SELECT '2010', COUNT(CASE WHEN "[2010]" IS NULL THEN 1 END), COUNT(*) FROM esg_wide_raw
UNION ALL
SELECT '2020', COUNT(CASE WHEN "[2020]" IS NULL THEN 1 END), COUNT(*) FROM esg_wide_raw
UNION ALL
SELECT '2025', COUNT(CASE WHEN "[2025]" IS NULL THEN 1 END), COUNT(*) FROM esg_wide_raw
ORDER BY year;

-- Sample data quality
SELECT TOP 20
	Country_Name,
	Indicator_Name,
	"[2019]",
	"[2020]",
	"[2021]",
	"[2022]",
	"[2023]",
	"[2024]",
	"[2025]"
FROM dbo.esg_wide_raw
WHERE "[2024]" IS NOT NULL
AND "[2025]" IS NOT NULL
ORDER BY Country_Name;

-- Value Range Check
SELECT 
  'Min value' AS metric,
  CAST(MIN(CAST("[2020]" AS FLOAT)) AS VARCHAR(50)) AS value
FROM esg_wide_raw
WHERE "[2020]" IS NOT NULL
UNION ALL
SELECT 'Max value', CAST(MAX(CAST("[2020]" AS FLOAT)) AS VARCHAR(50)) FROM esg_wide_raw WHERE "[2020]" IS NOT NULL
UNION ALL
SELECT 'Avg value', CAST(AVG(CAST("[2020]" AS FLOAT)) AS VARCHAR(50)) FROM esg_wide_raw WHERE "[2020]" IS NOT NULL;