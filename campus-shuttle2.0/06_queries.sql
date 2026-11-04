-- =====================================================================
-- 06_queries.sql
-- Analytical queries on the demo day (Tuesday 2026-10-20, simulated up to
-- 16:20) and the following day's schedule. Read-only: nothing is changed.
--
-- Run in : pgAdmin 4 > Query Tool on campus_shuttle, after files 02-04.
-- How    : run ONE query at a time (select it, press F5).
-- Tags   : [S] spatial   [T] temporal   [ST] spatio-temporal (both at once)
--          [V] temporal validity (versioned reference data)   [E] evaluation
--
-- All figures come from SIMULATED data. Lateness is always measured at one
-- stop event at a time (arrival actual - arrival scheduled); arrival and
-- departure lateness are never added together; missing observations are
-- excluded, never counted as zero.
-- Thresholds come from service_params: late = more than late_threshold_s
-- (300 s) after schedule; early = more than 60 s before schedule.
-- =====================================================================


-- =====================================================================
-- Q1 [S+T window] Which shuttles were within 50 m of Student Centre
--    between 09:00 and 09:30, and when?
--    A space-time window query: distance in metres (geography) AND a time range.
-- =====================================================================
SELECT vp.vehicle_id, vp.trip_id, vp.recorded_at,
       round(ST_Distance(vp.location::geography, s.location::geography)::numeric, 1) AS metres_from_stop
FROM public.vehicle_position vp
JOIN public.stops s ON s.stop_name = 'Student Centre'
WHERE vp.recorded_at >= TIMESTAMP '2026-10-20 09:00' AND vp.recorded_at < TIMESTAMP '2026-10-20 09:30'
  AND ST_DWithin(vp.location::geography, s.location::geography, 50)
ORDER BY vp.recorded_at;


-- =====================================================================
-- Q2 [S snapshot] Which vehicles were inside the Academic Core zone at 09:19:30?
--    Uses each vehicle's latest fix in the 30 seconds up to that instant.
-- =====================================================================
SELECT DISTINCT ON (vp.vehicle_id)
       vp.vehicle_id, vp.trip_id, vp.recorded_at, z.zone_name
FROM public.vehicle_position vp
JOIN public.campus_zones z ON z.zone_name = 'Academic Core' AND ST_Within(vp.location, z.boundary)
WHERE vp.recorded_at > TIMESTAMP '2026-10-20 09:19:30' - interval '30 seconds'
  AND vp.recorded_at <= TIMESTAMP '2026-10-20 09:19:30'
ORDER BY vp.vehicle_id, vp.recorded_at DESC;


-- =====================================================================
-- Q3 [ST] Where was a shuttle at an instant that has NO fix?
--    Interpolates between the fixes either side, along the route (linear
--    referencing), then names the nearest stop. The sample trip is the first
--    completed trip of the day, queried 4 min 7 s after its start.
-- =====================================================================
WITH target AS (
    SELECT t.trip_id, t.route_id, t.actual_start + interval '4 minutes 7 seconds' AS at_time
    FROM public.trips t
    WHERE t.service_date = DATE '2026-10-20' AND t.status = 'Completed'
    ORDER BY t.trip_id LIMIT 1
), b AS (
    SELECT tg.*, pm.measure_m AS m_before, vp.recorded_at AS t_before
    FROM target tg
    JOIN LATERAL (SELECT pm.measure_m, pm.position_id FROM public.position_match pm
                  JOIN public.vehicle_position q USING (position_id)
                  WHERE pm.trip_id = tg.trip_id AND q.recorded_at <= tg.at_time
                  ORDER BY q.recorded_at DESC LIMIT 1) pm ON true
    JOIN public.vehicle_position vp ON vp.position_id = pm.position_id
), a AS (
    SELECT b.*, pm.measure_m AS m_after, vp.recorded_at AS t_after
    FROM b
    JOIN LATERAL (SELECT pm.measure_m, pm.position_id FROM public.position_match pm
                  JOIN public.vehicle_position q USING (position_id)
                  WHERE pm.trip_id = b.trip_id AND q.recorded_at > b.at_time
                  ORDER BY q.recorded_at ASC LIMIT 1) pm ON true
    JOIN public.vehicle_position vp ON vp.position_id = pm.position_id
), est AS (
    SELECT a.*, 
           a.m_before + (a.m_after - a.m_before)
             * EXTRACT(EPOCH FROM (a.at_time - a.t_before))
             / NULLIF(EXTRACT(EPOCH FROM (a.t_after - a.t_before)), 0) AS m_at
    FROM a
)
SELECT est.trip_id, est.at_time, est.t_before, est.t_after,
       round(est.m_at::numeric, 1) AS metres_along_route,
       round(ST_X(pt.g)::numeric, 5) AS lon, round(ST_Y(pt.g)::numeric, 5) AS lat,
       ns.stop_name AS nearest_stop,
       round(ns.d::numeric, 1) AS metres_to_nearest_stop
