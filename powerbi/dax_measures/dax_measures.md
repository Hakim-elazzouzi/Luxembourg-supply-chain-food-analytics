# DAX measures

All measures of the Power BI report, exported from the final model.

**Conventions**

- Trade partner key `6` is `WORLD`, the total over all partners. Using it avoids double counting.
- Trade quantities are in 100 kg, so tonnes = value / 10.
- Price indices are 2025 = 100 for every country: the report compares growth, never price levels.
- `Fact_Trade[ReporterCountryKey]` is the active relationship; the partner relationship is inactive and is switched on with `USERELATIONSHIP` in the partner measures.

## Calculated table and columns

```dax
-- Calculated table
Dim_Year = DISTINCT ( Dim_Date[Year] )
```

```dax
-- Calculated column on Dim_Country
Country Color =
SWITCH (
    Dim_Country[CountryCode],
    "LU", "#1D9E75",
    "BE", "#BA7517",
    "FR", "#378ADD",
    "DE", "#D85A30",
    "EU27", "#888780",
    "#CCCCCC"
)
```

```dax
-- Calculated column on Dim_ProductCategory
Category Color =
SWITCH (
    Dim_ProductCategory[ProductGroup],
    "Meat",           "#534AB7",
    "Fish & Seafood", "#0F6E56",
    "Dairy & Eggs",   "#7CCBB0",
    "Oils & Fats",    "#D4537E",
    "Fruit & Nuts",   "#7F77DD",
    "Vegetables",     "#A3C95A",
    "Cereals",        "#5F5E5A",
    "Bread & Bakery", "#B4B2A9",
    "Coffee & Tea",   "#0F3D33",
    "#C8D3CF"
)
```

## 1. Production

```dax
Total Production (Tonnes) =
SUM(Fact_Production[ProductionTonnes])
```

```dax
Converted Production (Tonnes) =
CALCULATE ( [Total Production (Tonnes)], Fact_Production[ProductionMethod] = "Converted" )
```

```dax
Production Tonnes (SQL style) =
VAR _g = SELECTEDVALUE ( Dim_ProductCategory[ProductGroup] )
RETURN
    IF (
        _g IN { "Fish & Seafood", "Bread & Bakery", "Coffee & Tea" }
            && ISBLANK ( [Total Production (Tonnes)] ),
        0,
        [Total Production (Tonnes)]
    )
```

## 2. Trade in tonnes

```dax
Import Tonnes =
DIVIDE (
    CALCULATE (
        SUM ( Fact_Trade[TradeValue] ),
        Fact_Trade[FlowType] = "IMPORT",
        Fact_Trade[IndicatorType] = "QUANTITY_IN_100KG",
        Fact_Trade[PartnerCountryKey] = 6
    ),
10
)
```

```dax
Export Tonnes =
DIVIDE (
    CALCULATE (
        SUM ( Fact_Trade[TradeValue] ),
        Fact_Trade[FlowType] = "EXPORT",
        Fact_Trade[IndicatorType] = "QUANTITY_IN_100KG",
        Fact_Trade[PartnerCountryKey] = 6
    ),
    10
)
```

## 3. Trade in euros and net balance

```dax
Total Imports (EUR) =
CALCULATE(
    SUM(Fact_Trade[TradeValue]),
    Fact_Trade[FlowType] = "IMPORT",
    Fact_Trade[IndicatorType] = "VALUE_IN_EUROS",
    Fact_Trade[PartnerCountryKey] = 6
)
```

```dax
Total Exports (EUR) =
CALCULATE(
    SUM(Fact_Trade[TradeValue]),
    Fact_Trade[FlowType] = "EXPORT",
    Fact_Trade[IndicatorType] = "VALUE_IN_EUROS",
    Fact_Trade[PartnerCountryKey] = 6
)
```

```dax
Net Trade Balance (EUR) =
[Total Imports (EUR)] - [Total Exports (EUR)]
```

