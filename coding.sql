/*
 WITHIN THIS SECTION WE ARE GOING TO TRANSFER OPENSTREETMAP LINKS INTO A MORE USABLE FORMAT.
 FOR THIS WE ARE GOING TO SPLIT LINKS SO THAT AN INTERSECTION WITH ANOTHER LINK IS ALWAYS
 AT THE REFERENCE (FIRST) OR NON-REFERENCE (LAST) NODE OF THE LINK
 */
DROP TABLE IF EXISTS results.end_nodes;

WITH way_nodes AS (
    SELECT 
        id AS way_id, 
        unnest(nodes) AS node_id, 
        generate_subscripts(nodes, 1) AS index
    FROM osm.occ_sql_postgis_ways
),
first_last_index AS (
    SELECT 
        way_id, 
        MIN(index) AS index_min, 
        MAX(index) AS index_max
    FROM way_nodes
    GROUP BY way_id
),
first_last_nodes AS (
    SELECT 
        wn.way_id, 
        wn.node_id AS first_node_id,
        NULL AS last_node_id 
    FROM way_nodes wn
    JOIN first_last_index fli ON wn.way_id = fli.way_id AND wn.index = fli.index_min
    UNION
    SELECT 
        wn.way_id, 
        NULL AS first_node_id,  
        wn.node_id AS last_node_id
    FROM way_nodes wn
    JOIN first_last_index fli ON wn.way_id = fli.way_id AND wn.index = fli.index_max
),
middle_nodes AS (
    SELECT 
        wn.way_id, 
        wn.node_id
    FROM way_nodes wn
    LEFT JOIN first_last_index fli ON wn.way_id = fli.way_id
    WHERE wn.index != fli.index_min AND wn.index != fli.index_max
),
first_or_last_nodes AS (
    SELECT 
        way_id, 
        first_node_id AS node_id
    FROM first_last_nodes
    UNION
    SELECT 
        way_id, 
        last_node_id AS node_id
    FROM first_last_nodes
),
intersection_first_or_last_with_middle AS (
    SELECT 
        fln.way_id, 
        fln.node_id
    FROM first_or_last_nodes fln
    JOIN middle_nodes mn ON fln.node_id = mn.node_id
),
intersection_middle_with_middle AS (
    SELECT 
        mn1.way_id, 
        mn1.node_id
    FROM middle_nodes mn1
    JOIN middle_nodes mn2 ON mn1.node_id = mn2.node_id AND mn1.way_id != mn2.way_id
),
split_nodes AS (
    SELECT 
        way_id, 
        node_id, 
        true AS split
    FROM intersection_first_or_last_with_middle
    UNION
    SELECT 
        way_id, 
        node_id, 
        true AS split
    FROM intersection_middle_with_middle
),
new_nodes AS (
    SELECT DISTINCT 
        nn.way_id, 
        nn.node_id, 
        nn.split, 
        n.geom
    FROM (
        SELECT way_id, node_id, split
        FROM split_nodes
        UNION
        SELECT way_id, node_id, false AS split
        FROM first_or_last_nodes
    ) AS nn
    JOIN osm.occ_sql_postgis_nodes n ON nn.node_id = n.id
),
/*
 THE RESULT OF THIS QUERY IS A TABLE WHICH CONTAINS THE IMPORTANT NODES OF A LINK.
 THESE NODES WILL BE USED TO TRANSFER THE WAYS INTO LINKS LATER ON.
 */
SELECT *
INTO results.end_nodes
FROM new_nodes;

DROP TABLE IF EXISTS results.new_nodes;

WITH distinct_nodes AS (
    SELECT DISTINCT node_id
    FROM results.end_nodes
)
/*
 THE RESULT OF THIS QUERY TRANSFORMS THE IMPORTANT NODES INTO A DISTINCT LIST WITHOUT DUPLICATES
 */
SELECT DISTINCT dn.node_id, n.geom
INTO results.new_nodes
FROM distinct_nodes dn
JOIN osm.occ_sql_postgis_nodes n ON dn.node_id=n.id;

/*
 HERE WE WILL MAKE USE OF THE COLLECTED NODES AND TRANSFORM THE WAYS OF OSM INTO LINKS.
 SOME LINKS MUST BE SPLIT AND SOME NOT.
 */