FROM est
JOIN public.routes r ON r.route_id = est.route_id
CROSS JOIN LATERAL (SELECT ST_Transform(
        ST_LineInterpolatePoint(public.to_m(r.route_geometry), est.m_at / ST_Length(public.to_m(r.route_geometry))),
        4326) AS g) pt
CROSS JOIN LATERAL (SELECT s.stop_name, ST_Distance(pt.g::geography, s.location::geography) AS d
                    FROM public.stops s ORDER BY s.location <-> pt.g LIMIT 1) ns;


-- =====================================================================
-- Q4 [S] Route deviation per trip: how far did fixes stray from the planned
--    route? (GPS noise is +/- 6 m per axis, so values above ~10 m would be real.)
--    Top 10 trips by worst deviation; "flagged" counts fixes beyond off_route_threshold_m.
-- =====================================================================
SELECT pm.trip_id, r.route_code, count(*) AS fixes,
       round(avg(pm.dist_to_route_m), 1) AS mean_dev_m,
       round(max(pm.dist_to_route_m), 1) AS max_dev_m,
       count(*) FILTER (WHERE NOT pm.on_route) AS flagged_off_route
FROM public.position_match pm
JOIN public.routes r ON r.route_id = pm.route_id
GROUP BY pm.trip_id, r.route_code
ORDER BY max_dev_m DESC, pm.trip_id
LIMIT 10;


-- =====================================================================
-- Q5 [T] Early / on-time / late performance of arrivals, overall and per route.
--    Observed arrivals only. (Incomplete trips are included up to what was observed.)
-- =====================================================================
WITH ev AS (
    SELECT r.route_code,
           EXTRACT(EPOCH FROM (e.actual_arrival - e.scheduled_arrival)) AS late_s
    FROM public.trip_stop_event e
    JOIN public.trips t ON t.trip_id = e.trip_id
    JOIN public.routes r ON r.route_id = t.route_id
    WHERE e.actual_arrival IS NOT NULL AND e.scheduled_arrival IS NOT NULL
)
SELECT coalesce(route_code, 'ALL ROUTES') AS route,
       count(*) AS observed_arrivals,
       round(100.0 * count(*) FILTER (WHERE late_s < -60) / count(*), 1) AS pct_early,
       round(100.0 * count(*) FILTER (WHERE late_s BETWEEN -60 AND public.param('late_threshold_s')) / count(*), 1) AS pct_on_time,
       round(100.0 * count(*) FILTER (WHERE late_s > public.param('late_threshold_s')) / count(*), 1) AS pct_late,
       round((avg(late_s) / 60)::numeric, 2) AS mean_lateness_min
FROM ev
GROUP BY ROLLUP (route_code)
ORDER BY route_code NULLS LAST;