```dax
Net Position =
IF (
    [Net Trade Balance (EUR)] > 0, "Net importer",
    IF ( [Net Trade Balance (EUR)] < 0, "Net exporter" )
)
```

```dax
Total Imports YoY % =
VAR _Y = SELECTEDVALUE ( Dim_Year[Year] )
VAR _Cur = [Total Imports (EUR)]
VAR _Prev = CALCULATE ( [Total Imports (EUR)], Dim_Year[Year] = _Y - 1 )
RETURN IF ( NOT ISBLANK ( _Y ), DIVIDE ( _Cur - _Prev, _Prev ) * 100 )
```

## 4. Luxembourg's trade partners

```dax
LU Imports by Partner (EUR) =
CALCULATE (
    SUM ( Fact_Trade[TradeValue] ),
    Fact_Trade[FlowType] = "IMPORT",
    Fact_Trade[IndicatorType] = "VALUE_IN_EUROS",
    Fact_Trade[ReporterCountryKey] = 1,
    Dim_Country[CountryCode] <> "WORLD",
    USERELATIONSHIP ( Fact_Trade[PartnerCountryKey], Dim_Country[CountryKey] )
)
```

```dax
LU Exports by Partner (EUR) =
CALCULATE (
    SUM ( Fact_Trade[TradeValue] ),
    Fact_Trade[FlowType] = "EXPORT",
    Fact_Trade[IndicatorType] = "VALUE_IN_EUROS",
    Fact_Trade[ReporterCountryKey] = 1,
    Dim_Country[CountryCode] <> "WORLD",
    USERELATIONSHIP ( Fact_Trade[PartnerCountryKey], Dim_Country[CountryKey] )
)
```

```dax
LU Import Share by Partner % =
DIVIDE (
    [LU Imports by Partner (EUR)],
    CALCULATE ( [LU Imports by Partner (EUR)], REMOVEFILTERS ( Dim_Country ) )
) * 100
```

```dax
LU Imports from Neighbours Share % =
DIVIDE (
    [LU Imports by Partner (EUR)],
    CALCULATE ( [Total Imports (EUR)], Dim_Country[CountryCode] = "LU" )
) * 100
```

```dax
Top Partner =
VAR _t = ADDCOLUMNS ( VALUES ( Dim_Country[CountryName] ), "Val", [LU Imports by Partner (EUR)] )
RETURN CONCATENATEX (
    TOPN ( 1, FILTER ( _t, NOT ISBLANK ( [Val] ) ), [Val], DESC ),
    Dim_Country[CountryName], ", " )
```

```dax
Top Partner Share % =
VAR _t = ADDCOLUMNS ( VALUES ( Dim_Country[CountryName] ), "Val", [LU Imports by Partner (EUR)] )
RETURN DIVIDE ( MAXX ( _t, [Val] ), SUMX ( _t, [Val] ) ) * 100
```

## 5. Self-sufficiency

```dax
Self-Sufficiency % (no year limit) =
VAR _Group = SELECTEDVALUE ( Dim_ProductCategory[ProductGroup] )
VAR _NoProduction = _Group IN { "Fish & Seafood", "Bread & Bakery", "Coffee & Tea" }
VAR _Production = IF ( _NoProduction, 0, [Total Production (Tonnes)] )
VAR _Imports = [Import Tonnes]
VAR _Exports = [Export Tonnes]
RETURN
    IF (
        ISBLANK ( _Group ) || ISBLANK ( _Production ),
        BLANK (),
        DIVIDE ( _Production, _Production + _Imports - _Exports ) * 100
    )
```

```dax
Self-Sufficiency % =
CALCULATE (
    [Self-Sufficiency % (no year limit)],
    KEEPFILTERS ( Dim_Year[Year] <= 2024 )
)
```

```dax
Self-Sufficiency % (KPI) =
VAR _Y = MIN ( MAX ( Dim_Year[Year] ), 2024 )
RETURN
    CALCULATE (
        [Self-Sufficiency % (no year limit)],
        REMOVEFILTERS ( Dim_Year ),
        Dim_Year[Year] = _Y
    )
```

