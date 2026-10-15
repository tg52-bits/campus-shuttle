-- BASELINE QUERIES

-- QUERY 1: VIEW ALL TRIPS
-- Basic retrieval of trip records.

SELECT *
FROM trips;

SELECT *
FROM campus_zones;

SELECT *
FROM stops;


SELECT *
FROM vehicles

SELECT *
FROM delays
ORDER BY trip_id;

SELECT *
FROM route_stops;

SELECT *
FROM vehicle_position;


-- QUERY 2: FIND ACTIVE VEHICLES
-- Identify vehicles currently marked as active.

SELECT *
FROM vehicles
WHERE status = 'Active';


-- QUERY 3: TRIP DETAILS WITH VEHICLE, ROUTE AND DRIVER
-- Demonstrates relational JOINs between core entities.

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
-- Demonstrates temporal data processing.

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
-- Combines occupancy, trip and vehicle capacity data.

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
-- Basic analytical aggregation of delays by route.

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
-- Identify trips whose total recorded delay is at least 10 minutes.

SELECT
    trip_id,
    SUM(delay_duration) AS total_delay_minutes
FROM delays
GROUP BY trip_id
HAVING SUM(delay_duration) >= 10;


-- QUERY 8: TIME-BASED GPS QUERY
-- Retrieve vehicle positions recorded during a specified time interval.

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
-- Find vehicle positions within 500 metres of the Main Gate.
-- Geography casting makes the distance unit metres.

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
-- Find vehicle positions that occurred:
-- 1. Between 08:00 and 09:00
-- 2. Within 500 metres of Main Gate

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
-- Demonstrates the ordered relationship between routes and stops.

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
-- Calculate delay at individual stops using scheduled and actual arrival times.

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


-- QUERY 13: SPATIO-TEMPORAL QUERY
-- Find vehicle positions inside the Hostel Zone
SELECT
    vp.vehicle_id,
    vp.trip_id,
    vp.timestamp,
    cz.zone_name,
    ST_AsText(vp.location) AS vehicle_location
FROM vehicle_position vp
JOIN campus_zones cz
    ON ST_Intersects(vp.location, cz.boundary)
WHERE cz.zone_name = 'Hostel Zone'
ORDER BY vp.timestamp;


-- QUERY 14: DELAY ANALYSIS BY REASON
SELECT
    COALESCE(delay_type, 'Unspecified') AS delay_reason,
    COUNT(*) AS delay_events,
    COUNT(DISTINCT trip_id) AS affected_trips,
    ROUND(AVG(delay_duration)::numeric, 2)
        AS avg_delay_minutes,
    MAX(delay_duration) AS max_delay_minutes,
    SUM(delay_duration) AS total_recorded_delay_minutes
FROM delays
GROUP BY COALESCE(delay_type, 'Unspecified')
ORDER BY total_recorded_delay_minutes DESC;

-- QUERY 15: DELAY HOTSPOTS BY STOP

SELECT
    s.stop_name,
    COUNT(*) AS delay_events,
    COUNT(DISTINCT d.trip_id) AS affected_trips,
    ROUND(AVG(d.delay_duration)::numeric, 2)
        AS avg_delay_minutes,
    SUM(d.delay_duration) AS total_recorded_delay_minutes,
    MAX(d.delay_duration) AS max_delay_minutes
FROM delays d
JOIN stops s
    ON d.stop_id = s.stop_id
GROUP BY s.stop_id, s.stop_name
ORDER BY avg_delay_minutes DESC;

-- QUERY 16: DELAY PROGRESSION ALONG A TRIP
WITH stop_delays AS (
    SELECT
        tse.trip_id,
        tse.stop_sequence,
        s.stop_name,
        ROUND(
            (
                EXTRACT(
                    EPOCH FROM (
                        tse.actual_arrival - tse.scheduled_arrival
                    )
                ) / 60.0
            )::numeric,
            2
        ) AS delay_minutes
    FROM trip_stop_event tse
    JOIN stops s
        ON tse.stop_id = s.stop_id
    WHERE tse.actual_arrival IS NOT NULL
      AND tse.scheduled_arrival IS NOT NULL
),
delay_progression AS (
    SELECT
        trip_id,
        stop_sequence,
        stop_name,
        delay_minutes,
        LAG(delay_minutes) OVER (
            PARTITION BY trip_id
            ORDER BY stop_sequence
        ) AS previous_stop_delay
    FROM stop_delays
)
SELECT
    trip_id,
    stop_sequence,
    stop_name,
    delay_minutes,
    previous_stop_delay,
    ROUND(
        (delay_minutes - previous_stop_delay)::numeric,
        2
    ) AS delay_change_minutes,
    CASE
        WHEN previous_stop_delay IS NULL
            THEN 'First observed stop'
        WHEN delay_minutes > previous_stop_delay
            THEN 'Delay increased'
        WHEN delay_minutes < previous_stop_delay
            THEN 'Delay recovered'
        ELSE 'Delay unchanged'
    END AS delay_trend
FROM delay_progression
ORDER BY trip_id, stop_sequence;


-- QUERY 17: DELAY PATTERNS BY HOUR

SELECT
    EXTRACT(HOUR FROM timestamp)::integer AS delay_hour,
    COUNT(*) AS delay_events,
    COUNT(DISTINCT trip_id) AS affected_trips,
    ROUND(AVG(delay_duration)::numeric, 2)
        AS avg_delay_minutes,
    SUM(delay_duration) AS total_recorded_delay_minutes
FROM delays
GROUP BY EXTRACT(HOUR FROM timestamp)::integer
ORDER BY total_recorded_delay_minutes DESC;
