USE AdventureWorks2025;
GO

-- ============================================================
--  VIEWS  (run once to create; re-run to refresh)
-- ============================================================

-- ------------------------------------------------------------
--  dim_customer
--  One row per customer. Resolves both Person and Store types.
-- ------------------------------------------------------------
CREATE OR ALTER VIEW dim_customer AS
SELECT
    sc.CustomerID,
    sc.PersonID,
    sc.StoreID,
    sc.TerritoryID,

    CASE
        WHEN sc.StoreID  IS NOT NULL THEN ss.Name
        WHEN sc.PersonID IS NOT NULL 
            THEN CONCAT(pp.FirstName, ' ', pp.LastName)
        ELSE 'Unclassified'
    END AS CustomerName,

    CASE
        WHEN sc.StoreID  IS NOT NULL THEN 'Store'
        WHEN sc.PersonID IS NOT NULL THEN 'Person'
        ELSE 'Unclassified'
    END AS CustomerType

FROM Sales.Customer sc
LEFT JOIN Person.Person pp
    ON sc.PersonID = pp.BusinessEntityID
LEFT JOIN Sales.Store ss
    ON sc.StoreID = ss.BusinessEntityID;
GO


-- ------------------------------------------------------------
--  dim_product
--  One row per product, enriched with subcategory and category.
-- ------------------------------------------------------------
CREATE OR ALTER VIEW dim_product AS
SELECT
    p.ProductID,
    p.Name           AS ProductName,
    p.ProductNumber,
    p.Color,
    p.Size,
    p.StandardCost,
    p.ListPrice,
    p.MakeFlag,
    p.FinishedGoodsFlag,
    p.SafetyStockLevel,
    p.ReorderPoint,
    p.DiscontinuedDate,

    psc.ProductSubcategoryID,
    psc.Name         AS SubcategoryName,

    pc.ProductCategoryID,
    pc.Name          AS CategoryName

FROM Production.Product p
LEFT JOIN Production.ProductSubcategory psc
    ON p.ProductSubcategoryID = psc.ProductSubcategoryID
LEFT JOIN Production.ProductCategory pc
    ON psc.ProductCategoryID = pc.ProductCategoryID;
GO


-- ------------------------------------------------------------
--  dim_territory
--  One row per sales territory.
-- ------------------------------------------------------------
CREATE OR ALTER VIEW dim_territory AS
SELECT
    TerritoryID,
    CountryRegionCode,
    Name  AS TerritoryName,
    [Group] AS TerritoryGroup
FROM Sales.SalesTerritory;
GO


-- ------------------------------------------------------------
--  fact_sales
--  Grain: one row per order line item.
-- ------------------------------------------------------------
ALTER VIEW fact_sales AS
SELECT
    d.SalesOrderID,
    d.SalesOrderDetailID,

    d.ProductID,
    h.TerritoryID,
    h.CustomerID,

    h.OrderDate,
    h.ShipDate,

    d.OrderQty,
    d.UnitPrice,
    d.UnitPriceDiscount,

    d.OrderQty * d.UnitPrice AS GrossRevenue,

    (d.OrderQty * d.UnitPrice)
        - (d.OrderQty * d.UnitPrice * d.UnitPriceDiscount) AS NetRevenue

FROM Sales.SalesOrderDetail d
LEFT JOIN Sales.SalesOrderHeader h
    ON d.SalesOrderID = h.SalesOrderID;
GO


-- ============================================================
--  ANALYTICAL QUERIES
-- ============================================================

-- ------------------------------------------------------------
--  Challenge 1 — Top 10 customers by total revenue (all time)
-- ------------------------------------------------------------
WITH customer_sales AS (
    SELECT
        dc.CustomerID,
        dc.CustomerName,
        COUNT(soh.SalesOrderID)  AS total_orders,
        SUM(soh.TotalDue)        AS total_revenue
    FROM Sales.SalesOrderHeader soh
    JOIN dim_customer dc
        ON soh.CustomerID = dc.CustomerID
    GROUP BY
        dc.CustomerID,
        dc.CustomerName
)
SELECT TOP 10
    CustomerID,
    CustomerName,
    total_orders,
    ROUND(total_revenue, 2) AS total_revenue
