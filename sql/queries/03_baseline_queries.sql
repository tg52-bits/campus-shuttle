-- BASELINE QUERIES

-- QUERY 1: VIEW ALL TRIPS
-- Purpose:
-- Basic retrieval of trip records.
-- ============================================================

SELECT *
FROM trips;


-- QUERY 2: FIND ACTIVE VEHICLES
-- Purpose:
-- Identify vehicles currently marked as active.
-- ============================================================

SELECT *
FROM vehicles
WHERE status = 'Active';


-- QUERY 3: TRIP DETAILS WITH VEHICLE, ROUTE AND DRIVER
-- Purpose:
-- Demonstrates relational JOINs between core entities.
-- ============================================================

SELECT
    t.trip_id,
    r.route_name,
    v.vehicle_type,
    d.name AS driver_name,
    t.scheduled_start,
    t.actual_start,
    t.status
FROM trips t
JOIN routes r
    ON t.route_id = r.route_id
JOIN vehicles v
    ON t.vehicle_id = v.vehicle_id
LEFT JOIN drivers d
    ON t.driver_id = d.driver_id;


-- QUERY 4: CALCULATE TRIP START DELAY
-- Purpose:
-- Demonstrates temporal data processing.
-- ============================================================

SELECT
    trip_id,
    scheduled_start,
    actual_start,
    ROUND(
        EXTRACT(
            EPOCH FROM (actual_start - scheduled_start)
        ) / 60,
        2
    ) AS start_delay_minutes
FROM trips;


-- QUERY 5: OCCUPANCY PERCENTAGE
-- Purpose:
-- Combines occupancy, trip and vehicle capacity data.
-- ============================================================

SELECT
    o.trip_id,
    o.stop_id,
    o.passenger_count,
    v.capacity,
    ROUND(
        100.0 * o.passenger_count / v.capacity,
        2
    ) AS occupancy_percentage
FROM occupancy o
JOIN trips t
    ON o.trip_id = t.trip_id
JOIN vehicles v
    ON t.vehicle_id = v.vehicle_id;


-- QUERY 6: AVERAGE DELAY BY ROUTE
-- Purpose:
-- Basic analytical aggregation of delays by route.
-- ============================================================

SELECT
    r.route_name,
    ROUND(
        AVG(d.delay_duration),
        2
    ) AS avg_delay_minutes
FROM delays d
JOIN trips t
    ON d.trip_id = t.trip_id
JOIN routes r
    ON t.route_id = r.route_id
GROUP BY r.route_name;


-- QUERY 7: FIND HIGHLY DELAYED TRIPS
-- Purpose:
-- Identify trips whose total recorded delay is
-- at least 10 minutes.
-- ============================================================

SELECT
    trip_id,
    SUM(delay_duration) AS total_delay_minutes
FROM delays
GROUP BY trip_id
HAVING SUM(delay_duration) >= 10;


-- QUERY 8: TIME-BASED GPS QUERY
-- Purpose:
-- Retrieve vehicle positions recorded during a
-- specified time interval.
-- ============================================================

SELECT
    vehicle_id,
    trip_id,
    timestamp,
    speed
FROM vehicle_position
WHERE timestamp BETWEEN
      '2026-09-17 08:00'
      AND
      '2026-09-17 09:00'
ORDER BY timestamp;


-- QUERY 9: SPATIAL QUERY
-- Purpose:
-- Find vehicle positions within 500 metres
-- of the Main Gate.
--
-- Geography casting makes the distance unit metres.
-- ============================================================

SELECT
    vp.vehicle_id,
    vp.trip_id,
    vp.timestamp,
    ROUND(
        ST_Distance(
            vp.location::geography,
            s.location::geography
        )::numeric,
        2
    ) AS distance_meters
FROM vehicle_position vp
CROSS JOIN stops s
WHERE s.stop_name = 'Main Gate'
  AND ST_DWithin(
        vp.location::geography,
        s.location::geography,
        500
      )
ORDER BY distance_meters;



-- QUERY 10: SPATIO-TEMPORAL QUERY
-- Purpose:
-- Find vehicle positions that occurred:
--
-- 1. Between 08:00 and 09:00
-- 2. Within 500 metres of Main Gate
-- ============================================================

SELECT
    vp.vehicle_id,
    vp.trip_id,
    vp.timestamp,
    ST_AsText(vp.location) AS position
FROM vehicle_position vp
WHERE vp.timestamp BETWEEN
      '2026-09-17 08:00'
      AND
      '2026-09-17 09:00'
  AND ST_DWithin(
        vp.location::geography,
        ST_SetSRID(
            ST_MakePoint(78.4867, 17.3850),
            4326
        )::geography,
        500
      )
ORDER BY vp.timestamp;


-- QUERY 11: VIEW ROUTE STOP ORDER
-- Purpose:
-- Demonstrates the ordered relationship between
-- routes and stops.
-- ============================================================

SELECT
    r.route_name,
    rs.stop_sequence,
    s.stop_name
FROM route_stops rs
JOIN routes r
    ON rs.route_id = r.route_id
JOIN stops s
    ON rs.stop_id = s.stop_id
ORDER BY
    r.route_id,
    rs.stop_sequence;


-- QUERY 12: STOP-LEVEL ARRIVAL DELAY
-- Purpose:
-- Calculate delay at individual stops using
-- scheduled and actual arrival times.
-- ============================================================

SELECT
    tse.trip_id,
    s.stop_name,
    tse.scheduled_arrival,
    tse.actual_arrival,
    ROUND(
        EXTRACT(
            EPOCH FROM
            (tse.actual_arrival - tse.scheduled_arrival)
        ) / 60,
        2
    ) AS arrival_delay_minutes
FROM trip_stop_event tse
JOIN stops s
    ON tse.stop_id = s.stop_id
WHERE tse.actual_arrival IS NOT NULL
ORDER BY
    tse.trip_id,
    tse.stop_sequence;
