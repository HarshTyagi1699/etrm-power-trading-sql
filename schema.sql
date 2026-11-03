CREATE DATABASE IF NOT EXISTS ctrm_power_db;
USE ctrm_power_db;

DROP TABLE IF EXISTS settlement;
DROP TABLE IF EXISTS trade;
DROP TABLE IF EXISTS market_price;
DROP TABLE IF EXISTS counterparty;

-- 1. Counterparty Master Table (Reference Data)

CREATE TABLE counterparty (
    company_id INT AUTO_INCREMENT PRIMARY KEY,
    company_code VARCHAR(10) NOT NULL UNIQUE,
    company_name VARCHAR(30) NOT NULL,
    role ENUM('Buy', 'Sell') NOT NULL
);

INSERT INTO counterparty (company_code, company_name, `role`) VALUES 
('REL', 'Reliance', 'Buy'),
('CRO', 'Croma', 'Buy'),
('VJS', 'Vijaysales', 'Buy'),
('TA', 'Tata', 'Sell'),
('ADA', 'Adani', 'Sell');

-- 2. Front-Office Trade Capture Table

CREATE TABLE trade (
    trade_id INT AUTO_INCREMENT PRIMARY KEY,
    buyer_id INT NOT NULL,
    seller_id INT NOT NULL,
    quantity_mw INT NOT NULL CHECK (quantity_mw > 0),
    price DECIMAL(10,2) NOT NULL CHECK (price > 0),
    delivery_date DATE NOT NULL,
    status ENUM('Scheduled', 'Flowing', 'Completed', 'Cancelled') NOT NULL,
    FOREIGN KEY (buyer_id) REFERENCES counterparty(company_id),
    FOREIGN KEY (seller_id) REFERENCES counterparty(company_id)
);

INSERT INTO trade (buyer_id, seller_id, quantity_mw, price, delivery_date, status) VALUES
-- Trade 1: Tata sells to Reliance (Expected Invoice = 200 * 250 = 50,000)
(1, 4, 200, 250.00, '2026-11-02', 'Scheduled'),
-- Trade 2: Adani sells to Reliance (Expected Invoice = 100 * 300 = 30,000)
(1, 5, 100, 300.00, '2026-10-31', 'Flowing'),
-- Trade 3: Adani sells to Vijaysales - CANCELLED (Should NOT have an active invoice!)
(3, 5, 500, 150.00, '2026-11-02', 'Cancelled'),
-- Trade 4: Tata sells to Croma (Expected Invoice = 500 * 200 = 100,000)
(2, 4, 500, 200.00, '2026-10-31', 'Completed'),
-- Trade 5: Adani sells to Croma (Expected Invoice = 500 * 180 = 90,000)
(2, 5, 500, 180.00, '2026-11-01', 'Scheduled'),
-- Trade 6: Tata sells to Reliance for a future date where EOD price curve is NOT loaded yet
(1, 4, 300, 215.00, '2026-11-15', 'Scheduled');

-- 3. Back-Office Settlement & Invoicing Table

CREATE TABLE settlement (
    invoice_id INT AUTO_INCREMENT PRIMARY KEY,
    trade_id INT NOT NULL,
    invoice_amount DECIMAL(12,2) NOT NULL,
    payment_status ENUM('Pending', 'Paid', 'Voided') NOT NULL,
    FOREIGN KEY (trade_id) REFERENCES trade(trade_id)
);

INSERT INTO settlement (trade_id, invoice_amount, payment_status) VALUES 
(1, 50000.00, 'Pending'),
(2, 30000.00, 'Pending'),
-- Break #1: Trade 3 was Cancelled in Front Office, but Back Office still has it as 'Pending'!
(3, 75000.00, 'Pending'),
(4, 100000.00, 'Paid'),
-- Break #2: Trade 5 should be 90,000 (500 * 180), but Back Office billed 85,000!
(5, 85000.00, 'Pending');

-- 4. Middle-Office EOD Market Price Curve Table

CREATE TABLE market_price (
    valuation_date DATE PRIMARY KEY,
    closing_price DECIMAL(10,2) NOT NULL
);

INSERT INTO market_price (valuation_date, closing_price) VALUES 
('2026-10-31', 210.00),
('2026-11-01', 220.00),
('2026-11-02', 195.00);