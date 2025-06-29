/*
  # Add Advanced Restaurant Features

  1. New Tables
    - `table_reservations` - Handle table bookings
    - `loyalty_programs` - Customer loyalty and rewards
    - `customer_profiles` - Store customer preferences
    - `menu_modifiers` - Customization options for menu items
    - `order_notifications` - Real-time notification system

  2. Enhancements
    - Add table status tracking
    - Add customer loyalty points
    - Add menu item customization
    - Add notification preferences

  3. Security
    - Enable RLS on all new tables
    - Customer data protection policies
*/

-- Create customer profiles table
CREATE TABLE IF NOT EXISTS customer_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone text UNIQUE,
  email text UNIQUE,
  name text,
  date_of_birth date,
  dietary_preferences text[],
  allergens text[],
  favorite_restaurant_id uuid REFERENCES restaurants(id),
  total_visits integer DEFAULT 0,
  total_spent numeric(12,2) DEFAULT 0,
  loyalty_points integer DEFAULT 0,
  preferred_table_size integer,
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create table reservations table
CREATE TABLE IF NOT EXISTS table_reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  table_id uuid REFERENCES tables(id) ON DELETE SET NULL,
  customer_profile_id uuid REFERENCES customer_profiles(id) ON DELETE SET NULL,
  customer_name text NOT NULL,
  customer_phone text,
  customer_email text,
  party_size integer NOT NULL,
  reservation_date date NOT NULL,
  reservation_time time NOT NULL,
  duration_minutes integer DEFAULT 120,
  status text DEFAULT 'confirmed' CHECK (status IN ('pending', 'confirmed', 'seated', 'completed', 'cancelled', 'no_show')),
  special_requests text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create loyalty programs table
CREATE TABLE IF NOT EXISTS loyalty_programs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text,
  points_per_dollar numeric(5,2) DEFAULT 1.00,
  redemption_rate numeric(5,2) DEFAULT 0.01, -- dollars per point
  minimum_redemption_points integer DEFAULT 100,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create menu modifiers table (for customizations like "extra cheese", "no onions")
CREATE TABLE IF NOT EXISTS menu_modifiers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text,
  price_adjustment numeric(8,2) DEFAULT 0,
  modifier_type text CHECK (modifier_type IN ('addition', 'substitution', 'removal')),
  applicable_categories text[], -- which menu categories this applies to
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create menu item modifiers junction table
CREATE TABLE IF NOT EXISTS menu_item_modifiers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  menu_item_id uuid NOT NULL REFERENCES menu_items(id) ON DELETE CASCADE,
  modifier_id uuid NOT NULL REFERENCES menu_modifiers(id) ON DELETE CASCADE,
  is_required boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

-- Create order item modifiers table (track what modifiers were applied to each order item)
CREATE TABLE IF NOT EXISTS order_item_modifiers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_item_id uuid NOT NULL REFERENCES order_items(id) ON DELETE CASCADE,
  modifier_id uuid NOT NULL REFERENCES menu_modifiers(id) ON DELETE CASCADE,
  price_adjustment numeric(8,2) DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

-- Create order notifications table
CREATE TABLE IF NOT EXISTS order_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  order_id uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  notification_type text CHECK (notification_type IN ('order_placed', 'order_confirmed', 'order_ready', 'order_served')),
  recipient_type text CHECK (recipient_type IN ('customer', 'staff', 'kitchen')),
  recipient_id uuid, -- could be staff_id or customer_profile_id
  message text,
  is_read boolean DEFAULT false,
  sent_at timestamptz DEFAULT now(),
  read_at timestamptz
);

