-- =====================================================================
-- 03_functions_triggers.sql
-- STEP 2: functions and triggers that DERIVE data, so almost nothing has to
--         be typed in. Run after 02_synthetic_map.sql.
--
-- Run in : pgAdmin 4 > Query Tool on campus_shuttle (new database).
-- Changes: creates functions, triggers and one backfill call at the end.
--          Safe to rerun (CREATE OR REPLACE / DROP TRIGGER IF EXISTS).
-- Order  : run one PART at a time.
--
-- What is derived, and by what
--   stops (zone, road, snapped point) ........ trigger on stops
--   route line, route_segments, distances,
--   planned offsets ........................... deferred trigger on route_stops
--   trip scheduled_end + planned stop events .. triggers on trips
--   trips for a date .......................... function generate_service_day()
--   fix -> trip, position on route ............ trigger on vehicle_position
--   actual stop arrival / departure ........... same trigger (geofence rule)
--   trip actual_start/end/status .............. trigger on trip_stop_event
--   segment traversals + speed profile ........ trigger when a trip completes
--
-- Stop-detection rule (documented assumption, tunable in service_params):
--   ARRIVAL   = the moment the shuttle's path enters the geofence
--               (geofence_radius_m) of the next unvisited stop, interpolated
--               between the last fix outside and the first fix inside.
--   DEPARTURE = the moment the path leaves the geofence, interpolated the same way.
--   DWELL     = if the time inside is shorter than min_dwell_s the visit is
--               treated as a drive-by and discarded (the stop stays unvisited).
-- Nearness alone is never enough: arrival also requires that this stop is the
-- next one the trip is expected to serve.
-- =====================================================================


-- =====================================================================
-- PART 0: helpers
-- =====================================================================
-- the stop_speed_kmh parameter from the schema file is not used by this rule
DELETE FROM public.service_params WHERE param_key = 'stop_speed_kmh';

-- A finished trip may still receive fixes for this long after its final arrival,
-- and only while the vehicle is still at the final stop (the final dwell).
INSERT INTO public.service_params (param_key, param_value, unit, description)
VALUES ('tail_window_s', 45, 's', 'Time after the final arrival during which fixes at the final stop still belong to the finished trip')
ON CONFLICT (param_key) DO NOTHING;

-- A forward-window match farther than this from the fix is re-checked against the whole route.
INSERT INTO public.service_params (param_key, param_value, unit, description)
VALUES ('match_refine_distance_m', 15, 'm', 'Route matches farther than this from the fix are re-checked along the whole route')
ON CONFLICT (param_key) DO NOTHING;

