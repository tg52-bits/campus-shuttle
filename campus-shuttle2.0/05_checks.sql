-- =====================================================================
-- 05_checks.sql
-- A test suite for the schema, the derivation triggers and the constraints.
--
-- Run in : pgAdmin 4 > Query Tool on campus_shuttle, after files 02-04.
-- Use    : run PART 1 once (creates two functions), then run PART 2:
--              SELECT * FROM public.run_checks();
-- Effect : the tests create their own trips on dates in 2030, feed them GPS,
--          try illegal inserts, and then ROLL EVERYTHING BACK. Your data is
--          not changed. (Sequence counters still advance, so identity ids
--          show gaps afterwards; that is normal PostgreSQL behaviour.)
-- Time   : roughly 20-40 seconds (it generates a whole test timetable day).
-- Reading the result: every row is one check; passed = true is good. The
--          last row summarises. If a check fails, `detail` says what was seen.
--
-- Coverage (project requirements, section 15):
--   valid trip creation; invalid route/vehicle/driver references; correct
--   stop-event generation; duplicate-generation prevention; route-stop
--   sequence consistency; scheduled timestamps; trip actual start/end;
--   Scheduled -> In Progress -> Completed; corrected and deleted observations;
--   missing observations; early/late handled by the demo-data queries (06);
--   geometry validity and SRID; GPS ordering; route deviation; drive-by vs
--   real stop; out-of-order fixes; live path == batch path; temporal rules.
-- =====================================================================