FROM customer_sales
ORDER BY total_revenue DESC;


-- ------------------------------------------------------------
--  Challenge 2 — Revenue and percent of total by subcategory
-- ------------------------------------------------------------
WITH subcategory_revenue AS (
    SELECT
        pc.Name  AS category,
        psc.Name AS subcategory,
        SUM(sod.LineTotal) AS revenue
    FROM Production.ProductSubcategory psc
    JOIN Production.ProductCategory pc
        ON psc.ProductCategoryID = pc.ProductCategoryID
    JOIN Production.Product p
        ON p.ProductSubcategoryID = psc.ProductSubcategoryID
    JOIN Sales.SalesOrderDetail sod
        ON sod.ProductID = p.ProductID
    GROUP BY
        pc.Name,
        psc.Name
)
SELECT
    category,
    subcategory,
    ROUND(revenue, 2) AS revenue,
    ROUND(
        revenue * 100.0 / SUM(revenue) OVER (),
    2) AS pct_of_total
FROM subcategory_revenue
ORDER BY revenue DESC;


-- ------------------------------------------------------------
--  Challenge 3 — Monthly revenue trend with prior-month comparison
-- ------------------------------------------------------------
WITH monthly_revenue AS (
    SELECT
        YEAR(OrderDate)  AS sales_year,
        MONTH(OrderDate) AS sales_month,
        SUM(TotalDue)    AS revenue
    FROM Sales.SalesOrderHeader
    GROUP BY
        YEAR(OrderDate),
        MONTH(OrderDate)
)
SELECT
    sales_year,
    sales_month,
    DATENAME(MONTH, DATEFROMPARTS(sales_year, sales_month, 1)) AS month_name,
    ROUND(revenue, 2) AS revenue,

    ROUND(
        LAG(revenue) OVER (ORDER BY sales_year, sales_month),
    2) AS prev_month_revenue,

    ROUND(
        (revenue - LAG(revenue) OVER (ORDER BY sales_year, sales_month))
        * 100.0
        / NULLIF(LAG(revenue) OVER (ORDER BY sales_year, sales_month), 0),
    2) AS pct_change,

    ROUND(
        SUM(revenue) OVER (
            ORDER BY sales_year, sales_month
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ),
    2) AS rolling_3_month_total

FROM monthly_revenue
ORDER BY sales_year, sales_month;


-- ------------------------------------------------------------
--  Challenge 4 — Best sales day of each month
-- ------------------------------------------------------------
WITH daily_revenue AS (
    SELECT
        YEAR(OrderDate)  AS sales_year,
        MONTH(OrderDate) AS sales_month,
        DAY(OrderDate)   AS sales_day,
        SUM(TotalDue)    AS daily_revenue
    FROM Sales.SalesOrderHeader
    GROUP BY
        YEAR(OrderDate),
        MONTH(OrderDate),
        DAY(OrderDate)
),
ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY sales_year, sales_month
            ORDER BY daily_revenue DESC
        ) AS day_rank
    FROM daily_revenue
)
SELECT
    sales_year,
    sales_month,
    sales_day,
    ROUND(daily_revenue, 2) AS daily_revenue
FROM ranked
WHERE day_rank = 1
ORDER BY sales_year, sales_month;


-- ------------------------------------------------------------
--  Challenge 5 — Order volume and revenue by day of week
-- ------------------------------------------------------------
WITH weekday_orders AS (
    SELECT
        DATENAME(WEEKDAY, OrderDate) AS day_name,
        DATEPART(WEEKDAY, OrderDate) AS day_number,   -- for correct sort order
        COUNT(*)         AS number_of_orders,
        SUM(TotalDue)    AS revenue
    FROM Sales.SalesOrderHeader
    GROUP BY
        DATENAME(WEEKDAY, OrderDate),
        DATEPART(WEEKDAY, OrderDate)
)
SELECT
    day_name,
    number_of_orders,
    ROUND(revenue, 2) AS revenue,
    DENSE_RANK() OVER (ORDER BY number_of_orders DESC) AS order_rank
