# Power Query: cleaning and keying the three files

Goal: turn the long Eurostat and FAOSTAT labels into short codes shared by all three files, add a `ProductGroup` that maps three classification systems to one list, and export three clean fact files: `Fact_FoodPrice.csv`, `Fact_Trade.csv`, `Fact_Production.csv`.


## Food price file (`eurostat_food_price_raw.csv`)

1. Remove `DATAFLOW`, `LAST UPDATE`, `freq`, `OBS_FLAG`, `CONF_STATUS`.
2. `CountryCode`:
```m
if Text.Contains([geo], "Belgium") then "BE"
else if Text.Contains([geo], "Germany") then "DE"
else if Text.Contains([geo], "France") then "FR"
else if Text.Contains([geo], "Luxembourg") then "LU"
else if Text.Contains([geo], "European Union") then "EU27"
else "UNKNOWN"
```
3. `ProductGroup`:
```m
if [coicop18] = "Food" then "All Food"
else if Text.Contains([coicop18], "Meat") then "Meat"
else if Text.Contains([coicop18], "Fish") then "Fish & Seafood"
else if Text.Contains([coicop18], "Milk") then "Dairy & Eggs"
else if Text.Contains([coicop18], "Oils") then "Oils & Fats"
else if Text.Contains([coicop18], "Fruits") then "Fruit & Nuts"
else if Text.Contains([coicop18], "Vegetables") then "Vegetables"
else if [coicop18] = "Cereals (ND)" then "Cereals"
else if [coicop18] = "Bread" then "Bread & Bakery"
else if [coicop18] = "Other bakery products" then "Bread & Bakery"
else if Text.Contains([coicop18], "Macaroni") then "Bread & Bakery"
else if Text.Contains([coicop18], "Coffee") then "Coffee & Tea"
else if Text.Contains([coicop18], "Tea,") then "Coffee & Tea"
else "UNKNOWN"
```
4. `IndexType`:
```m
if Text.Contains([indx], "Agricultural") then "ACPI"
else if Text.Contains([indx], "Harmonised") then "HICP"
else if Text.Contains([indx], "Import") then "IPI"
else if Text.Contains([indx], "Producer") then "PPI"
else "UNKNOWN"
```
5. Rename `OBS_VALUE` to `IndexValue` and `TIME_PERIOD` to `YearMonth`.
6. `DateKey` (an integer that matches `Dim_Date`): `Date.Year([YearMonth]) * 100 + Date.Month([YearMonth])`
7. Make `YearMonth` unambiguous text: add `YearMonthText = Date.ToText([YearMonth], "yyyy-MM")`, remove the old `YearMonth`, rename `YearMonthText` to `YearMonth`.
8. Filter out `(null)` in `IndexValue`.
9. Duplicate check (Reference query > Group By `CountryCode`, `coicop18`, `IndexType`, `DateKey` > count rows > keep > 1): expect no rows. Use the raw `coicop18`, not `ProductGroup`.
10. Export as `Fact_FoodPrice.csv` (CSV UTF-8). Expected: 36,966 rows after the null filter.

After every mapping step, filter the new column for `UNKNOWN`; any hit means a label did not match exactly.

## Trade file (`eurostat_comext_trade_raw.csv`)

1. Remove `DATAFLOW`, `LAST UPDATE`, `freq`.
2. `ReporterCode`: same pattern as `CountryCode` above, on `[reporter]` (Belgium, Germany, France, Luxembourg).
3. `PartnerCode`: the same four plus `else if Text.Contains([partner], "All countries") then "WORLD"`.
4. `ProductGroup`:
```m
if [product] = "CEREALS" then "Cereals"
else if Text.Contains([product], "MEAT AND EDIBLE MEAT OFFAL") then "Meat"
else if Text.Contains([product], "FISH AND CRUSTACEANS") then "Fish & Seafood"
else if Text.Contains([product], "DAIRY PRODUCE") then "Dairy & Eggs"
else if Text.Contains([product], "ANIMAL OR VEGETABLE FATS") then "Oils & Fats"
else if Text.Contains([product], "EDIBLE FRUIT AND NUTS") then "Fruit & Nuts"
else if Text.Contains([product], "EDIBLE VEGETABLES") then "Vegetables"
else if Text.Contains([product], "MILLING INDUSTRY") then "Bread & Bakery"
else if Text.Contains([product], "PASTRYCOOKS") then "Bread & Bakery"
else if Text.Contains([product], "COFFEE, TEA") then "Coffee & Tea"
else "UNKNOWN"
```
   `"CEREALS"` stays an exact match and is checked first: the word also appears inside "PREPARATIONS OF CEREALS...".