-- =====================================================================
-- Q6 [T] Lateness by time of day (scheduled hour), weekday.
--    The class-change congestion should make some hours worse.
-- =====================================================================
SELECT EXTRACT(HOUR FROM e.scheduled_arrival)::int AS hour_of_day,
       count(*) AS observed_arrivals,
       round((avg(EXTRACT(EPOCH FROM (e.actual_arrival - e.scheduled_arrival))) / 60)::numeric, 2) AS mean_lateness_min,
       round((max(EXTRACT(EPOCH FROM (e.actual_arrival - e.scheduled_arrival))) / 60)::numeric, 2) AS max_lateness_min
FROM public.trip_stop_event e
WHERE e.actual_arrival IS NOT NULL
GROUP BY 1 ORDER BY 1;


-- =====================================================================
-- Q7 [ST] Lateness progression along a route: where does delay build up?
--    For route R2: mean arrival lateness at each stop, and the change from the
--    previous stop (window function). Distance along the route comes from the
--    derived route geometry, so this is lateness as a function of position.
-- =====================================================================
SELECT rs.stop_sequence, s.stop_name, rs.distance_from_start_m AS metres_along_route,
       count(e.actual_arrival) AS observed,
       round((avg(EXTRACT(EPOCH FROM (e.actual_arrival - e.scheduled_arrival))) / 60)::numeric, 2) AS mean_lateness_min,
       round(((avg(EXTRACT(EPOCH FROM (e.actual_arrival - e.scheduled_arrival)))
               - lag(avg(EXTRACT(EPOCH FROM (e.actual_arrival - e.scheduled_arrival)))) OVER (ORDER BY rs.stop_sequence)) / 60)::numeric, 2)
           AS change_from_previous_stop_min
FROM public.routes r
JOIN public.route_stops rs ON rs.route_id = r.route_id
JOIN public.stops s ON s.stop_id = rs.stop_id
LEFT JOIN public.trips t ON t.route_id = r.route_id
LEFT JOIN public.trip_stop_event e ON e.trip_id = t.trip_id AND e.stop_sequence = rs.stop_sequence
                                  AND e.actual_arrival IS NOT NULL
WHERE r.route_code = 'R2'
GROUP BY rs.stop_sequence, s.stop_name, rs.distance_from_start_m
ORDER BY rs.stop_sequence;


-- =====================================================================
-- Q8 [ST] Spatial delay hotspots. Definition used: a stop's mean ARRIVAL
--    lateness over observed arrivals; also shows how many arrivals were late
--    (> 5 min) and the zone the stop lies in. Ranked worst first.
-- =====================================================================
SELECT s.stop_name, z.zone_name,
       round(ST_X(s.location)::numeric, 5) AS lon, round(ST_Y(s.location)::numeric, 5) AS lat,
       count(e.actual_arrival) AS observed_arrivals,
       round((avg(EXTRACT(EPOCH FROM (e.actual_arrival - e.scheduled_arrival))) / 60)::numeric, 2) AS mean_lateness_min,
       count(*) FILTER (WHERE e.actual_arrival - e.scheduled_arrival > make_interval(secs => public.param('late_threshold_s')))
           AS late_arrivals
FROM public.stops s
LEFT JOIN public.campus_zones z ON z.zone_id = s.zone_id
LEFT JOIN public.trip_stop_event e ON e.stop_id = s.stop_id AND e.actual_arrival IS NOT NULL
GROUP BY s.stop_id, s.stop_name, z.zone_name, s.location
ORDER BY mean_lateness_min DESC NULLS LAST;


-- =====================================================================
-- Q9 [ST] Speed profile: the slowest (road, time-of-day) combinations on weekdays,
--    with the zone each road passes through. Built from segment_traversal, which the
--    triggers fill automatically when a trip completes.
-- =====================================================================
SELECT rd.road_name, rd.road_id, z.zone_name, p.bucket_start AS bucket_15min,
       p.avg_speed_kmh, p.n_obs
