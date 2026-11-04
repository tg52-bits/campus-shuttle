-- =====================================================================
-- 04_simulator_v0.sql
-- A small first simulator (v0) so the triggers and queries have data to work
-- on. It generates ONLY raw GPS fixes. Everything else (stop times, lateness,
-- trip status, traversals, speed profile) is derived by the triggers from 03.
--
-- Run in : pgAdmin 4 > Query Tool on campus_shuttle, after 03.
-- Changes: creates functions in schema sim (PART 1); PART 2 loads one demo
--          day (inserts rows; run it once). PART 3 shows how to remove a run.
--
-- What is random (reproducible with a seed):
--   * driver/vehicle speed factor per trip (0.8 - 1.2 of the road limit, capped at 25 km/h)
--   * start offset (a few early, mostly slightly late)
--   * dwell at each stop (15 - 45 s)
--   * speed noise per segment
--   * GPS noise (uniform +/- 6 m), time jitter (+/- 0.5 s), 2% fix dropout
-- What is systematic (the pattern the analysis should rediscover):
--   * class-change congestion on weekdays: minutes :50-:10 of each hour between
--     08:00 and 18:00, strongest on roads in academic/administrative zones
--   * one injected incident per run (a slow-down on the busiest road)
--   * knock-on delay: a vehicle cannot start its next trip before it has
--     finished the previous one (+60 s turnaround), so late trips cascade
-- Limits of v0 (stated, not hidden): vehicles teleport between trip end and
-- next trip start; closures do not re-route; no skipped stops; one fix interval.
-- =====================================================================


-- =====================================================================
-- PART 1: simulator functions
-- =====================================================================
CREATE OR REPLACE FUNCTION sim.new_run(p_seed bigint, p_description text) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE rid integer;
BEGIN
    INSERT INTO sim.run (seed, parameters, description)
    VALUES (p_seed,
            jsonb_build_object('simulator', 'v0', 'gps_noise_m', 6, 'fix_interval_s', 5,
                               'dropout', 0.02, 'speed_cap_kmh', 25),
            p_description)
    RETURNING run_id INTO rid;
    PERFORM setseed(((p_seed % 1000000) / 1000000.0)::double precision);
    RETURN rid;
END $$;

-- Speed multiplier (1 = free flow) for a road at a time within a run.
CREATE OR REPLACE FUNCTION sim.congestion_factor(p_road_id integer, p_ts timestamp, p_run_id integer)
RETURNS double precision LANGUAGE plpgsql STABLE AS $$
DECLARE f double precision := 1.0; central boolean; m numeric;
BEGIN
    IF public.day_type_of(p_ts::date) = 'weekday'
       AND EXTRACT(HOUR FROM p_ts) BETWEEN 8 AND 17
       AND (EXTRACT(MINUTE FROM p_ts) >= 50 OR EXTRACT(MINUTE FROM p_ts) < 10) THEN
        SELECT EXISTS (
            SELECT 1 FROM public.road_segments r
            JOIN public.campus_zones z ON ST_Intersects(z.boundary, ST_LineInterpolatePoint(r.geom, 0.5))
            WHERE r.road_id = p_road_id AND z.zone_type IN ('academic', 'service')) INTO central;
        f := f * CASE WHEN central THEN 0.60 ELSE 0.90 END;
    END IF;

    SELECT min(e.magnitude) INTO m
    FROM sim.injected_event e
    WHERE e.run_id = p_run_id AND e.event_type = 'congestion'
      AND e.road_id = p_road_id AND e.valid_period @> p_ts;
    IF m IS NOT NULL THEN f := f * m::double precision; END IF;
    RETURN f;
END $$;

