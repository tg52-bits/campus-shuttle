-- QUERY: CALCULATING ALL 
SELECT
    tse.trip_id,
    t.route_id,
    r.route_name,
    tse.stop_sequence,
    s.stop_id,
    s.stop_name,

    -- 1. Departure delay
    EXTRACT(EPOCH FROM (
        tse.actual_departure - tse.scheduled_departure
    )) AS departure_delay_seconds,

    -- 2. Scheduled stoppage duration
    EXTRACT(EPOCH FROM (
        tse.scheduled_departure - tse.scheduled_arrival
    )) AS scheduled_stoppage_seconds,

    -- 3. Extra time spent at the stop
    EXTRACT(EPOCH FROM (
        tse.actual_departure - tse.actual_arrival
        - (tse.scheduled_departure - tse.scheduled_arrival)
    )) AS at_stop_delay_seconds,

    -- 4. In-transit / arrival delay
    EXTRACT(EPOCH FROM (
        tse.actual_arrival - tse.scheduled_arrival
    )) AS in_transit_delay_seconds

FROM trip_stop_event tse
JOIN trips t
    ON tse.trip_id = t.trip_id
JOIN routes r
    ON t.route_id = r.route_id
JOIN stops s
    ON tse.stop_id = s.stop_id

ORDER BY tse.trip_id, tse.stop_sequence;

WITH stop_delays AS (
    SELECT
        tse.trip_id,
        t.route_id,
        r.route_name,
        tse.stop_id,
        s.stop_name,
        tse.stop_sequence,

        EXTRACT(EPOCH FROM (
            tse.actual_arrival - tse.scheduled_arrival
        )) AS arrival_delay_seconds

    FROM trip_stop_event tse
    JOIN trips t
        ON tse.trip_id = t.trip_id
    JOIN routes r
        ON t.route_id = r.route_id
    JOIN stops s
        ON tse.stop_id = s.stop_id

    WHERE tse.actual_arrival IS NOT NULL
      AND tse.scheduled_arrival IS NOT NULL
),
cascading_delays AS (
    SELECT
        *,
        LAG(arrival_delay_seconds) OVER (
            PARTITION BY trip_id
            ORDER BY stop_sequence
        ) AS previous_stop_delay_seconds
    FROM stop_delays
)
SELECT
    trip_id,
    route_id,
    route_name,
    stop_sequence,
    stop_id,
    stop_name,
    ROUND(arrival_delay_seconds::numeric, 2)
        AS current_arrival_delay_seconds,
    ROUND(previous_stop_delay_seconds::numeric, 2)
        AS previous_stop_delay_seconds,
    ROUND((
        arrival_delay_seconds - previous_stop_delay_seconds
    )::numeric, 2) AS delay_change_seconds,

    CASE
        WHEN previous_stop_delay_seconds IS NULL
            THEN 'First recorded stop'
        WHEN arrival_delay_seconds > previous_stop_delay_seconds
            THEN 'Delay increased'
        WHEN arrival_delay_seconds < previous_stop_delay_seconds
            THEN 'Delay decreased'
        ELSE 'Delay unchanged'
    END AS delay_trend

FROM cascading_delays
ORDER BY trip_id, stop_sequence;

--QUERY: TRACK CASCADING DELAYS STOP TO STOP

WITH stop_delays AS (
    SELECT
        tse.trip_id,
        t.route_id,
        r.route_name,
        tse.stop_id,
        s.stop_name,
        tse.stop_sequence,

        EXTRACT(EPOCH FROM (
            tse.actual_arrival - tse.scheduled_arrival
        )) AS arrival_delay_seconds

    FROM trip_stop_event tse
    JOIN trips t
        ON tse.trip_id = t.trip_id
    JOIN routes r
        ON t.route_id = r.route_id
    JOIN stops s
        ON tse.stop_id = s.stop_id

    WHERE tse.actual_arrival IS NOT NULL
      AND tse.scheduled_arrival IS NOT NULL
),
cascading_delays AS (
    SELECT
        *,
        LAG(arrival_delay_seconds) OVER (
            PARTITION BY trip_id
            ORDER BY stop_sequence
        ) AS previous_stop_delay_seconds
    FROM stop_delays
)
SELECT
    trip_id,
    route_id,
    route_name,
    stop_sequence,
    stop_id,
    stop_name,
    ROUND(arrival_delay_seconds::numeric, 2)
        AS current_arrival_delay_seconds,
    ROUND(previous_stop_delay_seconds::numeric, 2)
        AS previous_stop_delay_seconds,
    ROUND((
        arrival_delay_seconds - previous_stop_delay_seconds
    )::numeric, 2) AS delay_change_seconds,

    CASE
        WHEN previous_stop_delay_seconds IS NULL
            THEN 'First recorded stop'
        WHEN arrival_delay_seconds > previous_stop_delay_seconds
            THEN 'Delay increased'
        WHEN arrival_delay_seconds < previous_stop_delay_seconds
            THEN 'Delay decreased'
        ELSE 'Delay unchanged'
    END AS delay_trend

FROM cascading_delays
ORDER BY trip_id, stop_sequence;