-- =====================================================================
-- PART 1: helper and the test function
-- =====================================================================
CREATE OR REPLACE FUNCTION public._chk(p_area text, p_test text, p_ok boolean, p_detail text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
    SELECT jsonb_build_object('area', p_area, 'test', p_test,
                              'passed', coalesce(p_ok, false), 'detail', p_detail)
$$;

CREATE OR REPLACE FUNCTION public.run_checks()
RETURNS TABLE (test_no integer, area text, test text, passed boolean, detail text)
LANGUAGE plpgsql AS $$
DECLARE
    res jsonb := '[]'::jsonb;
    d text; m text;
    r1 integer; r2 integer; tr integer; tr2 integer;
    t1 integer; tC integer; t2 integer; t3 integer;
    dur integer; n integer; n2 integer; k integer;
    g1 record; g2 record;
    rid integer; ids bigint[]; v_new bigint;
    s1 jsonb; s2 jsonb; st text; loc geometry; far_pt geometry; t0 timestamp;
    max_arr numeric; max_dep numeric; ev record;
    ok boolean;
BEGIN
  BEGIN   -- everything in this block is rolled back at the end
    SELECT route_id INTO r1 FROM public.routes WHERE route_code = 'R1';
    SELECT route_id INTO r2 FROM public.routes WHERE route_code = 'R2';

    ------------------------------------------------------------------
    -- A. Map and route derivation (uses the loaded synthetic map)
    ------------------------------------------------------------------
    SELECT count(*) INTO n FROM public.routes
    WHERE route_geometry IS NULL OR NOT ST_IsValid(route_geometry)
       OR ST_SRID(route_geometry) <> 4326 OR GeometryType(route_geometry) <> 'LINESTRING';
    res := res || public._chk('Spatial', 'every route has a valid LINESTRING in SRID 4326', n = 0, n || ' bad routes');

    SELECT count(*) INTO n FROM public.road_segments
    WHERE NOT ST_IsValid(geom) OR ST_SRID(geom) <> 4326 OR length_m <= 0;
    res := res || public._chk('Spatial', 'every road segment is valid, SRID 4326, positive length', n = 0, n || ' bad roads');

    SELECT count(*) INTO n FROM public.stops
    WHERE road_id IS NULL OR snap_distance_m IS NULL OR snap_distance_m > 1 OR snapped_location IS NULL;
    res := res || public._chk('Spatial', 'every stop is snapped to a road within 1 m', n = 0, n || ' stops not snapped');

    SELECT count(*) INTO n FROM (
        SELECT r.route_id
        FROM public.routes r
        JOIN LATERAL (SELECT s.location FROM public.route_stops rs JOIN public.stops s USING (stop_id)
                      WHERE rs.route_id = r.route_id ORDER BY rs.stop_sequence ASC  LIMIT 1) f ON true
        JOIN LATERAL (SELECT s.location FROM public.route_stops rs JOIN public.stops s USING (stop_id)
                      WHERE rs.route_id = r.route_id ORDER BY rs.stop_sequence DESC LIMIT 1) l ON true
        WHERE ST_Distance(ST_StartPoint(r.route_geometry)::geography, f.location::geography) > 1
           OR ST_Distance(ST_EndPoint(r.route_geometry)::geography,   l.location::geography) > 1) x;
    res := res || public._chk('Spatial', 'each route starts at its first stop and ends at its last stop', n = 0, n || ' routes off');

    SELECT count(*) INTO n FROM (
        SELECT route_id, seq, start_measure_m,
               lag(end_measure_m) OVER (PARTITION BY route_id ORDER BY seq) AS prev_end
        FROM public.route_segments) x
    WHERE (seq = 1 AND start_measure_m <> 0) OR (seq > 1 AND abs(start_measure_m - prev_end) > 0.01);
    res := res || public._chk('Route', 'route segments are contiguous from 0 m', n = 0, n || ' gaps');

    SELECT count(*) INTO n FROM public.routes r
    WHERE abs((SELECT max(end_measure_m) FROM public.route_segments s WHERE s.route_id = r.route_id)
              - ST_Length(public.to_m(r.route_geometry))) > 1;
    res := res || public._chk('Route', 'route segment total equals route line length (within 1 m)', n = 0, n || ' mismatches');

    SELECT count(*) INTO n FROM (
        SELECT route_id, stop_sequence, distance_from_start_m,
               lag(distance_from_start_m) OVER (PARTITION BY route_id ORDER BY stop_sequence) AS prev_d
        FROM public.route_stops) x
    WHERE (stop_sequence = 1 AND distance_from_start_m <> 0)
       OR (prev_d IS NOT NULL AND distance_from_start_m < prev_d);
    res := res || public._chk('Route', 'stop distances start at 0 and never decrease', n = 0, n || ' violations');

    SELECT count(*) INTO n FROM (
        SELECT planned_arrival_offset_s AS arr, planned_departure_offset_s AS dep,
               lag(planned_departure_offset_s) OVER (PARTITION BY route_id ORDER BY stop_sequence) AS prev_dep
        FROM public.route_stops) x
    WHERE arr IS NULL OR dep IS NULL OR dep < arr OR (prev_dep IS NOT NULL AND arr < prev_dep);
    res := res || public._chk('Route', 'planned offsets are complete and non-decreasing', n = 0, n || ' violations');

    -- typed offsets are protected; missing ones are derived; one-stop route builds nothing
    INSERT INTO public.routes (route_code, route_name, data_source) VALUES ('TST', 'Test typed offsets', 'assumed') RETURNING route_id INTO tr;
    INSERT INTO public.route_stops (route_id, stop_id, stop_sequence, planned_arrival_offset_s, planned_departure_offset_s)
    SELECT tr, s.stop_id, v.seq, v.arr_s, v.dep_s
    FROM (VALUES ('S01', 1, 0, 0), ('S02', 2, 300, 330), ('S03', 3, 600, 630)) v(code, seq, arr_s, dep_s)
    JOIN public.stops s ON s.stop_code = v.code;
    SET CONSTRAINTS ALL IMMEDIATE;
    SET CONSTRAINTS ALL DEFERRED;
    SELECT array_agg(planned_arrival_offset_s ORDER BY stop_sequence)::text INTO d FROM public.route_stops WHERE route_id = tr;
    res := res || public._chk('Route', 'offsets typed in by hand are not overwritten', d = '{0,300,600}', d);
    SELECT (route_geometry IS NOT NULL) INTO ok FROM public.routes WHERE route_id = tr;
    res := res || public._chk('Route', 'a new route gets its geometry from its stops automatically', ok, NULL);

    INSERT INTO public.routes (route_code, route_name, data_source) VALUES ('TST2', 'Test derived offsets', 'assumed') RETURNING route_id INTO tr2;
    INSERT INTO public.route_stops (route_id, stop_id, stop_sequence)
    SELECT tr2, s.stop_id, v.seq FROM (VALUES ('S01', 1), ('S03', 2)) v(code, seq) JOIN public.stops s ON s.stop_code = v.code;
    SET CONSTRAINTS ALL IMMEDIATE;
    SET CONSTRAINTS ALL DEFERRED;
    SELECT (min(planned_arrival_offset_s) = 0 AND max(planned_arrival_offset_s) > 0 AND bool_and(NOT offsets_entered))
      INTO ok FROM public.route_stops WHERE route_id = tr2;
    res := res || public._chk('Route', 'missing offsets are derived from distance and design speed', ok, NULL);

    INSERT INTO public.routes (route_code, route_name, data_source) VALUES ('TST3', 'Test one stop', 'assumed') RETURNING route_id INTO n;
    INSERT INTO public.route_stops (route_id, stop_id, stop_sequence) SELECT n, stop_id, 1 FROM public.stops WHERE stop_code = 'S01';
    SET CONSTRAINTS ALL IMMEDIATE;
    SET CONSTRAINTS ALL DEFERRED;
    SELECT (route_geometry IS NULL) INTO ok FROM public.routes WHERE route_id = n;
    res := res || public._chk('Route', 'a one-stop route is left unbuilt without an error', ok, NULL);

    ------------------------------------------------------------------
    -- B. Trips and planned stop events
    ------------------------------------------------------------------
    INSERT INTO public.trips (service_date, route_id, vehicle_id, driver_id, scheduled_start, status, data_source)
    VALUES (DATE '2030-01-07', r1, 1, 1, TIMESTAMP '2030-01-07 08:00', 'Scheduled', 'assumed') RETURNING trip_id INTO t1;
    SELECT max(planned_departure_offset_s) INTO dur FROM public.route_stops WHERE route_id = r1;
    SELECT (scheduled_end = scheduled_start + make_interval(secs => dur)) INTO ok FROM public.trips WHERE trip_id = t1;
    res := res || public._chk('Trips', 'scheduled_end = start + last stop planned departure', ok, 'duration ' || dur || ' s');

    SELECT count(*) INTO n  FROM public.trip_stop_event WHERE trip_id = t1;
    SELECT count(*) INTO n2 FROM public.route_stops WHERE route_id = r1;
    res := res || public._chk('Trips', 'one stop event per route stop', n = n2, n || ' events, ' || n2 || ' route stops');

    SELECT count(*) INTO n FROM (
        SELECT stop_id, stop_sequence FROM public.route_stops WHERE route_id = r1
        EXCEPT SELECT stop_id, stop_sequence FROM public.trip_stop_event WHERE trip_id = t1) x;
    res := res || public._chk('Trips', 'stop events match the route stop order exactly', n = 0, n || ' differences');

    SELECT count(*) INTO n
    FROM public.trip_stop_event e
    JOIN public.trips t USING (trip_id)
    JOIN public.route_stops rs ON rs.route_id = t.route_id AND rs.stop_sequence = e.stop_sequence
    WHERE e.trip_id = t1
      AND (e.scheduled_arrival   <> t.scheduled_start + make_interval(secs => rs.planned_arrival_offset_s)
        OR e.scheduled_departure <> t.scheduled_start + make_interval(secs => rs.planned_departure_offset_s));
    res := res || public._chk('Trips', 'scheduled timestamps = trip start + route offsets', n = 0, n || ' wrong');

    SELECT count(*) INTO n FROM public.trip_stop_event
    WHERE trip_id = t1 AND (actual_arrival IS NOT NULL OR actual_departure IS NOT NULL);
    SELECT status INTO st FROM public.trips WHERE trip_id = t1;
    res := res || public._chk('Trips', 'new trip has no invented actual times and is Scheduled', n = 0 AND st = 'Scheduled', 'status ' || st);

    SELECT * INTO g1 FROM public.generate_service_day(DATE '2030-01-08');
    SELECT * INTO g2 FROM public.generate_service_day(DATE '2030-01-08');
    res := res || public._chk('Trips', 'generating a day twice creates no duplicates',
        g1.trips_created > 0 AND g2.trips_created = 0 AND g2.departures_skipped_existing = g1.trips_created,
        'first call ' || g1.trips_created || ' created; second call ' || g2.trips_created || ' created, '
        || g2.departures_skipped_existing || ' skipped');

    SELECT count(*) INTO n FROM public.trips t
    WHERE t.service_date = DATE '2030-01-08'
      AND (SELECT count(*) FROM public.trip_stop_event e WHERE e.trip_id = t.trip_id)
        <> (SELECT count(*) FROM public.route_stops rs WHERE rs.route_id = t.route_id);
    res := res || public._chk('Trips', 'every generated trip has the right number of stop events', n = 0, n || ' trips wrong');

    -- illegal inserts
    BEGIN
        INSERT INTO public.trips (service_date, route_id, vehicle_id, scheduled_start, status)
        VALUES (DATE '2030-01-10', 999999, 1, TIMESTAMP '2030-01-10 08:00', 'Scheduled');
        res := res || public._chk('Integrity', 'invalid route reference rejected', false, 'insert succeeded');
    EXCEPTION WHEN foreign_key_violation THEN
        res := res || public._chk('Integrity', 'invalid route reference rejected', true, NULL);
    END;
    BEGIN
        INSERT INTO public.trips (service_date, route_id, vehicle_id, scheduled_start, status)
        VALUES (DATE '2030-01-10', r1, 999999, TIMESTAMP '2030-01-10 08:00', 'Scheduled');
        res := res || public._chk('Integrity', 'invalid vehicle reference rejected', false, 'insert succeeded');
    EXCEPTION WHEN foreign_key_violation THEN
        res := res || public._chk('Integrity', 'invalid vehicle reference rejected', true, NULL);
    END;
    BEGIN
        INSERT INTO public.trips (service_date, route_id, vehicle_id, driver_id, scheduled_start, status)
        VALUES (DATE '2030-01-10', r1, 1, 999999, TIMESTAMP '2030-01-10 08:00', 'Scheduled');
        res := res || public._chk('Integrity', 'invalid driver reference rejected', false, 'insert succeeded');
    EXCEPTION WHEN foreign_key_violation THEN
        res := res || public._chk('Integrity', 'invalid driver reference rejected', true, NULL);
    END;
    BEGIN
        INSERT INTO public.trips (service_date, route_id, vehicle_id, scheduled_start, status)
        VALUES (DATE '2030-01-07', r1, 1, TIMESTAMP '2030-01-07 08:05', 'Scheduled');
        res := res || public._chk('Temporal', 'a vehicle cannot have two overlapping trips', false, 'insert succeeded');
    EXCEPTION WHEN exclusion_violation THEN
        res := res || public._chk('Temporal', 'a vehicle cannot have two overlapping trips', true, NULL);
    END;
    BEGIN
        INSERT INTO public.trips (service_date, route_id, vehicle_id, driver_id, scheduled_start, status)
        VALUES (DATE '2030-01-07', r1, 2, 1, TIMESTAMP '2030-01-07 08:05', 'Scheduled');
        res := res || public._chk('Temporal', 'a driver cannot have two overlapping trips', false, 'insert succeeded');
    EXCEPTION WHEN exclusion_violation THEN
        res := res || public._chk('Temporal', 'a driver cannot have two overlapping trips', true, NULL);
    END;
    BEGIN
        INSERT INTO public.vehicle_status_history (vehicle_id, status, valid_period)
        VALUES (3, 'Maintenance', tsrange('2030-02-01 00:00', '2030-02-02 00:00'));
        INSERT INTO public.trips (service_date, route_id, vehicle_id, scheduled_start, status)
        VALUES (DATE '2030-02-01', r1, 3, TIMESTAMP '2030-02-01 09:00', 'Scheduled');
        res := res || public._chk('Temporal', 'a vehicle in Maintenance cannot be given a trip', false, 'insert succeeded');
    EXCEPTION WHEN raise_exception THEN
        res := res || public._chk('Temporal', 'a vehicle in Maintenance cannot be given a trip', true, SQLERRM);
    END;
    BEGIN
        INSERT INTO public.vehicle_status_history (vehicle_id, status, valid_period)
        VALUES (4, 'Active', tsrange('2030-03-01', '2030-03-10')), (4, 'Not Active', tsrange('2030-03-05', '2030-03-12'));
        res := res || public._chk('Temporal', 'overlapping vehicle status periods rejected', false, 'insert succeeded');
    EXCEPTION WHEN exclusion_violation THEN
        res := res || public._chk('Temporal', 'overlapping vehicle status periods rejected', true, NULL);
    END;
    BEGIN
        INSERT INTO public.timetable_departures (route_id, day_type, departure_time, valid_from)
        SELECT route_id, day_type, departure_time, valid_from + 30 FROM public.timetable_departures LIMIT 1;
        res := res || public._chk('Temporal', 'overlapping timetable versions rejected', false, 'insert succeeded');
    EXCEPTION WHEN exclusion_violation THEN
        res := res || public._chk('Temporal', 'overlapping timetable versions rejected', true, NULL);
    END;
    BEGIN
        INSERT INTO public.trips (service_date, route_id, vehicle_id, scheduled_start, status)
        VALUES (DATE '2030-01-11', r1, 5, TIMESTAMP '2030-01-12 08:00', 'Scheduled');
        res := res || public._chk('Integrity', 'service_date must match scheduled_start', false, 'insert succeeded');
    EXCEPTION WHEN raise_exception THEN
        res := res || public._chk('Integrity', 'service_date must match scheduled_start', true, NULL);
    END;
    BEGIN
        UPDATE public.trips SET route_id = r2 WHERE trip_id = t1;
        res := res || public._chk('Integrity', 'route of a trip with stop events cannot be changed', false, 'update succeeded');
    EXCEPTION WHEN raise_exception THEN
        res := res || public._chk('Integrity', 'route of a trip with stop events cannot be changed', true, NULL);
    END;

    ------------------------------------------------------------------
    -- C. GPS pipeline: trip assignment, route matching, stop detection,
    --    status transitions, corrections, live path == batch path
    ------------------------------------------------------------------
    INSERT INTO public.trips (service_date, route_id, vehicle_id, driver_id, scheduled_start, status, data_source)
    VALUES (DATE '2030-01-09', r2, 2, 2, TIMESTAMP '2030-01-09 10:00', 'Scheduled', 'assumed') RETURNING trip_id INTO tC;

    rid := sim.new_run(7, 'run_checks');
    PERFORM set_config('shuttle.derive_on_insert', 'off', true);          -- insert raw fixes without deriving
    k := sim.generate_trip_gps(tC, rid, p_noise_m => 0, p_dropout => 0);
    PERFORM set_config('shuttle.derive_on_insert', 'on', true);
    res := res || public._chk('GPS', 'simulator produced fixes without a trip_id', k > 100, k || ' fixes');

    ids := ARRAY(SELECT position_id FROM public.vehicle_position
                 WHERE vehicle_id = 2 AND recorded_at::date = DATE '2030-01-09' ORDER BY recorded_at);
    SELECT status INTO st FROM public.trips WHERE trip_id = tC;
    res := res || public._chk('Status', 'before any GPS the trip is Scheduled', st = 'Scheduled', st);

    PERFORM public.process_position(ids[1]);
    SELECT status INTO st FROM public.trips WHERE trip_id = tC;
    SELECT trip_id INTO n FROM public.vehicle_position WHERE position_id = ids[1];
    res := res || public._chk('GPS', 'the first fix is assigned to the right trip by inference', n = tC, 'assigned ' || coalesce(n::text, 'NULL'));
    res := res || public._chk('Status', 'after the first fix at stop 1 the trip is In Progress', st = 'In Progress', st);

    FOR k IN 2 .. array_length(ids, 1) LOOP
        PERFORM public.process_position(ids[k]);
    END LOOP;
    SELECT status INTO st FROM public.trips WHERE trip_id = tC;
    res := res || public._chk('Status', 'after the last fix the trip is Completed', st = 'Completed', st);

    SELECT count(*) INTO n FROM public.vehicle_position WHERE vehicle_id = 2 AND recorded_at::date = DATE '2030-01-09' AND trip_id IS DISTINCT FROM tC;
    res := res || public._chk('GPS', 'every fix of the trip was assigned to it', n = 0, n || ' fixes elsewhere');

    SELECT count(*) INTO n FROM public.trip_stop_event WHERE trip_id = tC AND actual_arrival IS NULL;
    res := res || public._chk('Observations', 'every stop has an inferred arrival', n = 0, n || ' stops without arrival');

    SELECT (t.actual_start = coalesce(f.actual_departure, f.actual_arrival)
            AND t.actual_end = coalesce(l.actual_departure, l.actual_arrival)) INTO ok
    FROM public.trips t
    JOIN public.trip_stop_event f ON f.trip_id = t.trip_id AND f.stop_sequence = 1
    JOIN public.trip_stop_event l ON l.trip_id = t.trip_id
         AND l.stop_sequence = (SELECT max(stop_sequence) FROM public.trip_stop_event WHERE trip_id = t.trip_id)
    WHERE t.trip_id = tC;
    res := res || public._chk('Status', 'actual start/end come from the first/last stop events', ok, NULL);

    SELECT max(abs(EXTRACT(EPOCH FROM e.actual_arrival - v.true_arrival))),
           max(abs(EXTRACT(EPOCH FROM e.actual_departure - v.true_departure)))
      INTO max_arr, max_dep
    FROM public.trip_stop_event e
    JOIN sim.true_stop_visit v ON v.run_id = rid AND v.trip_id = e.trip_id AND v.stop_sequence = e.stop_sequence
    WHERE e.trip_id = tC AND e.actual_departure IS NOT NULL;
    res := res || public._chk('Observations', 'inferred stop times match the simulator truth (noise-free, within 10 s)',
                              max_arr <= 10 AND max_dep <= 10, 'max arrival error ' || round(max_arr, 1) || ' s, departure ' || round(max_dep, 1) || ' s');

    SELECT count(*) INTO n FROM public.position_match WHERE trip_id = tC AND (NOT on_route OR dist_to_route_m > 1);
    res := res || public._chk('Spatial', 'noise-free fixes lie on the route (route deviation < 1 m)', n = 0, n || ' fixes deviating');

    SELECT count(*) INTO n FROM (
        SELECT pm.measure_m, lag(pm.measure_m) OVER (ORDER BY vp.recorded_at) AS prev_m
        FROM public.position_match pm JOIN public.vehicle_position vp USING (position_id)
        WHERE pm.trip_id = tC) x
    WHERE prev_m IS NOT NULL AND measure_m < prev_m - 1;
    res := res || public._chk('Spatial', 'route position never moves backwards in time order', n = 0, n || ' backwards steps');

    SELECT count(*) INTO n  FROM public.segment_traversal WHERE trip_id = tC;
    SELECT count(*) INTO n2 FROM public.route_segments WHERE route_id = r2;
    res := res || public._chk('Derived', 'a completed trip has one traversal per route segment', n = n2, n || ' traversals, ' || n2 || ' segments');

    SELECT count(*) INTO n FROM public.segment_traversal WHERE trip_id = tC AND (avg_speed_kmh < 3 OR avg_speed_kmh > 40);
    res := res || public._chk('Derived', 'traversal speeds are plausible (3-40 km/h)', n = 0, n || ' outside range');

    SELECT count(*) INTO n FROM public.segment_traversal trv
    WHERE trv.trip_id = tC AND NOT EXISTS (SELECT 1 FROM public.segment_speed_profile p WHERE p.road_id = trv.road_id);
    res := res || public._chk('Derived', 'the speed profile covers every traversed road', n = 0, n || ' roads missing');

    -- live path == batch path
    SELECT jsonb_agg(jsonb_build_object('s', stop_sequence, 'a', actual_arrival, 'd', actual_departure) ORDER BY stop_sequence)
      INTO s1 FROM public.trip_stop_event WHERE trip_id = tC;
    SELECT count(*) INTO n FROM public.position_match WHERE trip_id = tC;
    SELECT count(*) INTO n2 FROM public.segment_traversal WHERE trip_id = tC;
    k := public.reprocess_trip(tC);
    SELECT jsonb_agg(jsonb_build_object('s', stop_sequence, 'a', actual_arrival, 'd', actual_departure) ORDER BY stop_sequence)
      INTO s2 FROM public.trip_stop_event WHERE trip_id = tC;
    res := res || public._chk('Equivalence', 'reprocess_trip reproduces the trigger-path results exactly',
        s1 = s2 AND n = (SELECT count(*) FROM public.position_match WHERE trip_id = tC)
                AND n2 = (SELECT count(*) FROM public.segment_traversal WHERE trip_id = tC),
        k || ' fixes replayed');

    -- corrections and deletions
    UPDATE public.trip_stop_event SET actual_arrival = NULL, actual_departure = NULL, detection_method = NULL
    WHERE trip_id = tC AND stop_sequence = (SELECT max(stop_sequence) FROM public.trip_stop_event WHERE trip_id = tC);
    SELECT status, actual_end INTO ev FROM public.trips WHERE trip_id = tC;
    res := res || public._chk('Status', 'removing the final observation reverts the trip to In Progress with no end time',
                              ev.status = 'In Progress' AND ev.actual_end IS NULL, ev.status || ', end ' || coalesce(ev.actual_end::text, 'NULL'));

    UPDATE public.trip_stop_event SET actual_departure = actual_arrival + interval '90 seconds', detection_method = 'manual'
    WHERE trip_id = tC AND stop_sequence = 1;
    SELECT (t.actual_start = e.actual_arrival + interval '90 seconds') INTO ok
    FROM public.trips t JOIN public.trip_stop_event e ON e.trip_id = t.trip_id AND e.stop_sequence = 1 WHERE t.trip_id = tC;
    res := res || public._chk('Status', 'a corrected first-stop time updates the trip actual_start', ok, NULL);

    UPDATE public.trip_stop_event SET actual_arrival = NULL, actual_departure = NULL, detection_method = NULL WHERE trip_id = tC;
    SELECT status, actual_start, actual_end INTO ev FROM public.trips WHERE trip_id = tC;
    res := res || public._chk('Status', 'clearing all observations returns the trip to Scheduled with null actuals',
                              ev.status = 'Scheduled' AND ev.actual_start IS NULL AND ev.actual_end IS NULL, ev.status);

    k := public.reprocess_trip(tC);
    SELECT status INTO st FROM public.trips WHERE trip_id = tC;
    res := res || public._chk('Status', 'reprocessing the GPS restores Completed', st = 'Completed', st);

    -- out-of-order fix
    SELECT max(recorded_at) INTO t0 FROM public.vehicle_position WHERE trip_id = tC;
    INSERT INTO public.vehicle_position (vehicle_id, recorded_at, location, data_source)
    SELECT 2, t0 - interval '90 seconds' + interval '123 milliseconds', location, 'simulated'
    FROM public.stops WHERE stop_code = 'S02' RETURNING position_id INTO v_new;
    SELECT count(*) INTO n FROM public.position_match WHERE position_id = v_new;
    res := res || public._chk('GPS', 'a late-arriving (out-of-order) fix is not derived, and does not corrupt the trip',
                              n = 0 AND (SELECT status FROM public.trips WHERE trip_id = tC) = 'Completed', NULL);

    -- an observation moved between trips: both trips are recalculated
    INSERT INTO public.trips (service_date, route_id, vehicle_id, driver_id, scheduled_start, status, data_source)
    VALUES (DATE '2030-01-09', r2, 5, 5, TIMESTAMP '2030-01-09 11:00', 'Scheduled', 'assumed') RETURNING trip_id INTO t2;
    DELETE FROM public.trip_stop_event WHERE trip_id = t2 AND stop_sequence = 2;
    UPDATE public.trip_stop_event SET trip_id = t2 WHERE trip_id = tC AND stop_sequence = 2;
    SELECT status INTO st FROM public.trips WHERE trip_id = t2;
    res := res || public._chk('Status', 'moving an observation to another trip recalculates the new trip', st = 'In Progress', st);

    -- drive-by versus a real stop (geofence + dwell rule)
    INSERT INTO public.trips (service_date, route_id, vehicle_id, driver_id, scheduled_start, status, data_source)
    VALUES (DATE '2030-01-09', r2, 6, 6, TIMESTAMP '2030-01-09 12:00', 'Scheduled', 'assumed') RETURNING trip_id INTO t3;
    SELECT location INTO loc FROM public.stops WHERE stop_code = 'S01';
    far_pt := ST_Project(loc::geography, 100, 0)::geometry;
    t0 := TIMESTAMP '2030-01-09 11:59:50';
    INSERT INTO public.vehicle_position (vehicle_id, recorded_at, location, data_source) VALUES (6, t0, far_pt, 'simulated');
    INSERT INTO public.vehicle_position (vehicle_id, recorded_at, location, data_source) VALUES (6, t0 + interval '4 seconds', loc, 'simulated');
    INSERT INTO public.vehicle_position (vehicle_id, recorded_at, location, data_source) VALUES (6, t0 + interval '8 seconds', far_pt, 'simulated');
    SELECT actual_arrival INTO ev FROM public.trip_stop_event WHERE trip_id = t3 AND stop_sequence = 1;
    res := res || public._chk('Observations', 'passing the stop in a few seconds is a drive-by, not a visit',
                              ev.actual_arrival IS NULL AND (SELECT status FROM public.trips WHERE trip_id = t3) = 'Scheduled', NULL);
    INSERT INTO public.vehicle_position (vehicle_id, recorded_at, location, data_source) VALUES (6, t0 + interval '60 seconds', loc, 'simulated');
    INSERT INTO public.vehicle_position (vehicle_id, recorded_at, location, data_source) VALUES (6, t0 + interval '75 seconds', loc, 'simulated');
    INSERT INTO public.vehicle_position (vehicle_id, recorded_at, location, data_source) VALUES (6, t0 + interval '90 seconds', far_pt, 'simulated');
    SELECT actual_arrival, actual_departure INTO ev FROM public.trip_stop_event WHERE trip_id = t3 AND stop_sequence = 1;
    res := res || public._chk('Observations', 'stopping and dwelling creates an arrival and a departure',
                              ev.actual_arrival IS NOT NULL AND ev.actual_departure IS NOT NULL
                              AND ev.actual_departure - ev.actual_arrival >= interval '5 seconds',
                              coalesce(ev.actual_arrival::text, 'NULL') || ' -> ' || coalesce(ev.actual_departure::text, 'NULL'));

    ------------------------------------------------------------------
    -- D. Constraints
    ------------------------------------------------------------------
    BEGIN
        INSERT INTO public.stops (stop_name, location) VALUES ('Bad lon', ST_SetSRID(ST_MakePoint(200, 17), 4326));
        res := res || public._chk('Integrity', 'a stop with longitude 200 is rejected', false, 'insert succeeded');
    EXCEPTION WHEN check_violation THEN
        res := res || public._chk('Integrity', 'a stop with longitude 200 is rejected', true, NULL);
    END;
    BEGIN
        INSERT INTO public.vehicle_position (vehicle_id, recorded_at, location)
        SELECT vehicle_id, recorded_at, location FROM public.vehicle_position LIMIT 1;
        res := res || public._chk('Integrity', 'a duplicate fix (same vehicle and instant) is rejected', false, 'insert succeeded');
    EXCEPTION WHEN unique_violation THEN
        res := res || public._chk('Integrity', 'a duplicate fix (same vehicle and instant) is rejected', true, NULL);
    END;
    BEGIN
        INSERT INTO public.stops (stop_name, location, data_source)
        VALUES ('Bad source', ST_SetSRID(ST_MakePoint(78.3, 17.4), 4326), 'made_up');
        res := res || public._chk('Integrity', 'an unknown data_source label is rejected', false, 'insert succeeded');
    EXCEPTION WHEN check_violation THEN
        res := res || public._chk('Integrity', 'an unknown data_source label is rejected', true, NULL);
    END;
    BEGIN
        INSERT INTO public.vehicle_position (vehicle_id, recorded_at, location, speed_kmh)
        VALUES (7, TIMESTAMP '2030-01-09 09:00', ST_SetSRID(ST_MakePoint(78.33, 17.45), 4326), -5);
        res := res || public._chk('Integrity', 'a negative speed is rejected', false, 'insert succeeded');
    EXCEPTION WHEN check_violation THEN
        res := res || public._chk('Integrity', 'a negative speed is rejected', true, NULL);
    END;
    BEGIN
        UPDATE public.trip_stop_event
        SET actual_arrival = TIMESTAMP '2030-01-09 10:10', actual_departure = TIMESTAMP '2030-01-09 10:05'
        WHERE trip_id = t1 AND stop_sequence = 1;
        res := res || public._chk('Integrity', 'a departure before the arrival is rejected', false, 'update succeeded');
    EXCEPTION WHEN check_violation THEN
        res := res || public._chk('Integrity', 'a departure before the arrival is rejected', true, NULL);
    END;
    BEGIN
        UPDATE public.routes SET route_geometry = ST_GeomFromText('LINESTRING EMPTY', 4326) WHERE route_id = r1;
        res := res || public._chk('Integrity', 'an empty route geometry is rejected', false, 'update succeeded');
    EXCEPTION WHEN check_violation THEN
        res := res || public._chk('Integrity', 'an empty route geometry is rejected', true, NULL);
    END;

    RAISE EXCEPTION 'ROLLBACK_CHECKS' USING DETAIL = res::text;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS d = PG_EXCEPTION_DETAIL, m = MESSAGE_TEXT;
    IF m = 'ROLLBACK_CHECKS' THEN
        res := d::jsonb;                                   -- normal end: all test data rolled back
    ELSE
        res := res || public._chk('ERROR', 'test run aborted (see detail)', false, m);
    END IF;
  END;

  RETURN QUERY
    SELECT x.ord::integer, x.j ->> 'area', x.j ->> 'test', (x.j ->> 'passed')::boolean, x.j ->> 'detail'
    FROM jsonb_array_elements(res) WITH ORDINALITY AS x(j, ord)
    UNION ALL
    SELECT 9999, 'SUMMARY', count(*) FILTER (WHERE (j ->> 'passed')::boolean) || ' passed, '
                            || count(*) FILTER (WHERE NOT (j ->> 'passed')::boolean) || ' failed',
           count(*) FILTER (WHERE NOT (j ->> 'passed')::boolean) = 0, NULL
    FROM jsonb_array_elements(res) AS j
    ORDER BY 1;
END $$;


-- =====================================================================
-- PART 2: run the checks
-- =====================================================================
SELECT * FROM public.run_checks();

-- Afterwards, confirm nothing was left behind (expect 0 test trips, 0 test routes):
SELECT (SELECT count(*) FROM public.trips WHERE service_date >= DATE '2030-01-01') AS test_trips_left,
       (SELECT count(*) FROM public.routes WHERE route_code LIKE 'TST%') AS test_routes_left;