-- A trip already In Progress keeps its fixes as long as the vehicle keeps reporting
-- within this many seconds, even if the trip has run far beyond its scheduled end.
INSERT INTO public.service_params (param_key, param_value, unit, description)
VALUES ('trip_continuity_s', 300, 's', 'Maximum gap between fixes for an in-progress trip to keep owning the vehicle''s fixes')
ON CONFLICT (param_key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.param(p_key text) RETURNS numeric
LANGUAGE plpgsql STABLE AS $$
DECLARE v numeric;
BEGIN
    SELECT param_value INTO v FROM public.service_params WHERE param_key = p_key;
    IF v IS NULL THEN
        RAISE EXCEPTION 'service_params has no value for %', p_key;
    END IF;
    RETURN v;
END $$;

-- Project a geometry into the metric CRS (metres)
CREATE OR REPLACE FUNCTION public.to_m(g geometry) RETURNS geometry
LANGUAGE sql STABLE AS $$
    SELECT ST_Transform(g, public.param('metric_srid')::int)
$$;

CREATE OR REPLACE FUNCTION public.day_type_of(d date) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE EXTRACT(DOW FROM d) WHEN 6 THEN 'saturday' WHEN 0 THEN 'sunday' ELSE 'weekday' END
$$;

-- Nearest junction to a stop (must be within 150 m, else the stop is not on the network)
CREATE OR REPLACE FUNCTION public.stop_node(p_stop_id integer) RETURNS integer
LANGUAGE plpgsql STABLE AS $$
DECLARE
    loc geometry; n integer; d numeric;
BEGIN
    SELECT location INTO loc FROM public.stops WHERE stop_id = p_stop_id;
    IF loc IS NULL THEN RAISE EXCEPTION 'stop % does not exist', p_stop_id; END IF;
    SELECT node_id, ST_Distance(geom::geography, loc::geography)
      INTO n, d
      FROM public.v_road_nodes ORDER BY geom <-> loc LIMIT 1;
    IF n IS NULL OR d > 150 THEN
        RAISE EXCEPTION 'stop % is more than 150 m from any road junction', p_stop_id;
    END IF;
    RETURN n;
END $$;

-- Shortest path over the road network (Dijkstra on the small campus graph).
-- Returns the ordered road segments and whether each is travelled backwards.
CREATE OR REPLACE FUNCTION public.shortest_path_roads(p_from integer, p_to integer)
RETURNS TABLE (seq integer, road_id integer, reversed boolean)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    n integer;
    dist double precision[];
    prev_node integer[]; prev_road integer[]; prev_rev boolean[]; done boolean[];
    u integer; best double precision; alt double precision; cur integer;
    r record;
    path_roads integer[] := '{}'; path_rev boolean[] := '{}';
BEGIN
    SELECT max(x) INTO n
    FROM (SELECT max(rs.source_node) AS x FROM public.road_segments rs
          UNION ALL SELECT max(rs.target_node) FROM public.road_segments rs) q;
    IF n IS NULL THEN RAISE EXCEPTION 'the road network has no junctions'; END IF;

    dist      := array_fill('Infinity'::double precision, ARRAY[n]);
    prev_node := array_fill(NULL::integer, ARRAY[n]);
    prev_road := array_fill(NULL::integer, ARRAY[n]);
    prev_rev  := array_fill(false, ARRAY[n]);
    done      := array_fill(false, ARRAY[n]);
    dist[p_from] := 0;

    LOOP
        u := NULL; best := 'Infinity';
        FOR i IN 1..n LOOP
            IF NOT done[i] AND dist[i] < best THEN best := dist[i]; u := i; END IF;
        END LOOP;
        EXIT WHEN u IS NULL OR u = p_to;
        done[u] := true;
        FOR r IN
            SELECT rs.road_id AS rid, rs.target_node AS nxt, false AS rev, rs.length_m::double precision AS len
            FROM public.road_segments rs WHERE rs.source_node = u
            UNION ALL
            SELECT rs.road_id, rs.source_node, true, rs.length_m::double precision
            FROM public.road_segments rs WHERE rs.target_node = u AND NOT rs.oneway
        LOOP
            alt := dist[u] + r.len;
            IF alt < dist[r.nxt] THEN
                dist[r.nxt] := alt; prev_node[r.nxt] := u;
                prev_road[r.nxt] := r.rid; prev_rev[r.nxt] := r.rev;
            END IF;
        END LOOP;
    END LOOP;

    IF dist[p_to] = 'Infinity' THEN
        RAISE EXCEPTION 'no path between junctions % and %', p_from, p_to;
    END IF;
    cur := p_to;
    WHILE cur <> p_from LOOP
        path_roads := prev_road[cur] || path_roads;
        path_rev   := prev_rev[cur]  || path_rev;
        cur := prev_node[cur];
    END LOOP;
    RETURN QUERY
        SELECT t.ord::integer, t.rid, t.rev
        FROM unnest(path_roads, path_rev) WITH ORDINALITY AS t(rid, rev, ord)
        ORDER BY t.ord;
END $$;


-- =====================================================================
-- PART 1: stops -> zone, road, snapped point (BEFORE INSERT/UPDATE trigger)
-- =====================================================================
CREATE OR REPLACE FUNCTION public.trg_stops_derive() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    rid integer; snapped geometry;
BEGIN
    -- an impossible coordinate is left for the CHECK constraint to reject
    IF NOT (ST_X(NEW.location) BETWEEN -180 AND 180 AND ST_Y(NEW.location) BETWEEN -90 AND 90) THEN
        RETURN NEW;
    END IF;

    -- smallest zone that contains the stop (NULL if none)
    SELECT z.zone_id INTO NEW.zone_id
    FROM public.campus_zones z
    WHERE ST_Intersects(z.boundary, NEW.location)
    ORDER BY ST_Area(z.boundary) LIMIT 1;

    -- nearest road and the stop's projection onto it (NULL while no roads are loaded)
    SELECT r.road_id, ST_ClosestPoint(r.geom, NEW.location)
      INTO rid, snapped
    FROM public.road_segments r
    ORDER BY r.geom <-> NEW.location LIMIT 1;

    NEW.road_id          := rid;
    NEW.snapped_location := snapped;
    NEW.snap_distance_m  := CASE WHEN snapped IS NULL THEN NULL
                                 ELSE least(round(ST_Distance(NEW.location::geography, snapped::geography)::numeric, 2), 999999.99) END;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_stops_derive ON public.stops;
CREATE TRIGGER trg_stops_derive
    BEFORE INSERT OR UPDATE OF location ON public.stops
    FOR EACH ROW EXECUTE FUNCTION public.trg_stops_derive();


-- =====================================================================
-- PART 2: routes -> geometry, segments, distances, planned offsets
-- =====================================================================
CREATE OR REPLACE FUNCTION public.rebuild_route(p_route_id integer) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    n integer; sr record; leg record; rd record;
    prev_node integer; cur_node integer;
    seq_no integer := 0; cum numeric := 0; len numeric;
    geoms geometry[] := '{}'; g geometry;
    speed_ms numeric; dwell numeric;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.routes WHERE route_id = p_route_id) THEN RETURN; END IF;
    SELECT count(*) INTO n FROM public.route_stops WHERE route_id = p_route_id;
    IF n < 2 THEN
        RAISE NOTICE 'route % has % stop(s); a route needs at least 2, nothing built', p_route_id, n;
        RETURN;
    END IF;

    DELETE FROM public.route_segments WHERE route_id = p_route_id;

    FOR sr IN SELECT route_stop_id, stop_id FROM public.route_stops
              WHERE route_id = p_route_id ORDER BY stop_sequence
    LOOP
        cur_node := public.stop_node(sr.stop_id);
        IF prev_node IS NOT NULL AND cur_node <> prev_node THEN
            FOR leg IN SELECT * FROM public.shortest_path_roads(prev_node, cur_node) ORDER BY seq LOOP
                SELECT road_id, geom INTO rd FROM public.road_segments WHERE road_id = leg.road_id;
                len := ST_Length(public.to_m(rd.geom));
                seq_no := seq_no + 1;
                INSERT INTO public.route_segments (route_id, seq, road_id, reversed, start_measure_m, end_measure_m)
                VALUES (p_route_id, seq_no, rd.road_id, leg.reversed, round(cum, 2), round(cum + len, 2));
                cum := cum + len;
                g := CASE WHEN leg.reversed THEN ST_Reverse(rd.geom) ELSE rd.geom END;
                geoms := geoms || g;
            END LOOP;
        END IF;
        UPDATE public.route_stops SET distance_from_start_m = round(cum, 2)
        WHERE route_stop_id = sr.route_stop_id;
        prev_node := cur_node;
    END LOOP;

    IF array_length(geoms, 1) IS NULL THEN
        RAISE EXCEPTION 'route % has all stops at the same junction', p_route_id;
    END IF;

    UPDATE public.routes
    SET route_geometry = ST_RemoveRepeatedPoints(ST_MakeLine(geoms)),
        data_source = 'derived'
    WHERE route_id = p_route_id;

    -- planned offsets for stops whose offsets were not typed in
    speed_ms := public.param('design_speed_kmh') / 3.6;
    dwell    := public.param('default_dwell_s');
    UPDATE public.route_stops rs
    SET planned_arrival_offset_s   = round(rs.distance_from_start_m / speed_ms + (x.rn - 1) * dwell),
        planned_departure_offset_s = round(rs.distance_from_start_m / speed_ms + (x.rn - 1) * dwell + dwell)
    FROM (SELECT route_stop_id, row_number() OVER (ORDER BY stop_sequence) AS rn
          FROM public.route_stops WHERE route_id = p_route_id) x
    WHERE rs.route_stop_id = x.route_stop_id
      AND NOT rs.offsets_entered;