FROM public.segment_speed_profile p
JOIN public.road_segments rd ON rd.road_id = p.road_id
LEFT JOIN public.campus_zones z ON ST_Intersects(z.boundary, ST_LineInterpolatePoint(rd.geom, 0.5))
WHERE p.day_type = 'weekday' AND p.n_obs >= 3
ORDER BY p.avg_speed_kmh ASC
LIMIT 10;


-- =====================================================================
-- Q10 [ST + E] Can the database rediscover the simulator's injected incident?
--     Compares mean traversal speed on the incident road DURING the incident
--     with the same road at other times. (The truth sits in sim.injected_event,
--     which no trigger reads.)
-- =====================================================================
SELECT ie.event_type, rd.road_name, ie.road_id, ie.valid_period, ie.magnitude AS injected_speed_factor,
       round(avg(st.avg_speed_kmh) FILTER (WHERE ie.valid_period @> st.entered_at), 1) AS mean_kmh_during,
       round(avg(st.avg_speed_kmh) FILTER (WHERE NOT ie.valid_period @> st.entered_at), 1) AS mean_kmh_otherwise,
       round((avg(st.avg_speed_kmh) FILTER (WHERE ie.valid_period @> st.entered_at)
            / avg(st.avg_speed_kmh) FILTER (WHERE NOT ie.valid_period @> st.entered_at))::numeric, 2) AS observed_ratio,
       count(*) FILTER (WHERE ie.valid_period @> st.entered_at) AS traversals_during
FROM sim.injected_event ie
JOIN public.road_segments rd ON rd.road_id = ie.road_id
JOIN public.segment_traversal st ON st.road_id = ie.road_id
GROUP BY ie.event_id, ie.event_type, rd.road_name, ie.road_id, ie.valid_period, ie.magnitude;


-- =====================================================================
-- Q11 [ST] Space-time cube: zone x hour. Counts fixes and mean reported speed
--     inside each zone for each hour (point-in-polygon on every fix, using the GiST index).
-- =====================================================================
SELECT z.zone_name, z.zone_type,
       EXTRACT(HOUR FROM vp.recorded_at)::int AS hour_of_day,
       count(*) AS fixes,
       round(avg(vp.speed_kmh), 1) AS mean_speed_kmh
FROM public.campus_zones z
JOIN public.vehicle_position vp ON ST_Within(vp.location, z.boundary)
WHERE vp.recorded_at::date = DATE '2026-10-20'
GROUP BY z.zone_name, z.zone_type, 3
ORDER BY z.zone_name, 3;


-- =====================================================================
-- Q12 [ST] Convoy / bunching candidates: two different shuttles within 60 m of
--     each other in at least 3 of the same 10-second time buckets (any route, so
--     shuttles sharing a road count). Co-location across space AND time.
--     A candidate for review, not proof of an operational problem.
-- =====================================================================
WITH f AS (
    SELECT vp.vehicle_id, vp.trip_id, vp.location,
           floor(EXTRACT(EPOCH FROM vp.recorded_at) / 10) AS bucket
    FROM public.vehicle_position vp
    WHERE vp.trip_id IS NOT NULL
)
SELECT a.vehicle_id AS vehicle_a, b.vehicle_id AS vehicle_b,
       a.trip_id AS trip_a, b.trip_id AS trip_b,
       count(*) AS close_buckets,
       to_timestamp(min(a.bucket) * 10) AT TIME ZONE 'UTC' AS first_seen,
       round(avg(ST_Distance(a.location::geography, b.location::geography))::numeric, 1) AS mean_gap_m
FROM f a
JOIN f b ON a.bucket = b.bucket AND a.vehicle_id < b.vehicle_id
        AND ST_DWithin(a.location::geography, b.location::geography, 60)
GROUP BY a.vehicle_id, b.vehicle_id, a.trip_id, b.trip_id
HAVING count(*) >= 3
ORDER BY close_buckets DESC
LIMIT 10;


