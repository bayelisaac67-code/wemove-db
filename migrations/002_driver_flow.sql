-- 002: Driver flow support
-- Adds pickup tracking to bookings (driver marks passengers picked up in-trip).
-- No-shows are already covered by bookings.status = 'NO_SHOW_PASSENGER'.

ALTER TABLE bookings ADD COLUMN IF NOT EXISTS picked_up_at TIMESTAMPTZ;