END $$;

-- A route is rebuilt once per transaction per distinct stop list. The signature
-- of the stop list is remembered in a transaction-local setting so that a
-- multi-row insert (one trigger call per row) triggers a single rebuild.
CREATE OR REPLACE FUNCTION public.trg_route_stops_rebuild() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    rid integer; sig text; done_list text;
BEGIN
    FOREACH rid IN ARRAY ARRAY[
        CASE WHEN TG_OP <> 'INSERT' THEN OLD.route_id END,
        CASE WHEN TG_OP <> 'DELETE' THEN NEW.route_id END] LOOP
        CONTINUE WHEN rid IS NULL;
        SELECT rid::text || ':' || coalesce(md5(string_agg(stop_id || '@' || stop_sequence, ',' ORDER BY stop_sequence)), 'none')
          INTO sig FROM public.route_stops WHERE route_id = rid;
        done_list := coalesce(current_setting('shuttle.rebuilt_routes', true), '');
        IF position(';' || sig || ';' IN ';' || done_list || ';') = 0 THEN
            PERFORM public.rebuild_route(rid);
            -- remember the signature of the list as it is AFTER the rebuild
            SELECT rid::text || ':' || coalesce(md5(string_agg(stop_id || '@' || stop_sequence, ',' ORDER BY stop_sequence)), 'none')
              INTO sig FROM public.route_stops WHERE route_id = rid;
            PERFORM set_config('shuttle.rebuilt_routes', done_list || ';' || sig, true);
        END IF;
    END LOOP;
    RETURN NULL;
END $$;

-- Offsets typed in by hand are protected from later derivation.
CREATE OR REPLACE FUNCTION public.trg_route_stops_flag_entered() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.planned_arrival_offset_s IS NOT NULL OR NEW.planned_departure_offset_s IS NOT NULL THEN
        NEW.offsets_entered := true;
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_route_stops_flag_entered ON public.route_stops;
CREATE TRIGGER trg_route_stops_flag_entered
    BEFORE INSERT ON public.route_stops
    FOR EACH ROW EXECUTE FUNCTION public.trg_route_stops_flag_entered();

-- Deferred: fires at commit, so a route and all its stops can be inserted in
-- any order inside one transaction. Only the structural columns fire it, so the
-- distance/offset updates made by rebuild_route() do not retrigger it.
DROP TRIGGER IF EXISTS trg_route_stops_rebuild ON public.route_stops;
CREATE CONSTRAINT TRIGGER trg_route_stops_rebuild
    AFTER INSERT OR DELETE OR UPDATE OF route_id, stop_id, stop_sequence ON public.route_stops
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION public.trg_route_stops_rebuild();


-- =====================================================================
-- PART 3: trips -> scheduled end, planned stop events, availability rule
-- =====================================================================
CREATE OR REPLACE FUNCTION public.vehicle_available_at(p_vehicle_id integer, p_ts timestamp)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT NOT EXISTS (
        SELECT 1 FROM public.vehicle_status_history h
        WHERE h.vehicle_id = p_vehicle_id AND h.status <> 'Active' AND h.valid_period @> p_ts)
$$;

CREATE OR REPLACE FUNCTION public.trg_trips_before() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    dur integer; n_events integer;
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.route_id <> OLD.route_id THEN
        SELECT count(*) INTO n_events FROM public.trip_stop_event WHERE trip_id = NEW.trip_id;
        IF n_events > 0 THEN
            RAISE EXCEPTION 'trip % already has stop events; create a new trip instead of changing its route', NEW.trip_id;
        END IF;
    END IF;

    IF NEW.service_date <> NEW.scheduled_start::date THEN
        RAISE EXCEPTION 'service_date % does not match scheduled_start %', NEW.service_date, NEW.scheduled_start;
    END IF;

    IF NOT public.vehicle_available_at(NEW.vehicle_id, NEW.scheduled_start) THEN
        RAISE EXCEPTION 'vehicle % is not Active at % (see vehicle_status_history)', NEW.vehicle_id, NEW.scheduled_start;
    END IF;

    -- (a nonexistent route is left for the foreign key to reject with its own error)
    IF TG_OP = 'INSERT' AND NEW.scheduled_end IS NULL
       AND EXISTS (SELECT 1 FROM public.routes WHERE route_id = NEW.route_id) THEN
        SELECT max(planned_departure_offset_s) INTO dur
        FROM public.route_stops WHERE route_id = NEW.route_id;
        IF dur IS NULL THEN
            RAISE EXCEPTION 'route % has no planned offsets; build the route first (rebuild_route)', NEW.route_id;
        END IF;
        NEW.scheduled_end := NEW.scheduled_start + make_interval(secs => dur);
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_trips_before ON public.trips;
CREATE TRIGGER trg_trips_before
    BEFORE INSERT OR UPDATE OF route_id, vehicle_id, scheduled_start, service_date ON public.trips
    FOR EACH ROW EXECUTE FUNCTION public.trg_trips_before();

-- One stop event per route stop, with planned times and no actual times.
CREATE OR REPLACE FUNCTION public.trg_trips_after_insert() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.trip_stop_event
           (trip_id, stop_id, stop_sequence, scheduled_arrival, scheduled_departure, data_source)
    SELECT NEW.trip_id, rs.stop_id, rs.stop_sequence,
           NEW.scheduled_start + make_interval(secs => rs.planned_arrival_offset_s),
           NEW.scheduled_start + make_interval(secs => rs.planned_departure_offset_s),
           'derived'
    FROM public.route_stops rs
    WHERE rs.route_id = NEW.route_id
    ORDER BY rs.stop_sequence;
    RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_trips_after_insert ON public.trips;