FROM weekday_orders
ORDER BY day_number;


-- ------------------------------------------------------------
--  Challenge 6 — Customers who ordered in 2024 but not 2025
--  (lapsed customer list — foundation for segmentation)
-- ------------------------------------------------------------
SELECT
    c.CustomerID,
    MAX(soh.OrderDate)       AS last_order_date,
    COUNT(soh.SalesOrderID)  AS lifetime_orders,
    ROUND(SUM(soh.TotalDue), 2) AS lifetime_revenue
FROM Sales.Customer c
JOIN Sales.SalesOrderHeader soh
    ON c.CustomerID = soh.CustomerID
WHERE EXISTS (
    SELECT 1
    FROM Sales.SalesOrderHeader s24
    WHERE s24.CustomerID = c.CustomerID
      AND s24.OrderDate >= '2024-01-01'
      AND s24.OrderDate <  '2025-01-01'
)
AND NOT EXISTS (
    SELECT 1
    FROM Sales.SalesOrderHeader s25
    WHERE s25.CustomerID = c.CustomerID
      AND s25.OrderDate >= '2025-01-01'
      AND s25.OrderDate <  '2026-01-01'
)
GROUP BY c.CustomerID
ORDER BY lifetime_revenue DESC;


-- ------------------------------------------------------------
--  RFM metrics
-- ------------------------------------------------------------

WITH rfm_base AS (
    SELECT
        CustomerID,
        DATEDIFF(day, MAX(OrderDate), GETDATE()) AS recency_days,
        COUNT(SalesOrderID)                       AS frequency,
        SUM(TotalDue)                             AS monetary
    FROM Sales.SalesOrderHeader
    GROUP BY CustomerID
),

rfm_scored AS (
    SELECT
        CustomerID,
        recency_days,
        frequency,
        monetary,

        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
       
        NTILE(5) OVER (ORDER BY frequency ASC)     AS f_score,
       
        NTILE(5) OVER (ORDER BY monetary ASC)      AS m_score
    FROM rfm_base
),

rfm_labeled AS (
    SELECT
        CustomerID,
        recency_days,
        frequency,
        ROUND(monetary, 2)        AS monetary,
        r_score,
        f_score,
        m_score,
        r_score + f_score + m_score AS rfm_combined
    FROM rfm_scored
)

SELECT
    CustomerID,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    rfm_combined,

    CASE
        WHEN rfm_combined >= 13                        THEN 'Champion'
        WHEN rfm_combined BETWEEN 10 AND 12            THEN 'Loyal'
        WHEN rfm_combined BETWEEN 7  AND 9             THEN 'Promising'
        WHEN rfm_combined BETWEEN 4  AND 6             THEN 'At Risk'
        WHEN rfm_combined <= 3                         THEN 'Lost'
    END AS rfm_segment

FROM rfm_labeled
ORDER BY rfm_combined DESC;
GO

-- ---------------------------------------------------
-- Create View 
-- ---------------------------------------------------
CREATE OR ALTER VIEW dim_customer_segment AS

WITH rfm_base AS (
    SELECT
        CustomerID,
        DATEDIFF(day, MAX(OrderDate), GETDATE()) AS recency_days,
        COUNT(SalesOrderID)                       AS frequency,
        SUM(TotalDue)                             AS monetary
    FROM Sales.SalesOrderHeader
    GROUP BY CustomerID
),

rfm_scored AS (
    SELECT
        CustomerID,
        recency_days,
        frequency,
        monetary,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC)     AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC)      AS m_score
    FROM rfm_base
),

