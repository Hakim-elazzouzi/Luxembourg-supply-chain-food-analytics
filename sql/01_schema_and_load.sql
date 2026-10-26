CREATE DATABASE FoodSupplyChain;
GO
USE FoodSupplyChain;
GO

-----------------------------------------------------------------------------------------------------
-- 1. Creating the six tables --------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------

CREATE TABLE Dim_Country (
	CountryKey					INT PRIMARY KEY,
	CountryCode					NVARCHAR(10) NOT NULL,
	CountryName					NVARCHAR(50) NOT NULL,
	Role						NVARCHAR(30)
);
CREATE TABLE Dim_Date (
	DateKey						INT PRIMARY KEY,
	YearMonth					NVARCHAR(7),
	Year						INT,
	Month						INT,
	MonthName					NVARCHAR(15),
	Quarter						INT
);
CREATE TABLE Dim_ProductCategory (
	ProductKey					INT PRIMARY KEY,
	ProductGroup				NVARCHAR(50) NOT NULL
);
CREATE TABLE Fact_FoodPrice (
    FoodPriceKey				INT IDENTITY(1,1) PRIMARY KEY,
    DateKey						INT FOREIGN KEY REFERENCES Dim_Date(DateKey),
    CountryKey					INT FOREIGN KEY REFERENCES Dim_Country(CountryKey),
    ProductKey					INT FOREIGN KEY REFERENCES Dim_ProductCategory(ProductKey),
    IndexType					NVARCHAR(10),
    IndexValue					DECIMAL(10,2)
);
CREATE TABLE Fact_Trade (
    TradeKey					INT IDENTITY(1,1) PRIMARY KEY,
    DateKey						INT FOREIGN KEY REFERENCES Dim_Date(DateKey),
    ReporterCountryKey			INT FOREIGN KEY REFERENCES Dim_Country(CountryKey),
    PartnerCountryKey			INT FOREIGN KEY REFERENCES Dim_Country(CountryKey),
    ProductKey					INT FOREIGN KEY REFERENCES Dim_ProductCategory(ProductKey),
    FlowType					NVARCHAR(10),
    IndicatorType				NVARCHAR(20),
    TradeValue					DECIMAL(18,2)
);

-- Fact_Production: one row per country / item / year.
-- Milk and eggs stay separate rows (they share ProductKey 3 = Dairy & Eggs), so summing by
-- ProductKey adds them together once each. Eggs appear in FAOSTAT in two units (t and 1000 No)
-- for the same year: where tonnes exist we keep the tonnes row and ignore the count row;
-- where only the count exists we keep the count row and convert it with the country's own
-- average tonnes-per-1000-eggs ratio (calculated from the years where both units are reported).

CREATE TABLE Fact_Production (
    ProductionKey              INT IDENTITY(1,1) PRIMARY KEY,
    Year                       INT,
    CountryKey                 INT FOREIGN KEY REFERENCES Dim_Country(CountryKey),
    ProductKey                 INT FOREIGN KEY REFERENCES Dim_ProductCategory(ProductKey),
    Item                       NVARCHAR(100),
    ProductionUnit             NVARCHAR(10),     -- unit as reported by FAOSTAT: 't' or '1000 No'
    ProductionQuantity         DECIMAL(18,2),    -- value as reported, in its own unit
    ConversionFactorToTonnes   DECIMAL(8,5),     -- 1 for tonnes rows; tonnes per 1000 eggs for count rows
    ProductionTonnes           AS CAST(ProductionQuantity * ConversionFactorToTonnes AS DECIMAL(18,2)) PERSISTED,
    ProductionMethod           NVARCHAR(10)      -- 'Reported' or 'Converted'
);
GO

-----------------------------------------------------------------------------------------------------
-- 2. Filling the three dimension tables with a script ----------------------------------------------
-----------------------------------------------------------------------------------------------------
-- 2.1 Inserting Data Into Dim Tables:------------- 
-- Dim_Country (must match your Dim_Country.xlsx)