CREATE TRIGGER trg_trips_after_insert
    AFTER INSERT ON public.trips
    FOR EACH ROW EXECUTE FUNCTION public.trg_trips_after_insert();

-- Create the day's trips from the timetable. Idempotent: a departure already
-- generated for that date is skipped (unique key departure_id + service_date).
-- Vehicle and driver: whoever has been idle longest and has no overlapping trip.
CREATE OR REPLACE FUNCTION public.generate_service_day(p_date date)
RETURNS TABLE (trips_created integer, departures_skipped_existing integer, unassigned integer)
LANGUAGE plpgsql AS $$
DECLARE
    d record; dur integer; st timestamp; en timestamp; veh integer; drv integer;
    created integer := 0; existing integer := 0; unassigned_n integer := 0;
BEGIN
    FOR d IN
        SELECT td.departure_id, td.route_id, td.departure_time
        FROM public.timetable_departures td
        WHERE td.day_type = public.day_type_of(p_date)
          AND p_date >= td.valid_from AND (td.valid_to IS NULL OR p_date <= td.valid_to)
        ORDER BY td.departure_time, td.route_id
    LOOP
        IF EXISTS (SELECT 1 FROM public.trips WHERE departure_id = d.departure_id AND service_date = p_date) THEN
            existing := existing + 1; CONTINUE;
        END IF;

        SELECT max(planned_departure_offset_s) INTO dur FROM public.route_stops WHERE route_id = d.route_id;
        IF dur IS NULL THEN
            RAISE EXCEPTION 'route % has no planned offsets; run SELECT rebuild_route(%)', d.route_id, d.route_id;
        END IF;
        st := p_date + d.departure_time;
        en := st + make_interval(secs => dur);

        SELECT v.vehicle_id INTO veh
        FROM public.vehicles v
        WHERE public.vehicle_available_at(v.vehicle_id, st)
          AND NOT EXISTS (SELECT 1 FROM public.trips t
                          WHERE t.vehicle_id = v.vehicle_id AND t.status <> 'Cancelled'
                            AND t.scheduled_end IS NOT NULL
                            AND tsrange(t.scheduled_start, t.scheduled_end) && tsrange(st, en))
        ORDER BY (SELECT max(t.scheduled_end) FROM public.trips t
                  WHERE t.vehicle_id = v.vehicle_id AND t.scheduled_end <= st) NULLS FIRST,
                 v.vehicle_id
        LIMIT 1;

        SELECT dr.driver_id INTO drv
        FROM public.drivers dr
        WHERE NOT EXISTS (SELECT 1 FROM public.trips t
                          WHERE t.driver_id = dr.driver_id AND t.status <> 'Cancelled'
                            AND t.scheduled_end IS NOT NULL
                            AND tsrange(t.scheduled_start, t.scheduled_end) && tsrange(st, en))
        ORDER BY (SELECT max(t.scheduled_end) FROM public.trips t
                  WHERE t.driver_id = dr.driver_id AND t.scheduled_end <= st) NULLS FIRST,
                 dr.driver_id
        LIMIT 1;

        IF veh IS NULL OR drv IS NULL THEN
            unassigned_n := unassigned_n + 1; CONTINUE;
        END IF;

        INSERT INTO public.trips (departure_id, service_date, route_id, vehicle_id, driver_id,
                                  scheduled_start, status, data_source)
        VALUES (d.departure_id, p_date, d.route_id, veh, drv, st, 'Scheduled', 'derived');
        created := created + 1;
    END LOOP;
    RETURN QUERY SELECT created, existing, unassigned_n;
END $$;


-- =====================================================================
-- PART 4: stop events -> trip actual start / end / status
-- Replaces the old sync trigger. Handles inserts, updates, deletes, a trip_id
-- change (both trips are recalculated) and incomplete observations. Never
-- invents a timestamp: values come only from the stop events.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.sync_trip(p_trip_id integer) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    first_t timestamp; last_t timestamp; any_obs boolean; new_status text; cur_status text;
BEGIN
    SELECT status INTO cur_status FROM public.trips WHERE trip_id = p_trip_id;
    IF cur_status IS NULL THEN RETURN; END IF;           -- trip deleted
    IF cur_status = 'Cancelled' THEN RETURN; END IF;

    SELECT coalesce(f.actual_departure, f.actual_arrival),
           coalesce(l.actual_departure, l.actual_arrival),
           EXISTS (SELECT 1 FROM public.trip_stop_event e
                   WHERE e.trip_id = p_trip_id
                     AND (e.actual_arrival IS NOT NULL OR e.actual_departure IS NOT NULL))
      INTO first_t, last_t, any_obs
    FROM (SELECT 1) dummy
    LEFT JOIN LATERAL (SELECT actual_arrival, actual_departure FROM public.trip_stop_event
                       WHERE trip_id = p_trip_id ORDER BY stop_sequence ASC  LIMIT 1) f ON true
    LEFT JOIN LATERAL (SELECT actual_arrival, actual_departure FROM public.trip_stop_event
                       WHERE trip_id = p_trip_id ORDER BY stop_sequence DESC LIMIT 1) l ON true;

    new_status := CASE WHEN last_t IS NOT NULL THEN 'Completed'
                       WHEN any_obs THEN 'In Progress'
                       ELSE 'Scheduled' END;

    UPDATE public.trips
    SET actual_start = first_t,
        actual_end   = CASE WHEN last_t IS NOT NULL THEN last_t ELSE NULL END,
        status       = new_status
    WHERE trip_id = p_trip_id
      AND (actual_start IS DISTINCT FROM first_t
        OR actual_end   IS DISTINCT FROM CASE WHEN last_t IS NOT NULL THEN last_t ELSE NULL END
        OR status       IS DISTINCT FROM new_status);
END $$;

