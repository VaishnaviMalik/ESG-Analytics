-- Normalization & Composite Scoring Pipeline

-- Purpose: Transform raw ESG indicators into normalized 0-100 scores with
--          directionality-aware logic, filter by coverage (>30%), and compute
--          composite E/S/G/ESG scores by Country + Year (2000-2025).

-- Methodology:
--   1. Filter Year >= 2000 (pre-2000 data ~60-90% sparse, unreliable for normalization)
--   2. Calculate indicator coverage (% non-null values in 2000-2025)
--   3. Map directionality based on unit semantics (Higher_Better vs Lower_Better)
--   4. Apply min-max normalization with directionality logic
--   5. Aggregate to Country + Year level (simple average of normalized indicators)
--   6. Assign ESG_Tier (High, Medium, Low)

USE ESG_Project;
GO

-- Create Directionality Reference Table
-- Heuristic-based mapping from unit semantics + manual overrides for edge cases

IF OBJECT_ID('dbo.esg_directionality', 'U') IS NOT NULL
    DROP TABLE dbo.esg_directionality;
GO

CREATE TABLE dbo.esg_directionality (
    Indicator_Code NVARCHAR(50) PRIMARY KEY,
    Unit NVARCHAR(100),
    Directionality NVARCHAR(20), -- 'Higher_Better' or 'Lower_Better'
    Rationale NVARCHAR(255)
);
GO

-- Populate directionality table based on unit heuristics

INSERT INTO dbo.esg_directionality (Indicator_Code, Unit, Directionality, Rationale)
SELECT 
    s.Series_Code,
    s.Unit_of_measure,
    CASE 
        -- Emissions, pollution, environmental harm → Lower is Better
        WHEN s.Unit_of_measure LIKE '%Mt CO2eq%' THEN 'Lower_Better'
        WHEN s.Unit_of_measure LIKE '%kg of oil equivalent%' THEN 'Lower_Better'
        WHEN s.Unit_of_measure LIKE '%Degrees%Celsius%' THEN 'Lower_Better'
        WHEN s.Unit_of_measure LIKE '%microgram per cubic meter%' THEN 'Lower_Better'
        WHEN s.Unit_of_measure LIKE '%t CO2e/capita%' THEN 'Lower_Better'
        
        -- Pre-normalized indices (already on 1-100 scale) → Higher is Better
        WHEN s.Unit_of_measure LIKE '%index (2014-2016=100)%' THEN 'Higher_Better'
        WHEN s.Unit_of_measure LIKE '%Score on 1-100 scale%' THEN 'Higher_Better'
        WHEN s.Unit_of_measure LIKE '%Standardized scores%' THEN 'Higher_Better'
        WHEN s.Unit_of_measure LIKE '%Standardized value%' THEN 'Higher_Better'
        
        -- Mortality, morbidity rates → Lower is Better
        WHEN s.Unit_of_measure LIKE '%Per 1000 live births%' THEN 'Lower_Better'
        WHEN s.Unit_of_measure LIKE '%Per 1000 people%' THEN 'Lower_Better'
        
        -- Economic welfare, health, development indicators → Higher is Better
        WHEN s.Unit_of_measure LIKE '%MJ per 2021 USD PPP GDP%' THEN 'Lower_Better' -- Energy intensity (inverse)
        WHEN s.Unit_of_measure LIKE '%Births per woman%' THEN 'Higher_Better' -- Context: fertility planning/women's rights
        WHEN s.Unit_of_measure LIKE '%Fractional count%' THEN 'Higher_Better' -- Coverage/access metrics default
        
        -- Percentages: Most are positive (% employment, % access) → Higher is Better
        -- Exception: "% of internal resources" in context of government spending
        WHEN s.Unit_of_measure LIKE '%Percent%' OR s.Unit_of_measure LIKE '%%%' THEN 'Higher_Better'
        
        -- Default: Data-driven (inspect actual correlation with development)
        ELSE 'Higher_Better'
    END AS Directionality,
    CASE 
        WHEN s.Unit_of_measure LIKE '%Mt CO2eq%' THEN 'Emissions reduction drives higher ESG scores'
        WHEN s.Unit_of_measure LIKE '%index (2014-2016=100)%' THEN 'Pre-normalized index; higher inherently better'
        WHEN s.Unit_of_measure LIKE '%Score on 1-100 scale%' THEN 'Pre-normalized score; higher inherently better'
        WHEN s.Unit_of_measure LIKE '%Per 1000 live births%' THEN 'Mortality proxy; lower = better health outcomes'
        WHEN s.Unit_of_measure LIKE '%Percent%' OR s.Unit_of_measure LIKE '%%%' THEN 'Access/participation metric; higher = broader coverage'
        WHEN s.Unit_of_measure LIKE '%MJ per 2021 USD PPP GDP%' THEN 'Energy intensity; lower = more efficient economy'
        ELSE 'Semantic heuristic from unit measurement'
    END AS Rationale