DROP TABLE IF EXISTS  results.links;
WITH split_ways AS (
	SELECT id AS way_id, en.node_id
	FROM osm.occ_sql_postgis_ways w
	JOIN results.end_nodes en ON en.way_id = w.id
    WHERE en.split
),
no_split_ways AS (
    SELECT 
        w.id AS way_id, 
        w.nodes, 
        ST_MakeLine(array_agg(n.geom ORDER BY wn.index)) AS geom
    FROM osm.occ_sql_postgis_ways w
    JOIN (
        SELECT id AS way_id, unnest(nodes) AS node_id, generate_subscripts(nodes, 1) AS index
        FROM osm.occ_sql_postgis_ways
    ) wn ON w.id = wn.way_id
    JOIN osm.occ_sql_postgis_nodes n ON wn.node_id = n.id
    WHERE w.id NOT IN (SELECT way_id FROM results.end_nodes WHERE split = true)
    GROUP BY w.id, w.nodes
),
way_nodes AS (
	SELECT id AS way_id, unnest(nodes) AS node_id, generate_subscripts(nodes, 1) AS index
    FROM osm.occ_sql_postgis_ways w
),
self_intersecting AS (
    SELECT way_id, node_id
    FROM (
        SELECT way_id, node_id, COUNT(*) AS cnt
        FROM way_nodes
        GROUP BY way_id, node_id
        HAVING COUNT(*) > 1
    ) AS self_intersect
),
first_last_index AS (
    SELECT way_id, MIN(index) AS index_min, MAX(index) AS index_max
    FROM way_nodes
    GROUP BY way_id
),
first_last_nodes AS (
    SELECT wn.way_id, 
           wn.node_id AS first_node_id,
           wn2.node_id AS last_node_id
    FROM way_nodes wn
    JOIN first_last_index fli ON wn.way_id = fli.way_id AND wn.index = fli.index_min
    JOIN way_nodes wn2 ON wn.way_id = wn2.way_id AND wn2.index = fli.index_max
),
split_nodes AS (
    SELECT DISTINCT sn.way_id, sn.index, sn.node_id, n.geom
    FROM (
        SELECT sw.way_id, wn.index, sw.node_id
        FROM split_ways sw
        JOIN way_nodes wn ON sw.way_id = wn.way_id AND sw.node_id = wn.node_id
        UNION
        SELECT fli.way_id, index_min AS index, fln.first_node_id AS node_id
        FROM first_last_index fli
        JOIN first_last_nodes fln ON fli.way_id = fln.way_id
        UNION
        SELECT fli.way_id, index_max AS index, fln.last_node_id AS node_id
        FROM first_last_index fli
        JOIN first_last_nodes fln ON fli.way_id = fln.way_id
    ) AS sn
    JOIN osm.occ_sql_postgis_nodes n ON sn.node_id = n.id
),
splitted_ways AS (
    SELECT
        sn1.way_id,
        sn1.node_id AS ref_node_id,
        sn2.node_id AS non_ref_node_id,
        sn1.geom AS ref_node_geometry,
        sn2.geom AS non_ref_node_geometry
    FROM split_nodes AS sn1
    LEFT JOIN split_nodes AS sn2 ON sn1.way_id = sn2.way_id AND sn1.index < sn2.index
    LEFT JOIN split_nodes AS sn3 ON sn2.way_id = sn3.way_id AND sn3.index > sn1.index AND sn3.index < sn2.index
    WHERE sn2.node_id IS NOT NULL
    AND sn3.node_id IS NULL
    ORDER BY sn1.way_id, sn1.index, sn2.index
),
sub_linestring AS (
    SELECT ST_MakeLine(ref_node_geometry, non_ref_node_geometry) AS geometry,
           sw.way_id,
           ref_node_id,
           non_ref_node_id
    FROM splitted_ways sw
    JOIN osm.occ_sql_postgis_ways wa ON wa.id = sw.way_id
),
split_links AS (
    SELECT
        ST_Length(sss.geometry) * 100 AS length_cm, 
        w.way_id,  
        w.ref_node_id,
        w.non_ref_node_id,
        sss.geometry AS geometry
    FROM splitted_ways w
    JOIN sub_linestring sss ON (
        w.way_id = sss.way_id
        AND w.ref_node_id = sss.ref_node_id
        AND w.non_ref_node_id = sss.non_ref_node_id
    )
),
no_split_links AS (
    SELECT
        ST_Length(w.geom) * 100 AS length_cm,  
        w.way_id,
        fln.first_node_id AS ref_node_id,
        fln.last_node_id AS non_ref_node_id,
        w.geom AS geometry  
    FROM no_split_ways w
    JOIN first_last_nodes fln ON w.way_id = fln.way_id
)

SELECT row_number() OVER() AS link_id, links.*, w.highway, w.bicycle, w.foot, w.motor_vehicle, w.oneway
INTO results.links
FROM (
    SELECT *
    FROM split_links
    UNION
    SELECT *
    FROM no_split_links
) AS links
JOIN osm.occ_sql_postgis_ways w ON w.id = links.way_id
-- integrity check
JOIN results.new_nodes ref_node ON ref_node.node_id = ref_node_id
JOIN results.new_nodes non_ref_node ON non_ref_node.node_id = non_ref_node_id;

