-- WeMove Phase 1 — initial schema
-- Run in order; each migration is idempotent with IF NOT EXISTS

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ─── Users ───────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
  id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  phone                VARCHAR(20) UNIQUE NOT NULL,
  full_name            VARCHAR(200),
  preferred_name       VARCHAR(100),
  email                VARCHAR(200),
  role_flags           TEXT[]        NOT NULL DEFAULT ARRAY['PASSENGER'],
  verification_status  VARCHAR(20)   NOT NULL DEFAULT 'UNVERIFIED'
                         CHECK (verification_status IN ('UNVERIFIED','PENDING','VERIFIED','REJECTED')),
  account_status       VARCHAR(20)   NOT NULL DEFAULT 'ACTIVE'
                         CHECK (account_status IN ('ACTIVE','SUSPENDED','BANNED')),
  reliability_score    INT           NOT NULL DEFAULT 50 CHECK (reliability_score BETWEEN 0 AND 100),
  emergency_contact    JSONB,
  is_admin             BOOLEAN       NOT NULL DEFAULT FALSE,
  created_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- ─── OTP codes ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS otp_codes (
  phone        VARCHAR(20) PRIMARY KEY,
  code         VARCHAR(6)  NOT NULL,
  expires_at   TIMESTAMPTZ NOT NULL,
  attempts     INT         NOT NULL DEFAULT 0
);