FROM dbo.ESGSeries s
WHERE s.Series_Code IS NOT NULL;

GO

-- Correction step: Update directionality table
BEGIN TRANSACTION;

WITH CorrectDirectionality AS (
    SELECT Indicator_Code, New_Directionality, New_Rationale
    FROM (VALUES
        -- Environmental
        ('EG.ELC.COAL.ZS',    'Lower_Better',  'Coal electricity share; lower fossil fuel dependence drives higher E score'),
        ('EG.USE.COMM.FO.ZS', 'Lower_Better',  'Fossil fuel consumption; lower fossil dependence drives higher E score'),
        ('EN.CLC.CDDY.XD',    'Lower_Better',  'Cooling degree days; lower climate heat stress/energy demand is better'),
        ('EN.CLC.HDDY.XD',    'Lower_Better',  'Heating degree days; lower climate cold stress/energy demand is better'),
        ('EN.CLC.HEAT.XD',    'Lower_Better',  'Heatwave days; lower physical climate risk is better'),
        ('EN.LND.LTMP.DC',    'Lower_Better',  'Land surface temperature; lower temperature anomaly/heat island risk'),
        ('EN.MAM.THRD.NO',    'Lower_Better',  'Threatened mammal species; lower count indicates better biodiversity'),
        ('ER.H2O.FWST.ZS',    'Lower_Better',  'Level of water stress; lower stress indicates water security'),
        ('ER.H2O.FWTL.ZS',    'Lower_Better',  'Freshwater withdrawals; lower extraction rate prevents resource depletion'),
        ('NY.ADJ.DFOR.GN.ZS', 'Lower_Better',  'Forest depletion % GNI; lower depletion preserves natural capital'),
        ('NY.ADJ.DRES.GN.ZS', 'Lower_Better',  'Natural resource depletion % GNI; lower depletion preserves natural capital'),
        
        -- Social & Health
        ('SH.DTH.COMM.ZS',    'Lower_Better',  'Deaths from communicable diseases; lower mortality indicates better healthcare'),
        ('SH.STA.OWAD.ZS',    'Lower_Better',  'Prevalence of overweight adults; lower prevalence indicates better public health'),
        ('SI.POV.DDAY',       'Lower_Better',  'Poverty headcount ($2.15/day); lower poverty drives higher S score'),
        ('SI.POV.GINI',       'Lower_Better',  'Gini index; lower income inequality drives higher S score'),
        ('SI.POV.NAHC',       'Lower_Better',  'National poverty headcount; lower poverty drives higher S score'),
        ('SI.POV.UMIC',       'Lower_Better',  'Poverty headcount ($6.85/day); lower poverty drives higher S score'),
        ('SI.SPR.PGAP',       'Lower_Better',  'Poverty gap; lower gap indicates less extreme poverty severity'),
        ('SL.TLF.0714.ZS',    'Lower_Better',  'Child labor rate; lower child employment rate protects human rights'),
        ('SL.UEM.NEET.FE.ZS', 'Lower_Better',  'Female youth NEET rate; lower rate indicates social/economic inclusion'),
        ('SL.UEM.NEET.ME.ZS', 'Lower_Better',  'Male youth NEET rate; lower rate indicates social/economic inclusion'),
        ('SL.UEM.TOTL.ZS',    'Lower_Better',  'Total unemployment rate; lower unemployment indicates labor market health'),
        ('SN.ITK.DEFC.ZS',    'Lower_Better',  'Undernourishment prevalence; lower hunger rate drives higher S score'),
        ('SP.UWT.TFRT',       'Lower_Better',  'Unmet need for contraception; lower unmet need reflects better healthcare access'),
        
        -- Infrastructure
        ('SH.MED.BEDS.ZS',    'Higher_Better', 'Hospital beds per 1,000 people; higher capacity indicates stronger healthcare infrastructure')
    ) AS T(Indicator_Code, New_Directionality, New_Rationale)
)
UPDATE target
SET target.Directionality = src.New_Directionality,
    target.Rationale      = src.New_Rationale
