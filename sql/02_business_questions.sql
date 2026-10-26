----------------------------------------------------------------------------------------------
-- Business Questions ------------------------------------------------------------------------
----------------------------------------------------------------------------------------------
-- 8 queries total, answering the project's core question: how dependent is Luxembourg on
-- food imports from its neighbors, and does that dependency show up in higher prices?
--   1.   Self-sufficiency ratio by country, category, and year
--   2.1  Where Luxembourg imports from, by partner + category + year
--   2.2  Where Luxembourg imports from, by partner + year (total)
--   3.1  Where Luxembourg exports to, by partner + category + year
--   3.2  Where Luxembourg exports to, by partner + year (total)
--   4.   Price trend by country and category -- the price side of the core question
--   5.   Net trade balance (imports - exports) by country, category, and year
--   6.   Price transmission: import price index vs. consumer price index
----------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------
-- =====================================================================================
-- 1. Self-sufficiency ratio by country, category, and year

--    Formula: Self-sufficiency % = Production / (Production + Imports - Exports)

--    This approximates "apparent consumption" and shows how much of what's consumed
--    was actually produced locally vs. brought in from abroad.
--
--    NOTE ON EGGS: FAOSTAT reports hen eggs in two units for the same year, tonnes (t) and
--    thousands of eggs (1000 No). Fact_Production already resolves this at load time: where
--    tonnes exist they are used and the count row is ignored; where only the count exists
--    (Belgium 2018-2024, France 2018-2023) it was converted to tonnes with that country's own
--    average tonnes-per-1000-eggs ratio (derived from the years where both units are reported).
--    Milk and eggs are separate rows sharing ProductKey 3 (Dairy & Eggs), so summing by
--    ProductKey adds them once each. ProductionTonnes is therefore used as-is below.
--    Known gap: France has no egg data at all for 2024, so its 2024 Dairy & Eggs is milk only.
-- =====================================================================================

-- Step 1: collapse Fact_Trade's monthly rows into yearly totals per country/product.

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

-- Step 2: total production per country/product/year.
ProductionYearly AS (
	SELECT
		CountryKey,
		ProductKey,
		Year,
		SUM(ProductionTonnes) AS ProductionTonnes
	FROM FoodSupplyChain.dbo.Fact_Production
	GROUP BY CountryKey, ProductKey, Year
)

-- Step 3: join trade and production together and compute one unified self-sufficiency ratio.
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
ORDER BY c.CountryName, p.ProductGroup, ty.Year;

-- 2.1 Where does Luxembourg actually import from:

SELECT
	reporter.CountryName			AS ReporterCountry,
	partner.CountryName				AS PartnerCountry,
	p.ProductGroup,
	d.Year,
	SUM(t.TradeValue)				AS TotalImportValueEUR
FROM FoodSupplyChain.dbo.Fact_Trade t
JOIN Dim_Country reporter			ON t.ReporterCountryKey = reporter.CountryKey
JOIN Dim_Country partner			ON t.PartnerCountryKey = partner.CountryKey
JOIN Dim_ProductCategory p			ON t.ProductKey = p.ProductKey
JOIN Dim_Date d						ON t.DateKey = d.DateKey
WHERE reporter.CountryCode = 'LU'
	AND t.FlowType = 'IMPORT'
	AND t.IndicatorType = 'VALUE_IN_EUROS'
	AND partner.CountryCode <> 'WORLD'
GROUP BY reporter.CountryName, partner.CountryName, p.ProductGroup, d.Year
ORDER BY d.Year DESC, PartnerCountry, TotalImportValueEUR;

-- 2.2 Total imports by partner country, by year (no category breakdown):

SELECT
    reporter.CountryName AS ReporterCountry,
    partner.CountryName  AS PartnerCountry,
    d.Year,
    SUM(t.TradeValue) AS TotalImportValueEUR
FROM FoodSupplyChain.dbo.Fact_Trade t
JOIN Dim_Country reporter       ON t.ReporterCountryKey = reporter.CountryKey
JOIN Dim_Country partner        ON t.PartnerCountryKey = partner.CountryKey
JOIN Dim_Date d                 ON t.DateKey = d.DateKey
WHERE reporter.CountryCode = 'LU'
    AND t.FlowType = 'IMPORT'
    AND t.IndicatorType = 'VALUE_IN_EUROS'
    AND partner.CountryCode <> 'WORLD'
GROUP BY reporter.CountryName, partner.CountryName, d.Year
ORDER BY d.Year, TotalImportValueEUR DESC;

-- 3.1 Where does Luxembourg actually export to:

SELECT
	reporter.CountryName			AS ReporterCountry,
	partner.CountryName				AS PartnerCountry,
	p.ProductGroup,
	d.Year,
	SUM(t.TradeValue)				AS TotalExportValueEUR
FROM FoodSupplyChain.dbo.Fact_Trade t
JOIN Dim_Country reporter			ON t.ReporterCountryKey = reporter.CountryKey
JOIN Dim_Country partner			ON t.PartnerCountryKey = partner.CountryKey
JOIN Dim_ProductCategory p			ON t.ProductKey = p.ProductKey
JOIN Dim_Date d						ON t.DateKey = d.DateKey
WHERE reporter.CountryCode = 'LU'
	AND t.FlowType = 'EXPORT'
	AND t.IndicatorType = 'VALUE_IN_EUROS'
	AND partner.CountryCode <> 'WORLD'
GROUP BY reporter.CountryName, partner.CountryName, p.ProductGroup, d.Year
ORDER BY d.Year DESC, PartnerCountry, TotalExportValueEUR;

-- 3.2 Total exports by partner country, by year (no category breakdown):

SELECT
    reporter.CountryName AS ReporterCountry,
    partner.CountryName  AS PartnerCountry,
    d.Year,
    SUM(t.TradeValue) AS TotalExportValueEUR
FROM FoodSupplyChain.dbo.Fact_Trade t
JOIN Dim_Country reporter       ON t.ReporterCountryKey = reporter.CountryKey
JOIN Dim_Country partner        ON t.PartnerCountryKey = partner.CountryKey
JOIN Dim_Date d                 ON t.DateKey = d.DateKey
WHERE reporter.CountryCode = 'LU'
    AND t.FlowType = 'EXPORT'
    AND t.IndicatorType = 'VALUE_IN_EUROS'
    AND partner.CountryCode <> 'WORLD'
GROUP BY reporter.CountryName, partner.CountryName, d.Year
ORDER BY d.Year, TotalExportValueEUR DESC;

-- 4. Price trend by country and category

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
GROUP BY c.CountryName, p.ProductGroup, d.Year, fp.IndexType
ORDER BY c.CountryName, p.ProductGroup, d.Year;

-- 5. Net trade balance (imports - exports) by country, category, and year

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
ORDER BY reporter.CountryName, p.ProductGroup, d.Year;


-- 6. Price transmission: import price index vs. consumer price index

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
ORDER BY CountryName, ProductGroup, Year;
