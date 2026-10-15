SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_name IN ('ev_market_2026', 'ev_market_clean');

USE efresh;

CREATE TABLE efresh.ev_market_clean (
  id                     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  brand                  VARCHAR(50)   NOT NULL,
  model                  VARCHAR(60)   NOT NULL,
  year                   SMALLINT      NOT NULL,
  variant                VARCHAR(30)   NOT NULL,
  price_usd              DECIMAL(10,2) NOT NULL,
  battery_capacity_kwh   DECIMAL(5,1),
  range_miles            SMALLINT,
  charging_speed_kw      DECIMAL(5,1),
  acceleration_0_60_mph  DECIMAL(4,2),
  top_speed_mph          SMALLINT,
  horsepower             SMALLINT,
  torque_nm              SMALLINT,
  drive_type             ENUM('AWD','FWD','RWD') NOT NULL,
  seating_capacity       TINYINT UNSIGNED,
  body_type              VARCHAR(20),
  cargo_volume_cubic_ft  DECIMAL(5,1),
  weight_kg              SMALLINT,
  safety_rating          TINYINT UNSIGNED,
  autopilot_level        TINYINT UNSIGNED,
  country_of_origin      VARCHAR(40),
  market_segment         VARCHAR(20),
  annual_sales_units     INT UNSIGNED,
  customer_rating        DECIMAL(3,2),
  warranty_years         TINYINT UNSIGNED,
  dq_flags               VARCHAR(255) NULL,
  CONSTRAINT chk_price    CHECK (price_usd > 0),
  CONSTRAINT chk_year     CHECK (year BETWEEN 2010 AND 2030),
  CONSTRAINT chk_safety   CHECK (safety_rating BETWEEN 1 AND 5),
  CONSTRAINT chk_autopl   CHECK (autopilot_level BETWEEN 0 AND 5),
  CONSTRAINT chk_rating   CHECK (customer_rating BETWEEN 0 AND 5)
) ENGINE=InnoDB;

INSERT INTO efresh.ev_market_clean
  (brand, model, year, variant, price_usd, battery_capacity_kwh, range_miles,
   charging_speed_kw, acceleration_0_60_mph, top_speed_mph, horsepower, torque_nm,
   drive_type, seating_capacity, body_type, cargo_volume_cubic_ft, weight_kg,
   safety_rating, autopilot_level, country_of_origin, market_segment,
   annual_sales_units, customer_rating, warranty_years)
SELECT
  TRIM(brand),
  TRIM(model),
  CAST(NULLIF(TRIM(year),'') AS UNSIGNED),
  TRIM(variant),
  CAST(NULLIF(TRIM(price_usd),'') AS DECIMAL(10,2)),
  CAST(NULLIF(TRIM(battery_capacity_kwh),'') AS DECIMAL(5,1)),
  CAST(NULLIF(TRIM(range_miles),'') AS DECIMAL(6,1)),
  CAST(NULLIF(TRIM(charging_speed_kw),'') AS DECIMAL(5,1)),
  CAST(NULLIF(TRIM(acceleration_0_60_mph),'') AS DECIMAL(4,2)),
  CAST(NULLIF(TRIM(top_speed_mph),'') AS DECIMAL(6,1)),
  CAST(NULLIF(TRIM(horsepower),'') AS DECIMAL(6,1)),
  CAST(NULLIF(TRIM(torque_nm),'') AS DECIMAL(6,1)),
  UPPER(TRIM(drive_type)),
  CAST(NULLIF(TRIM(seating_capacity),'') AS UNSIGNED),
  TRIM(body_type),
  CAST(NULLIF(TRIM(cargo_volume_cubic_ft),'') AS DECIMAL(5,1)),
  CAST(NULLIF(TRIM(weight_kg),'') AS DECIMAL(6,1)),
  CAST(NULLIF(TRIM(safety_rating),'') AS UNSIGNED),
  CAST(NULLIF(TRIM(autopilot_level),'') AS UNSIGNED),
  TRIM(country_of_origin),
  TRIM(market_segment),
  CAST(NULLIF(TRIM(annual_sales_units),'') AS UNSIGNED),
  CAST(NULLIF(TRIM(customer_rating),'') AS DECIMAL(3,2)),
  CAST(NULLIF(TRIM(warranty_years),'') AS UNSIGNED)