## 6. Prices

```dax
Consumer Price Index (HICP) =
CALCULATE ( AVERAGE ( Fact_FoodPrice[IndexValue] ), Fact_FoodPrice[IndexType] = "HICP" )
```

```dax
Import Price Index (IPI) =
CALCULATE ( AVERAGE ( Fact_FoodPrice[IndexValue] ), Fact_FoodPrice[IndexType] = "IPI" )
```

```dax
Consumer Price Change Since 2005 % =
VAR _Base = CALCULATE ( [Consumer Price Index (HICP)], Dim_Year[Year] = 2005 )
RETURN
    DIVIDE ( [Consumer Price Index (HICP)] - _Base, _Base ) * 100
```

```dax
Price Change Gap vs EU (pp) =
[Consumer Price Change Since 2005 %]
    - CALCULATE (
        [Consumer Price Change Since 2005 %],
        REMOVEFILTERS ( Dim_Country ),
        Dim_Country[CountryCode] = "EU27"
    )
```

## 7. Year-over-year change

```dax
Consumer Price Change YoY % =
VAR _Year = SELECTEDVALUE ( Dim_Year[Year] )
VAR _Current = [Consumer Price Index (HICP)]
VAR _Previous = CALCULATE ( [Consumer Price Index (HICP)], Dim_Year[Year] = _Year - 1 )
RETURN
    IF ( NOT ISBLANK ( _Year ), DIVIDE ( _Current - _Previous, _Previous ) * 100 )
```

```dax
Import Price Change YoY % =
VAR _Year = SELECTEDVALUE ( Dim_Year[Year] )
VAR _Current = [Import Price Index (IPI)]
VAR _Previous = CALCULATE ( [Import Price Index (IPI)], Dim_Year[Year] = _Year - 1 )
RETURN
    IF ( NOT ISBLANK ( _Year ), DIVIDE ( _Current - _Previous, _Previous ) * 100 )
```

## 8. Price pass-through (page 4)

```dax
Pass-through Slope =
VAR _t =
    FILTER (
        ADDCOLUMNS (
            SUMMARIZE ( Fact_FoodPrice, Dim_Country[CountryName],
                        Dim_ProductCategory[ProductGroup], Dim_Year[Year] ),
            "X", [Import Price Change YoY %],
            "Y", [Consumer Price Change YoY %]
        ),
        Dim_Country[CountryName] IN { "Luxembourg", "Belgium", "France", "Germany" }
            && Dim_ProductCategory[ProductGroup] <> "All Food"
            && Dim_Year[Year] <= 2025
            && NOT ISBLANK ( [X] ) && NOT ISBLANK ( [Y] )
    )
VAR _n = COUNTROWS ( _t )
VAR _sx = SUMX ( _t, [X] )
VAR _sy = SUMX ( _t, [Y] )
VAR _sxy = SUMX ( _t, [X] * [Y] )
VAR _sxx = SUMX ( _t, [X] ^ 2 )
RETURN DIVIDE ( _n * _sxy - _sx * _sy, _n * _sxx - _sx ^ 2 )
```

```dax
Import-Consumer Correlation =
VAR _t =
    FILTER (
        ADDCOLUMNS (
            SUMMARIZE ( Fact_FoodPrice, Dim_Country[CountryName],
                        Dim_ProductCategory[ProductGroup], Dim_Year[Year] ),
            "X", [Import Price Change YoY %],
            "Y", [Consumer Price Change YoY %]
        ),
        Dim_Country[CountryName] IN { "Luxembourg", "Belgium", "France", "Germany" }
            && Dim_ProductCategory[ProductGroup] <> "All Food"
            && Dim_Year[Year] <= 2025
            && NOT ISBLANK ( [X] ) && NOT ISBLANK ( [Y] )
    )
VAR _n   = COUNTROWS ( _t )
VAR _sx  = SUMX ( _t, [X] )
VAR _sy  = SUMX ( _t, [Y] )
VAR _sxy = SUMX ( _t, [X] * [Y] )
VAR _sxx = SUMX ( _t, [X] ^ 2 )
VAR _syy = SUMX ( _t, [Y] ^ 2 )
RETURN
    DIVIDE (
        _n * _sxy - _sx * _sy,
        SQRT ( ( _n * _sxx - _sx ^ 2 ) * ( _n * _syy - _sy ^ 2 ) )
    )
```

