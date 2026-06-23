-- ============================================================
-- ACCOUNTS PAYABLE ANALYSIS — 2024
-- Author: Griselda Verónica Cuello
-- Tools: SQL (SQLite), Excel
-- Dataset: 261 synthetic invoices · 20 vendors · FY 2024
-- ============================================================

-- ============================================================
-- 0. SETUP: Create tables and load data
-- ============================================================

CREATE TABLE IF NOT EXISTS vendors (
    vendor_id          TEXT PRIMARY KEY,
    vendor_name        TEXT NOT NULL,
    category           TEXT,
    has_cc             TEXT,   -- 'Yes' / 'No'
    payment_terms_days INTEGER
);

CREATE TABLE IF NOT EXISTS invoices (
    invoice_id         TEXT PRIMARY KEY,
    vendor_id          TEXT REFERENCES vendors(vendor_id),
    vendor_name        TEXT,
    category           TEXT,
    has_cc             TEXT,
    payment_terms_days INTEGER,
    invoice_date       DATE,
    due_date           DATE,
    amount_usd         REAL,
    payment_date       DATE,
    status             TEXT,   -- 'Paid', 'Paid Late', 'Pending', 'Overdue'
    days_late          INTEGER
);

-- ============================================================
-- 1. PORTFOLIO OVERVIEW
--    High-level summary of total AP activity for FY 2024
-- ============================================================

SELECT
    COUNT(*)                                      AS total_invoices,
    COUNT(DISTINCT vendor_id)                     AS total_vendors,
    ROUND(SUM(amount_usd), 2)                     AS total_billed_usd,
    ROUND(AVG(amount_usd), 2)                     AS avg_invoice_usd,
    ROUND(MIN(amount_usd), 2)                     AS min_invoice_usd,
    ROUND(MAX(amount_usd), 2)                     AS max_invoice_usd,
    COUNT(CASE WHEN status = 'Paid' THEN 1 END)   AS paid_on_time,
    COUNT(CASE WHEN status = 'Paid Late' THEN 1 END) AS paid_late,
    COUNT(CASE WHEN status = 'Overdue' THEN 1 END)   AS overdue,
    COUNT(CASE WHEN status = 'Pending' THEN 1 END)   AS pending
FROM invoices;

-- ============================================================
-- 2. PAYMENT STATUS BREAKDOWN
--    Distribution of invoice statuses with totals
-- ============================================================

SELECT
    status,
    COUNT(*)                             AS invoice_count,
    ROUND(SUM(amount_usd), 2)           AS total_usd,
    ROUND(AVG(amount_usd), 2)           AS avg_usd,
    ROUND(100.0 * COUNT(*) /
          (SELECT COUNT(*) FROM invoices), 1) AS pct_of_total
FROM invoices
GROUP BY status
ORDER BY invoice_count DESC;

-- ============================================================
-- 3. TOP 10 VENDORS BY SPEND
--    Identify highest-value supplier relationships
-- ============================================================

SELECT
    v.vendor_id,
    v.vendor_name,
    v.category,
    v.has_cc,
    v.payment_terms_days,
    COUNT(i.invoice_id)                  AS invoice_count,
    ROUND(SUM(i.amount_usd), 2)         AS total_spend_usd,
    ROUND(AVG(i.amount_usd), 2)         AS avg_invoice_usd,
    ROUND(100.0 * SUM(i.amount_usd) /
          (SELECT SUM(amount_usd) FROM invoices), 1) AS pct_total_spend
FROM vendors v
JOIN invoices i ON v.vendor_id = i.vendor_id
GROUP BY v.vendor_id
ORDER BY total_spend_usd DESC
LIMIT 10;

-- ============================================================
-- 4. ACCOUNTS PAYABLE AGING REPORT
--    Classifies outstanding balances by overdue bucket
--    Standard aging: Current / 1-30 / 31-60 / 61-90 / 90+
-- ============================================================

SELECT
    vendor_name,
    SUM(CASE WHEN status = 'Pending'
             THEN amount_usd ELSE 0 END)             AS current_usd,
    SUM(CASE WHEN status = 'Overdue' AND days_late BETWEEN 1  AND 30
             THEN amount_usd ELSE 0 END)             AS overdue_1_30_usd,
    SUM(CASE WHEN status = 'Overdue' AND days_late BETWEEN 31 AND 60
             THEN amount_usd ELSE 0 END)             AS overdue_31_60_usd,
    SUM(CASE WHEN status = 'Overdue' AND days_late BETWEEN 61 AND 90
             THEN amount_usd ELSE 0 END)             AS overdue_61_90_usd,
    SUM(CASE WHEN status = 'Overdue' AND days_late > 90
             THEN amount_usd ELSE 0 END)             AS overdue_90plus_usd,
    ROUND(SUM(CASE WHEN status IN ('Pending','Overdue')
              THEN amount_usd ELSE 0 END), 2)        AS total_outstanding_usd
FROM invoices
GROUP BY vendor_name
HAVING total_outstanding_usd > 0
ORDER BY total_outstanding_usd DESC;

-- ============================================================
-- 5. LATE PAYMENT ANALYSIS BY VENDOR
--    Which vendors are most affected by delayed payments?
-- ============================================================