CREATE OR REPLACE FUNCTION public.trg_tse_sync() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP <> 'INSERT' THEN PERFORM public.sync_trip(OLD.trip_id); END IF;
    IF TG_OP <> 'DELETE' AND (TG_OP = 'INSERT' OR NEW.trip_id IS DISTINCT FROM OLD.trip_id) THEN
        PERFORM public.sync_trip(NEW.trip_id);
    END IF;
    RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_tse_sync_ins ON public.trip_stop_event;
DROP TRIGGER IF EXISTS trg_tse_sync_upd ON public.trip_stop_event;
DROP TRIGGER IF EXISTS trg_tse_sync_del ON public.trip_stop_event;
CREATE TRIGGER trg_tse_sync_ins
    AFTER INSERT ON public.trip_stop_event
    FOR EACH ROW WHEN (NEW.actual_arrival IS NOT NULL OR NEW.actual_departure IS NOT NULL)
    EXECUTE FUNCTION public.trg_tse_sync();
CREATE TRIGGER trg_tse_sync_upd
    AFTER UPDATE ON public.trip_stop_event
    FOR EACH ROW WHEN (OLD.actual_arrival   IS DISTINCT FROM NEW.actual_arrival
                    OR OLD.actual_departure IS DISTINCT FROM NEW.actual_departure
                    OR OLD.trip_id          IS DISTINCT FROM NEW.trip_id
                    OR OLD.stop_sequence    IS DISTINCT FROM NEW.stop_sequence)
    EXECUTE FUNCTION public.trg_tse_sync();
CREATE TRIGGER trg_tse_sync_del
    AFTER DELETE ON public.trip_stop_event
    FOR EACH ROW EXECUTE FUNCTION public.trg_tse_sync();

-- Keep the new sync and the stale actual columns consistent when stop events
-- are cleared in bulk (see reprocess_trip). A manual repair helper:
CREATE OR REPLACE FUNCTION public.resync_all_trips() RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE t integer; n integer := 0;
BEGIN
    FOR t IN SELECT trip_id FROM public.trips LOOP PERFORM public.sync_trip(t); n := n + 1; END LOOP;
    RETURN n;
END $$;


-- =====================================================================
-- PART 5: GPS fix -> trip, route position, stop visits
-- =====================================================================
-- Which trip is this vehicle serving at this instant?
-- Candidates: open trips (Scheduled / In Progress) whose scheduled window
-- (+/- trip_assign_slack_s) contains the instant. A trip that has just
-- completed may still own fixes for tail_window_s after its final arrival,
-- but only while the vehicle is within twice the geofence of the final stop
-- (the final dwell); after that the vehicle belongs to its next trip.
-- An in-progress trip that is still reporting always keeps its fixes (even far
-- beyond its scheduled end). Otherwise, among trips whose route passes near the
-- fix, the earliest unfinished one wins.
CREATE OR REPLACE FUNCTION public.infer_trip_for_fix(p_vehicle_id integer, p_ts timestamp, p_loc geometry)
RETURNS integer LANGUAGE sql STABLE AS $$
    SELECT q.trip_id FROM (
        -- 1. continuity: an in-progress trip whose last matched fix is recent
        SELECT t.trip_id, 0 AS pri, 0::double precision AS d
        FROM public.trips t
        WHERE t.vehicle_id = p_vehicle_id AND t.status = 'In Progress'
          AND (SELECT max(vp.recorded_at)
               FROM public.position_match pm JOIN public.vehicle_position vp USING (position_id)
               WHERE pm.trip_id = t.trip_id) >= p_ts - make_interval(secs => public.param('trip_continuity_s'))
        UNION ALL
        -- 2. schedule window
        SELECT t.trip_id,
               CASE WHEN t.status IN ('In Progress','Completed') THEN 1 ELSE 2 END,
               -- trips whose route does not pass near the fix rank after those that do;
               -- among the rest the earliest unfinished trip wins (a vehicle serves its
               -- trips in order, so a delayed trip must not be mistaken for the next one)
               (CASE WHEN rt.route_geometry IS NULL THEN 1e9
                     WHEN ST_Distance(public.to_m(rt.route_geometry), public.to_m(p_loc))
                          > public.param('match_max_distance_m') THEN 1e8 ELSE 0 END)
               + EXTRACT(EPOCH FROM (t.scheduled_start - timestamp '2000-01-01')) / 1e9
        FROM public.trips t
        JOIN public.routes rt ON rt.route_id = t.route_id
        WHERE t.vehicle_id = p_vehicle_id
          AND t.status <> 'Cancelled'
          AND t.scheduled_end IS NOT NULL
          AND p_ts BETWEEN t.scheduled_start - make_interval(secs => public.param('trip_assign_slack_s'))
                       AND t.scheduled_end   + make_interval(secs => public.param('trip_assign_slack_s'))
          AND (t.status IN ('Scheduled','In Progress')
               OR (t.status = 'Completed'
                   AND p_ts <= t.actual_end + make_interval(secs => public.param('tail_window_s'))
                   AND EXISTS (
                     SELECT 1 FROM public.trip_stop_event e JOIN public.stops s ON s.stop_id = e.stop_id
                     WHERE e.trip_id = t.trip_id
                       AND e.stop_sequence = (SELECT max(stop_sequence) FROM public.trip_stop_event WHERE trip_id = t.trip_id)
                       AND e.actual_departure IS NULL
                       AND ST_DWithin(s.location::geography, p_loc::geography,
                                      2 * public.param('geofence_radius_m')))))
    ) q
    ORDER BY q.pri, q.d
    LIMIT 1
$$;

-- Time at which the trip passed route measure p_measure, interpolated between
-- the two matched fixes on either side. NULL if the fixes do not bracket it
-- (within 30 m of the route ends, the nearest fix time is used).
CREATE OR REPLACE FUNCTION public.time_at_measure(p_trip_id integer, p_measure numeric)
RETURNS timestamp LANGUAGE plpgsql STABLE AS $$
DECLARE
    b record; a record; frac double precision;