FROM efresh.ev_market_2026;

SELECT COUNT(*) AS rows_in_clean FROM efresh.ev_market_clean;

select * from efresh.ev_market_clean;

-- STEP 3: Remove exact duplicate rows (expect 0) ------------------------
DELETE c
FROM efresh.ev_market_clean c
JOIN (
  SELECT id,
         ROW_NUMBER() OVER (
           PARTITION BY brand, model, year, variant, price_usd,
                        battery_capacity_kwh, range_miles, charging_speed_kw,
                        acceleration_0_60_mph, top_speed_mph, horsepower,
                        torque_nm, drive_type, seating_capacity, body_type,
                        cargo_volume_cubic_ft, weight_kg, safety_rating,
                        autopilot_level, country_of_origin, market_segment,
                        annual_sales_units, customer_rating, warranty_years
           ORDER BY id) AS rn
  FROM efresh.ev_market_clean
) d ON d.id = c.id
WHERE d.rn > 1;
 
-- STEP 4: Flag suspect rows (flag, never delete) ------------------------
UPDATE efresh.ev_market_clean SET dq_flags = CONCAT_WS(',', dq_flags, 'HP_AT_CAP')       WHERE horsepower = 1000;
UPDATE efresh.ev_market_clean SET dq_flags = CONCAT_WS(',', dq_flags, 'TOPSPEED_AT_CAP') WHERE top_speed_mph = 200;
UPDATE efresh.ev_market_clean SET dq_flags = CONCAT_WS(',', dq_flags, 'WEIGHT_AT_FLOOR') WHERE weight_kg = 1500;
UPDATE efresh.ev_market_clean SET dq_flags = CONCAT_WS(',', dq_flags, 'TORQUE_AT_FLOOR') WHERE torque_nm = 200;
UPDATE efresh.ev_market_clean SET dq_flags = CONCAT_WS(',', dq_flags, 'RANGE_AT_FLOOR')  WHERE range_miles = 150;
 
UPDATE efresh.ev_market_clean SET dq_flags = CONCAT_WS(',', dq_flags, 'ACCEL_VS_HP')
WHERE (acceleration_0_60_mph > 7 AND horsepower > 900)
   OR (acceleration_0_60_mph < 3 AND horsepower < 400);
 
UPDATE efresh.ev_market_clean SET dq_flags = CONCAT_WS(',', dq_flags, 'L3_ON_BUDGET')
WHERE autopilot_level = 3 AND market_segment = 'Budget';
 
UPDATE efresh.ev_market_clean SET dq_flags = CONCAT_WS(',', dq_flags, 'LOW_SALES')
WHERE annual_sales_units < 1000;
 
UPDATE efresh.ev_market_clean c
JOIN (
  SELECT market_segment, AVG(price_usd) AS mu, STDDEV_POP(price_usd) AS sd
  FROM efresh.ev_market_clean
  GROUP BY market_segment
) s ON s.market_segment = c.market_segment
SET c.dq_flags = CONCAT_WS(',', c.dq_flags, 'PRICE_OUTLIER')
WHERE ABS(c.price_usd - s.mu) > 3 * s.sd;

-- STEP 5: Final view (drops only hard contradictions) -------------------
CREATE OR REPLACE VIEW efresh.ev_market_trusted AS
SELECT *
FROM efresh.ev_market_clean
WHERE dq_flags IS NULL
   OR dq_flags NOT REGEXP 'ACCEL_VS_HP|PRICE_OUTLIER|L3_ON_BUDGET|LOW_SALES';
   
- STEP 6: Verification --------------------------------------------------
SELECT
  (SELECT COUNT(*) FROM efresh.ev_market_2026)                             AS source_rows,
  (SELECT COUNT(*) FROM efresh.ev_market_clean)                            AS clean_rows,
  (SELECT COUNT(*) FROM efresh.ev_market_clean WHERE dq_flags IS NOT NULL) AS flagged_rows,
  (SELECT COUNT(*) FROM efresh.ev_market_trusted)                          AS trusted_rows;
 