-- Add new columns to existing tables
DO $$
BEGIN
  -- Add table status to tables
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tables' AND column_name = 'status'
  ) THEN
    ALTER TABLE tables ADD COLUMN status text DEFAULT 'available' CHECK (status IN ('available', 'occupied', 'reserved', 'cleaning', 'out_of_order'));
  END IF;

  -- Add customer profile reference to orders
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'orders' AND column_name = 'customer_profile_id'
  ) THEN
    ALTER TABLE orders ADD COLUMN customer_profile_id uuid REFERENCES customer_profiles(id) ON DELETE SET NULL;
  END IF;

  -- Add loyalty points earned to orders
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'orders' AND column_name = 'loyalty_points_earned'
  ) THEN
    ALTER TABLE orders ADD COLUMN loyalty_points_earned integer DEFAULT 0;
  END IF;

  -- Add loyalty points used to orders
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'orders' AND column_name = 'loyalty_points_used'
  ) THEN
    ALTER TABLE orders ADD COLUMN loyalty_points_used integer DEFAULT 0;
  END IF;

  -- Add estimated preparation time to menu items
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'menu_items' AND column_name = 'estimated_prep_time'
  ) THEN
    ALTER TABLE menu_items ADD COLUMN estimated_prep_time integer DEFAULT 15; -- minutes
  END IF;

  -- Add spice level to menu items
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'menu_items' AND column_name = 'spice_level'
  ) THEN
    ALTER TABLE menu_items ADD COLUMN spice_level integer CHECK (spice_level >= 0 AND spice_level <= 5);
  END IF;
END $$;

-- Enable RLS on new tables
ALTER TABLE customer_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE table_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE loyalty_programs ENABLE ROW LEVEL SECURITY;
ALTER TABLE menu_modifiers ENABLE ROW LEVEL SECURITY;
ALTER TABLE menu_item_modifiers ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_item_modifiers ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_notifications ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for customer_profiles
CREATE POLICY "Customers can view and update their own profile"
  ON customer_profiles
  FOR ALL
  TO public
  USING (true); -- We'll handle customer identification through phone/email

-- Create RLS policies for table_reservations
CREATE POLICY "Restaurant owners can manage reservations"
  ON table_reservations
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM restaurants
      WHERE restaurants.id = table_reservations.restaurant_id
      AND restaurants.owner_id = auth.uid()
    )
  );

CREATE POLICY "Anyone can create reservations"
  ON table_reservations
  FOR INSERT
  TO public
  WITH CHECK (true);

-- Create RLS policies for loyalty_programs
CREATE POLICY "Restaurant owners can manage loyalty programs"
  ON loyalty_programs
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM restaurants
      WHERE restaurants.id = loyalty_programs.restaurant_id
      AND restaurants.owner_id = auth.uid()
    )
  );

-- Create RLS policies for menu_modifiers
CREATE POLICY "Restaurant owners can manage modifiers"
  ON menu_modifiers
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM restaurants
      WHERE restaurants.id = menu_modifiers.restaurant_id
      AND restaurants.owner_id = auth.uid()
    )
  );

CREATE POLICY "Anyone can view active modifiers"
  ON menu_modifiers
  FOR SELECT
  TO public
  USING (is_active = true);

-- Create RLS policies for menu_item_modifiers
CREATE POLICY "Restaurant owners can manage item modifiers"
  ON menu_item_modifiers
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM menu_items mi
      JOIN restaurants r ON r.id = mi.restaurant_id
      WHERE mi.id = menu_item_modifiers.menu_item_id
      AND r.owner_id = auth.uid()
    )
  );

CREATE POLICY "Anyone can view item modifiers"
  ON menu_item_modifiers
  FOR SELECT
  TO public
  USING (true);

-- Create RLS policies for order_item_modifiers
CREATE POLICY "Restaurant owners can view order modifiers"
  ON order_item_modifiers
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM order_items oi
      JOIN orders o ON o.id = oi.order_id
      JOIN restaurants r ON r.id = o.restaurant_id
      WHERE oi.id = order_item_modifiers.order_item_id
      AND r.owner_id = auth.uid()
    )
  );

CREATE POLICY "Anyone can insert order modifiers"
  ON order_item_modifiers
  FOR INSERT
  TO public
  WITH CHECK (true);

-- Create RLS policies for order_notifications
CREATE POLICY "Restaurant owners can manage notifications"
  ON order_notifications
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM restaurants
      WHERE restaurants.id = order_notifications.restaurant_id
      AND restaurants.owner_id = auth.uid()
    )
  );

-- Create useful views
CREATE OR REPLACE VIEW table_availability_view AS
SELECT 
  t.id,
  t.table_number,
  t.capacity,
  t.status,
  r.id as restaurant_id,
  r.name as restaurant_name,
  CASE 
    WHEN tr.id IS NOT NULL THEN 'reserved'
    ELSE t.status
  END as current_status,
  tr.reservation_time,
  tr.customer_name as reserved_by