INSERT INTO Dim_Country (CountryKey, CountryCode, CountryName, Role) VALUES
(1, 'LU',	'Luxembourg',				  'Focus'),
(2, 'BE',	'Belgium',					  'Neighbor'),
(3, 'FR',	'France',					  'Neighbor'),
(4, 'DE',	'Germany',					  'Neighbor'),
(5, 'EU27',	'European Union average',	  'Reference'),
(6, 'WORLD','All countries of the world', 'Trade partner aggregate only');

-- Dim_ProductCategory (the ProductGroup spelling must match the fact files exactly)

INSERT INTO Dim_ProductCategory (ProductKey, ProductGroup) VALUES
(1,		'Meat'),
(2,		'Fish & Seafood'),
(3,		'Dairy & Eggs'),
(4,		'Oils & Fats'),
(5,		'Fruit & Nuts'),
(6,		'Vegetables'),
(7,		'Cereals'),
(8,		'Bread & Bakery'),
(9,		'Coffee & Tea'),
(10,	'All Food');

-- Dim_Date (one row per month, January 2005 to December 2026)

WITH Months AS (
	SELECT CAST('2005-01-01' AS DATE) AS MonthStart
	UNION ALL
	SELECT DATEADD(MONTH, 1, MonthStart)
	FROM Months
	WHERE MonthStart < '2026-12-01'
)
INSERT INTO Dim_Date (DateKey, YearMonth, Year, Month, MonthName, Quarter)
SELECT
	YEAR(MonthStart) * 100 + MONTH(MonthStart),
	FORMAT(MonthStart, 'yyyy-MM'),
	YEAR(MonthStart),
	MONTH(MonthStart),
	DATENAME(MONTH, MonthStart),
	DATEPART(QUARTER, MonthStart)
FROM Months
OPTION (MAXRECURSION 400);

-- 2.2 Checking Dim Tables Values

SELECT 'Dim_Country' AS TableName, COUNT(*) AS Rows FROM FoodSupplyChain.dbo.Dim_Country
UNION ALL SELECT 'Dim_ProductCategory', COUNT(*) FROM Dim_ProductCategory
UNION ALL SELECT 'Dim_Date', COUNT(*) FROM Dim_Date;

-----------------------------------------------------------------------------------------------------
-- 3. Importing the three Fact tables with a script and named Staging Tables-------------------------
-----------------------------------------------------------------------------------------------------

-- ONE-TIME FIX (run once, then never again): the import wizard left a trailing tab in the
-- staging table's name. This removes it so the table can be written as Staging_Production.
-- EXEC sp_rename 'dbo.[Staging_Production	]', 'Staging_Production';

-- Checking the imported Staging Tables 

SELECT 'Staging_FoodPrice' AS TableName, COUNT(*) AS Rows FROM FoodSupplyChain.dbo.Staging_FoodPrice
UNION ALL SELECT 'Staging_Trade', COUNT(*) FROM FoodSupplyChain.dbo.Staging_Trade
UNION ALL SELECT 'Staging_Production', COUNT(*) FROM FoodSupplyChain.dbo.Staging_Production;

-----------------------------------------------------------------------------------------------------
-- 4. Duplicate check on the staging tables ---------------------------------------------------------
-----------------------------------------------------------------------------------------------------
-- Duplicate Checking on the Staging_FoodPrice

SELECT CountryCode, coicop18, IndexType, DateKey, COUNT(*) AS Occurences
FROM FoodSupplyChain.dbo.Staging_FoodPrice
GROUP BY CountryCode, coicop18, IndexType, DateKey
HAVING COUNT (*) > 1;

-- Duplicate Checking on the Staging_Trade

SELECT ReporterCode, PartnerCode, product, FlowType, IndicatorType, DateKey,
	COUNT(*) AS Occurrences
FROM FoodSupplyChain.dbo.Staging_Trade
GROUP BY ReporterCode, PartnerCode, product, FlowType, IndicatorType, DateKey
HAVING COUNT(*) > 1;

-- Duplicate Checking on the Staging_Production

