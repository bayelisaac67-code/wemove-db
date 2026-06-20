-- Seed: Accra Central ↔ Oyarifa corridor (Phase 1 launch corridor)

INSERT INTO corridors (id, name, status) VALUES
  ('a1b2c3d4-0000-0000-0000-000000000001', 'Accra Central ↔ Oyarifa', 'ACTIVE')
ON CONFLICT DO NOTHING;

-- Pickup points along the corridor (order_index 1 = Accra Central end)
INSERT INTO pickup_points (id, corridor_id, name, lat, lng, geofence_radius_m, order_index) VALUES
  ('b1000001-0000-0000-0000-000000000001', 'a1b2c3d4-0000-0000-0000-000000000001', 'Accra Central (Kwame Nkrumah Circle)',  5.5500,  -0.2167, 150, 1),
  ('b1000002-0000-0000-0000-000000000001', 'a1b2c3d4-0000-0000-0000-000000000001', '37 Military Hospital',                  5.5733,  -0.1822, 100, 2),
  ('b1000003-0000-0000-0000-000000000001', 'a1b2c3d4-0000-0000-0000-000000000001', 'Shiashie / American House',             5.5900,  -0.1700, 100, 3),
  ('b1000004-0000-0000-0000-000000000001', 'a1b2c3d4-0000-0000-0000-000000000001', 'Pantang Junction',                     5.6300,  -0.1500, 100, 4),
  ('b1000005-0000-0000-0000-000000000001', 'a1b2c3d4-0000-0000-0000-000000000001', 'Oyarifa Market',                       5.6800,  -0.1350, 150, 5)
ON CONFLICT DO NOTHING;
