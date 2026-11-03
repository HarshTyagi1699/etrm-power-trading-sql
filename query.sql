USE ctrm_power_db;

-- QUERY 1: Unsettled Credit Exposure + % Share of Risk (Uses: CTE + Window Function) 

WITH buyer_exposure AS (
    SELECT 
        c.company_name AS buyer_name,
        COUNT(t.trade_id) AS unsettled_trades,
        SUM(s.invoice_amount) AS total_exposure
    FROM trade AS t
    INNER JOIN settlement AS s ON t.trade_id = s.trade_id
    INNER JOIN counterparty AS c ON t.buyer_id = c.company_id
    WHERE s.payment_status = 'Pending'
      AND t.status != 'Cancelled'
    GROUP BY buyer_name
)
SELECT 
    buyer_name,
    unsettled_trades,
    total_exposure,
    ROUND((total_exposure / SUM(total_exposure) OVER ()) * 100, 2) AS exposure_percentage,
    RANK() OVER (ORDER BY total_exposure DESC) AS risk_rank
FROM buyer_exposure;

-- QUERY 2: Daily Mark-to-Market (MtM) Valuation for Both Buyer & Seller

SELECT 
    t.trade_id,
    b.company_name AS buyer,
    s.company_name AS seller,
    t.delivery_date,
    t.quantity_mw,
    t.price AS contract_price,
    mp.closing_price AS eod_market_price,
    -- If market price > contract price, Buyer profits and Seller loses
    (mp.closing_price - t.price) * t.quantity_mw AS buyer_mtm_pnl,
    (t.price - mp.closing_price) * t.quantity_mw AS seller_mtm_pnl
FROM trade AS t
INNER JOIN market_price AS mp ON t.delivery_date = mp.valuation_date
INNER JOIN counterparty AS b ON t.buyer_id = b.company_id
INNER JOIN counterparty AS s ON t.seller_id = s.company_id
WHERE t.status IN ('Scheduled', 'Flowing');

-- QUERY 3: MtM P&L Summary by Trade Status

SELECT 
    t.status,
    COUNT(t.trade_id) AS total_trades,
    SUM(t.quantity_mw) AS total_volume_mw,
    SUM((mp.closing_price - t.price) * t.quantity_mw) AS net_buyer_portfolio_mtm
FROM trade AS t
INNER JOIN market_price AS mp ON t.delivery_date = mp.valuation_date
WHERE t.status != 'Cancelled'
GROUP BY t.status;

-- QUERY 4: Market Risk Stress Test (20% Price Drop Shock on Open Positions)

SELECT 
    t.trade_id,
    t.status,
    t.quantity_mw,
    t.price AS contract_price,
    mp.closing_price AS current_market_price,
    ROUND(mp.closing_price * 0.80, 2) AS stressed_price_20pct_drop,
    (mp.closing_price - t.price) * t.quantity_mw AS base_buyer_mtm,
    ROUND(((mp.closing_price * 0.80) - t.price) * t.quantity_mw, 2) AS stressed_buyer_mtm
FROM trade AS t
CROSS JOIN market_price AS mp
WHERE mp.valuation_date = '2026-11-01'
  AND t.status IN ('Scheduled', 'Flowing');

-- QUERY 5: PRODUCTION SUPPORT - Front-to-Back Office Reconciliation Breaks
-- Catches: (1) Cancelled trades with active invoices.
--  		(2) Invoice math mismatches.
--          (3) Active trades missing an invoice entirely.

SELECT 
    t.trade_id,
    t.status AS front_office_status,
    (t.quantity_mw * t.price) AS expected_trade_value,
    s.invoice_id,
    s.invoice_amount AS back_office_invoice,
    s.payment_status,
    CASE 
        WHEN t.status = 'Cancelled' AND s.payment_status = 'Pending' 
            THEN 'CRITICAL BREAK: Cancelled trade still has Pending invoice'
        WHEN s.invoice_id IS NULL AND t.status != 'Cancelled' 
            THEN 'MISSING INVOICE: Active trade not yet generated in Back Office'
        WHEN s.invoice_amount != (t.quantity_mw * t.price) 
            THEN 'AMOUNT MISMATCH: Invoice does not match Quantity * Price'
        ELSE 'OK'
    END AS reconciliation_status
FROM trade AS t
LEFT JOIN settlement AS s ON t.trade_id = s.trade_id
WHERE (t.status = 'Cancelled' AND s.payment_status = 'Pending')
   OR (s.invoice_id IS NULL AND t.status != 'Cancelled')
   OR (s.invoice_amount != (t.quantity_mw * t.price));

-- QUERY 6: EOD BATCH SUPPORT - Missing Market Price Curve Check (LEFT JOIN + IS NULL)

SELECT 
    t.trade_id,
    b.company_name AS buyer,
    t.delivery_date,
    t.quantity_mw,
    t.status,
    'EOD BATCH EXCEPTION: Missing closing price for delivery date' AS error_alert
FROM trade AS t
LEFT JOIN market_price AS mp ON t.delivery_date = mp.valuation_date
INNER JOIN counterparty AS b ON t.buyer_id = b.company_id
WHERE mp.closing_price IS NULL
  AND t.status IN ('Scheduled', 'Flowing');