FROM dbo.esg_directionality AS target
INNER JOIN CorrectDirectionality AS src
    ON target.Indicator_Code = src.Indicator_Code;

-- Cheak updated record count
SELECT @@ROWCOUNT AS Updated_Rows;

COMMIT TRANSACTION;
GO

-- Calculate Indicator Coverage (% non-null in 2000-2025)

IF OBJECT_ID('dbo.esg_indicator_coverage', 'U') IS NOT NULL
    DROP TABLE dbo.esg_indicator_coverage;
GO

CREATE TABLE dbo.esg_indicator_coverage (
    Indicator_Code NVARCHAR(50) PRIMARY KEY,
    Total_Records INT,
    Non_Null_Records INT,
    Coverage_Pct DECIMAL(5, 2),
    Meets_Threshold BIT -- 1 if > 30%, 0 otherwise
);
GO

INSERT INTO dbo.esg_indicator_coverage
SELECT DISTINCT
    Indicator_Code,
    COUNT(*) OVER (PARTITION BY Indicator_Code) AS Total_Records,
    SUM(CASE WHEN Value IS NOT NULL THEN 1 ELSE 0 END) OVER (PARTITION BY Indicator_Code) AS Non_Null_Records,
    CAST(
        SUM(CASE WHEN Value IS NOT NULL THEN 1 ELSE 0 END) OVER (PARTITION BY Indicator_Code) * 100.0 
        / COUNT(*) OVER (PARTITION BY Indicator_Code) 
        AS DECIMAL(5, 2)
    ) AS Coverage_Pct,
    CASE 
        WHEN CAST(
            SUM(CASE WHEN Value IS NOT NULL THEN 1 ELSE 0 END) OVER (PARTITION BY Indicator_Code) * 100.0 
            / COUNT(*) OVER (PARTITION BY Indicator_Code) 
            AS DECIMAL(5, 2)
        ) > 30 
        THEN 1 
        ELSE 0 
    END AS Meets_Threshold
FROM dbo.esg_long_raw
WHERE Year >= 2000;

GO

-- Create Normalized Indicator Table (CTE APPROACH)

IF OBJECT_ID('dbo.esg_normalized', 'U') IS NOT NULL
    DROP TABLE dbo.esg_normalized;
GO

CREATE TABLE dbo.esg_normalized (
    Indicator_Code NVARCHAR(50),
    Country_Name NVARCHAR(100),
    Country_Code NVARCHAR(10),
    Year INT,
    Value DECIMAL(18, 6),
    ESG_Category NVARCHAR(1),
    Min_Value DECIMAL(18, 6),
    Max_Value DECIMAL(18, 6),
    Directionality NVARCHAR(20),
    Normalized_Score DECIMAL(5, 2),
    INDEX idx_country_year (Country_Code, Year),
    INDEX idx_category (ESG_Category)
);
GO

