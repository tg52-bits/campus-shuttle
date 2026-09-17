-- CAMPUS SHUTTLE
-- M3: DATABASE SCHEMA

CREATE TABLE drivers (
    driver_id       SERIAL PRIMARY KEY,
    name            VARCHAR(100) NOT NULL,
    license_info    VARCHAR(100)
);

CREATE TABLE vehicles (
    vehicle_id      SERIAL PRIMARY KEY,
    vehicle_type    VARCHAR(50) NOT NULL,
    capacity        INTEGER NOT NULL CHECK (capacity > 0),
    status          VARCHAR(30) NOT NULL
);

CREATE TABLE routes (
    route_id        SERIAL PRIMARY KEY,
    route_name      VARCHAR(100) NOT NULL,
    route_geometry  GEOMETRY(LineString, 4326)
);

CREATE TABLE stops (
    stop_id         SERIAL PRIMARY KEY,
    stop_name       VARCHAR(100) NOT NULL,
    location        GEOMETRY(Point, 4326) NOT NULL
);

CREATE TABLE route_stops (
    route_stop_id   SERIAL PRIMARY KEY,
    route_id        INTEGER NOT NULL,
    stop_id         INTEGER NOT NULL,
    stop_sequence   INTEGER NOT NULL CHECK (stop_sequence > 0),

    FOREIGN KEY (route_id)
        REFERENCES routes(route_id),

    FOREIGN KEY (stop_id)
        REFERENCES stops(stop_id),

    UNIQUE (route_id, stop_sequence),
    UNIQUE (route_id, stop_id)
);

CREATE TABLE trips (
    trip_id         SERIAL PRIMARY KEY,
    vehicle_id      INTEGER NOT NULL,
    route_id        INTEGER NOT NULL,
    driver_id       INTEGER,

    scheduled_start TIMESTAMP NOT NULL,
    scheduled_end   TIMESTAMP,

    actual_start    TIMESTAMP,
    actual_end      TIMESTAMP,

    status           VARCHAR(30) NOT NULL,

    FOREIGN KEY (vehicle_id)
        REFERENCES vehicles(vehicle_id),

    FOREIGN KEY (route_id)
        REFERENCES routes(route_id),

    FOREIGN KEY (driver_id)
        REFERENCES drivers(driver_id),

    CHECK (
        actual_end IS NULL
        OR actual_start IS NULL
        OR actual_end >= actual_start
    )
);

CREATE TABLE trip_stop_event (
    trip_stop_id        SERIAL PRIMARY KEY,
    trip_id             INTEGER NOT NULL,
    stop_id             INTEGER NOT NULL,
    stop_sequence       INTEGER NOT NULL CHECK (stop_sequence > 0),

    scheduled_arrival   TIMESTAMP,
    actual_arrival      TIMESTAMP,

    scheduled_departure TIMESTAMP,
    actual_departure    TIMESTAMP,

    FOREIGN KEY (trip_id)
        REFERENCES trips(trip_id),

    FOREIGN KEY (stop_id)
        REFERENCES stops(stop_id),

    UNIQUE (trip_id, stop_sequence),

    CHECK (
        actual_departure IS NULL
        OR actual_arrival IS NULL
        OR actual_departure >= actual_arrival
    )
);

CREATE TABLE occupancy (
    occupancy_id    BIGSERIAL PRIMARY KEY,
    trip_id         INTEGER NOT NULL,
    stop_id         INTEGER,
    timestamp       TIMESTAMP NOT NULL,

    passenger_count INTEGER NOT NULL
        CHECK (passenger_count >= 0),

    FOREIGN KEY (trip_id)
        REFERENCES trips(trip_id),

    FOREIGN KEY (stop_id)
        REFERENCES stops(stop_id)
);

CREATE TABLE delays (
    delay_id        BIGSERIAL PRIMARY KEY,
    trip_id         INTEGER NOT NULL,
    stop_id         INTEGER,

    delay_duration  INTEGER NOT NULL
        CHECK (delay_duration >= 0),

    delay_type      VARCHAR(50),
    timestamp       TIMESTAMP NOT NULL,

    FOREIGN KEY (trip_id)
        REFERENCES trips(trip_id),

    FOREIGN KEY (stop_id)
        REFERENCES stops(stop_id)
);

CREATE TABLE maintenance (
    maintenance_id   SERIAL PRIMARY KEY,
    vehicle_id       INTEGER NOT NULL,
    maintenance_date DATE NOT NULL,
    type              VARCHAR(100),

    FOREIGN KEY (vehicle_id)
        REFERENCES vehicles(vehicle_id)
);

CREATE TABLE vehicle_position (
    position_id     BIGSERIAL PRIMARY KEY,
    vehicle_id      INTEGER NOT NULL,
    trip_id         INTEGER,

    timestamp       TIMESTAMP NOT NULL,

    location        GEOMETRY(Point, 4326) NOT NULL,

    speed           NUMERIC(6,2),

    FOREIGN KEY (vehicle_id)
        REFERENCES vehicles(vehicle_id),

    FOREIGN KEY (trip_id)
        REFERENCES trips(trip_id),

    CHECK (
        speed IS NULL
        OR speed >= 0
    )
);

CREATE TABLE campus_zones (
    zone_id       SERIAL PRIMARY KEY,
    zone_name     VARCHAR(100) NOT NULL,

    boundary      GEOMETRY(Polygon, 4326) NOT NULL
);