BEGIN
    SELECT vp.recorded_at AS ts, pm.measure_m AS m INTO b
    FROM public.position_match pm JOIN public.vehicle_position vp USING (position_id)
    WHERE pm.trip_id = p_trip_id AND pm.measure_m < p_measure
    ORDER BY vp.recorded_at DESC LIMIT 1;
    SELECT vp.recorded_at AS ts, pm.measure_m AS m INTO a
    FROM public.position_match pm JOIN public.vehicle_position vp USING (position_id)
    WHERE pm.trip_id = p_trip_id AND pm.measure_m >= p_measure
    ORDER BY vp.recorded_at ASC LIMIT 1;

    IF b.ts IS NOT NULL AND a.ts IS NOT NULL THEN
        frac := (p_measure - b.m)::double precision / NULLIF((a.m - b.m)::double precision, 0);
        RETURN b.ts + make_interval(secs => coalesce(frac, 0) * EXTRACT(EPOCH FROM (a.ts - b.ts)));
    ELSIF b.ts IS NULL AND a.ts IS NOT NULL AND a.m - p_measure <= 30 THEN
        RETURN a.ts;
    ELSIF a.ts IS NULL AND b.ts IS NOT NULL AND p_measure - b.m <= 30 THEN
        RETURN b.ts;
    END IF;
    RETURN NULL;
END $$;

-- Core pipeline for one fix. Called by the insert trigger and by reprocess_trip,
-- so live ingestion and batch reprocessing share exactly the same logic.
CREATE OR REPLACE FUNCTION public.process_position(p_position_id bigint) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    v record; trip_ref integer; rt record;
    r_m geometry; p_m geometry; L double precision;
    prev_meas double precision; prev_meas_t timestamp; f0 double precision; f1 double precision;
    m2 double precision; d2 double precision;
    sub geometry; frac double precision; meas double precision; dist double precision;
    off_thr double precision; max_dist double precision;
    on_rt boolean; rd integer;
    ev record; stop_m geometry; radius double precision; min_dwell double precision;
    d_now double precision; d_prev double precision; prev_fix record; t_cross timestamp;