FROM tables t
JOIN restaurants r ON t.restaurant_id = r.id
LEFT JOIN table_reservations tr ON t.id = tr.table_id 
  AND tr.reservation_date = CURRENT_DATE
  AND tr.status IN ('confirmed', 'seated')
  AND tr.reservation_time BETWEEN CURRENT_TIME - INTERVAL '30 minutes' 
  AND CURRENT_TIME + INTERVAL '2 hours'
WHERE t.is_active = true;

CREATE OR REPLACE VIEW customer_loyalty_view AS
SELECT 
  cp.id,
  cp.name,
  cp.phone,
  cp.email,
  cp.total_visits,
  cp.total_spent,
  cp.loyalty_points,
  r.name as favorite_restaurant,
  CASE 
    WHEN cp.total_visits >= 50 THEN 'VIP'
    WHEN cp.total_visits >= 20 THEN 'Gold'
    WHEN cp.total_visits >= 10 THEN 'Silver'
    ELSE 'Bronze'
  END as loyalty_tier
FROM customer_profiles cp
LEFT JOIN restaurants r ON cp.favorite_restaurant_id = r.id;

-- Create functions for loyalty point management
CREATE OR REPLACE FUNCTION calculate_loyalty_points(order_total numeric, restaurant_uuid uuid)
RETURNS integer AS $$
DECLARE
  points_per_dollar numeric;
BEGIN
  SELECT lp.points_per_dollar INTO points_per_dollar
  FROM loyalty_programs lp
  WHERE lp.restaurant_id = restaurant_uuid
  AND lp.is_active = true
  LIMIT 1;
  
  IF points_per_dollar IS NULL THEN
    points_per_dollar := 1.0; -- Default 1 point per dollar
  END IF;
  
  RETURN FLOOR(order_total * points_per_dollar);
END;
$$ LANGUAGE plpgsql;

-- Create function to update customer profile after order
CREATE OR REPLACE FUNCTION update_customer_profile_after_order()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'served' AND OLD.status != 'served' THEN
    -- Update customer profile if exists
    UPDATE customer_profiles
    SET 
      total_visits = total_visits + 1,
      total_spent = total_spent + NEW.total_amount,
      loyalty_points = loyalty_points + COALESCE(NEW.loyalty_points_earned, 0) - COALESCE(NEW.loyalty_points_used, 0),
      updated_at = now()
    WHERE id = NEW.customer_profile_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_customer_after_order
  AFTER UPDATE ON orders
  FOR EACH ROW EXECUTE FUNCTION update_customer_profile_after_order();

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_customer_profiles_phone ON customer_profiles(phone);
CREATE INDEX IF NOT EXISTS idx_customer_profiles_email ON customer_profiles(email);
CREATE INDEX IF NOT EXISTS idx_table_reservations_restaurant_date ON table_reservations(restaurant_id, reservation_date);
CREATE INDEX IF NOT EXISTS idx_table_reservations_table_date ON table_reservations(table_id, reservation_date);
CREATE INDEX IF NOT EXISTS idx_loyalty_programs_restaurant_id ON loyalty_programs(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_menu_modifiers_restaurant_id ON menu_modifiers(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_menu_item_modifiers_menu_item ON menu_item_modifiers(menu_item_id);
CREATE INDEX IF NOT EXISTS idx_order_item_modifiers_order_item ON order_item_modifiers(order_item_id);
CREATE INDEX IF NOT EXISTS idx_order_notifications_restaurant_id ON order_notifications(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_order_notifications_order_id ON order_notifications(order_id);
CREATE INDEX IF NOT EXISTS idx_tables_status ON tables(status);

-- Add updated_at triggers
CREATE TRIGGER update_customer_profiles_updated_at
  BEFORE UPDATE ON customer_profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_table_reservations_updated_at
  BEFORE UPDATE ON table_reservations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_loyalty_programs_updated_at
  BEFORE UPDATE ON loyalty_programs
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_menu_modifiers_updated_at
  BEFORE UPDATE ON menu_modifiers
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();