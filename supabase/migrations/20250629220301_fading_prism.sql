/*
  # Add Analytics and Reporting Features

  1. New Tables
    - `daily_sales_summary` - Daily aggregated sales data
    - `menu_item_analytics` - Track menu item performance
    - `customer_feedback` - Store customer reviews and ratings
    - `promotional_campaigns` - Manage discounts and promotions

  2. Views
    - `popular_items_view` - Most ordered items
    - `revenue_trends_view` - Revenue analysis over time
    - `low_stock_alerts_view` - Items running low

  3. Functions
    - Daily sales aggregation function
    - Menu item popularity calculation
*/

-- Create customer feedback table
CREATE TABLE IF NOT EXISTS customer_feedback (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  order_id uuid REFERENCES orders(id) ON DELETE SET NULL,
  customer_name text,
  customer_email text,
  rating integer CHECK (rating >= 1 AND rating <= 5),
  feedback_text text,
  feedback_type text CHECK (feedback_type IN ('food', 'service', 'ambiance', 'overall')),
  is_public boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

-- Create promotional campaigns table
CREATE TABLE IF NOT EXISTS promotional_campaigns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text,
  discount_type text CHECK (discount_type IN ('percentage', 'fixed_amount', 'buy_one_get_one')),
  discount_value numeric(10,2),
  minimum_order_amount numeric(10,2),
  start_date timestamptz NOT NULL,
  end_date timestamptz NOT NULL,
  is_active boolean DEFAULT true,
  usage_limit integer,
  current_usage integer DEFAULT 0,
  applicable_items uuid[], -- array of menu_item_ids
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create daily sales summary table
CREATE TABLE IF NOT EXISTS daily_sales_summary (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  date date NOT NULL,
  total_orders integer DEFAULT 0,
  total_revenue numeric(12,2) DEFAULT 0,
  average_order_value numeric(10,2) DEFAULT 0,
  most_popular_item_id uuid REFERENCES menu_items(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(restaurant_id, date)
);

-- Create menu item analytics table
CREATE TABLE IF NOT EXISTS menu_item_analytics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  menu_item_id uuid NOT NULL REFERENCES menu_items(id) ON DELETE CASCADE,
  date date NOT NULL,
  times_ordered integer DEFAULT 0,
  total_quantity integer DEFAULT 0,
  total_revenue numeric(10,2) DEFAULT 0,
  average_rating numeric(3,2),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(menu_item_id, date)
);

-- Add new columns to orders table for better analytics
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'orders' AND column_name = 'order_source'
  ) THEN
    ALTER TABLE orders ADD COLUMN order_source text DEFAULT 'qr_code' CHECK (order_source IN ('qr_code', 'staff', 'phone', 'online'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'orders' AND column_name = 'preparation_time'
  ) THEN
    ALTER TABLE orders ADD COLUMN preparation_time integer; -- actual time taken in minutes
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'orders' AND column_name = 'customer_rating'
  ) THEN
    ALTER TABLE orders ADD COLUMN customer_rating integer CHECK (customer_rating >= 1 AND customer_rating <= 5);
  END IF;
END $$;

-- Enable RLS on new tables
ALTER TABLE customer_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE promotional_campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_sales_summary ENABLE ROW LEVEL SECURITY;
ALTER TABLE menu_item_analytics ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY "Restaurant owners can manage feedback"
  ON customer_feedback
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM restaurants
      WHERE restaurants.id = customer_feedback.restaurant_id
      AND restaurants.owner_id = auth.uid()
    )
  );

CREATE POLICY "Anyone can insert feedback"
  ON customer_feedback
  FOR INSERT
  TO public
  WITH CHECK (true);

CREATE POLICY "Restaurant owners can manage campaigns"
  ON promotional_campaigns
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM restaurants
      WHERE restaurants.id = promotional_campaigns.restaurant_id
      AND restaurants.owner_id = auth.uid()
    )
  );

CREATE POLICY "Restaurant owners can view sales summary"
  ON daily_sales_summary
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM restaurants
      WHERE restaurants.id = daily_sales_summary.restaurant_id
      AND restaurants.owner_id = auth.uid()
    )
  );

CREATE POLICY "Restaurant owners can view menu analytics"
  ON menu_item_analytics
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM menu_items
      JOIN restaurants ON restaurants.id = menu_items.restaurant_id
      WHERE menu_items.id = menu_item_analytics.menu_item_id
      AND restaurants.owner_id = auth.uid()
    )
  );