-- CTE 1: Calculate min/max for each indicator from 2020-2025 only
WITH MinMax_2020_2025 AS (
    SELECT 
        Indicator_Code,
        MIN(Value) AS Min_Value_2020_2025,
        MAX(Value) AS Max_Value_2020_2025
    FROM dbo.esg_long_raw
    WHERE Year >= 2020 AND Year <= 2025 AND Value IS NOT NULL
    GROUP BY Indicator_Code
),
-- CTE 2: Join all data with min/max and directionality
Normalized_Data AS (
    SELECT 
        l.Indicator_Code,
        l.Country_Name,
        l.Country_Code,
        l.Year,
        l.Value,
        c.ESG_Category,
        m.Min_Value_2020_2025,
        m.Max_Value_2020_2025,
        d.Directionality,
        CASE 
            -- Handle NULL values
            WHEN l.Value IS NULL THEN NULL
            -- Handle cases where min = max (zero variance → score = 50)
            WHEN m.Min_Value_2020_2025 = m.Max_Value_2020_2025 THEN 50.0
            -- Higher is Better: (Value - Min) / (Max - Min) * 100
            WHEN d.Directionality = 'Higher_Better'
                THEN CAST(
                    (l.Value - m.Min_Value_2020_2025) / 
                    (m.Max_Value_2020_2025 - m.Min_Value_2020_2025) * 100 
                    AS DECIMAL(5, 2)
                )
            -- Lower is Better: (Max - Value) / (Max - Min) * 100 [INVERTED]
            WHEN d.Directionality = 'Lower_Better'
                THEN CAST(
                    (m.Max_Value_2020_2025 - l.Value) / 
                    (m.Max_Value_2020_2025 - m.Min_Value_2020_2025) * 100 
                    AS DECIMAL(5, 2)
                )
            ELSE NULL
        END AS Normalized_Score
    FROM dbo.esg_long_raw l
    LEFT JOIN dbo.esg_category_lookup c ON l.Indicator_Code = c.Indicator_Code
    LEFT JOIN dbo.esg_directionality d ON l.Indicator_Code = d.Indicator_Code
    LEFT JOIN dbo.esg_indicator_coverage ic ON l.Indicator_Code = ic.Indicator_Code
    LEFT JOIN MinMax_2020_2025 m ON l.Indicator_Code = m.Indicator_Code
    WHERE l.Year >= 2000
      AND ic.Meets_Threshold = 1
)
-- Insert final normalized data
INSERT INTO dbo.esg_normalized
SELECT 
    Indicator_Code,
    Country_Name,
    Country_Code,
    Year,
    Value,
    ESG_Category,
    Min_Value_2020_2025,
    Max_Value_2020_2025,
    Directionality,
    Normalized_Score
FROM Normalized_Data;

GO

-- Create Composite ESG Scores by Country + Year

IF OBJECT_ID('dbo.esg_scores_final', 'U') IS NOT NULL
    DROP TABLE dbo.esg_scores_final;
GO

CREATE TABLE dbo.esg_scores_final (
    Country_Name NVARCHAR(100),
    Country_Code NVARCHAR(10),
    Year INT,
    E_Score DECIMAL(5, 2),
    S_Score DECIMAL(5, 2),
    G_Score DECIMAL(5, 2),
    ESG_Score DECIMAL(5, 2),
    ESG_Tier NVARCHAR(20),
    E_Indicator_Count INT,
    S_Indicator_Count INT,
    G_Indicator_Count INT,
    PRIMARY KEY (Country_Code, Year)
);
GO

