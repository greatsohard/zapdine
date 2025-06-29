/*
  # Add Staff Management System

  1. New Tables
    - `staff_roles` - Define different staff roles
    - `restaurant_staff` - Link staff to restaurants with roles
    - `staff_shifts` - Track working hours and shifts
    - `staff_permissions` - Define what each role can do

  2. Enhancements
    - Add staff assignment to orders
    - Add staff performance tracking
    - Add time tracking for shifts

  3. Security
    - Enable RLS with role-based access
    - Staff can only see their own data and restaurant data
*/

-- Create staff roles table
CREATE TABLE IF NOT EXISTS staff_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text,
  permissions jsonb DEFAULT '{}', -- JSON object with permission flags
  hourly_rate numeric(10,2),
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(restaurant_id, name)
);

-- Create restaurant staff table
CREATE TABLE IF NOT EXISTS restaurant_staff (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role_id uuid NOT NULL REFERENCES staff_roles(id) ON DELETE CASCADE,
  employee_id text,
  hire_date date DEFAULT CURRENT_DATE,
  is_active boolean DEFAULT true,
  emergency_contact_name text,
  emergency_contact_phone text,
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(restaurant_id, user_id)
);

-- Create staff shifts table
CREATE TABLE IF NOT EXISTS staff_shifts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id uuid NOT NULL REFERENCES restaurant_staff(id) ON DELETE CASCADE,
  shift_date date NOT NULL,
  start_time time NOT NULL,
  end_time time,
  actual_start_time timestamptz,
  actual_end_time timestamptz,
  break_duration integer DEFAULT 0, -- in minutes
  status text DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'in_progress', 'completed', 'cancelled')),
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Add staff assignment to orders
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'orders' AND column_name = 'assigned_staff_id'
  ) THEN
    ALTER TABLE orders ADD COLUMN assigned_staff_id uuid REFERENCES restaurant_staff(id) ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'orders' AND column_name = 'served_by_staff_id'
  ) THEN
    ALTER TABLE orders ADD COLUMN served_by_staff_id uuid REFERENCES restaurant_staff(id) ON DELETE SET NULL;
  END IF;
END $$;

-- Create default staff roles function
CREATE OR REPLACE FUNCTION create_default_staff_roles(restaurant_uuid uuid)
RETURNS void AS $$
BEGIN
  -- Manager role
  INSERT INTO staff_roles (restaurant_id, name, description, permissions, hourly_rate)
  VALUES (
    restaurant_uuid,
    'Manager',
    'Restaurant manager with full access',
    '{"manage_staff": true, "manage_menu": true, "view_reports": true, "manage_inventory": true, "process_orders": true}',
    25.00
  );

  -- Waiter role
  INSERT INTO staff_roles (restaurant_id, name, description, permissions, hourly_rate)
  VALUES (
    restaurant_uuid,
    'Waiter',
    'Front-of-house staff serving customers',
    '{"process_orders": true, "view_menu": true, "update_order_status": true}',
    15.00
  );

  -- Chef role
  INSERT INTO staff_roles (restaurant_id, name, description, permissions, hourly_rate)
  VALUES (
    restaurant_uuid,
    'Chef',
    'Kitchen staff preparing food',
    '{"view_orders": true, "update_order_status": true, "manage_inventory": true}',
    20.00
  );

  -- Cashier role
  INSERT INTO staff_roles (restaurant_id, name, description, permissions, hourly_rate)
  VALUES (
    restaurant_uuid,
    'Cashier',
    'Handle payments and customer service',
    '{"process_orders": true, "view_reports": true, "handle_payments": true}',
    14.00
  );
END;
$$ LANGUAGE plpgsql;

-- Create trigger to add default roles when restaurant is created
CREATE OR REPLACE FUNCTION add_default_staff_roles()
RETURNS TRIGGER AS $$
BEGIN
  PERFORM create_default_staff_roles(NEW.id);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_restaurant_created_add_roles
  AFTER INSERT ON restaurants
  FOR EACH ROW EXECUTE FUNCTION add_default_staff_roles();