SELECT CountryCode, Item, Year, ProductionUnit, COUNT(*) AS Occurrences
FROM FoodSupplyChain.dbo.Staging_Production
GROUP BY CountryCode, Item, Year, ProductionUnit
HAVING COUNT(*) > 1;

-----------------------------------------------------------------------------------------------------
-- 5.  Loading the real fact tables from staging ----------------------------------------------------
-----------------------------------------------------------------------------------------------------
-- Joining The Staging_FoodPrice Into Fact_FoodPrice Table Using INNER JOIN

INSERT INTO FoodSupplyChain.dbo.Fact_FoodPrice (DateKey, CountryKey, ProductKey, IndexType, IndexValue)
SELECT d.Datekey, c.CountryKey, p.ProductKey, s.IndexType, s.IndexValue
FROM FoodSupplyChain.dbo.Staging_FoodPrice s
JOIN Dim_Date d				ON s.DateKey = d.DateKey
JOIN Dim_Country c			ON s.CountryCode = c.CountryCode
JOIN Dim_ProductCategory p	ON s.ProductGroup = p.ProductGroup;

-- Joining The Staging_Trade Into Fact_Trade Table Using INNER JOIN

INSERT INTO Fact_Trade (DateKey, ReporterCountryKey, PartnerCountryKey, ProductKey, FlowType, IndicatorType, TradeValue)
SELECT d.DateKey, rc.CountryKey, pc.CountryKey, p.ProductKey, s.FlowType, s.IndicatorType, s.TradeValue
FROM FoodSupplyChain.dbo.Staging_Trade s
JOIN Dim_Date d				ON s.DateKey = d.DateKey
JOIN Dim_Country rc			ON s.ReporterCode = rc.CountryCode
JOIN Dim_Country pc			ON s.PartnerCode = pc.CountryCode
JOIN Dim_ProductCategory p  ON s.ProductGroup = p.ProductGroup;

-- Loading Staging_Production into Fact_Production
--
-- Rule: keep every tonnes row. Keep a count row ('1000 No') ONLY when no tonnes row exists for
-- the same country / item / year (Belgium eggs 2018-2024, France eggs 2018-2023). Those count
-- rows are converted with the country's own average tonnes-per-1000-eggs ratio, taken from the
-- years where FAOSTAT reports both units for the same eggs (Belgium and France 2005-2017).
--
-- If you need to redo this load:  TRUNCATE TABLE Fact_Production;  then run the INSERT once.

TRUNCATE TABLE Fact_Production;

WITH EggFactor AS (
	SELECT
		c.CountryKey,
		AVG(t.ProductionQuantity / NULLIF(n.ProductionQuantity, 0)) AS Factor
	FROM FoodSupplyChain.dbo.Staging_Production t
	JOIN FoodSupplyChain.dbo.Staging_Production n
		ON  t.CountryCode = n.CountryCode
		AND t.Year        = n.Year
		AND t.Item        = n.Item
	JOIN Dim_Country c ON t.CountryCode = c.CountryCode
	WHERE t.Item LIKE 'Hen eggs%'
		AND t.ProductionUnit = 't'
		AND n.ProductionUnit = '1000 No'
	GROUP BY c.CountryKey
)
INSERT INTO Fact_Production
	(Year, CountryKey, ProductKey, Item, ProductionUnit, ProductionQuantity, ConversionFactorToTonnes, ProductionMethod)
SELECT
	s.Year,
	c.CountryKey,
	p.ProductKey,
	s.Item,
	s.ProductionUnit,
	s.ProductionQuantity,
	CASE WHEN s.ProductionUnit = 't' THEN 1.0 ELSE r.Factor END,
	CASE WHEN s.ProductionUnit = 't' THEN 'Reported' ELSE 'Converted' END
FROM FoodSupplyChain.dbo.Staging_Production s
JOIN Dim_Country c			ON s.CountryCode = c.CountryCode
JOIN Dim_ProductCategory p	ON s.ProductGroup = p.ProductGroup
LEFT JOIN EggFactor r		ON r.CountryKey = c.CountryKey
WHERE s.ProductionUnit = 't'
	OR NOT EXISTS (
		SELECT 1
		FROM FoodSupplyChain.dbo.Staging_Production t
		WHERE t.CountryCode    = s.CountryCode
			AND t.Item         = s.Item
			AND t.Year         = s.Year
			AND t.ProductionUnit = 't'
	);