BEGIN
    SELECT * INTO v FROM public.vehicle_position WHERE position_id = p_position_id;
    IF v.position_id IS NULL THEN RETURN; END IF;

    -- late-arriving fix: a later fix of this vehicle was already processed, so
    -- stateful derivation would go backwards. Use reprocess_trip() to repair.
    IF EXISTS (SELECT 1 FROM public.position_match pm
               JOIN public.vehicle_position q USING (position_id)
               WHERE q.vehicle_id = v.vehicle_id AND q.recorded_at > v.recorded_at) THEN
        RAISE NOTICE 'fix % arrived out of order; not derived (run reprocess_trip)', p_position_id;
        RETURN;
    END IF;

    trip_ref := v.trip_id;
    IF trip_ref IS NULL THEN
        trip_ref := public.infer_trip_for_fix(v.vehicle_id, v.recorded_at, v.location);
        IF trip_ref IS NOT NULL THEN
            UPDATE public.vehicle_position SET trip_id = trip_ref WHERE position_id = p_position_id;
        END IF;
    END IF;
    IF trip_ref IS NULL THEN RETURN; END IF;

    SELECT t.route_id, r.route_geometry INTO rt
    FROM public.trips t JOIN public.routes r USING (route_id) WHERE t.trip_id = trip_ref;
    IF rt.route_geometry IS NULL THEN RETURN; END IF;

    off_thr  := public.param('off_route_threshold_m');
    max_dist := public.param('match_max_distance_m');
    radius   := public.param('geofence_radius_m');
    min_dwell:= public.param('min_dwell_s');

    r_m := public.to_m(rt.route_geometry);
    p_m := public.to_m(v.location);
    L   := ST_Length(r_m);

    -- Route position. The shuttle only moves forward along its route, so search
    -- from 20 m behind the previous position to a speed-limited distance ahead (the
    -- 20 m allows for GPS noise). This matters where a route doubles back over the same road or
    -- crosses itself: the same place appears at two route positions, and only the
    -- forward-only window picks the right one. Fall back to the whole route for a
    -- first fix or after a dropout.
    SELECT pm.measure_m, q.recorded_at INTO prev_meas, prev_meas_t
    FROM public.position_match pm JOIN public.vehicle_position q USING (position_id)
    WHERE pm.trip_id = trip_ref AND pm.measure_m IS NOT NULL
    ORDER BY q.recorded_at DESC LIMIT 1;

    meas := NULL; dist := NULL;
    IF prev_meas IS NOT NULL THEN
        -- ahead: at least 60 m, or what 40 km/h covers since the previous fix
        f1 := least(prev_meas + greatest(60, 11.1 * EXTRACT(EPOCH FROM (v.recorded_at - prev_meas_t))), L) / L;

        -- candidate 1: strictly forward from the previous position
        f0 := greatest(prev_meas, 0) / L;
        IF f1 - f0 > 0.0001 THEN
            sub  := ST_LineSubstring(r_m, f0, f1);
            frac := ST_LineLocatePoint(sub, p_m);
            meas := (f0 + frac * (f1 - f0)) * L;
            dist := ST_Distance(p_m, ST_LineInterpolatePoint(r_m, meas / L));
        END IF;

        -- candidate 2: allow up to 20 m back (GPS noise); used only if clearly better,
        -- so that at a turnaround (same place on the way out and back) the forward
        -- position wins a tie
        f0 := greatest(prev_meas - 20, 0) / L;
        IF f1 - f0 > 0.0001 THEN
            sub  := ST_LineSubstring(r_m, f0, f1);
            frac := ST_LineLocatePoint(sub, p_m);
            m2   := (f0 + frac * (f1 - f0)) * L;
            d2   := ST_Distance(p_m, ST_LineInterpolatePoint(r_m, m2 / L));
            IF meas IS NULL OR d2 < dist - 2.0 THEN meas := m2; dist := d2; END IF;
        END IF;
    END IF;
    IF meas IS NULL OR dist > public.param('match_refine_distance_m') THEN
        -- no good forward match (first fix, dropout, or a hairpin): look along the
        -- whole route and keep whichever candidate lies closer to the fix
        frac := ST_LineLocatePoint(r_m, p_m);
        IF meas IS NULL
           OR ST_Distance(p_m, ST_LineInterpolatePoint(r_m, frac)) < dist THEN
            meas := frac * L;
            dist := ST_Distance(p_m, ST_LineInterpolatePoint(r_m, frac));
        END IF;
    END IF;
    on_rt := dist <= off_thr;

    SELECT rs.road_id INTO rd
    FROM public.route_segments rs
    WHERE rs.route_id = rt.route_id AND meas >= rs.start_measure_m AND meas < rs.end_measure_m
    ORDER BY rs.seq LIMIT 1;
    IF rd IS NULL THEN
        SELECT rs.road_id INTO rd FROM public.route_segments rs
        WHERE rs.route_id = rt.route_id ORDER BY abs(rs.end_measure_m - meas) LIMIT 1;
    END IF;

    INSERT INTO public.position_match
           (position_id, trip_id, route_id, road_id, measure_m, route_fraction, dist_to_route_m, on_route)
    VALUES (p_position_id, trip_ref, rt.route_id, rd, round(meas::numeric, 2),
            round(least(meas / L, 1)::numeric, 6), round(dist::numeric, 2), on_rt)
    ON CONFLICT (position_id) DO UPDATE
       SET trip_id = EXCLUDED.trip_id, route_id = EXCLUDED.route_id, road_id = EXCLUDED.road_id,
           measure_m = EXCLUDED.measure_m, route_fraction = EXCLUDED.route_fraction,
           dist_to_route_m = EXCLUDED.dist_to_route_m, on_route = EXCLUDED.on_route,
           matched_at = now();

    -- ---------- stop-visit detection (state machine, one expected stop at a time)
    SELECT e.trip_stop_id, e.stop_id, e.actual_arrival, e.actual_departure, s.location AS loc
      INTO ev
    FROM public.trip_stop_event e JOIN public.stops s ON s.stop_id = e.stop_id
    WHERE e.trip_id = trip_ref AND e.actual_departure IS NULL
    ORDER BY e.stop_sequence LIMIT 1;
    IF ev.trip_stop_id IS NULL THEN RETURN; END IF;

    stop_m := public.to_m(ev.loc);
    d_now  := ST_Distance(p_m, stop_m);

    SELECT q.recorded_at AS ts, q.location AS loc INTO prev_fix
    FROM public.vehicle_position q
    WHERE q.vehicle_id = v.vehicle_id AND q.recorded_at < v.recorded_at
      AND q.recorded_at >= v.recorded_at - make_interval(secs => public.param('gps_gap_flag_s'))
    ORDER BY q.recorded_at DESC LIMIT 1;
    d_prev := CASE WHEN prev_fix.ts IS NULL THEN NULL
                   ELSE ST_Distance(public.to_m(prev_fix.loc), stop_m) END;

    IF ev.actual_arrival IS NULL THEN
        IF d_now <= radius THEN
            t_cross := v.recorded_at;
            IF d_prev IS NOT NULL AND d_prev > radius AND d_prev > d_now THEN
                t_cross := prev_fix.ts + make_interval(secs =>
                    (d_prev - radius) / (d_prev - d_now) * EXTRACT(EPOCH FROM (v.recorded_at - prev_fix.ts)));
            END IF;
            UPDATE public.trip_stop_event
            SET actual_arrival = t_cross, detection_method = 'gps_inferred'
            WHERE trip_stop_id = ev.trip_stop_id;
        END IF;
    ELSE
        IF d_now > radius THEN
            t_cross := v.recorded_at;
            IF d_prev IS NOT NULL AND d_prev <= radius AND d_now > d_prev THEN
                t_cross := prev_fix.ts + make_interval(secs =>
                    (radius - d_prev) / (d_now - d_prev) * EXTRACT(EPOCH FROM (v.recorded_at - prev_fix.ts)));
            END IF;
            IF EXTRACT(EPOCH FROM (t_cross - ev.actual_arrival)) < min_dwell THEN
                -- drive-by, not a visit: forget the tentative arrival
                UPDATE public.trip_stop_event
                SET actual_arrival = NULL, detection_method = NULL
                WHERE trip_stop_id = ev.trip_stop_id;
            ELSE
                UPDATE public.trip_stop_event
                SET actual_departure = greatest(t_cross, ev.actual_arrival), detection_method = 'gps_inferred'
                WHERE trip_stop_id = ev.trip_stop_id;
            END IF;
        END IF;
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.trg_vehicle_position_after_insert() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    -- bulk loads can switch derivation off:  SET shuttle.derive_on_insert = 'off';
    IF coalesce(current_setting('shuttle.derive_on_insert', true), 'on') = 'off' THEN
        RETURN NULL;
    END IF;
    PERFORM public.process_position(NEW.position_id);
    RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_vehicle_position_after_insert ON public.vehicle_position;
CREATE TRIGGER trg_vehicle_position_after_insert
    AFTER INSERT ON public.vehicle_position
    FOR EACH ROW EXECUTE FUNCTION public.trg_vehicle_position_after_insert();

-- Rebuild everything derived from GPS for one trip, replaying its fixes in
-- time order through the same process_position() logic. Manually entered
-- actual times are left alone; GPS-inferred ones are recomputed.
CREATE OR REPLACE FUNCTION public.reprocess_trip(p_trip_id integer) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE pid bigint; n integer := 0;
BEGIN
    DELETE FROM public.segment_traversal WHERE trip_id = p_trip_id;
    DELETE FROM public.position_match   WHERE trip_id = p_trip_id;
    UPDATE public.trip_stop_event
    SET actual_arrival = NULL, actual_departure = NULL, detection_method = NULL
    WHERE trip_id = p_trip_id AND detection_method = 'gps_inferred';
    PERFORM public.sync_trip(p_trip_id);

    FOR pid IN SELECT position_id FROM public.vehicle_position
               WHERE trip_id = p_trip_id ORDER BY recorded_at LOOP
        PERFORM public.process_position(pid);
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;


