USE ESG_Project;

-- Look at the topics of the indicators for once for categorization
SELECT DISTINCT(Topic) FROM dbo.ESGSeries;

-- Add a category column
ALTER TABLE ESGSeries ADD ESG_Category CHAR(1);
UPDATE ESGSeries
SET ESG_Category = CASE
	WHEN Topic LIKE 'Environment%' THEN 'E'
	WHEN Topic LIKE 'Governance%' THEN 'G'
	WHEN Topic Like 'Social%' THEN 'S'
	WHEN Topic LIKE 'Education' THEN 'S'
	ELSE 'U'
END;

-- Minimal lookup from the populated ESGSeries table
CREATE TABLE esg_category_lookup(
	Indicator_Code NVARCHAR(50) PRIMARY KEY,
	ESG_Category CHAR(1)
);

INSERT INTO esg_category_lookup
SELECT DISTINCT
	Series_Code AS Indicator_Code,
	ESG_Category
FROM ESGSeries;

-- Join to esg_long
ALTER TABLE esg_long_raw ADD ESG_Category CHAR(1);

UPDATE esg_long_raw
SET ESG_Category = esg_category_lookup.ESG_Category
FROM esg_long_raw
LEFT JOIN esg_category_lookup ON esg_long_raw.Indicator_Code = esg_category_lookup.Indicator_Code;

-- Final check
SELECT TOP 10 * FROM esg_long_raw;

SELECT 
    ESG_Category,
    COUNT(DISTINCT Indicator_Code) AS indicator_count,
    COUNT(*) AS total_rows
FROM esg_long_raw
WHERE ESG_Category IS NOT NULL
GROUP BY ESG_Category
ORDER BY ESG_Category;