-- Rows per flag
SELECT jt.flag, COUNT(*) AS n
FROM efresh.ev_market_clean c
JOIN JSON_TABLE(
       CONCAT('["', REPLACE(c.dq_flags, ',', '","'), '"]'),
       '$[*]' COLUMNS (flag VARCHAR(30) PATH '$')
     ) jt
WHERE c.dq_flags IS NOT NULL
GROUP BY jt.flag
ORDER BY n DESC;
 
-- STEP 7: Reports for manual review -------------------------------------
-- 7a. Rows sharing brand+model+year+variant (not true duplicates)
SELECT COUNT(*) AS rows_sharing_a_key_with_another_row
FROM (
  SELECT id, COUNT(*) OVER (PARTITION BY brand, model, year, variant) AS n
  FROM efresh.ev_market_clean
) t WHERE n > 1;
 
-- 7b. Models that appear under several body types
SELECT brand, model, COUNT(DISTINCT body_type) AS distinct_body_types
FROM efresh.ev_market_clean
GROUP BY brand, model
HAVING COUNT(DISTINCT body_type) > 1
ORDER BY distinct_body_types DESC, brand, model;
 
-- 7c. Brand/model list (look for models under the wrong brand, e.g. BYD Leaf 50X)
SELECT brand, model, COUNT(*) AS n
FROM efresh.ev_market_clean
GROUP BY brand, model
ORDER BY brand, model;

USE efresh;

SELECT 'Row count matches source' AS check_name,
       IF((SELECT COUNT(*) FROM ev_market_clean) = (SELECT COUNT(*) FROM ev_market_2026), 'PASS', 'FAIL') AS result
UNION ALL
SELECT 'No missing values in key columns',
       IF((SELECT COUNT(*) FROM ev_market_clean
           WHERE brand IS NULL OR model IS NULL OR year IS NULL OR price_usd IS NULL
              OR horsepower IS NULL OR range_miles IS NULL) = 0, 'PASS', 'FAIL')
UNION ALL
SELECT 'No extra spaces in text columns',
       IF((SELECT COUNT(*) FROM ev_market_clean
           WHERE brand <> TRIM(brand) OR model <> TRIM(model) OR variant <> TRIM(variant)
              OR body_type <> TRIM(body_type) OR country_of_origin <> TRIM(country_of_origin)) = 0, 'PASS', 'FAIL')
UNION ALL
SELECT 'No exact duplicate rows',
       IF((SELECT COUNT(*) FROM (
             SELECT 1 FROM ev_market_clean
             GROUP BY brand, model, year, variant, price_usd, battery_capacity_kwh, range_miles,
                      charging_speed_kw, acceleration_0_60_mph, top_speed_mph, horsepower, torque_nm,
                      drive_type, seating_capacity, body_type, cargo_volume_cubic_ft, weight_kg,
                      safety_rating, autopilot_level, country_of_origin, market_segment,
                      annual_sales_units, customer_rating, warranty_years
             HAVING COUNT(*) > 1) d) = 0, 'PASS', 'FAIL')
UNION ALL
SELECT 'Values in valid ranges',
       IF((SELECT COUNT(*) FROM ev_market_clean
           WHERE price_usd <= 0 OR year NOT BETWEEN 2010 AND 2030
              OR safety_rating NOT BETWEEN 1 AND 5
              OR customer_rating NOT BETWEEN 0 AND 5) = 0, 'PASS', 'FAIL')
UNION ALL
SELECT 'Flagged rows = 926',
       IF((SELECT COUNT(*) FROM ev_market_clean WHERE dq_flags IS NOT NULL) = 926, 'PASS', 'FAIL')
UNION ALL
SELECT 'Trusted view rows = 1904',
       IF((SELECT COUNT(*) FROM ev_market_trusted) = 1904, 'PASS', 'FAIL');