-- Enable RLS on new tables
ALTER TABLE staff_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE restaurant_staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_shifts ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for staff_roles
CREATE POLICY "Restaurant owners can manage staff roles"
  ON staff_roles
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM restaurants
      WHERE restaurants.id = staff_roles.restaurant_id
      AND restaurants.owner_id = auth.uid()
    )
  );

CREATE POLICY "Staff can view their restaurant roles"
  ON staff_roles
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM restaurant_staff rs
      JOIN restaurants r ON r.id = rs.restaurant_id
      WHERE rs.user_id = auth.uid()
      AND rs.restaurant_id = staff_roles.restaurant_id
      AND rs.is_active = true
    )
  );

-- Create RLS policies for restaurant_staff
CREATE POLICY "Restaurant owners can manage staff"
  ON restaurant_staff
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM restaurants
      WHERE restaurants.id = restaurant_staff.restaurant_id
      AND restaurants.owner_id = auth.uid()
    )
  );

CREATE POLICY "Staff can view their own record"
  ON restaurant_staff
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Staff can view colleagues in same restaurant"
  ON restaurant_staff
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM restaurant_staff rs
      WHERE rs.user_id = auth.uid()
      AND rs.restaurant_id = restaurant_staff.restaurant_id
      AND rs.is_active = true
    )
  );

-- Create RLS policies for staff_shifts
CREATE POLICY "Restaurant owners can manage shifts"
  ON staff_shifts
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM restaurant_staff rs
      JOIN restaurants r ON r.id = rs.restaurant_id
      WHERE rs.id = staff_shifts.staff_id
      AND r.owner_id = auth.uid()
    )
  );

CREATE POLICY "Staff can view and update their own shifts"
  ON staff_shifts
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM restaurant_staff rs
      WHERE rs.id = staff_shifts.staff_id
      AND rs.user_id = auth.uid()
    )
  );

-- Create useful views for staff management
CREATE OR REPLACE VIEW staff_performance_view AS
SELECT 
  rs.id as staff_id,
  p.full_name as staff_name,
  sr.name as role_name,
  r.name as restaurant_name,
  COUNT(o.id) as orders_handled,
  AVG(o.customer_rating) as average_rating,
  SUM(EXTRACT(EPOCH FROM (ss.actual_end_time - ss.actual_start_time))/3600) as total_hours_worked
FROM restaurant_staff rs
JOIN profiles p ON rs.user_id = p.id
JOIN staff_roles sr ON rs.role_id = sr.id
JOIN restaurants r ON rs.restaurant_id = r.id
LEFT JOIN orders o ON (o.assigned_staff_id = rs.id OR o.served_by_staff_id = rs.id)
LEFT JOIN staff_shifts ss ON rs.id = ss.staff_id AND ss.status = 'completed'
WHERE rs.is_active = true
GROUP BY rs.id, p.full_name, sr.name, r.name;

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_staff_roles_restaurant_id ON staff_roles(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_restaurant_staff_restaurant_id ON restaurant_staff(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_restaurant_staff_user_id ON restaurant_staff(user_id);
CREATE INDEX IF NOT EXISTS idx_restaurant_staff_role_id ON restaurant_staff(role_id);
CREATE INDEX IF NOT EXISTS idx_staff_shifts_staff_id ON staff_shifts(staff_id);
CREATE INDEX IF NOT EXISTS idx_staff_shifts_date ON staff_shifts(shift_date);
CREATE INDEX IF NOT EXISTS idx_orders_assigned_staff ON orders(assigned_staff_id);
CREATE INDEX IF NOT EXISTS idx_orders_served_by_staff ON orders(served_by_staff_id);

-- Add updated_at triggers
CREATE TRIGGER update_staff_roles_updated_at
  BEFORE UPDATE ON staff_roles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_restaurant_staff_updated_at
  BEFORE UPDATE ON restaurant_staff
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_staff_shifts_updated_at
  BEFORE UPDATE ON staff_shifts
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();