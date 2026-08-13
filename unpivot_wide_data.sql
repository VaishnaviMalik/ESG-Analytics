USE ESG_Project;
SELECT TOP 5 * FROM dbo.esg_wide_raw;

-- wide to long format
SELECT 
	Country_Name,
	Country_Code,
	Indicator_Name,
	Indicator_Code,
	CAST(REPLACE(REPLACE(Year, '[', ''), ']', '') AS INT) AS Year,
	CAST(Value AS FLOAT) AS Value
INTO
	esg_long_raw
FROM
	esg_wide_raw
UNPIVOT(
	Value FOR Year IN(
		"[1960]", "[1961]", "[1962]", "[1963]", "[1964]", "[1965]", "[1966]", "[1967]", "[1968]", "[1969]",
        "[1970]", "[1971]", "[1972]", "[1973]", "[1974]", "[1975]", "[1976]", "[1977]", "[1978]", "[1979]",
        "[1980]", "[1981]", "[1982]", "[1983]", "[1984]", "[1985]", "[1986]", "[1987]", "[1988]", "[1989]",
        "[1990]", "[1991]", "[1992]", "[1993]", "[1994]", "[1995]", "[1996]", "[1997]", "[1998]", "[1999]",
        "[2000]", "[2001]", "[2002]", "[2003]", "[2004]", "[2005]", "[2006]", "[2007]", "[2008]", "[2009]",
        "[2010]", "[2011]", "[2012]", "[2013]", "[2014]", "[2015]", "[2016]", "[2017]", "[2018]", "[2019]",
        "[2020]", "[2021]", "[2022]", "[2023]", "[2024]", "[2025]"
		)
) AS unpivoted_data
WHERE Value IS NOT NULL;

-- UNPIVOT Verification
SELECT 'Total rows in long format' AS check_name, COUNT(*) AS row_count FROM esg_long_raw;
SELECT MIN(Year) AS min_year, MAX(Year) AS max_year FROM esg_long_raw;
SELECT COUNT(DISTINCT(Country_Name)) AS country_count FROM esg_long_raw;
SELECT COUNT(DISTINCT(Indicator_Name)) AS indecator_Count FROM esg_long_raw;
SELECT MIN(Value) AS min_val,
	   MAX(Value) AS max_val,
	   AVG(Value) AS avg_val,
	   STDEV(Value) AS standard_deviation
FROM esg_long_raw;

-- check dataset
SELECT TOP 10 * FROM esg_long_raw ORDER BY Country_Name, Indicator_Code, Year;

-- Indexing
CREATE NONCLUSTERED INDEX idx_year ON esg_long_raw(Year);