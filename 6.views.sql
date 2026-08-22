-- ESG Analytics: Views for Power BI Dashboard

-- Purpose: Create reusable SQL views as the data layer for Power BI

-- Views created:
--   1. vw_ESG_Scores_Detailed - Composite scores with data quality metrics
--   2. vw_ESG_Normalized_Detail - Raw normalized scores for drill-down

USE ESG_Project;
GO

-- Drop views if they exist (in reverse dependency order)
DROP VIEW IF EXISTS dbo.vw_ESG_Normalized_Detail;
DROP VIEW IF EXISTS dbo.vw_ESG_Scores_Detailed;
GO

-- View 1: Detailed Dashboard View (Main)
-- Composite ESG scores with data quality metrics

CREATE VIEW dbo.vw_ESG_Scores_Detailed AS
SELECT 
    s.Country_Name,
    s.Country_Code,
    s.Year,
    s.ESG_Score,
    s.ESG_Tier,
    s.E_Score,
    s.S_Score,
    s.G_Score,
    s.E_Indicator_Count,
    s.S_Indicator_Count,
    s.G_Indicator_Count,
    ROUND(CAST(s.E_Indicator_Count AS FLOAT) / 35 * 100, 1) AS E_Coverage_Pct,
    ROUND(CAST(s.S_Indicator_Count AS FLOAT) / 28 * 100, 1) AS S_Coverage_Pct,
    ROUND(CAST(s.G_Indicator_Count AS FLOAT) / 17 * 100, 1) AS G_Coverage_Pct,
    CASE 
        WHEN (s.E_Indicator_Count + s.S_Indicator_Count + s.G_Indicator_Count) >= 68 THEN 'Complete'
        WHEN (s.E_Indicator_Count + s.S_Indicator_Count + s.G_Indicator_Count) >= 60 THEN 'Good'
        ELSE 'Partial'
    END AS Data_Quality
FROM dbo.esg_scores_final s;

GO

-- View 2: Normalized Scores Detail View
-- Raw normalized indicator scores for drill-down analysis

CREATE VIEW dbo.vw_ESG_Normalized_Detail AS
SELECT 
    n.Country_Name,
    n.Country_Code,
    n.Year,
    n.Indicator_Code,
    n.ESG_Category,
    n.Value AS Raw_Value,
    n.Min_Value AS Indicator_Min_2020_2025,
    n.Max_Value AS Indicator_Max_2020_2025,
    n.Directionality,
    n.Normalized_Score,
    d.Unit,
    d.Rationale AS Directionality_Rationale
FROM dbo.esg_normalized n
LEFT JOIN dbo.esg_directionality d ON n.Indicator_Code = d.Indicator_Code;

GO

-- Validation
SELECT TOP 3 * FROM dbo.vw_ESG_Scores_Detailed WHERE Year = 2025 ORDER BY ESG_Score DESC;
SELECT TOP 3 * FROM dbo.vw_ESG_Normalized_Detail WHERE Year = 2025;

GO