-- Simulate one trip: build a time/position profile along the route, then emit
-- GPS fixes from it. trip_id is deliberately left NULL on the fixes; the
-- database must infer it. Fixes later than p_asof are not emitted, so a trip
-- can be "in progress" at the as-of time. Ground truth goes to sim.true_stop_visit.
CREATE OR REPLACE FUNCTION sim.generate_trip_gps(
    p_trip_id integer, p_run_id integer,
    p_noise_m double precision DEFAULT 6,
    p_interval_s double precision DEFAULT 5,
    p_dropout double precision DEFAULT 0.02,
    p_asof timestamp DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE
    t record; r_m geometry; L double precision; sg record; stp integer; last_stp integer;
    times double precision[]; meas double precision[];
    clk double precision; trip_factor double precision; v_ms double precision; lim double precision;
    dwell double precision; prev_end timestamp; min_off double precision;
    s double precision; i integer := 1; m double precision; spd double precision;
    pt geometry; x double precision; y double precision; n integer := 0; last_i integer;
    srid integer := public.param('metric_srid')::int;
    ts timestamp;
BEGIN
    SELECT tr.trip_id, tr.vehicle_id, tr.route_id, tr.scheduled_start, r.route_geometry
      INTO t
    FROM public.trips tr JOIN public.routes r USING (route_id) WHERE tr.trip_id = p_trip_id;
    IF t.trip_id IS NULL THEN RAISE EXCEPTION 'trip % not found', p_trip_id; END IF;
    IF t.route_geometry IS NULL THEN RAISE EXCEPTION 'route % has no geometry', t.route_id; END IF;

    r_m := public.to_m(t.route_geometry);
    L   := ST_Length(r_m);
    SELECT max(stop_sequence) INTO last_stp FROM public.route_stops WHERE route_id = t.route_id;

    trip_factor := 0.80 + random() * 0.40;
    clk := (random() - 0.4) * 180;                       -- -72 s .. +108 s relative to schedule

    -- the vehicle cannot start before it finished its previous simulated trip
    SELECT max(tv.true_departure) INTO prev_end
    FROM sim.true_stop_visit tv JOIN public.trips pt2 ON pt2.trip_id = tv.trip_id
    WHERE tv.run_id = p_run_id AND pt2.vehicle_id = t.vehicle_id
      AND pt2.scheduled_start < t.scheduled_start;
    IF prev_end IS NOT NULL THEN
        min_off := EXTRACT(EPOCH FROM (prev_end + interval '60 seconds' - t.scheduled_start));
        clk := greatest(clk, min_off);
    END IF;

    -- first stop
    dwell := 15 + random() * 30;
    SELECT stop_sequence INTO stp FROM public.route_stops
    WHERE route_id = t.route_id AND distance_from_start_m < 1 ORDER BY stop_sequence LIMIT 1;
    INSERT INTO sim.true_stop_visit (run_id, trip_id, stop_sequence, true_arrival, true_departure)
    VALUES (p_run_id, p_trip_id, stp,
            t.scheduled_start + make_interval(secs => clk),
            t.scheduled_start + make_interval(secs => clk + dwell))
    ON CONFLICT (run_id, trip_id, stop_sequence) DO NOTHING;
    times := ARRAY[clk]; meas := ARRAY[0.0::double precision];
    clk := clk + dwell;
    times := times || clk; meas := meas || 0.0::double precision;

    FOR sg IN
        SELECT rs.road_id, rs.start_measure_m, rs.end_measure_m, rd.speed_limit_kmh
        FROM public.route_segments rs JOIN public.road_segments rd USING (road_id)
        WHERE rs.route_id = t.route_id ORDER BY rs.seq
    LOOP
        lim  := least(coalesce(sg.speed_limit_kmh, 25), 25);
        v_ms := greatest(lim * trip_factor
                         * sim.congestion_factor(sg.road_id, t.scheduled_start + make_interval(secs => clk), p_run_id)
                         * (0.9 + random() * 0.2), 4) / 3.6;
        clk := clk + (sg.end_measure_m - sg.start_measure_m)::double precision / v_ms;
        times := times || clk; meas := meas || sg.end_measure_m::double precision;

        SELECT stop_sequence INTO stp FROM public.route_stops
        WHERE route_id = t.route_id AND abs(distance_from_start_m - sg.end_measure_m) < 1
        ORDER BY stop_sequence LIMIT 1;
        IF FOUND THEN
            dwell := CASE WHEN stp = last_stp THEN 20 ELSE 15 + random() * 30 END;
            INSERT INTO sim.true_stop_visit (run_id, trip_id, stop_sequence, true_arrival, true_departure)
            VALUES (p_run_id, p_trip_id, stp,
                    t.scheduled_start + make_interval(secs => clk),
                    t.scheduled_start + make_interval(secs => clk + dwell))
            ON CONFLICT (run_id, trip_id, stop_sequence) DO NOTHING;
            clk := clk + dwell;
            times := times || clk; meas := meas || sg.end_measure_m::double precision;
        END IF;
    END LOOP;

    -- sample the profile into GPS fixes
    last_i := array_length(times, 1);
    s := times[1];
    WHILE s <= times[last_i] LOOP
        WHILE i < last_i - 1 AND times[i + 1] < s LOOP i := i + 1; END LOOP;
        IF times[i + 1] = times[i] THEN
            m := meas[i]; spd := 0;
        ELSE
            m   := meas[i] + (s - times[i]) / (times[i + 1] - times[i]) * (meas[i + 1] - meas[i]);
            spd := (meas[i + 1] - meas[i]) / (times[i + 1] - times[i]) * 3.6;
        END IF;

        ts := t.scheduled_start + make_interval(secs => s + (random() - 0.5));
        IF (p_asof IS NULL OR ts <= p_asof) AND random() >= p_dropout THEN
            pt := ST_LineInterpolatePoint(r_m, least(m / L, 1.0));
            x := ST_X(pt) + (random() - 0.5) * 2 * p_noise_m;
            y := ST_Y(pt) + (random() - 0.5) * 2 * p_noise_m;
            INSERT INTO public.vehicle_position
                   (vehicle_id, trip_id, recorded_at, location, speed_kmh, accuracy_m, sim_run_id, data_source)
            VALUES (t.vehicle_id, NULL, ts,
                    ST_Transform(ST_SetSRID(ST_MakePoint(x, y), srid), 4326),
                    round(greatest(spd + (random() - 0.5), 0)::numeric, 2), p_noise_m, p_run_id, 'simulated')
            ON CONFLICT (vehicle_id, recorded_at) DO NOTHING;
            n := n + 1;
        END IF;
        s := s + p_interval_s;
    END LOOP;
    RETURN n;
END $$;

-- Simulate every trip of a date in chronological order, up to an as-of time.
CREATE OR REPLACE FUNCTION sim.run_day(p_date date, p_run_id integer, p_asof timestamp DEFAULT NULL)
RETURNS TABLE (trips_simulated integer, fixes_inserted bigint)
LANGUAGE plpgsql AS $$
DECLARE tr record; n_trips integer := 0; n_fix bigint := 0; k integer;
BEGIN
    FOR tr IN SELECT trip_id FROM public.trips
              WHERE service_date = p_date AND status <> 'Cancelled'
                AND (p_asof IS NULL OR scheduled_start <= p_asof)
              ORDER BY scheduled_start, trip_id
    LOOP
        k := sim.generate_trip_gps(tr.trip_id, p_run_id, p_asof => p_asof);
        n_trips := n_trips + 1; n_fix := n_fix + k;
    END LOOP;
    RETURN QUERY SELECT n_trips, n_fix;
END $$;

-- Verify: functions exist
SELECT proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'sim' ORDER BY proname;


-- =====================================================================
-- PART 2: load one demo day (run ONCE; takes a minute or two)
-- Tuesday 2026-10-20, simulated up to 16:20 so that some trips are completed,
-- one or more are in progress, and the rest are still scheduled.
-- Also generates the next day's schedule (no GPS) and a road closure on it,
-- to demonstrate planned-versus-closure queries.
-- =====================================================================

-- 2a. create the run, inject one incident on the busiest road, generate trips
DO $$
DECLARE
    rid integer; busy_road integer; res record;
BEGIN
    IF EXISTS (SELECT 1 FROM public.trips WHERE service_date = DATE '2026-10-20') THEN
        RAISE NOTICE 'demo day already loaded; skipping';
        RETURN;
    END IF;

    rid := sim.new_run(42, 'demo day 2026-10-20, seed 42');

    SELECT road_id INTO busy_road
    FROM public.route_segments GROUP BY road_id ORDER BY count(*) DESC, road_id LIMIT 1;

    INSERT INTO sim.injected_event (run_id, event_type, road_id, valid_period, magnitude, note)
    VALUES (rid, 'congestion', busy_road,
            tsrange('2026-10-20 09:00', '2026-10-20 09:40'), 0.35,
            'incident on the busiest road: speed x0.35 for 40 minutes');

    SELECT * INTO res FROM public.generate_service_day(DATE '2026-10-20');
    RAISE NOTICE 'trips created: %, unassigned: %', res.trips_created, res.unassigned;

    PERFORM sim.run_day(DATE '2026-10-20', rid, TIMESTAMP '2026-10-20 16:20:00');
END $$;

-- 2b. next day: schedule only (no GPS) and a closure on a busy road
SELECT * FROM public.generate_service_day(DATE '2026-10-21');

INSERT INTO public.road_closures (road_id, valid_period, reason, data_source)
SELECT (SELECT road_id FROM public.route_segments GROUP BY road_id
        ORDER BY count(*) DESC, road_id OFFSET 1 LIMIT 1),
       tsrange('2026-10-21 10:00', '2026-10-21 12:00'),
       'planned maintenance (demo)', 'simulated'
WHERE NOT EXISTS (SELECT 1 FROM public.road_closures);

-- 2c. a maintenance period for one vehicle on the demo day (history, not a snapshot)
INSERT INTO public.vehicle_status_history (vehicle_id, status, valid_period, reason, data_source)
SELECT 12, 'Maintenance', tsrange('2026-10-22 00:00', '2026-10-24 00:00'), 'scheduled service (demo)', 'simulated'
WHERE NOT EXISTS (SELECT 1 FROM public.vehicle_status_history);

-- Verify: what the triggers derived from nothing but raw GPS.
-- Expect: ~280 trips on 20 Oct; most Completed, a few In Progress, later ones Scheduled;
--         tens of thousands of fixes; every fix assigned a trip; ground-truth rows present.
SELECT status, count(*) AS trips FROM public.trips WHERE service_date = DATE '2026-10-20' GROUP BY status ORDER BY status;

SELECT count(*) AS fixes,
       count(*) FILTER (WHERE trip_id IS NULL) AS fixes_without_trip,
       min(recorded_at) AS first_fix, max(recorded_at) AS last_fix
FROM public.vehicle_position;

SELECT (SELECT count(*) FROM public.position_match)  AS matched_fixes,
       (SELECT count(*) FROM public.segment_traversal) AS traversals,
       (SELECT count(*) FROM public.segment_speed_profile) AS speed_profile_rows,
       (SELECT count(*) FROM sim.true_stop_visit)    AS ground_truth_visits;


-- =====================================================================
-- PART 3: remove a simulator run (only if you want to start over)
-- Deletes the run's fixes and trips' derived data, then the run itself.
-- Run only the statements you need; this one is DESTRUCTIVE for demo data.
-- =====================================================================
-- DELETE FROM public.segment_traversal WHERE trip_id IN (SELECT trip_id FROM public.trips WHERE service_date IN ('2026-10-20','2026-10-21'));
-- DELETE FROM public.vehicle_position WHERE sim_run_id = 1;      -- cascades to position_match
-- DELETE FROM public.trips WHERE service_date IN ('2026-10-20','2026-10-21');   -- cascades to trip_stop_event
-- DELETE FROM public.segment_speed_profile;
-- DELETE FROM sim.run WHERE run_id = 1;                           -- cascades to ground truth