```dax
Price Observations (n) =
VAR _t =
    FILTER (
        ADDCOLUMNS (
            SUMMARIZE ( Fact_FoodPrice, Dim_Country[CountryName],
                        Dim_ProductCategory[ProductGroup], Dim_Year[Year] ),
            "X", [Import Price Change YoY %],
            "Y", [Consumer Price Change YoY %]
        ),
        Dim_Country[CountryName] IN { "Luxembourg", "Belgium", "France", "Germany" }
            && Dim_ProductCategory[ProductGroup] <> "All Food"
            && Dim_Year[Year] <= 2025
            && NOT ISBLANK ( [X] ) && NOT ISBLANK ( [Y] )
    )
RETURN
    COUNTROWS ( _t )
```

## 9. Data coverage

```dax
Trade Months Available =
CALCULATE ( DISTINCTCOUNT ( Fact_Trade[DateKey] ), Fact_Trade[PartnerCountryKey] = 6 )
```

```dax
Year Coverage =
IF (
    ISBLANK ( [Trade Months Available] ), BLANK (),
    IF ( [Trade Months Available] < 12,
        "Partial year (" & [Trade Months Available] & " months)", "Full year" )
)
```

```dax
Trade First Month =
VAR _k = CALCULATE ( MIN ( Fact_Trade[DateKey] ), REMOVEFILTERS () )
RETURN LEFT ( _k, 4 ) & "-" & RIGHT ( _k, 2 )
```

```dax
Trade Last Month =
VAR _k = CALCULATE ( MAX ( Fact_Trade[DateKey] ), REMOVEFILTERS () )
RETURN LEFT ( _k, 4 ) & "-" & RIGHT ( _k, 2 )
```

```dax
Price Last Month =
VAR _k = CALCULATE ( MAX ( Fact_FoodPrice[DateKey] ), REMOVEFILTERS () )
RETURN LEFT ( _k, 4 ) & "-" & RIGHT ( _k, 2 )
```

```dax
Production Last Year =
CALCULATE ( MAX ( Fact_Production[Year] ), REMOVEFILTERS () )
```

## 10. KPI labels and colours

```dax
Label Self-Sufficiency Year =
IF ( MAX ( Dim_Year[Year] ) > 2024,
    "Latest data year: 2024",
    "Data year: " & MAX ( Dim_Year[Year] ) )
```

```dax
Label Price YoY =
VAR _v = CALCULATE ( [Consumer Price Change YoY %],
        Dim_Country[CountryCode] = "LU", Dim_ProductCategory[ProductGroup] = "All Food" )
RETURN IF ( ISBLANK ( _v ), "no previous year",
            IF ( _v >= 0, "▲ ", "▼ " ) & FORMAT ( ABS ( _v ), "0.0" ) & "% vs previous year" )
```

```dax
Label Gap vs EU =
VAR _g = CALCULATE ( [Price Change Gap vs EU (pp)],
        Dim_Country[CountryCode] = "LU", Dim_ProductCategory[ProductGroup] = "All Food" )
RETURN IF ( ISBLANK ( _g ), "no data",
            IF ( _g >= 0, "▲ rose more than EU-27", "▼ rose less than EU-27" ) )
```

```dax
Label Imports YoY =
VAR _v = CALCULATE ( [Total Imports YoY %], Dim_Country[CountryCode] = "LU" )
RETURN IF ( ISBLANK ( _v ), "no previous year",
            IF ( _v >= 0, "▲ ", "▼ " ) & FORMAT ( ABS ( _v ), "0.0" ) & "% vs previous year" )
```

