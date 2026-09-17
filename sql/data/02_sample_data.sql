-- SAMPLE DATA

-- 1. DRIVERS
INSERT INTO drivers (name, license_info) VALUES
('Amit Sharma', 'DL-001'),
('Priya Singh', 'DL-002'),
('Rahul Verma', 'DL-003');


-- 2. VEHICLES
INSERT INTO vehicles (vehicle_type, capacity, status) VALUES
('Electric Bus', 40, 'Active'),
('Electric Bus', 50, 'Active'),
('Mini Bus', 25, 'Maintenance');


-- 3. STOPS
-- Coordinates are synthetic test locations.
INSERT INTO stops (stop_name, location) VALUES
(
    'Main Gate',
    ST_SetSRID(ST_MakePoint(78.4867, 17.3850), 4326)
),
(
    'Library',
    ST_SetSRID(ST_MakePoint(78.4880, 17.3860), 4326)
),
(
    'Hostel',
    ST_SetSRID(ST_MakePoint(78.4900, 17.3875), 4326)
);


-- 4. ROUTES
INSERT INTO routes (route_name, route_geometry) VALUES
(
    'Route A',
    ST_SetSRID(
        ST_GeomFromText(
            'LINESTRING(
                78.4867 17.3850,
                78.4880 17.3860,
                78.4900 17.3875
            )'
        ),
        4326
    )
),
(
    'Route B',
    ST_SetSRID(
        ST_GeomFromText(
            'LINESTRING(
                78.4900 17.3875,
                78.4880 17.3860,
                78.4867 17.3850
            )'
        ),
        4326
    )
);


-- 5. ROUTE-STOP RELATIONSHIPS
INSERT INTO route_stops
(route_id, stop_id, stop_sequence)
VALUES
(1, 1, 1),
(1, 2, 2),
(1, 3, 3),
(2, 3, 1),
(2, 2, 2),
(2, 1, 3);


-- 6. TRIPS
INSERT INTO trips
(
    vehicle_id,
    route_id,
    driver_id,
    scheduled_start,
    scheduled_end,
    actual_start,
    actual_end,
    status
)
VALUES
(
    1,
    1,
    1,
    '2026-09-17 08:00',
    '2026-09-17 08:40',
    '2026-09-17 08:03',
    '2026-09-17 08:45',
    'Completed'
),
(
    2,
    1,
    2,
    '2026-09-17 08:30',
    '2026-09-17 09:10',
    '2026-09-17 08:37',
    '2026-09-17 09:20',
    'Completed'
),
(
    1,
    2,
    1,
    '2026-09-17 09:30',
    '2026-09-17 10:10',
    '2026-09-17 09:32',
    NULL,
    'In Progress'
);


-- 7. TRIP-STOP EVENTS
INSERT INTO trip_stop_event
(
    trip_id,
    stop_id,
    stop_sequence,
    scheduled_arrival,
    actual_arrival,
    scheduled_departure,
    actual_departure
)
VALUES
(
    1, 1, 1,
    '2026-09-17 08:05',
    '2026-09-17 08:07',
    '2026-09-17 08:06',
    '2026-09-17 08:08'
),
(
    1, 2, 2,
    '2026-09-17 08:18',
    '2026-09-17 08:21',
    '2026-09-17 08:19',
    '2026-09-17 08:22'
),
(
    1, 3, 3,
    '2026-09-17 08:30',
    '2026-09-17 08:35',
    '2026-09-17 08:31',
    '2026-09-17 08:36'
),
(
    2, 1, 1,
    '2026-09-17 08:35',
    '2026-09-17 08:42',
    '2026-09-17 08:36',
    '2026-09-17 08:43'
),
(
    2, 2, 2,
    '2026-09-17 08:48',
    '2026-09-17 08:56',
    '2026-09-17 08:49',
    '2026-09-17 08:57'
);


-- 8. OCCUPANCY
INSERT INTO occupancy
(
    trip_id,
    stop_id,
    timestamp,
    passenger_count
)
VALUES
(1, 1, '2026-09-17 08:08', 18),
(1, 2, '2026-09-17 08:22', 31),
(1, 3, '2026-09-17 08:36', 24),
(2, 1, '2026-09-17 08:43', 35),
(2, 2, '2026-09-17 08:57', 44);


-- 9. DELAYS
INSERT INTO delays
(
    trip_id,
    stop_id,
    delay_duration,
    delay_type,
    timestamp
)
VALUES
(1, 1, 2, 'Traffic', '2026-09-17 08:07'),
(1, 2, 3, 'High Occupancy', '2026-09-17 08:21'),
(1, 3, 5, 'Traffic', '2026-09-17 08:35'),
(2, 1, 7, 'Previous Trip Delay', '2026-09-17 08:42'),
(2, 2, 8, 'High Occupancy', '2026-09-17 08:56');


-- 10. VEHICLE GPS POSITIONS
INSERT INTO vehicle_position
(
    vehicle_id,
    trip_id,
    timestamp,
    location,
    speed
)
VALUES
(
    1, 1,
    '2026-09-17 08:10',
    ST_SetSRID(
        ST_MakePoint(78.4872, 17.3854),
        4326
    ),
    18.5
),
(
    1, 1,
    '2026-09-17 08:20',
    ST_SetSRID(
        ST_MakePoint(78.4880, 17.3860),
        4326
    ),
    15.2
),
(
    1, 1,
    '2026-09-17 08:30',
    ST_SetSRID(
        ST_MakePoint(78.4890, 17.3868),
        4326
    ),
    12.7
),
(
    2, 2,
    '2026-09-17 08:45',
    ST_SetSRID(
        ST_MakePoint(78.4875, 17.3856),
        4326
    ),
    16.4
),
(
    2, 2,
    '2026-09-17 08:55',
    ST_SetSRID(
        ST_MakePoint(78.4882, 17.3862),
        4326
    ),
    11.8
);