-- ─── Verification documents ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS verification_documents (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id          UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  doc_type         VARCHAR(30) NOT NULL
                     CHECK (doc_type IN ('GHANA_CARD','SELFIE','DRIVER_LICENCE','VEHICLE_REG')),
  file_url         TEXT        NOT NULL,
  extracted_number VARCHAR(100),
  review_status    VARCHAR(20) NOT NULL DEFAULT 'PENDING'
                     CHECK (review_status IN ('PENDING','APPROVED','REJECTED')),
  reviewed_by      UUID        REFERENCES users(id),
  reason           TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── Driver profiles ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS driver_profiles (
  user_id                    UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  driver_type                VARCHAR(30) NOT NULL DEFAULT 'FLEXIBLE'
                               CHECK (driver_type IN ('DAILY_COMMUTER','FLEXIBLE','PROFESSIONAL')),
  licence_number             VARCHAR(100),
  licence_expiry             DATE,
  driver_verification_status VARCHAR(20) NOT NULL DEFAULT 'PENDING'
                               CHECK (driver_verification_status IN ('PENDING','VERIFIED','REJECTED')),
  completed_trips            INT  NOT NULL DEFAULT 0,
  cancellation_count         INT  NOT NULL DEFAULT 0,
  on_time_rate               FLOAT NOT NULL DEFAULT 1.0,
  payout_method              JSONB
);

-- ─── Vehicles ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS vehicles (
  id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  driver_id            UUID        NOT NULL REFERENCES driver_profiles(user_id) ON DELETE CASCADE,
  make                 VARCHAR(100) NOT NULL,
  model                VARCHAR(100) NOT NULL,
  colour               VARCHAR(50)  NOT NULL,
  plate_number         VARCHAR(30)  UNIQUE NOT NULL,
  seat_capacity        INT          NOT NULL CHECK (seat_capacity > 1),
  registration_doc_url TEXT,
  status               VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE'
                         CHECK (status IN ('ACTIVE','INACTIVE'))
);

-- ─── Corridors ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS corridors (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name          VARCHAR(200) NOT NULL,
  path_geometry JSONB,
  status        VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE'
                  CHECK (status IN ('ACTIVE','INACTIVE'))
);

-- ─── Pickup points ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pickup_points (
  id                 UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  corridor_id        UUID         NOT NULL REFERENCES corridors(id),
  name               VARCHAR(200) NOT NULL,
  lat                FLOAT        NOT NULL,
  lng                FLOAT        NOT NULL,
  geofence_radius_m  INT          NOT NULL DEFAULT 100,
  order_index        INT          NOT NULL
);

-- ─── Trips ────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS trips (
  id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  driver_id             UUID        NOT NULL REFERENCES users(id),
  vehicle_id            UUID        NOT NULL REFERENCES vehicles(id),
  corridor_id           UUID        NOT NULL REFERENCES corridors(id),
  direction             VARCHAR(10) NOT NULL CHECK (direction IN ('FORWARD','REVERSE')),
  origin_point_id       UUID        NOT NULL REFERENCES pickup_points(id),
  destination_point_id  UUID        NOT NULL REFERENCES pickup_points(id),
  departure_time        TIMESTAMPTZ NOT NULL,
  total_seats           INT         NOT NULL CHECK (total_seats > 0),
  available_seats       INT         NOT NULL CHECK (available_seats >= 0),
  recurring_template_id UUID,
  status                VARCHAR(20) NOT NULL DEFAULT 'PUBLISHED'
                          CHECK (status IN ('DRAFT','PUBLISHED','IN_PROGRESS','COMPLETED','CANCELLED')),
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_trips_matching ON trips (corridor_id, direction, departure_time, status, available_seats);

-- ─── Bookings ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bookings (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  trip_id           UUID        NOT NULL REFERENCES trips(id),
  passenger_id      UUID        NOT NULL REFERENCES users(id),
  seats             INT         NOT NULL DEFAULT 1 CHECK (seats > 0),
  pickup_point_id   UUID        NOT NULL REFERENCES pickup_points(id),
  dropoff_point_id  UUID        NOT NULL REFERENCES pickup_points(id),
  per_seat_price    NUMERIC(10,2) NOT NULL,
  total_price       NUMERIC(10,2) NOT NULL,
  payment_method    VARCHAR(20) NOT NULL CHECK (payment_method IN ('CASH','MOMO','GHANAPAY')),
  status            VARCHAR(40) NOT NULL DEFAULT 'REQUESTED'
                      CHECK (status IN ('REQUESTED','CONFIRMED','REJECTED',
                                        'CANCELLED_BY_PASSENGER','CANCELLED_BY_DRIVER',
                                        'NO_SHOW_PASSENGER','COMPLETED')),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── Payments ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS payments (
  id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  booking_id           UUID          NOT NULL REFERENCES bookings(id),
  method               VARCHAR(20)   NOT NULL,
  amount               NUMERIC(10,2) NOT NULL,
  commission_amount    NUMERIC(10,2) NOT NULL,
  driver_payout_amount NUMERIC(10,2) NOT NULL,
  status               VARCHAR(30)   NOT NULL DEFAULT 'PENDING'
                         CHECK (status IN ('PENDING','HELD','RELEASED','REFUNDED','FAILED','CASH_DUE','CASH_RECONCILED')),
  provider_ref         VARCHAR(200),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── Ratings ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ratings (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  booking_id  UUID        NOT NULL REFERENCES bookings(id),
  rater_id    UUID        NOT NULL REFERENCES users(id),
  ratee_id    UUID        NOT NULL REFERENCES users(id),
  stars       INT         NOT NULL CHECK (stars BETWEEN 1 AND 5),
  reason_tags TEXT[]      NOT NULL DEFAULT '{}',
  comment     TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (booking_id, rater_id)
);

-- ─── Recurring templates ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS recurring_templates (
  id                     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id                UUID        NOT NULL REFERENCES users(id),
  role                   VARCHAR(30) NOT NULL CHECK (role IN ('PASSENGER_BOOKING','DRIVER_TRIP')),
  corridor_id            UUID        NOT NULL REFERENCES corridors(id),
  direction              VARCHAR(10) NOT NULL,
  origin_point_id        UUID        NOT NULL REFERENCES pickup_points(id),
  destination_point_id   UUID        NOT NULL REFERENCES pickup_points(id),
  weekdays               INT[]       NOT NULL,
  time_of_day            TIME        NOT NULL,
  default_seats          INT         NOT NULL DEFAULT 1,
  default_payment_method VARCHAR(20),
  active                 BOOLEAN     NOT NULL DEFAULT TRUE
);

-- ─── Notifications ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS notifications (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id    UUID        NOT NULL REFERENCES users(id),
  type       VARCHAR(10) NOT NULL,
  payload    JSONB,
  channel    VARCHAR(10) NOT NULL CHECK (channel IN ('PUSH','SMS','IN_APP')),
  read       BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── SOS events ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sos_events (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id    UUID        NOT NULL REFERENCES users(id),
  trip_id    UUID        REFERENCES trips(id),
  booking_id UUID        REFERENCES bookings(id),
  location   JSONB       NOT NULL,
  status     VARCHAR(20) NOT NULL DEFAULT 'OPEN'
               CHECK (status IN ('OPEN','ACKNOWLEDGED','RESOLVED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