```dax
Color Gap vs EU =
IF ( [Price Change Gap vs EU (pp)] > 0, "#D85A30", "#1D9E75" )
```

```dax
Color Net Position =
IF ( [Net Trade Balance (EUR)] > 0, "#BA7517", "#1D9E75" )
```

## 11. Insight sentences

```dax
Insight Prices =
VAR _Y = SELECTEDVALUE ( Dim_Year[Year], 2025 )
VAR _Chg = CALCULATE ( [Consumer Price Change Since 2005 %],
            Dim_Country[CountryCode] = "LU", Dim_ProductCategory[ProductGroup] = "All Food" )
VAR _Gap = CALCULATE ( [Price Change Gap vs EU (pp)],
            Dim_Country[CountryCode] = "LU", Dim_ProductCategory[ProductGroup] = "All Food" )
RETURN "Luxembourg food prices rose " & FORMAT ( _Chg, "0" ) & "% between 2005 and " & _Y
        & ", " & FORMAT ( ABS ( _Gap ), "0.0" ) & " pp " & IF ( _Gap >= 0, "more", "less" )
        & " than the EU-27 average."
```

```dax
Insight Partners =
IF ( ISBLANK ( [Top Partner Share %] ), BLANK (),
    [Top Partner] & " supplies " & FORMAT ( [Top Partner Share %], "0" )
    & "% of the food Luxembourg imports from its three neighbours." )
```

```dax
Insight Trade =
VAR _Net = CALCULATE ( [Net Trade Balance (EUR)], Dim_Country[CountryCode] = "LU" )
VAR _Y = SELECTEDVALUE ( Dim_Year[Year], 2025 )
RETURN "In " & _Y & " Luxembourg was a net " & IF ( _Net >= 0, "importer", "exporter" )
    & " of food: " & FORMAT ( ABS ( _Net ) / 1000000, "#,0.0" ) & " million EUR "
    & IF ( _Net >= 0, "more imported than exported.", "more exported than imported." )
```

```dax
Insight Self-Sufficiency =
VAR _Grp = SELECTEDVALUE ( Dim_ProductCategory[ProductGroup], "this category" )
VAR _Y = SELECTEDVALUE ( Dim_Year[Year], 2024 )
VAR _LU = CALCULATE ( [Self-Sufficiency %], Dim_Country[CountryCode] = "LU" )
RETURN IF ( ISBLANK ( _LU ),
        "No production series for " & _Grp & " in " & _Y & ": missing data, not zero.",
        "Luxembourg covered " & FORMAT ( _LU, "0" ) & "% of its " & LOWER ( _Grp )
        & " consumption from its own production in " & _Y & "." )
```

```dax
Insight Pass-through =
"Across " & [Price Observations (n)] & " country-category-years, a 1 pp rise in import prices"
    & " goes with a " & FORMAT ( [Pass-through Slope], "0.00" )
    & " pp change in consumer prices (association, not causation)."
```

## 12. Dynamic chart titles

```dax
Title Self-Sufficiency Map =
"Self-sufficiency (%) by Country: "
    & SELECTEDVALUE ( Dim_ProductCategory[ProductGroup])
    & " " & SELECTEDVALUE ( Dim_Year[Year] )
```

```dax
Title Imports Map =
" Where Imports Come From: "
    & SELECTEDVALUE ( Dim_ProductCategory[ProductGroup] )
    & " " & SELECTEDVALUE ( Dim_Year[Year] )
```

```dax
Title Self-Sufficiency Matrix =
"Self-sufficiency (%) by Category and Country: "
    & " " & SELECTEDVALUE ( Dim_Year[Year] )
```

```dax
Title Self-Sufficiency Line Chart =
"Self-sufficiency Trend by Country "
    & SELECTEDVALUE ( Dim_ProductCategory[ProductGroup])
```
