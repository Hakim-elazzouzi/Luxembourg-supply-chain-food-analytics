# Power BI report

> **The `.pbix` file is intentionally not published.** This folder holds everything needed to understand, audit and rebuild the report: screenshots, the data model, every DAX measure, the theme file and the design assets.

| Item | File |
|---|---|
| Dashboard screenshots (5 pages) | [`screenshots/`](screenshots/) |
| Star schema diagram | [`model/star_schema.png`](model/star_schema.png) |
| All DAX measures, calculated table and columns | [`dax_measures/dax_measures.md`](dax_measures/dax_measures.md) |

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
