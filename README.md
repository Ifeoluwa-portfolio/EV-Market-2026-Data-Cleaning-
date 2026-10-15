# EV-Market-2026-Data-Cleaning-
A SQL data-cleaning project on a 2,000-row electric vehicle market dataset. The goal was to take a raw CSV, load it into MySQL, build a typed and validated table, find the quality problems hiding in the data, and leave a reusable, documented pipeline behind.

# The dataset
ev_market_2026.csv has 2,000 rows and 24 columns. Each row is one vehicle configuration (brand, model, year, variant) with its specs, price, annual sales and ratings.

| Group                 |  Columns                                                                |
|-----------------------| ------------------------------------------------------------------------|
| Identity	            | brand, model, year, variant                                             |                            | Pricing and market    | price_usd, market_segment, annual_sales_units, country_of_origin        |
| Battery and charging	| battery_capacity_kwh, range_miles, charging_speed_kw                    |
Performance	            | acceleration_0_60_mph, top_speed_mph, horsepower, torque_nm, drive_type |
Body and practicality	  | body_type, seating_capacity, cargo_volume_cubic_ft, weight_kg           |
Ratings and features	  |  safety_rating, autopilot_level, customer_rating, warranty_years        |

# What the profiling found

At first glance the data looked clean: no nulls, no blanks, no stray whitespace, no exact duplicate rows, and consistent category labels. The real problems were logical, not formatting ones.

| Issue	                   | Finding                                                                       |
| -------------------------| ------------------------------------------------------------------------------|
| No natural key	         | 1,408 rows share the same brand, model, year and variant as another row, but differ in price                                and specs. They are not true duplicates, so they were reported rather than deleted. |
| Clamped values	         | 422 rows (21%) have horsepower of exactly 1000, and 162 have a top speed of exactly 200 mph.                                There are also pile-ups at the minimum for weight, torque and range. These look like capped                                  values, not real measurements.                                                      |
| Contradictory specs	     |83 rows have performance figures that conflict, such as a 0-60 time over 7 seconds with more                                 than 900 hp.                                                                     |
| Unreliable body type	   | The same model appears under several body types.                                |
| Odd brand/model pairs	   | For example, a BYD "Leaf 50X" (Leaf is a Nissan name).                          |
| Mixed units              | Miles, mph and cubic feet sit alongside kg, Nm and kW.                          |

 # Approach
The pipeline follows one rule: flag suspect rows, never silently delete them.

1. Create a typed table. ev_market_clean uses proper types (DECIMAL for money, an ENUM for drive type, small integer types for ratings) plus CHECK constraints that reject impossible values.
2. Copy and clean. Text is trimmed, blanks become NULL, and values are cast to their correct types.
3. Remove exact duplicates. This uses ROW_NUMBER() OVER (PARTITION BY ...) across every column. It removed 0 rows here but makes the script reusable.
4. Flag suspect rows. A dq_flags column records the reason, for example HP_AT_CAP, ACCEL_VS_HP, L3_ON_BUDGET, LOW_SALES and PRICE_OUTLIER (more than 3 standard deviations from the segment mean).
5. Build a trusted view. ev_market_trusted drops only the rows with hard logical contradictions and keeps the capped-value rows, because excluding them would discard about 46% of the data.
6. Validate A set of PASS/FAIL checks confirms row counts, missing values, whitespace, duplicates and value ranges.


# Results
|Table / view	        |  Rows     |
|---------------------|-----------|
| Source	             | 2,000     |
| ev_market_clean	    | 2,000     |
| Flagged rows        |	926       | 
| ev_market_trusted	  | 1,904     |


# SQL techniques used
* TRIM, NULLIF, CAST, UPPER for standardising
* CHECK constraints and ENUM types for data integrity
* Window functions: ROW_NUMBER() for de-duplication and COUNT() OVER for key-level duplicate detection
* Self-joined aggregates (AVG, STDDEV_POP) for statistical outlier detection
* CONCAT_WS to build multi-reason flags
* JSON_TABLE to split flags into rows for counting
* Views for a reusable, filtered output
* UNION ALL validation queries returning PASS/FAIL