--QUERY: IDENTIFY STOPS WHER DELAYS ACCUMULATE THE MOST
WITH arrival_delays AS (
    SELECT
        tse.trip_id,
        tse.stop_id,
        tse.stop_sequence,
        s.stop_name,

        EXTRACT(EPOCH FROM (
            tse.actual_arrival - tse.scheduled_arrival
        )) AS arrival_delay_seconds

    FROM trip_stop_event tse
    JOIN stops s
        ON tse.stop_id = s.stop_id

    WHERE tse.actual_arrival IS NOT NULL
      AND tse.scheduled_arrival IS NOT NULL
),
delay_changes AS (
    SELECT
        *,
        arrival_delay_seconds
        - LAG(arrival_delay_seconds) OVER (
            PARTITION BY trip_id
            ORDER BY stop_sequence
        ) AS delay_change_seconds

    FROM arrival_delays
)
SELECT
    stop_id,
    stop_name,
    COUNT(*) AS trips_observed,

    ROUND(AVG(delay_change_seconds)::numeric, 2)
        AS avg_delay_change_seconds,

    ROUND(MAX(delay_change_seconds)::numeric, 2)
        AS max_delay_increase_seconds,

    COUNT(*) FILTER (
        WHERE delay_change_seconds > 0
    ) AS trips_with_increasing_delay

FROM delay_changes
WHERE delay_change_seconds IS NOT NULL
GROUP BY stop_id, stop_name
ORDER BY avg_delay_change_seconds DESC NULLS LAST;

-- BASIC 2: DELAY STATISTICS BY TYPE

SELECT
    delay_type,
    COUNT(*) AS event_count,
    SUM(delay_duration) AS total_delay_minutes,
    ROUND(AVG(delay_duration)::numeric, 2)
        AS avg_delay_minutes
FROM delays
GROUP BY delay_type
ORDER BY total_delay_minutes DESC;

-- BASIC 2: DELAY STATISTICS BY TYPE

SELECT
    delay_type,
    COUNT(*) AS event_count,
    SUM(delay_duration) AS total_delay_minutes,
    ROUND(AVG(delay_duration)::numeric, 2)
        AS avg_delay_minutes
FROM delays
GROUP BY delay_type


-- BASIC 3: TOTAL RECORDED DELAY PER TRIP

SELECT
    trip_id,
    COUNT(*) AS delay_events,
    SUM(delay_duration) AS total_delay_minutes,
    ROUND(AVG(delay_duration)::numeric, 2)
        AS avg_event_delay_minutes
FROM delays
GROUP BY trip_id
ORDER BY total_delay_minutes DESC;


-- MEDIUM 1: DELAY ANALYSIS BY ROUTE

SELECT
    r.route_name,
    COUNT(d.delay_id) AS delay_events,
    COUNT(DISTINCT t.trip_id) AS affected_trips,
    SUM(d.delay_duration) AS total_delay_minutes,
    ROUND(AVG(d.delay_duration)::numeric, 2)
        AS avg_event_delay_minutes
FROM routes r
JOIN trips t
    ON t.route_id = r.route_id
JOIN delays d
    ON d.trip_id = t.trip_id
GROUP BY r.route_id, r.route_name
ORDER BY total_delay_minutes DESC;

-- MEDIUM 2: DELAY TYPE BREAKDOWN BY STOP

SELECT
    s.stop_name,
    d.delay_type,
    COUNT(*) AS event_count,
    SUM(d.delay_duration) AS total_delay_minutes,
    ROUND(AVG(d.delay_duration)::numeric, 2)
        AS avg_delay_minutes
FROM delays d
JOIN stops s
    ON s.stop_id = d.stop_id
GROUP BY
    s.stop_id,
    s.stop_name,
    d.delay_type
ORDER BY
    s.stop_name,
    total_delay_minutes DESC;


-- HARD 1: DELAY PROGRESSION ACROSS STOPS

WITH stop_delays AS (
    SELECT
        e.trip_id,
        e.stop_sequence,
        s.stop_name,
        EXTRACT(
            EPOCH FROM (
                e.actual_arrival - e.scheduled_arrival
            )
        ) / 60.0 AS lateness_minutes
    FROM trip_stop_event e
    JOIN stops s
        ON s.stop_id = e.stop_id
    WHERE e.scheduled_arrival IS NOT NULL
      AND e.actual_arrival IS NOT NULL
),
progression AS (
    SELECT
        *,
        LAG(lateness_minutes) OVER (
            PARTITION BY trip_id
            ORDER BY stop_sequence
        ) AS previous_lateness_minutes
    FROM stop_delays
)
SELECT
    trip_id,
    stop_sequence,
    stop_name,
    ROUND(lateness_minutes::numeric, 2)
        AS lateness_minutes,
    ROUND(previous_lateness_minutes::numeric, 2)
        AS previous_lateness_minutes,
    ROUND(
        (lateness_minutes - previous_lateness_minutes)::numeric,
        2
    ) AS change_in_lateness_minutes
FROM progression
ORDER BY trip_id, stop_sequence;

-- HARD 3: HOURLY DELAY PATTERNS BY TYPE

SELECT
    EXTRACT(HOUR FROM timestamp)::integer AS delay_hour,
    delay_type,
    COUNT(*) AS event_count,
    SUM(delay_duration) AS total_delay_minutes,
    ROUND(AVG(delay_duration)::numeric, 2)
        AS avg_delay_minutes
FROM delays
GROUP BY
    EXTRACT(HOUR FROM timestamp)::integer,
    delay_type
ORDER BY
    delay_hour,
    total_delay_minutes DESC;