-- Create useful views
CREATE OR REPLACE VIEW popular_items_view AS
SELECT 
  mi.id,
  mi.name,
  mi.restaurant_id,
  COUNT(oi.id) as times_ordered,
  SUM(oi.quantity) as total_quantity,
  SUM(oi.total_price) as total_revenue,
  AVG(oi.unit_price) as average_price
FROM menu_items mi
LEFT JOIN order_items oi ON mi.id = oi.menu_item_id
LEFT JOIN orders o ON oi.order_id = o.id
WHERE o.created_at >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY mi.id, mi.name, mi.restaurant_id
ORDER BY times_ordered DESC;

CREATE OR REPLACE VIEW revenue_trends_view AS
SELECT 
  r.id as restaurant_id,
  r.name as restaurant_name,
  DATE(o.created_at) as order_date,
  COUNT(o.id) as total_orders,
  SUM(o.total_amount) as daily_revenue,
  AVG(o.total_amount) as average_order_value
FROM restaurants r
LEFT JOIN orders o ON r.id = o.restaurant_id
WHERE o.created_at >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY r.id, r.name, DATE(o.created_at)
ORDER BY order_date DESC;

CREATE OR REPLACE VIEW low_stock_alerts_view AS
SELECT 
  ii.id,
  ii.name,
  ii.restaurant_id,
  r.name as restaurant_name,
  ii.current_stock,
  ii.minimum_stock,
  ii.unit,
  ii.category,
  (ii.minimum_stock - ii.current_stock) as shortage_amount
FROM inventory_items ii
JOIN restaurants r ON ii.restaurant_id = r.id
WHERE ii.current_stock <= ii.minimum_stock
AND ii.is_active = true
ORDER BY shortage_amount DESC;

-- Create function to update daily sales summary
CREATE OR REPLACE FUNCTION update_daily_sales_summary()
RETURNS void AS $$
BEGIN
  INSERT INTO daily_sales_summary (restaurant_id, date, total_orders, total_revenue, average_order_value, most_popular_item_id)
  SELECT 
    o.restaurant_id,
    CURRENT_DATE,
    COUNT(o.id),
    COALESCE(SUM(o.total_amount), 0),
    COALESCE(AVG(o.total_amount), 0),
    (
      SELECT oi.menu_item_id
      FROM order_items oi
      JOIN orders o2 ON oi.order_id = o2.id
      WHERE o2.restaurant_id = o.restaurant_id
      AND DATE(o2.created_at) = CURRENT_DATE
      GROUP BY oi.menu_item_id
      ORDER BY SUM(oi.quantity) DESC
      LIMIT 1
    )
  FROM orders o
  WHERE DATE(o.created_at) = CURRENT_DATE
  GROUP BY o.restaurant_id
  ON CONFLICT (restaurant_id, date)
  DO UPDATE SET
    total_orders = EXCLUDED.total_orders,
    total_revenue = EXCLUDED.total_revenue,
    average_order_value = EXCLUDED.average_order_value,
    most_popular_item_id = EXCLUDED.most_popular_item_id,
    updated_at = now();
END;
$$ LANGUAGE plpgsql;

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_customer_feedback_restaurant_id ON customer_feedback(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_customer_feedback_rating ON customer_feedback(rating);
CREATE INDEX IF NOT EXISTS idx_promotional_campaigns_restaurant_id ON promotional_campaigns(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_promotional_campaigns_dates ON promotional_campaigns(start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_daily_sales_summary_restaurant_date ON daily_sales_summary(restaurant_id, date);
CREATE INDEX IF NOT EXISTS idx_menu_item_analytics_item_date ON menu_item_analytics(menu_item_id, date);
CREATE INDEX IF NOT EXISTS idx_orders_source ON orders(order_source);
CREATE INDEX IF NOT EXISTS idx_orders_rating ON orders(customer_rating);

-- Add updated_at triggers
CREATE TRIGGER update_promotional_campaigns_updated_at
  BEFORE UPDATE ON promotional_campaigns
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_daily_sales_summary_updated_at
  BEFORE UPDATE ON daily_sales_summary
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_menu_item_analytics_updated_at
  BEFORE UPDATE ON menu_item_analytics
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();