/*
 WE HAVE NOW CONVERTED ALL WAYS TO LINKS. IN THE NEXT STEP WE WANT TO PROCESS SOME BUS STOP SIGN OBSERVATIONS
 FROM MAPILLARY (POINTS) AND FIND THE BEST MATCHING (NEAREST) ROAD LINKS FOR IT.
*/

DROP table if exists results.bus_stop_link ;

WITH roads AS (
    SELECT *
    FROM results.links
    WHERE highway IN ('primary', 'secondary', 'tertiary', 'residential', 'service')
),
node_link_count AS (
  SELECT node_id, COUNT(*) AS count
    FROM (
        SELECT ref_node_id AS node_id FROM roads
        UNION ALL
        SELECT non_ref_node_id AS node_id FROM roads
    ) AS nodes
    GROUP BY node_id

),
one_way_nodes AS (
   SELECT DISTINCT nn.node_id
    FROM results.new_nodes nn
    JOIN roads r ON nn.node_id = r.ref_node_id OR nn.node_id = r.non_ref_node_id
    WHERE r.oneway = 'yes'
),
intersection_internal_links AS (
   SELECT r.*
    FROM roads r
    JOIN node_link_count nlc_ref ON nlc_ref.node_id = r.ref_node_id
    JOIN node_link_count nlc_non_ref ON nlc_non_ref.node_id = r.non_ref_node_id
    WHERE r.length_cm < 3000 -- Kısa linkleri filtrele
      AND nlc_ref.count >= 3 -- En az 3 linke bağlı node'lar
      AND nlc_non_ref.count >= 3 -- En az 3 linke bağlı node'lar
      AND r.ref_node_id IN (SELECT node_id FROM one_way_nodes)
      AND r.non_ref_node_id IN (SELECT node_id FROM one_way_nodes)
),
link_not_intersection_internal AS (
    SELECT *
    FROM roads
    WHERE link_id NOT IN (SELECT link_id FROM intersection_internal_links)
),
bus_stops AS (
    SELECT
        id AS sign_id,
        geom,
        ST_Buffer(geom::geography, 30)::geometry AS buffer -- 30 metrelik buffer
    FROM mapillary.bus_stops
),
distances AS (
    SELECT
        r.link_id,
        r.geometry,
        bs.sign_id,
        ST_Distance(bs.geom::geography, r.geometry::geography)::integer AS dist_cm
    FROM link_not_intersection_internal r, bus_stops bs
    WHERE ST_Intersects(bs.buffer, r.geometry) 
    ORDER BY bs.sign_id, dist_cm ASC
),
bus_stop_link AS (
    SELECT d.*
    FROM distances d
    JOIN (
        SELECT sign_id, MIN(dist_cm) AS min_dist
        FROM distances
        GROUP BY sign_id
    ) AS shortest ON d.sign_id = shortest.sign_id AND d.dist_cm = shortest.min_dist
)
-- add the end we store one link per bus stop.
-- Some bus stop have no links within the specified distance and therefore no record is created
SELECT *
INTO results.bus_stop_link
FROM bus_stop_link;

/*
 ONCE WE HAVE IDENTIFIED THE CORRECT LINKS FOR THE BUS STOPS WE SHOULD ALSO CREATE THE SHORTEST LINE
 FROM THE BUS STOP SIGN TO THE LINK
 */
DROP TABLE IF EXISTS  results.connection;
-- add the end of this challenge please create table results.connection
-- which shall contain the shortest line between the bus stop and the selected link stored in results.bus_stop_link
-- FIELDS: link_id, sign_id, length_cm, geometry
WITH connection AS (
    SELECT
        bsl.link_id,
        bsl.sign_id,
        ST_Distance(bs.geom::geography, r.geometry::geography)::integer AS length_cm,
        ST_ShortestLine(bs.geom, r.geometry) AS geometry
    FROM results.bus_stop_link bsl
    JOIN mapillary.bus_stops bs ON bsl.sign_id = bs.id
    JOIN results.links r ON bsl.link_id = r.link_id
)
SELECT  *
INTO results.connection
FROM connection;

/*
 THE BELOW QUERIES SHALL HELP YOU TO TEST YOUR CODE AND RESULTS
*/
-- EXPECTED RESULTS FROM FOLLOWING QUERY ARE 2 RECORDS:
SELECT id
FROM mapillary.bus_stops
LEFT JOIN results.connection ON sign_id = id
WHERE sign_id IS NULL;

-- IN results.links TABLE EXPECTED RECORDS: 19095
SELECT count(*)
FROM results.links;

-- IN results.new_nodes TABLE EXPECTED RECORDS: 14144
SELECT count(*)
FROM results.new_nodes;