SELECT
    vendor_name,
    category,
    COUNT(*)                                         AS total_invoices,
    COUNT(CASE WHEN status = 'Paid Late' THEN 1 END) AS late_payments,
    ROUND(100.0 * COUNT(CASE WHEN status = 'Paid Late' THEN 1 END)
          / COUNT(*), 1)                             AS late_rate_pct,
    ROUND(AVG(CASE WHEN status = 'Paid Late'
              THEN days_late END), 1)                AS avg_days_late,
    MAX(days_late)                                   AS max_days_late
FROM invoices
GROUP BY vendor_name, category
HAVING total_invoices >= 3
ORDER BY late_rate_pct DESC
LIMIT 10;

-- ============================================================
-- 6. MONTHLY SPEND TREND
--    How does AP volume evolve throughout the year?
-- ============================================================

SELECT
    SUBSTR(invoice_date, 1, 7)           AS month,
    COUNT(*)                             AS invoice_count,
    ROUND(SUM(amount_usd), 2)           AS total_billed_usd,
    ROUND(AVG(amount_usd), 2)           AS avg_invoice_usd,
    COUNT(CASE WHEN status IN ('Overdue','Paid Late') THEN 1 END) AS late_or_overdue
FROM invoices
GROUP BY month
ORDER BY month;

-- ============================================================
-- 7. SPEND BY CATEGORY
--    Where does the AP budget go? Category breakdown.
-- ============================================================

SELECT
    category,
    COUNT(DISTINCT vendor_id)            AS vendor_count,
    COUNT(*)                             AS invoice_count,
    ROUND(SUM(amount_usd), 2)           AS total_spend_usd,
    ROUND(AVG(amount_usd), 2)           AS avg_invoice_usd,
    ROUND(100.0 * SUM(amount_usd) /
          (SELECT SUM(amount_usd) FROM invoices), 1) AS pct_total_spend
FROM invoices
GROUP BY category
ORDER BY total_spend_usd DESC;

-- ============================================================
-- 8. CC vs NON-CC VENDOR COMPARISON
--    Do vendors with current accounts behave differently?
-- ============================================================

SELECT
    has_cc                                           AS current_account,
    COUNT(DISTINCT vendor_id)                        AS vendor_count,
    COUNT(*)                                         AS total_invoices,
    ROUND(SUM(amount_usd), 2)                       AS total_spend_usd,
    ROUND(AVG(amount_usd), 2)                       AS avg_invoice_usd,
    COUNT(CASE WHEN status = 'Paid' THEN 1 END)     AS paid_on_time,
    COUNT(CASE WHEN status = 'Paid Late' THEN 1 END) AS paid_late,
    COUNT(CASE WHEN status = 'Overdue' THEN 1 END)  AS overdue,
    ROUND(100.0 * COUNT(CASE WHEN status IN ('Paid Late','Overdue') THEN 1 END)
          / COUNT(*), 1)                             AS late_overdue_pct
FROM invoices
GROUP BY has_cc;

-- ============================================================
-- 9. OVERDUE INVOICES DETAIL
--    Full list of unpaid invoices past due date
-- ============================================================

SELECT
    invoice_id,
    vendor_name,
    category,
    invoice_date,
    due_date,
    ROUND(amount_usd, 2)                AS amount_usd,
    julianday('2024-12-31') - julianday(due_date) AS days_overdue,
    CASE
        WHEN julianday('2024-12-31') - julianday(due_date) <= 30  THEN '1-30 days'
        WHEN julianday('2024-12-31') - julianday(due_date) <= 60  THEN '31-60 days'
        WHEN julianday('2024-12-31') - julianday(due_date) <= 90  THEN '61-90 days'
        ELSE '90+ days'
    END                                 AS aging_bucket
FROM invoices
WHERE status = 'Overdue'
ORDER BY days_overdue DESC;

-- ============================================================
-- 10. PAYMENT EFFICIENCY SCORE PER VENDOR
--     Composite metric: % on-time · avg days late · total spend
--     Useful for vendor risk scoring
-- ============================================================

SELECT
    vendor_name,
    category,
    has_cc,
    COUNT(*)                                         AS total_invoices,
    ROUND(SUM(amount_usd), 2)                       AS total_spend_usd,
    ROUND(100.0 * COUNT(CASE WHEN status = 'Paid' THEN 1 END)
          / COUNT(*), 1)                             AS on_time_pct,
    ROUND(COALESCE(AVG(CASE WHEN days_late > 0 THEN days_late END), 0), 1) AS avg_days_late,
    CASE
        WHEN 100.0 * COUNT(CASE WHEN status = 'Paid' THEN 1 END) / COUNT(*) >= 85 THEN 'A — Excellent'
        WHEN 100.0 * COUNT(CASE WHEN status = 'Paid' THEN 1 END) / COUNT(*) >= 65 THEN 'B — Good'
        WHEN 100.0 * COUNT(CASE WHEN status = 'Paid' THEN 1 END) / COUNT(*) >= 45 THEN 'C — Fair'
        ELSE 'D — Needs Review'
    END                                              AS payment_grade
FROM invoices
GROUP BY vendor_name, category, has_cc
ORDER BY on_time_pct DESC, total_spend_usd DESC;
