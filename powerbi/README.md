# Power BI report

> **The `.pbix` file is intentionally not published.** This folder holds everything needed to understand, audit and rebuild the report: screenshots, the data model, every DAX measure, the theme file and the design assets.

| Item | File |
|---|---|
| Dashboard screenshots (5 pages) | [`screenshots/`](screenshots/) |
| Star schema diagram | [`model/star_schema.png`](model/star_schema.png) |
| All DAX measures, calculated table and columns | [`dax_measures/dax_measures.md`](dax_measures.md) |

## Pages

| # | Page | Question it answers |
|---|---|---|
| 1 | Overview | How have Luxembourg's food prices moved compared with its neighbours and the EU, and what is its headline trade and self-sufficiency position? |
| 2 | Imports | Which neighbour does Luxembourg depend on, for which categories, and is that changing? |
| 3 | Self-sufficiency | For each food category, how much does each country produce itself, and is it a net importer or exporter? |
| 4 | Price vs dependency | Do import-dependent categories show faster consumer price rises, and do consumer prices follow import prices? |
| 5 | About | What the data covers and what it cannot show (sources, limitations, credits) |

## Data model

Seven tables: three dimensions (`Dim_Country`, `Dim_Date`, `Dim_ProductCategory`), one calculated shared year table (`Dim_Year`), and three facts (`Fact_FoodPrice`, `Fact_Trade`, `Fact_Production`). Imported from SQL Server in Import mode, using the base tables (not the `vw_*` views).

| # | From (one side) | To (many side) | State |
|---|---|---|---|
| 1 | `Dim_Country[CountryKey]` | `Fact_FoodPrice[CountryKey]` | Active |
| 2 | `Dim_Country[CountryKey]` | `Fact_Production[CountryKey]` | Active |
| 3 | `Dim_Country[CountryKey]` | `Fact_Trade[ReporterCountryKey]` | Active |
| 4 | `Dim_Country[CountryKey]` | `Fact_Trade[PartnerCountryKey]` | **Inactive** (used with `USERELATIONSHIP`) |
| 5 | `Dim_ProductCategory[ProductKey]` | `Fact_FoodPrice`, `Fact_Trade`, `Fact_Production` (`ProductKey`) | Active |
| 6 | `Dim_Date[DateKey]` | `Fact_FoodPrice[DateKey]`, `Fact_Trade[DateKey]` | Active |
| 7 | `Dim_Year[Year]` | `Dim_Date[Year]` | Active |
| 8 | `Dim_Year[Year]` | `Fact_Production[Year]` | Active |

All relationships are one-to-many with a single filter direction. Fact tables are never related to each other. `Fact_Production` is yearly, so it connects to `Dim_Year`, not to the monthly `Dim_Date`.

## Techniques worth a look

- **Shared year table** so one year selection filters monthly facts (prices, trade) and the yearly fact (production) consistently.
- **Two relationships to one dimension** (reporter active, partner inactive) with `USERELATIONSHIP` in the partner measures.
- **Self-sufficiency as a measure built from sums**, with explicit rules: structural zeros for categories without a production series, blanks (not zeros) where data ends, blank when more than one category is in context.
- **Price pass-through** computed by hand in DAX (least-squares slope and correlation over country x category x year), because DAX has no `CORREL` or `LINEST`.
- **Dynamic text**: change arrows under the KPI numbers, insight sentences and chart titles are measures, so they update with the slicers.
- **Consistent colour language**: one colour per country (`Country Color`) and one per food category (`Category Color`), never reused for something else.

## How to rebuild the report

1. Run the SQL in [`../03_sql`](../03_sql) and load the six tables (Home > Get data > SQL Server, database `FoodSupplyChain`, Import).
2. Create `Dim_Year`, the two colour columns and every measure from [`dax_measures.md`](dax_measures.md) (put the measures in a table named `_Measures`).
3. Build the eight relationships above (the partner link inactive).
4. Import [`lux_food_theme.json`](lux_food_theme.json) (View > Themes > Browse for themes). Set the canvas to 16:9 (1280 x 720).
5. Add the sidebar image from [`assets/`](assets/) and build the five pages.

## Checks used to validate the report against SQL

| Check | Expected |
|---|---|
| Luxembourg, Dairy & Eggs, 2005, `Total Production (Tonnes)` | 271,134.97 (milk 269,711.00 + eggs 1,423.97) |
| Belgium, Dairy & Eggs, 2018, `Converted Production (Tonnes)` | 107,844.34 |
| Fish & Seafood, any country, year up to 2024, `Self-Sufficiency %` | 0.0 |
| Luxembourg, Oils & Fats, 2018 | blank, not 0 |
| Self-sufficiency and net trade balance for several rows | equal to SQL queries 1 and 5 |
| `Consumer Price Index (HICP)`, any country, All Food, 2025 | 100.0 |
