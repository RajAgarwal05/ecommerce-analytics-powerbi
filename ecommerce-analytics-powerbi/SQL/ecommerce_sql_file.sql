drop table orders
create table orders(
		order_id VARCHAR ,
		order_date Date,	
		customer_id VARCHAR,	
		order_status varchar(50),
		city varchar(50),
		state varchar(50),
		pincode INT
)
select * from products
drop table order_items
create table order_items(		
		order_id varchar,
		product_id varchar,
		seller_id varchar,
		quantity varchar,
		list_price varchar,
		unit_price varchar,
		item_total varchar
)
drop table products
create table products(
		product_id varchar,
		category varchar,
		subcategory varchar,
		brand varchar,
		list_price varchar
)
SELECT COUNT(*) FROM orders;
SELECT COUNT(*) FROM order_items;
SELECT COUNT(*) FROM products;


SELECT 
    o.order_id,
    o.order_date,
    oi.product_id,
    p.category,
    p.subcategory,
    oi.quantity,
    oi.item_total
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
LIMIT 10;



-- duplicates?
SELECT order_id,COUNT(*)
FROM orders
GROUP BY 1 
HAVING COUNT(*)>1;

-- null keys?
SELECT COUNT(*) 
FROM order_items 
WHERE order_id IS NULL OR product_id IS NULL;

-- negative values?
SELECT COUNT(*) 
FROM order_items
WHERE item_total::numeric < 0;


-- 4.1: optional indexes (faster joins)
CREATE INDEX IF NOT EXISTS idx_orders_id    ON orders(order_id);
CREATE INDEX IF NOT EXISTS idx_items_oid    ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_items_pid    ON order_items(product_id);
CREATE INDEX IF NOT EXISTS idx_prod_pid     ON products(product_id);

DROP VIEW IF EXISTS vw_order_items;

CREATE VIEW vw_order_items AS
SELECT
  oi.order_id,
  o.order_date,
  o.customer_id,
  o.order_status,
  oi.product_id,
  p.category,
  p.subcategory,
  p.brand,
  oi.seller_id,
  oi.quantity::int AS quantity,
  oi.list_price::numeric AS list_price,
  oi.unit_price::numeric AS unit_price,
  oi.item_total::numeric AS item_total,
  -- discount percentage
  CASE
    WHEN oi.list_price IS NULL OR oi.list_price = 0 THEN NULL
    ELSE 1 - (oi.unit_price / oi.list_price)
  END AS discount_pct,
  -- estimated cost (assume 80% of selling price)
  (oi.unit_price * oi.quantity * 0.8)::numeric AS item_cost,
  -- margin
  (oi.item_total - (oi.unit_price * oi.quantity * 0.8))::numeric AS item_margin
FROM order_items oi
JOIN orders o   ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id;
select * from vw_order_items


-- GMV
SELECT SUM(item_total) AS gmv
FROM vw_order_items
WHERE order_status IN ('delivered','shipped','processing');

-- Orders
SELECT COUNT(DISTINCT order_id) AS orders
FROM vw_order_items
WHERE order_status IN ('delivered','shipped','processing');

-- AOV
WITH o AS (
  SELECT order_id, SUM(item_total) AS order_gmv
  FROM vw_order_items
  WHERE order_status IN ('delivered','shipped','processing')
  GROUP BY order_id
)
SELECT AVG(order_gmv) AS aov FROM o;


SELECT
  category, subcategory,
  COUNT(DISTINCT order_id) AS orders,
  SUM(quantity)            AS units,
  SUM(item_total)          AS gmv
FROM vw_order_items
WHERE order_status IN ('delivered','shipped','processing')
GROUP BY 1,2
ORDER BY gmv DESC;

WITH b AS (
  SELECT *,
    CASE
      WHEN unit_price <= 500   THEN '<=₹500'
      WHEN unit_price <= 1000  THEN '₹501–1k'
      WHEN unit_price <= 2000  THEN '₹1k–2k'
      WHEN unit_price <= 5000  THEN '₹2k–5k'
      WHEN unit_price <= 10000 THEN '₹5k–10k'
      WHEN unit_price <= 20000 THEN '₹10k–20k'
      WHEN unit_price <= 50000 THEN '₹20k–50k'
      ELSE '>₹50k'
    END AS price_band
  FROM vw_order_items
  WHERE order_status IN ('delivered','shipped','processing')
)
SELECT category, price_band,
       COUNT(DISTINCT order_id) AS orders,
       SUM(item_total)          AS gmv
FROM b
GROUP BY 1,2
ORDER BY category, price_band;

WITH valid AS (
  SELECT * FROM vw_order_items
  WHERE order_status IN ('delivered','shipped','processing')
),
orders_agg AS (
  SELECT order_id, SUM(item_total) AS order_gmv
  FROM valid
  GROUP BY order_id
)
SELECT
  ROUND((SELECT SUM(item_total) FROM valid)::numeric,2)    AS gmv,
  (SELECT COUNT(DISTINCT order_id) FROM valid)             AS orders,
  ROUND((SELECT AVG(order_gmv) FROM orders_agg)::numeric,2) AS aov;



SELECT
  category, subcategory,
  SUM(item_total) AS gmv,
  SUM(item_margin) AS margin,
  ROUND( SUM(item_margin)::numeric / NULLIF(SUM(item_total),0) * 100, 2) AS margin_pct
FROM vw_order_items
WHERE order_status IN ('delivered','shipped','processing')
GROUP BY 1,2
ORDER BY gmv DESC
LIMIT 8;





SELECT
  category, subcategory,
  SUM(item_total) AS gmv,
  SUM(item_margin) AS margin,
  ROUND( SUM(item_margin)::numeric / NULLIF(SUM(item_total),0) * 100, 2) AS margin_pct
FROM vw_order_items
WHERE order_status IN ('delivered','shipped','processing')
GROUP BY 1,2
HAVING SUM(item_total) > 10000   -- exclude tiny-volume traps (adjust threshold)
ORDER BY margin_pct ASC
LIMIT 8;


WITH valid AS (
  SELECT *, CASE
      WHEN unit_price <= 500   THEN '<=₹500'
      WHEN unit_price <= 1000  THEN '₹501–1k'
      WHEN unit_price <= 2000  THEN '₹1k–2k'
      WHEN unit_price <= 5000  THEN '₹2k–5k'
      WHEN unit_price <= 10000 THEN '₹5k–10k'
      WHEN unit_price <= 20000 THEN '₹10k–20k'
      WHEN unit_price <= 50000 THEN '₹20k–50k'
      ELSE '>₹50k'
    END AS price_band
  FROM vw_order_items
  WHERE order_status IN ('delivered','shipped','processing')
)
SELECT category, price_band, SUM(item_total) AS gmv, ROUND( SUM(item_margin)::numeric / NULLIF(SUM(item_total),0)*100,2) AS margin_pct
FROM valid
GROUP BY 1,2
ORDER BY category, price_band;