-- =====================================================================
-- PART 6: completed trip -> segment traversals -> speed profile
-- =====================================================================
CREATE OR REPLACE FUNCTION public.refresh_segment_speed_profile(p_road_ids integer[])
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM public.segment_speed_profile WHERE road_id = ANY (p_road_ids);
    INSERT INTO public.segment_speed_profile (road_id, day_type, bucket_start, avg_speed_kmh, n_obs)
    SELECT st.road_id,
           public.day_type_of(st.entered_at::date),
           (date_trunc('hour', st.entered_at)
              + floor(EXTRACT(MINUTE FROM st.entered_at) / 15) * interval '15 minutes')::time,
           round(avg(st.avg_speed_kmh)::numeric, 2),
           count(*)
    FROM public.segment_traversal st
    WHERE st.road_id = ANY (p_road_ids) AND st.avg_speed_kmh IS NOT NULL
    GROUP BY 1, 2, 3;
END $$;

-- Entry/exit times of each route segment for a trip. Where a segment boundary
-- is a stop, the stop event's time is used (departure from the previous stop,
-- arrival at the next); elsewhere the time is interpolated from route position.
-- A traversal is stored only when both boundary times can be established.
CREATE OR REPLACE FUNCTION public.finalize_trip_traversals(p_trip_id integer) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
    rt integer; sg record; t_in timestamp; t_out timestamp; n integer := 0;
    secs numeric; roads integer[] := '{}';
BEGIN
    SELECT route_id INTO rt FROM public.trips WHERE trip_id = p_trip_id;
    DELETE FROM public.segment_traversal WHERE trip_id = p_trip_id;

    FOR sg IN SELECT * FROM public.route_segments WHERE route_id = rt ORDER BY seq LOOP
        -- entry
        SELECT coalesce(e.actual_departure, e.actual_arrival) INTO t_in
        FROM public.route_stops rs
        JOIN public.trip_stop_event e ON e.trip_id = p_trip_id AND e.stop_sequence = rs.stop_sequence
        WHERE rs.route_id = rt AND abs(rs.distance_from_start_m - sg.start_measure_m) < 1.0 LIMIT 1;
        IF t_in IS NULL THEN t_in := public.time_at_measure(p_trip_id, sg.start_measure_m); END IF;
        -- exit
        SELECT coalesce(e.actual_arrival, e.actual_departure) INTO t_out
        FROM public.route_stops rs
        JOIN public.trip_stop_event e ON e.trip_id = p_trip_id AND e.stop_sequence = rs.stop_sequence
        WHERE rs.route_id = rt AND abs(rs.distance_from_start_m - sg.end_measure_m) < 1.0 LIMIT 1;
        IF t_out IS NULL THEN t_out := public.time_at_measure(p_trip_id, sg.end_measure_m); END IF;

        IF t_in IS NOT NULL AND t_out IS NOT NULL AND t_out > t_in THEN
            secs := EXTRACT(EPOCH FROM (t_out - t_in));
            INSERT INTO public.segment_traversal (trip_id, road_id, entered_at, exited_at, avg_speed_kmh)
            VALUES (p_trip_id, sg.road_id, t_in, t_out,
                    round(((sg.end_measure_m - sg.start_measure_m) / secs * 3.6)::numeric, 2))
            ON CONFLICT (trip_id, road_id, entered_at) DO NOTHING;
            n := n + 1;
            roads := roads || sg.road_id;
        END IF;
    END LOOP;

    IF n > 0 THEN PERFORM public.refresh_segment_speed_profile(roads); END IF;
    RETURN n;
END $$;

CREATE OR REPLACE FUNCTION public.trg_trips_completed() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM public.finalize_trip_traversals(NEW.trip_id);
    RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_trips_completed ON public.trips;
CREATE TRIGGER trg_trips_completed
    AFTER UPDATE OF status, actual_end ON public.trips
    FOR EACH ROW
    WHEN (NEW.status = 'Completed'
          AND (OLD.status IS DISTINCT FROM NEW.status OR OLD.actual_end IS DISTINCT FROM NEW.actual_end))
    EXECUTE FUNCTION public.trg_trips_completed();


-- =====================================================================
-- PART 7: backfill derived data for the rows loaded by file 02
-- (the triggers did not exist yet when they were inserted)
-- =====================================================================
CREATE OR REPLACE FUNCTION public.rebuild_all_derived() RETURNS void
LANGUAGE plpgsql AS $$
DECLARE r integer;
BEGIN
    UPDATE public.stops SET location = location;          -- re-fires the stops trigger
    FOR r IN SELECT route_id FROM public.routes ORDER BY route_id LOOP
        PERFORM public.rebuild_route(r);
    END LOOP;
END $$;

SELECT public.rebuild_all_derived();

-- Verify (expect: 12 stops with road and snapped point, snap distance ~0;
--          10 routes with a geometry; route_segments rows; offsets filled)
SELECT count(*) FILTER (WHERE road_id IS NOT NULL)          AS stops_with_road,
       count(*) FILTER (WHERE zone_id IS NOT NULL)          AS stops_with_zone,
       max(snap_distance_m)                                 AS max_snap_m
FROM public.stops;

SELECT r.route_code, ST_NumPoints(r.route_geometry) AS vertices, r.length_m,
       (SELECT count(*) FROM public.route_segments s WHERE s.route_id = r.route_id) AS segments,
       (SELECT max(planned_departure_offset_s) FROM public.route_stops x WHERE x.route_id = r.route_id) AS planned_duration_s
FROM public.routes r ORDER BY r.route_code;

SELECT t.table_name, t.trigger_name
FROM (SELECT event_object_table AS table_name, trigger_name
      FROM information_schema.triggers WHERE trigger_schema = 'public'
      GROUP BY 1, 2) t
ORDER BY 1, 2;