rfm_labeled AS (
    SELECT
        CustomerID,
        recency_days,
        frequency,
        ROUND(monetary, 2)          AS monetary,
        r_score,
        f_score,
        m_score,
        r_score + f_score + m_score AS rfm_combined
    FROM rfm_scored
)

SELECT
    rl.CustomerID,
    dc.CustomerName,
    dc.CustomerType,
    rl.r_score,
    rl.f_score,
    rl.m_score,
    rl.rfm_combined,
    rl.recency_days,
    rl.frequency,
    rl.monetary,

    CASE
        WHEN rl.rfm_combined >= 13                 THEN 'Champion'
        WHEN rl.rfm_combined BETWEEN 10 AND 12     THEN 'Loyal'
        WHEN rl.rfm_combined BETWEEN 7  AND 9      THEN 'Promising'
        WHEN rl.rfm_combined BETWEEN 4  AND 6      THEN 'At Risk'
        WHEN rl.rfm_combined <= 3                  THEN 'Lost'
    END AS rfm_segment

FROM rfm_labeled rl
JOIN dim_customer dc
    ON rl.CustomerID = dc.CustomerID;
GO


SELECT
    dc.CustomerType,
    COUNT(DISTINCT dc.CustomerID)           AS customer_count,
    COUNT(soh.SalesOrderID)                 AS total_orders,
    ROUND(AVG(CAST(order_counts.order_count 
        AS FLOAT)), 2)                      AS avg_orders_per_customer,
    ROUND(AVG(soh.TotalDue), 2)             AS avg_order_value,
    ROUND(SUM(soh.TotalDue), 0)             AS total_revenue
FROM dim_customer dc
JOIN Sales.SalesOrderHeader soh
    ON dc.CustomerID = soh.CustomerID
JOIN (
    SELECT CustomerID, COUNT(SalesOrderID) AS order_count
    FROM Sales.SalesOrderHeader
    GROUP BY CustomerID
) AS order_counts
    ON dc.CustomerID = order_counts.CustomerID
GROUP BY dc.CustomerType
ORDER BY avg_orders_per_customer DESC;
GO

-- ------------------------------------------------------------
--  How are Store vs Person customers distributed
--  across RFM segments?
-- ------------------------------------------------------------
SELECT
    dc.CustomerType,
    dcs.rfm_segment,
    COUNT(*)                                        AS customer_count,
    ROUND(COUNT(*) * 100.0 / 
        SUM(COUNT(*)) OVER (PARTITION BY dc.CustomerType), 1) AS pct_within_type
FROM dim_customer_segment dcs
JOIN dim_customer dc
    ON dcs.CustomerID = dc.CustomerID
GROUP BY
    dc.CustomerType,
    dcs.rfm_segment
ORDER BY
    dc.CustomerType,
    customer_count DESC;
    GO



 ------------------------------------------------------------
  Do store customers actually order more frequently?
  Compare avg orders and revenue by CustomerType
 ------------------------------------------------------------
SELECT
    dc.CustomerType,
    COUNT(DISTINCT dc.CustomerID)           AS customer_count,
    COUNT(soh.SalesOrderID)                 AS total_orders,
    ROUND(AVG(CAST(order_counts.order_count 
        AS FLOAT)), 2)                      AS avg_orders_per_customer,
    ROUND(AVG(soh.TotalDue), 2)             AS avg_order_value,
    ROUND(SUM(soh.TotalDue), 0)             AS total_revenue
FROM dim_customer dc
JOIN Sales.SalesOrderHeader soh
    ON dc.CustomerID = soh.CustomerID
JOIN (
    SELECT CustomerID, COUNT(SalesOrderID) AS order_count
    FROM Sales.SalesOrderHeader
    GROUP BY CustomerID
) AS order_counts
    ON dc.CustomerID = order_counts.CustomerID
GROUP BY dc.CustomerType
ORDER BY avg_orders_per_customer DESC;
GO




