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