WITH CountryAggregates AS (
    SELECT 
        n.Country_Name,
        n.Country_Code,
        n.Year,
        
        -- Category Scores
        ROUND(AVG(CASE WHEN n.ESG_Category = 'E' THEN n.Normalized_Score END), 2) AS E_Score,
        ROUND(AVG(CASE WHEN n.ESG_Category = 'S' THEN n.Normalized_Score END), 2) AS S_Score,
        ROUND(AVG(CASE WHEN n.ESG_Category = 'G' THEN n.Normalized_Score END), 2) AS G_Score,
        
        -- Overall ESG Score (Calculated across present pillar scores)
        ROUND((
            ISNULL(AVG(CASE WHEN n.ESG_Category = 'E' THEN n.Normalized_Score END), 0) +
            ISNULL(AVG(CASE WHEN n.ESG_Category = 'S' THEN n.Normalized_Score END), 0) +
            ISNULL(AVG(CASE WHEN n.ESG_Category = 'G' THEN n.Normalized_Score END), 0)
        ) / 3, 2) AS ESG_Score,
        
        -- Indicator counts
        COUNT(CASE WHEN n.ESG_Category = 'E' AND n.Normalized_Score IS NOT NULL THEN 1 END) AS E_Indicator_Count,
        COUNT(CASE WHEN n.ESG_Category = 'S' AND n.Normalized_Score IS NOT NULL THEN 1 END) AS S_Indicator_Count,
        COUNT(CASE WHEN n.ESG_Category = 'G' AND n.Normalized_Score IS NOT NULL THEN 1 END) AS G_Indicator_Count,
        
        -- Assign 5 equal buckets (Top 20% to Bottom 20%) per year
        NTILE(5) OVER (
            PARTITION BY n.Year 
            ORDER BY (
                ISNULL(AVG(CASE WHEN n.ESG_Category = 'E' THEN n.Normalized_Score END), 0) +
                ISNULL(AVG(CASE WHEN n.ESG_Category = 'S' THEN n.Normalized_Score END), 0) +
                ISNULL(AVG(CASE WHEN n.ESG_Category = 'G' THEN n.Normalized_Score END), 0)
            ) / 3 DESC
        ) AS Percentile_Bucket

    FROM dbo.esg_normalized n
    GROUP BY n.Country_Name, n.Country_Code, n.Year
)
INSERT INTO dbo.esg_scores_final(
    Country_Name,
    Country_Code,
    Year,
    E_Score,
    S_Score,
    G_Score,
    ESG_Score,
    ESG_Tier,
    E_Indicator_Count,
    S_Indicator_Count,
    G_Indicator_Count
)
SELECT 
    Country_Name,
    Country_Code,
    Year,
    E_Score,
    S_Score,
    G_Score,
    ESG_Score,
    
    -- Dynamic Tier Mapping based on NTILE Percentile Buckets
    CASE 
        WHEN Percentile_Bucket = 1 THEN 'High'             -- Top 20%
        WHEN Percentile_Bucket IN (2, 3, 4) THEN 'Medium'   -- Middle 60%
        WHEN Percentile_Bucket = 5 THEN 'Low'              -- Bottom 20%
    END AS ESG_Tier,
    
    E_Indicator_Count,
    S_Indicator_Count,
    G_Indicator_Count
FROM CountryAggregates;

GO

-- Validation & Summary Queries

-- How many indicators met the >30% threshold?
PRINT '=== COVERAGE SUMMARY ===';
SELECT 
    ESG_Category = ISNULL(c.ESG_Category, 'N/A'),
    Total_Indicators = COUNT(*),
    Above_30pct_Coverage = SUM(CASE WHEN ic.Meets_Threshold = 1 THEN 1 ELSE 0 END),
    Coverage_Rate_Pct = ROUND(SUM(CASE WHEN ic.Meets_Threshold = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
FROM dbo.esg_indicator_coverage ic
LEFT JOIN dbo.esg_category_lookup c ON ic.Indicator_Code = c.Indicator_Code
GROUP BY c.ESG_Category
ORDER BY ESG_Category;

-- Directionality Distribution
PRINT '=== DIRECTIONALITY DISTRIBUTION ===';
SELECT 
    Directionality,
    Indicator_Count = COUNT(*),
    Examples = STRING_AGG(Indicator_Code, ', ')
FROM dbo.esg_directionality
GROUP BY Directionality;

-- ESG Scores Summary
PRINT '=== ESG SCORES SUMMARY (Latest Year - 2025) ===';
SELECT TOP 20
    Country_Name,
    Year,
    E_Score,
    S_Score,
    G_Score,
    ESG_Score,
    ESG_Tier,
    E_Indicator_Count,
    S_Indicator_Count,
    G_Indicator_Count
FROM dbo.esg_scores_final
WHERE Year = 2025
ORDER BY ESG_Score DESC;

-- Global ESG Score Distribution
PRINT '=== ESG TIER DISTRIBUTION (2025) ===';
SELECT 
    ESG_Tier,
    Country_Count = COUNT(DISTINCT Country_Code),
    Avg_ESG_Score = ROUND(AVG(ESG_Score), 2),
    Min_ESG_Score = ROUND(MIN(ESG_Score), 2),
    Max_ESG_Score = ROUND(MAX(ESG_Score), 2)
FROM dbo.esg_scores_final
WHERE Year = 2025
GROUP BY ESG_Tier
ORDER BY 
    CASE WHEN ESG_Tier = 'High' THEN 1
         WHEN ESG_Tier = 'Medium' THEN 2
         ELSE 3 END;

GO