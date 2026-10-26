----------------------------------------------------------------------------------------------
-- Views for Power BI ---------------------------------------------------------------------
-- Each view mirrors a finalized business-question query from 02_business_questions.sql,
-- with ORDER BY removed (views ignore it without TOP/OFFSET -- sort in Power BI/consumer instead).
-- 8 views total: vw_SelfSufficiency, vw_ImportsByPartnerCategory, vw_ImportsByPartnerYear,
-- vw_ExportsByPartnerCategory, vw_ExportsByPartnerYear, vw_PriceTrend, vw_NetTradeBalance,
-- vw_PriceTransmission.
----------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------

--vw_SelfSufficiency

CREATE OR ALTER VIEW vw_SelfSufficiency AS
WITH TradeYearly AS (
	SELECT
		t.ReporterCountryKey AS CountryKey,
		t.ProductKey,
		d.Year,
		SUM(CASE WHEN t.FlowType = 'IMPORT' THEN t.TradeValue ELSE 0 END) / 10.0 AS ImportTonnes,
		SUM(CASE WHEN t.FlowType = 'EXPORT' THEN t.TradeValue ELSE 0 END) / 10.0 AS ExportTonnes
	FROM FoodSupplyChain.dbo.Fact_Trade t
	JOIN Dim_Date d ON t.DateKey = d.DateKey
	JOIN Dim_Country w ON t.PartnerCountryKey = w.CountryKey
	WHERE t.IndicatorType = 'QUANTITY_IN_100KG'
		AND w.CountryCode = 'WORLD'
	GROUP BY t.ReporterCountryKey, t.ProductKey, d.Year
),
ProductionYearly AS (
	SELECT
		CountryKey,
		ProductKey,
		Year,
		SUM(ProductionTonnes) AS ProductionTonnes
	FROM FoodSupplyChain.dbo.Fact_Production
	GROUP BY CountryKey, ProductKey, Year
)
SELECT
	c.CountryName,
	p.ProductGroup,
	ty.Year,

	-- Clean presentation layout using DECIMAL
	CAST(CASE 
		WHEN p.ProductGroup IN ('Fish & Seafood', 'Bread & Bakery', 'Coffee & Tea', 'All Food') 
			 AND py.ProductionTonnes IS NULL THEN 0.0
		ELSE py.ProductionTonnes -- Keeps true NULL for Oils & Fats 2018-2024
	END AS DECIMAL(18,2)) AS ProductionTonnes,

	CAST(ty.ImportTonnes AS DECIMAL(18,2)) AS ImportTonnes,
	CAST(ty.ExportTonnes AS DECIMAL(18,2)) AS ExportTonnes,
	
	-- Self Sufficiency Percentage formatting using DECIMAL
	CAST(CASE
		-- 1. Structural dependencies always yield 0.0 when domestic production is entirely missing
		WHEN p.ProductGroup IN ('Fish & Seafood', 'Bread & Bakery', 'Coffee & Tea', 'All Food') 
			 AND py.ProductionTonnes IS NULL THEN 0.0
			 
		-- 2. Data gaps (like Oils & Fats 2018+) return true NULL
		WHEN py.ProductionTonnes IS NULL THEN NULL
		
		-- 3. Safe standard math calculation
		ELSE 100.0 * py.ProductionTonnes /
			NULLIF(py.ProductionTonnes + ISNULL(ty.ImportTonnes, 0) - ISNULL(ty.ExportTonnes, 0), 0)
	END AS DECIMAL(10,2)) AS SelfSufficiencyPct

FROM TradeYearly ty
JOIN Dim_Country c ON ty.CountryKey = c.CountryKey
JOIN Dim_ProductCategory p ON ty.ProductKey = p.ProductKey
LEFT JOIN ProductionYearly py
	ON py.CountryKey = ty.CountryKey
	AND py.ProductKey = ty.ProductKey
	AND py.Year = ty.Year
WHERE ty.Year <= 2024
GO

-- vw_ImportsByPartnerCategory

