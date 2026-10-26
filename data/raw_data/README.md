# Raw data (not included)

The three source files are public but large (the trade file is about 45 MB), so they are **not stored in this repository**. Download them as described below and save them in this folder with the exact names shown. Check each provider's terms of use before redistributing any data.

| Save as | Source | Dataset | Notes |
|---|---|---|---|
| `eurostat_food_price_raw.csv` | [Eurostat Food Price Monitoring Tool](https://ec.europa.eu/eurostat) | `prc_fpmt_m` | Flat SDMX-CSV, monthly, 2005-01 to 2026-07. Index types: Agricultural commodity price index, Harmonised index of consumer prices, Import price index, Producer price index. Base 2025 = 100. Countries: BE, DE, FR, LU, EU-27. 13 food categories (COICOP) |
| `eurostat_comext_trade_raw.csv` | [Eurostat Comext](https://ec.europa.eu/eurostat) | "EU trade since 1988 by HS2-4-6 and CN8" (`ds-045409`) | Flat SDMX-CSV, **monthly only**, indicators `VALUE_IN_EUROS` and `QUANTITY_IN_100KG`, reporters LU/BE/FR/DE, partners the same four plus "All countries of the world", 10 food chapters. 165,106 rows, 2005-01 to 2026-06 |
| `faostat_production_raw.csv` | [FAOSTAT](https://www.fao.org/faostat/) | Crops and livestock products (QCL) | Element Production, areas BE/FR/DE/LU, items: Vegetables Primary, Fruit Primary, Cereals primary, Oilcrops Oil Equivalent, Meat Total, Raw milk of cattle, Hen eggs in shell fresh. 597 rows, 2005 to 2024 |

## Selection tips

- **FAOSTAT:** aggregates (Vegetables Primary, Fruit Primary, Cereals primary, Oilcrops, Meat Total) are on the *Items Aggregated* tab; milk and eggs are on the *Items* tab. Always tick the **"+ (Total)"** line, never the parent "> (List)". Hen eggs come in two units (tonnes and thousands of eggs); the load script in `03_sql` resolves this.
- **Comext:** keep frequency to **Monthly only** (mixing monthly and annual creates duplicate rows) and drop the `SUPPLEMENTARY_QUANTITY` indicator (its unit differs between chapters). The Data Browser's 750,000-cell ceiling forces several narrowing rounds. After downloading, check `MIN(TIME_PERIOD)` and `MAX(TIME_PERIOD)` (2005-01 and 2026-06 for this project).
- **Eurostat prices:** the base year is **2025 = 100**, not 2015.

Next step: [`../02_power_query/POWER_QUERY_STEPS.md`](../02_power_query/POWER_QUERY_STEPS.md).