5. Remove `reporter` and `partner` (the codes replace them).
6. Rename `OBS_VALUE` to `TradeValue`, `TIME_PERIOD` to `YearMonth`, `indicators` to `IndicatorType`, `flow` to `FlowType`.
7. Add `DateKey` and fix `YearMonth` exactly as in the price file.
8. Filter out `(null)` in `TradeValue`. Duplicate check on `ReporterCode`, `PartnerCode`, `product`, `FlowType`, `IndicatorType`, `DateKey` (raw `product`).
9. Export as `Fact_Trade.csv`. Expected: 165,106 rows.

## Production file (`faostat_production_raw.csv`)

1. Remove `Domain Code`, `Domain`, `Area Code (FAO)`, `Element Code`, `Element`, `Item Code (FAO)`, `Year Code`, `Flag`, `Flag Description`, `Note`.
2. `CountryCode`: exact match on `[Area]` (Belgium BE, France FR, Germany DE, Luxembourg LU).
3. `ProductGroup`:
```m
if [Item] = "Meat, Total" then "Meat"
else if [Item] = "Hen eggs in shell, fresh" then "Dairy & Eggs"
else if [Item] = "Raw milk of cattle" then "Dairy & Eggs"
else if [Item] = "Oilcrops, Oil Equivalent" then "Oils & Fats"
else if [Item] = "Fruit Primary" then "Fruit & Nuts"
else if [Item] = "Vegetables Primary" then "Vegetables"
else if [Item] = "Cereals, primary" then "Cereals"
else "UNKNOWN"
```
4. Rename `Value` to `ProductionQuantity` and `Unit` to `ProductionUnit`; set `ProductionQuantity` to Decimal Number and `Year` to Whole Number. Optionally remove `Area`.
5. **Do not split or convert units here.** Keep one `ProductionQuantity` column and the unit it is reported in. The egg conversion needs to know which count rows duplicate a tonnes row, which the SQL load does.
6. Duplicate check on `CountryCode`, `Item`, `Year`, `ProductionUnit`: expect no rows.
7. Export as `Fact_Production.csv`. Expected: 597 rows with the columns `Item, Year, ProductionUnit, CountryCode, ProductGroup, ProductionQuantity`.

## Dimension tables

The three dimension tables are created by script in [`../sql/01_schema_and_load.sql`](../sql/01_schema_and_load.sql) (`Dim_Country`, `Dim_ProductCategory`, and a generated `Dim_Date` for 2005-01 to 2026-12, 264 rows).

| Key | ProductGroup | Eurostat prices (COICOP) | Comext (HS chapter) | FAOSTAT item |
|---|---|---|---|---|
| 1 | Meat | Meat, fresh, chilled or frozen | Meat and edible meat offal | Meat, Total |
| 2 | Fish & Seafood | Fish and other seafood | Fish and crustaceans, molluscs... | none |
| 3 | Dairy & Eggs | Milk, other dairy products and eggs | Dairy produce, birds' eggs, honey... | Raw milk of cattle; Hen eggs |
| 4 | Oils & Fats | Oils and fats | Animal or vegetable fats and oils... | Oilcrops, Oil Equivalent (2005-2017 only) |
| 5 | Fruit & Nuts | Fruits and nuts | Edible fruit and nuts... | Fruit Primary |
| 6 | Vegetables | Vegetables, tubers, plantains, pulses | Edible vegetables and certain roots... | Vegetables Primary |
| 7 | Cereals | Cereals | Cereals | Cereals, primary |
| 8 | Bread & Bakery | Bread; bakery products; pasta | Milling industry products; preparations of cereals, pastrycooks' products | none |
| 9 | Coffee & Tea | Coffee substitutes; tea | Coffee, tea, mate and spices | none |
| 10 | All Food | Food (headline) | none | none |