-- =====================================================================
-- Q13 [T] Candidate delay propagation between successive trips of the SAME vehicle.
--     Rule (explicit): the previous trip finished more than 2 min after its
--     scheduled end, the turnaround to the next scheduled start was under 2 min
--     as a result, and the next trip then started more than 1 min late.
--     This is a CANDIDATE relationship (same vehicle, consecutive trips, shrunken
--     turnaround). It does not prove the first delay caused the second.
-- =====================================================================
WITH seq AS (
    SELECT t.trip_id, t.vehicle_id, t.scheduled_start, t.scheduled_end, t.actual_start, t.actual_end,
           lead(t.trip_id)         OVER w AS next_trip,
           lead(t.scheduled_start) OVER w AS next_sched_start,
           lead(t.actual_start)    OVER w AS next_actual_start
    FROM public.trips t
    WHERE t.service_date = DATE '2026-10-20' AND t.status <> 'Cancelled'
    WINDOW w AS (PARTITION BY t.vehicle_id ORDER BY t.scheduled_start)
)
SELECT vehicle_id, trip_id AS earlier_trip, next_trip AS later_trip,
       round(EXTRACT(EPOCH FROM (actual_end - scheduled_end)))                 AS earlier_end_delay_s,
       round(EXTRACT(EPOCH FROM (next_sched_start - actual_end)))              AS turnaround_left_s,
       round(EXTRACT(EPOCH FROM (next_actual_start - next_sched_start)))       AS later_start_delay_s
FROM seq
WHERE actual_end IS NOT NULL AND next_actual_start IS NOT NULL
  AND actual_end - scheduled_end > interval '2 minutes'
  AND next_sched_start - actual_end < interval '2 minutes'
  AND next_actual_start - next_sched_start > interval '1 minute'
ORDER BY later_start_delay_s DESC
LIMIT 15;


-- =====================================================================
-- Q14 [V + ST] Which of tomorrow's (2026-10-21) trips are exposed to the road closure?
--     A trip is exposed if its route uses the closed road and its scheduled window
--     overlaps the closure period. Uses planned data only (no GPS exists yet).
-- =====================================================================
SELECT c.closure_id, rd.road_name, c.valid_period, c.reason,
       r.route_code, t.trip_id, t.scheduled_start, t.scheduled_end, t.status
FROM public.road_closures c
JOIN public.road_segments rd ON rd.road_id = c.road_id
JOIN public.route_segments rs ON rs.road_id = c.road_id
JOIN public.routes r ON r.route_id = rs.route_id
JOIN public.trips t ON t.route_id = r.route_id
WHERE t.service_date = DATE '2026-10-21'
  AND tsrange(t.scheduled_start, t.scheduled_end) && c.valid_period
ORDER BY t.scheduled_start, r.route_code;


-- =====================================================================
-- Q15 [V] "As of" questions on versioned reference data.
--     (a) timetable rows valid on a date; (b) vehicles available at an instant
--     (history, not the current-status snapshot).
-- =====================================================================
-- (a) departures per route in force on 2026-10-20 (a Tuesday)
SELECT r.route_code, d.day_type, count(*) AS departures, min(d.valid_from) AS valid_from
FROM public.timetable_departures d
JOIN public.routes r ON r.route_id = d.route_id
WHERE d.day_type = public.day_type_of(DATE '2026-10-20')
  AND DATE '2026-10-20' >= d.valid_from AND (d.valid_to IS NULL OR DATE '2026-10-20' <= d.valid_to)
GROUP BY r.route_code, d.day_type ORDER BY r.route_code;

-- (b) vehicles that can be assigned at 2026-10-23 10:00 (vehicle 12 is in maintenance then)
SELECT v.vehicle_id, v.registration_no, public.vehicle_available_at(v.vehicle_id, TIMESTAMP '2026-10-23 10:00') AS available
FROM public.vehicles v ORDER BY available, v.vehicle_id;