CREATE OR ALTER VIEW vw_ImportsByPartnerCategory AS
SELECT
	reporter.CountryName AS ReporterCountry,
	partner.CountryName  AS PartnerCountry,
	p.ProductGroup,
	d.Year,
	SUM(t.TradeValue) AS TotalImportValueEUR
FROM FoodSupplyChain.dbo.Fact_Trade t
JOIN Dim_Country reporter  ON t.ReporterCountryKey = reporter.CountryKey
JOIN Dim_Country partner   ON t.PartnerCountryKey = partner.CountryKey
JOIN Dim_ProductCategory p ON t.ProductKey = p.ProductKey
JOIN Dim_Date d             ON t.DateKey = d.DateKey
WHERE reporter.CountryCode = 'LU'
	AND t.FlowType = 'IMPORT'
	AND t.IndicatorType = 'VALUE_IN_EUROS'
	AND partner.CountryCode <> 'WORLD'
GROUP BY reporter.CountryName, partner.CountryName, p.ProductGroup, d.Year;
GO

--vw_ImportsByPartnerYear

CREATE OR ALTER VIEW vw_ImportsByPartnerYear AS
SELECT
    reporter.CountryName AS ReporterCountry,
    partner.CountryName  AS PartnerCountry,
    d.Year,
    SUM(t.TradeValue) AS TotalImportValueEUR
FROM FoodSupplyChain.dbo.Fact_Trade t
JOIN Dim_Country reporter ON t.ReporterCountryKey = reporter.CountryKey
JOIN Dim_Country partner  ON t.PartnerCountryKey = partner.CountryKey
JOIN Dim_Date d           ON t.DateKey = d.DateKey
WHERE reporter.CountryCode = 'LU'
    AND t.FlowType = 'IMPORT'
    AND t.IndicatorType = 'VALUE_IN_EUROS'
    AND partner.CountryCode <> 'WORLD'
GROUP BY reporter.CountryName, partner.CountryName, d.Year;
GO

-- vw_ExportsByPartnerCategory

CREATE OR ALTER VIEW vw_ExportsByPartnerCategory AS
SELECT
	reporter.CountryName AS ReporterCountry,
	partner.CountryName  AS PartnerCountry,
	p.ProductGroup,
	d.Year,
	SUM(t.TradeValue) AS TotalExportValueEUR
FROM FoodSupplyChain.dbo.Fact_Trade t
JOIN Dim_Country reporter  ON t.ReporterCountryKey = reporter.CountryKey
JOIN Dim_Country partner   ON t.PartnerCountryKey = partner.CountryKey
JOIN Dim_ProductCategory p ON t.ProductKey = p.ProductKey
JOIN Dim_Date d             ON t.DateKey = d.DateKey
WHERE reporter.CountryCode = 'LU'
	AND t.FlowType = 'EXPORT'
	AND t.IndicatorType = 'VALUE_IN_EUROS'
	AND partner.CountryCode <> 'WORLD'
GROUP BY reporter.CountryName, partner.CountryName, p.ProductGroup, d.Year;
GO

--vw_ExportsByPartnerYear

CREATE OR ALTER VIEW vw_ExportsByPartnerYear AS
SELECT
    reporter.CountryName AS ReporterCountry,
    partner.CountryName  AS PartnerCountry,
    d.Year,
    SUM(t.TradeValue) AS TotalExportValueEUR
FROM FoodSupplyChain.dbo.Fact_Trade t
JOIN Dim_Country reporter ON t.ReporterCountryKey = reporter.CountryKey
JOIN Dim_Country partner  ON t.PartnerCountryKey = partner.CountryKey
JOIN Dim_Date d           ON t.DateKey = d.DateKey
WHERE reporter.CountryCode = 'LU'
    AND t.FlowType = 'EXPORT'
    AND t.IndicatorType = 'VALUE_IN_EUROS'
    AND partner.CountryCode <> 'WORLD'
GROUP BY reporter.CountryName, partner.CountryName, d.Year;
GO