-- Validating that no rows were lost
-- For Production, the expected count is NOT the raw 597: egg count rows that duplicate an
-- existing tonnes row are deliberately left out (597 - 66 = 531).

SELECT 'FoodPrice' AS TableName,
		(SELECT COUNT(*) FROM FoodSupplyChain.dbo.Staging_FoodPrice) AS StagingRows,
		(SELECT COUNT(*) FROM FoodSupplyChain.dbo.Fact_FoodPrice) AS FactRows
UNION ALL
SELECT 'Trade',
		(SELECT COUNT(*) FROM FoodSupplyChain.dbo.Staging_Trade),
		(SELECT COUNT(*) FROM FoodSupplyChain.dbo.Fact_Trade)
UNION ALL
SELECT 'Production (after dropping duplicate egg counts)',
		(SELECT COUNT(*) FROM FoodSupplyChain.dbo.Staging_Production s
		 WHERE s.ProductionUnit = 't'
			OR NOT EXISTS (SELECT 1 FROM FoodSupplyChain.dbo.Staging_Production t
						   WHERE t.CountryCode = s.CountryCode AND t.Item = s.Item
							 AND t.Year = s.Year AND t.ProductionUnit = 't')),
		(SELECT COUNT(*) FROM FoodSupplyChain.dbo.Fact_Production);

-- Checking the converted egg rows: expect 13 rows (Belgium 2018-2024, France 2018-2023)

SELECT c.CountryName, f.Year, f.Item, f.ProductionUnit, f.ProductionQuantity,
	f.ConversionFactorToTonnes, f.ProductionTonnes, f.ProductionMethod
FROM FoodSupplyChain.dbo.Fact_Production f
JOIN Dim_Country c ON f.CountryKey = c.CountryKey
WHERE f.ProductionMethod = 'Converted'
ORDER BY c.CountryName, f.Year;

-- Safety check: no row should be left without a tonnes value (expect 0 rows)

SELECT * FROM FoodSupplyChain.dbo.Fact_Production WHERE ProductionTonnes IS NULL;

-- Egg conversion ratio by country

-- (tonnes per 1000 eggs, from the years where both units are reported for the same eggs)

SELECT
	c.CountryName,
	COUNT(*) AS OverlapYears,
	CAST(AVG(t.ProductionQuantity / NULLIF(n.ProductionQuantity, 0)) AS DECIMAL(8,4)) AS AvgTonnesPer1000Eggs,
	CAST(AVG(t.ProductionQuantity / NULLIF(n.ProductionQuantity, 0)) * 1000 AS DECIMAL(6,1)) AS ImpliedEggWeightGrams
FROM FoodSupplyChain.dbo.Staging_Production t
JOIN FoodSupplyChain.dbo.Staging_Production n
	ON t.CountryCode = n.CountryCode AND t.Year = n.Year AND t.Item = n.Item
JOIN Dim_Country c ON t.CountryCode = c.CountryCode
WHERE t.Item LIKE 'Hen eggs%'
	AND t.ProductionUnit = 't'
	AND n.ProductionUnit = '1000 No'
GROUP BY c.CountryName
ORDER BY c.CountryName;

-- Browsing all tables

SELECT * FROM FoodSupplyChain.dbo.Dim_Country
SELECT * FROM FoodSupplyChain.dbo.Dim_Date
SELECT * FROM FoodSupplyChain.dbo.Dim_ProductCategory

SELECT * FROM FoodSupplyChain.dbo.Fact_FoodPrice
SELECT * FROM FoodSupplyChain.dbo.Fact_Production
SELECT * FROM FoodSupplyChain.dbo.Fact_Trade

SELECT * FROM FoodSupplyChain.dbo.Staging_FoodPrice
SELECT * FROM FoodSupplyChain.dbo.Staging_Production
SELECT * FROM FoodSupplyChain.dbo.Staging_Trade

