# AdventureWorks 2025 — Sales & Customer Analytics Project

A full-cycle analytics project built on Microsoft's AdventureWorks 2025 database, covering data modeling, SQL analysis, RFM customer segmentation, and executive Power BI dashboards.

![Executive Overview](executive_overview.png)
![Customer Overview](customer_overview.png)

---

## Project Overview

Adventure Works Cycles is a fictitious multinational bicycle manufacturer. This project transforms their transactional SQL Server database into a structured star schema, performs sales and customer behavior analysis, and delivers two interactive Power BI dashboards for executive and customer-level reporting.

**Tools used:** SQL Server · Power BI · T-SQL · Git

---

## Repository Structure

```
adventureworks-analytics/
│
├── sql/
│   ├── views.sql               # Dimension and fact views (star schema)
│   ├── analysis_queries.sql    # Analytical challenge queries (6 total)
│   ├── rfm_segmentation.sql    # RFM scoring and dim_customer_segment view
│   └── validation_queries.sql  # Dashboard KPI validation queries
│
├── documentation/
│   └── project_phases.md       # Phase-by-phase project documentation
│
├── dashboards/
│   ├── executive_overview.png  # Sales Performance dashboard screenshot
│   └── customer_overview.png   # Customer Segmentation dashboard screenshot
│
└── README.md
```

---

## Phase 1 — Data Familiarity

- Connected AdventureWorks 2025 to SQL Server and explored tables across Sales, Production, Purchasing, HumanResources, and Person schemas
- Generated image maps of key tables, documenting primary keys, foreign keys, and relationships
- Identified grain of key tables — `SalesOrderDetail` is at the order line level; `SalesOrderHeader` is at the order level
- Determined star schema structure: one fact table for sales, with dimension tables for customer, product, and territory
- Performed exploratory `SELECT *` queries to understand column context and validate relationships
- Identified 701 orphaned customer records — customers in `Sales.Customer` with no corresponding entry in `Person.Person` (documented as a data quality finding)
- Discovered a CustomerType misclassification bug: customers with both a `PersonID` and `StoreID` were being labeled as "Person" due to CASE statement ordering — corrected by checking `StoreID` first

---

## Phase 2 — Sales Analysis

Built six analytical SQL queries covering:

| # | Question |
|---|----------|
| 1 | Top 10 customers by total revenue |
| 2 | Revenue and percent of total by product subcategory |
| 3 | Monthly revenue trend with prior-month comparison and rolling 3-month total |
| 4 | Best sales day of each month |
| 5 | Order volume and revenue by day of week |
| 6 | Customers who ordered in 2024 but not 2025 (lapsed customer foundation) |

**Key techniques used:** CTEs, window functions (`LAG`, `ROW_NUMBER`, `DENSE_RANK`, `NTILE`), rolling aggregations, `EXISTS` / `NOT EXISTS` subqueries, date functions

---

## Phase 3 — Customer Segmentation

### Customer Type Classification
Customers were classified into two types by checking `StoreID` before `PersonID` in the CASE logic:
- **Store (B2B):** 635 accounts — reseller/wholesale buyers
- **Person (B2C):** 18,484 individual consumers

### RFM Scoring
Each customer was scored independently on three dimensions using `NTILE(5)` (1–5 per metric, 3–15 combined):

| Metric | Definition | Scoring Direction |
|--------|------------|-------------------|
| Recency | Days since last order | Fewer days = higher score |
| Frequency | Total number of orders | More orders = higher score |
| Monetary | Total revenue generated | More revenue = higher score |

### Segment Labels

| Segment | Combined Score | Description |
|---------|---------------|-------------|
| Champion | 13–15 | High value, frequent, recent |
| Loyal | 10–12 | Strong across all three metrics |
| Promising | 7–9 | Moderate engagement |
| At Risk | 4–6 | Declining engagement |
| Lost | 3 | Low across all metrics |

---

## Phase 4 — Power BI Dashboards

### Executive Overview
Covers overall sales performance from 2022 through mid-2025.

**KPIs:** Total Sales ($110M) · Total Orders (31K) · Total Quantity (275K) · Avg Order Value ($3K) · YoY Growth (22%)

**Key findings:**
- Sales grew 22% year over year
- Q2 and Q3 consistently outperform, with an average 15% decline from Q3 to Q4 — a predictable seasonal pattern consistent across all years
- Bikes comprise 86% of revenue at $95M; Mountain-200 variants occupy all top 5 product slots
- Southwest territory leads with 22% of total sales ($24M)
- Note: 2025 Q2 data is incomplete (missing June 30) and may understate current quarter totals

### Customer Overview
Covers customer segmentation and behavior analysis.

**KPIs:** Total Customers (19.12K) · Avg Customer Spend ($6.44K) · Avg Orders Per Customer (1.65) · Avg Recency (517 days) · Repeat Purchase Rate (39.07%)

**Key findings:**
- Store accounts are 3% of customers but generate 74% of total revenue ($90.8M), with an avg order value of $23,850 — 20x higher than individual buyers ($1,173)
- 70% of store accounts are Champions; B2B relationships are healthy and highly concentrated
- Avg recency of 517 days reflects AdventureWorks' long consumer purchase cycle — frequent buyers are confirmed B2B reseller accounts (7.51 avg orders vs 2.31 for individuals)
- 49% of individual customers are At Risk or Promising — a re-engagement opportunity with demonstrated purchase history
- 701 customers exist on record but have never placed an order — potential lead nurturing opportunity

---

## Phase 5 — Validation

All dashboard KPI cards were validated by running equivalent SQL queries directly against the database. Key finding: Total Customers KPI was corrected to pull from `fact_sales` (customers who have purchased) rather than `dim_customer` (all customers on record), as the latter includes 701 non-purchasing records that should not factor into behavioral metrics.

| KPI | SQL Result | Dashboard | Status |
|-----|-----------|-----------|--------|
| Total Customers | 19,119 | 19.12K | ✅ |
| Avg Customer Spend | $6,444.73 | $6.44K | ✅ |
| Avg Recency (days) | 517.27 | 517.27 | ✅ |
| Repeat Purchase Rate | 39.07% | 39.07% | ✅ |
| Champion Revenue | $86.9M | ~$75M* | ✅ |

*Dashboard figure reflects filtered date range; SQL query runs against full dataset.

---

## Star Schema Design

```
                    dim_customer
                         │
dim_territory ──── fact_sales ──── dim_product
                         │
                    (OrderDate)
```

`fact_sales` is at the order line grain, joining `Sales.SalesOrderDetail` and `Sales.SalesOrderHeader`. Dimension views flatten subcategory/category hierarchies to avoid snowflaking.

---

## How to Run

1. Restore AdventureWorks 2025 to SQL Server
2. Run `sql/views.sql` to create all dimension and fact views
3. Run `sql/rfm_segmentation.sql` to create `dim_customer_segment`
4. Connect Power BI to your SQL Server instance and import the views
5. Use `sql/validation_queries.sql` to verify dashboard KPI values

---

## Author

Built as a portfolio project demonstrating end-to-end analytics skills: data modeling, T-SQL, business analysis, and data visualization.
