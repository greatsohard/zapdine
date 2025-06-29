/*
  # Add Inventory Management System

  1. New Tables
    - `inventory_items` - Track ingredients and supplies
    - `menu_item_ingredients` - Link menu items to ingredients
    - `inventory_transactions` - Track stock movements
    - `suppliers` - Manage supplier information

  2. Enhancements
    - Add cost tracking to menu items
    - Add preparation time to menu items
    - Add allergen information
    - Add nutritional information

  3. Security
    - Enable RLS on all new tables
    - Add appropriate policies for restaurant owners
*/

-- Create suppliers table
CREATE TABLE IF NOT EXISTS suppliers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  name text NOT NULL,
  contact_person text,
  email text,
  phone text,
  address text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create inventory items table
CREATE TABLE IF NOT EXISTS inventory_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  supplier_id uuid REFERENCES suppliers(id) ON DELETE SET NULL,
  name text NOT NULL,
  description text,
  unit text NOT NULL DEFAULT 'kg', -- kg, liters, pieces, etc.
  current_stock numeric(10,3) DEFAULT 0,
  minimum_stock numeric(10,3) DEFAULT 0,
  maximum_stock numeric(10,3),
  unit_cost numeric(10,2) DEFAULT 0,
  category text, -- vegetables, meat, dairy, etc.
  storage_location text,
  expiry_date date,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create menu item ingredients junction table
CREATE TABLE IF NOT EXISTS menu_item_ingredients (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  menu_item_id uuid NOT NULL REFERENCES menu_items(id) ON DELETE CASCADE,
  inventory_item_id uuid NOT NULL REFERENCES inventory_items(id) ON DELETE CASCADE,
  quantity_required numeric(10,3) NOT NULL,
  unit text NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- Create inventory transactions table
CREATE TABLE IF NOT EXISTS inventory_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  inventory_item_id uuid NOT NULL REFERENCES inventory_items(id) ON DELETE CASCADE,
  transaction_type text NOT NULL CHECK (transaction_type IN ('purchase', 'usage', 'waste', 'adjustment')),
  quantity numeric(10,3) NOT NULL,
  unit_cost numeric(10,2),
  total_cost numeric(10,2),
  reference_id uuid, -- Could reference order_id for usage transactions
  notes text,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now()
);

-- Add new columns to existing menu_items table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'menu_items' AND column_name = 'cost_price'
  ) THEN
    ALTER TABLE menu_items ADD COLUMN cost_price numeric(10,2) DEFAULT 0;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'menu_items' AND column_name = 'preparation_time'
  ) THEN
    ALTER TABLE menu_items ADD COLUMN preparation_time integer DEFAULT 0; -- in minutes
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'menu_items' AND column_name = 'allergens'
  ) THEN
    ALTER TABLE menu_items ADD COLUMN allergens text[]; -- array of allergens
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'menu_items' AND column_name = 'calories'
  ) THEN
    ALTER TABLE menu_items ADD COLUMN calories integer;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'menu_items' AND column_name = 'dietary_tags'
  ) THEN
    ALTER TABLE menu_items ADD COLUMN dietary_tags text[]; -- vegetarian, vegan, gluten-free, etc.
  END IF;
END $$;

-- Enable RLS on new tables
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE menu_item_ingredients ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_transactions ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for suppliers
CREATE POLICY "Restaurant owners can manage suppliers"
  ON suppliers
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM restaurants
      WHERE restaurants.id = suppliers.restaurant_id
      AND restaurants.owner_id = auth.uid()
    )
  );

-- Create RLS policies for inventory_items
CREATE POLICY "Restaurant owners can manage inventory"
  ON inventory_items
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM restaurants
      WHERE restaurants.id = inventory_items.restaurant_id
      AND restaurants.owner_id = auth.uid()
    )
  );

-- Create RLS policies for menu_item_ingredients
CREATE POLICY "Restaurant owners can manage menu ingredients"
  ON menu_item_ingredients
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM menu_items
      JOIN restaurants ON restaurants.id = menu_items.restaurant_id
      WHERE menu_items.id = menu_item_ingredients.menu_item_id
      AND restaurants.owner_id = auth.uid()
    )
  );

-- Create RLS policies for inventory_transactions
CREATE POLICY "Restaurant owners can view inventory transactions"
  ON inventory_transactions
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM inventory_items
      JOIN restaurants ON restaurants.id = inventory_items.restaurant_id
      WHERE inventory_items.id = inventory_transactions.inventory_item_id
      AND restaurants.owner_id = auth.uid()
    )
  );

CREATE POLICY "Restaurant owners can insert inventory transactions"
  ON inventory_transactions
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM inventory_items
      JOIN restaurants ON restaurants.id = inventory_items.restaurant_id
      WHERE inventory_items.id = inventory_transactions.inventory_item_id
      AND restaurants.owner_id = auth.uid()
    )
  );

-- Add updated_at triggers for new tables
CREATE TRIGGER update_suppliers_updated_at
  BEFORE UPDATE ON suppliers
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_inventory_items_updated_at
  BEFORE UPDATE ON inventory_items
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_inventory_items_restaurant_id ON inventory_items(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_inventory_items_category ON inventory_items(category);
CREATE INDEX IF NOT EXISTS idx_inventory_items_low_stock ON inventory_items(restaurant_id) WHERE current_stock <= minimum_stock;
CREATE INDEX IF NOT EXISTS idx_suppliers_restaurant_id ON suppliers(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_menu_item_ingredients_menu_item ON menu_item_ingredients(menu_item_id);
CREATE INDEX IF NOT EXISTS idx_inventory_transactions_item_id ON inventory_transactions(inventory_item_id);
CREATE INDEX IF NOT EXISTS idx_inventory_transactions_type ON inventory_transactions(transaction_type);
CREATE INDEX IF NOT EXISTS idx_inventory_transactions_date ON inventory_transactions(created_at);