-- =====================================================================
-- Q16 [E] How accurate is stop inference from GPS alone? Compared with the
--     simulator's ground truth, per route. (Real deployments have no ground
--     truth; this is what the simulator is for.)
-- =====================================================================
SELECT r.route_code,
       count(*) AS stop_visits_simulated,
       count(e.actual_arrival) AS detected,
       round(avg(abs(EXTRACT(EPOCH FROM (e.actual_arrival - v.true_arrival))))::numeric, 1) AS mean_abs_arrival_error_s,
       round(max(abs(EXTRACT(EPOCH FROM (e.actual_arrival - v.true_arrival))))::numeric, 1) AS max_abs_arrival_error_s,
       round(avg(abs(EXTRACT(EPOCH FROM (e.actual_departure - v.true_departure))))::numeric, 1) AS mean_abs_departure_error_s
FROM sim.true_stop_visit v
JOIN public.trips t ON t.trip_id = v.trip_id
JOIN public.routes r ON r.route_id = t.route_id
JOIN public.trip_stop_event e ON e.trip_id = v.trip_id AND e.stop_sequence = v.stop_sequence
GROUP BY r.route_code
ORDER BY r.route_code;


-- =====================================================================
-- Q17 [ST + E] Arrival-time prediction. For completed trips, at the moment each
--     trip left its 2nd stop, predict its arrival at the final stop two ways:
--       profile : remaining route length / typical speed from segment_speed_profile
--                 for that road and time bucket, plus planned dwell at intermediate stops
--       naive   : scheduled arrival + the delay already accumulated at the 2nd stop
--     and compare both with what actually happened. Note: the profile includes the
--     very trips being predicted (no train/test split), so it flatters the profile.
-- =====================================================================
WITH base AS (
    SELECT t.trip_id, t.route_id,
           e2.actual_departure AS t_dep, e2.scheduled_departure AS s_dep,
           el.actual_arrival AS a_last, el.scheduled_arrival AS s_last,
           rs2.distance_from_start_m AS m0,
           (SELECT max(stop_sequence) FROM public.route_stops WHERE route_id = t.route_id) AS last_seq
    FROM public.trips t
    JOIN public.route_stops rs2 ON rs2.route_id = t.route_id AND rs2.stop_sequence = 2
    JOIN public.trip_stop_event e2 ON e2.trip_id = t.trip_id AND e2.stop_sequence = 2
    JOIN public.trip_stop_event el ON el.trip_id = t.trip_id
         AND el.stop_sequence = (SELECT max(stop_sequence) FROM public.route_stops WHERE route_id = t.route_id)
    WHERE t.status = 'Completed' AND t.service_date = DATE '2026-10-20'
      AND e2.actual_departure IS NOT NULL AND el.actual_arrival IS NOT NULL
), pred AS (
    SELECT b.*,
           (SELECT sum((seg.end_measure_m - greatest(seg.start_measure_m, b.m0))
                       / (coalesce(sp.avg_speed_kmh, 20) / 3.6))
            FROM public.route_segments seg
            LEFT JOIN public.segment_speed_profile sp
                   ON sp.road_id = seg.road_id AND sp.day_type = 'weekday'
                  AND sp.bucket_start = (date_trunc('hour', b.t_dep)
                       + floor(EXTRACT(MINUTE FROM b.t_dep) / 15) * interval '15 minutes')::time
            WHERE seg.route_id = b.route_id AND seg.end_measure_m > b.m0) AS drive_s
    FROM base b
)
SELECT count(*) AS trips_predicted,
       round((avg(abs(EXTRACT(EPOCH FROM (t_dep + make_interval(secs => drive_s + greatest(last_seq - 3, 0) * public.param('default_dwell_s')) - a_last)))) / 60)::numeric, 2)
           AS profile_mean_abs_error_min,
       round((avg(abs(EXTRACT(EPOCH FROM ((s_last + (t_dep - s_dep)) - a_last)))) / 60)::numeric, 2)
           AS naive_mean_abs_error_min
FROM pred;