--vw_PriceTrend

CREATE OR ALTER VIEW vw_PriceTrend AS
SELECT
	c.CountryName,
	p.ProductGroup,
	d.Year,
	fp.IndexType,
	CAST(ROUND(AVG(fp.IndexValue), 2) AS DECIMAL(10,2)) AS AvgPriceIndex
FROM FoodSupplyChain.dbo.Fact_FoodPrice fp
JOIN Dim_Country c			ON fp.CountryKey = c.CountryKey
JOIN Dim_ProductCategory p	ON fp.ProductKey = p.ProductKey
JOIN Dim_Date d				ON fp.DateKey = d.DateKey
GROUP BY c.CountryName, p.ProductGroup, d.Year, fp.IndexType;
GO

-- vw_NetTradeBalance

CREATE OR ALTER VIEW vw_NetTradeBalance AS
SELECT
	reporter.CountryName AS ReporterCountry,
	p.ProductGroup,
	d.Year,
	SUM(CASE WHEN t.FlowType = 'IMPORT' THEN t.TradeValue ELSE 0 END) AS TotalImportsEUR,
	SUM(CASE WHEN t.FlowType = 'EXPORT' THEN t.TradeValue ELSE 0 END) AS TotalExportsEUR,
	SUM(CASE WHEN t.FlowType = 'IMPORT' THEN t.TradeValue ELSE 0 END)
	- SUM(CASE WHEN t.FlowType = 'EXPORT' THEN t.TradeValue ELSE 0 END) AS NetTradeBalanceEUR
FROM FoodSupplyChain.dbo.Fact_Trade t
JOIN Dim_Country reporter		ON t.ReporterCountryKey = reporter.CountryKey
JOIN Dim_Country partner		ON t.PartnerCountryKey = partner.CountryKey
JOIN Dim_ProductCategory p	ON t.ProductKey = p.ProductKey
JOIN Dim_Date d				ON t.DateKey = d.DateKey
WHERE t.IndicatorType = 'VALUE_IN_EUROS'
	AND partner.CountryCode = 'WORLD'
GROUP BY reporter.CountryName, p.ProductGroup, d.Year
GO

-- vw_PriceTransmission

CREATE OR ALTER VIEW vw_PriceTransmission AS
WITH Yearly AS (
	SELECT
		c.CountryName,
		p.ProductGroup,
		d.Year,
		CAST(AVG(CASE WHEN fp.IndexType = 'IPI'  THEN fp.IndexValue END) AS DECIMAL(10,3)) AS ImportIdx,
		CAST(AVG(CASE WHEN fp.IndexType = 'HICP' THEN fp.IndexValue END) AS DECIMAL(10,3)) AS ConsumerIdx
	FROM FoodSupplyChain.dbo.Fact_FoodPrice fp
	JOIN Dim_Country c			ON fp.CountryKey = c.CountryKey
	JOIN Dim_ProductCategory p	ON fp.ProductKey = p.ProductKey
	JOIN Dim_Date d				ON fp.DateKey = d.DateKey
	WHERE fp.IndexType IN ('IPI', 'HICP')
	GROUP BY c.CountryName, p.ProductGroup, d.Year
)
SELECT
	CountryName,
	ProductGroup,
	Year,
	ImportIdx,
	ConsumerIdx,
	CAST(100.0 * (ImportIdx   / NULLIF(LAG(ImportIdx)   OVER (PARTITION BY CountryName, ProductGroup ORDER BY Year), 0) - 1) AS DECIMAL(10,2)) AS ImportPriceChangePct,
	CAST(100.0 * (ConsumerIdx / NULLIF(LAG(ConsumerIdx) OVER (PARTITION BY CountryName, ProductGroup ORDER BY Year), 0) - 1) AS DECIMAL(10,2)) AS ConsumerPriceChangePct
FROM Yearly
WHERE ImportIdx IS NOT NULL AND ConsumerIdx IS NOT NULL
	AND CountryName <> 'European Union average'
	AND Year <= 2025
GO