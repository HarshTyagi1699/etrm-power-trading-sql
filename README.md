# Power Trading ETRM/CTRM Database & Production Support SQL Suite

## Overview
This project implements a relational **Energy & Commodity Trading and Risk Management (ETRM/CTRM)** database in **MySQL**, modeling the physical bilateral power trading lifecycle from Front-Office deal capture through Middle-Office risk valuation and Back-Office settlement.

It is specifically designed to simulate real-world **ETRM Production Support & Operations Analyst** workflows, including End-of-Day (EOD) batch price validation, daily Mark-to-Market (MtM) P&L calculations, market risk stress testing, credit exposure tracking, and automated front-to-back office reconciliation break detection.

---

## Database Architecture (`schema.sql`)

The database (`ctrm_power_db`) consists of four normalized tables linked via foreign keys and protected by domain integrity constraints (`CHECK` and `ENUM`):

1. **`counterparty` (Reference Data / Master Table)**
   * Stores master data and trading roles (`Buy` / `Sell`) for Indian market participants (**Reliance, Croma, Vijaysales, Tata, Adani**).
2. **`trade` (Front-Office Deal Capture)**
   * Captures bilateral physical power trades (`quantity_mw`, `price`, `delivery_date`) using self-referencing foreign keys (`buyer_id`, `seller_id`) linked to `counterparty`.
   * Tracks real-time physical lifecycle statuses: `Scheduled`, `Flowing`, `Completed`, and `Cancelled`.
3. **`settlement` (Back-Office Invoicing & Accounting)**
   * Tracks generated invoices (`invoice_amount`) and settlement states (`Pending`, `Paid`, `Voided`) mapped to individual trades.
   * Contains intentional production data anomalies to test SQL reconciliation scripts.
4. **`market_price` (Middle-Office EOD Price Curve)**
   * Stores daily End-of-Day (`valuation_date`, `closing_price`) power market settlement curves used for Mark-to-Market valuation.

---

## Production Support & Risk Analytics Queries (`query.sql`)

### 1. Counterparty Credit Exposure & Risk Concentration (`CTE` + `Window Functions`)
* **Business Problem:** Credit Risk teams need to monitor unsettled financial exposure (`Pending` invoices) per buyer while ensuring cancelled trades are excluded from exposure totals.
* **SQL Techniques:** Common Table Expressions (`WITH`), `INNER JOIN`, `SUM() OVER ()` for portfolio exposure share, and `RANK() OVER ()` for risk ranking.

### 2. Daily Mark-to-Market (MtM) Valuation (Buyer vs. Seller Book)
* **Business Problem:** Calculate unrealized daily P&L on active open positions (`Scheduled` and `Flowing`) against EOD market closing prices from both the buyer's and seller's perspectives.
* **Formula:**
  * $\text{Buyer MtM} = (\text{Closing Price} - \text{Contract Price}) \times \text{Quantity (MW)}$
  * $\text{Seller MtM} = (\text{Contract Price} - \text{Closing Price}) \times \text{Quantity (MW)}$

### 3. Portfolio-Level MtM P&L Summary
* **Business Problem:** Aggregate net volume (MW) and unrealized P&L across trade lifecycle statuses (`Scheduled`, `Flowing`, `Completed`) for EOD management reporting.

### 4. Market Risk Stress Testing (20% Price Shock Scenario)
* **Business Problem:** Simulate the impact of a sudden **20% drop in market power prices** on open trading positions to evaluate downside Value-at-Risk (VaR) shock.
* **SQL Techniques:** Explicit `CROSS JOIN` against target valuation dates with scenario arithmetic.

### 5. Front-to-Back Office Reconciliation Break Detection (`LEFT JOIN` + `CASE`)
* **Business Problem:** In a live ETRM environment, synchronization failures between Front Office (trade capture) and Back Office (settlements) cause financial discrepancies.
* **What This Query Catches Automatically:**
  * **Critical Break (Trade #3):** A trade marked `Cancelled` in Front Office that still has an active `Pending` invoice of ₹75,000 in Back Office.
  * **Amount Mismatch (Trade #5):** A trade where the Back-Office invoice (`₹85,000`) does not match the Front-Office contract value (`500 MW * ₹180 = ₹90,000`).
  * **Missing Invoice (Trade #6):** An active scheduled trade that has not yet generated a settlement record in Back Office.

### 6. EOD Batch Pre-Check: Missing Price Curve Alert (`LEFT JOIN ... IS NULL`)
* **Business Problem:** EOD valuation batch runs fail if an active trade's delivery date is missing a corresponding closing price in the `market_price` table.
* **What This Query Catches:** Flags **Trade #6 (`delivery_date = 2026-11-15`)** prior to EOD batch execution because its market price curve has not been loaded yet.
