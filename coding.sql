/*
 WITHIN THIS SECTION WE ARE GOING TO TRANSFER OPENSTREETMAP LINKS INTO A MORE USABLE FORMAT.
 FOR THIS WE ARE GOING TO SPLIT LINKS SO THAT AN INTERSECTION WITH ANOTHER LINK IS ALWAYS
 AT THE REFERENCE (FIRST) OR NON-REFERENCE (LAST) NODE OF THE LINK
 */
DROP TABLE IF EXISTS results.end_nodes;

WITH way_nodes AS (
	SELECT id AS way_id, unnest(nodes) AS node_id, generate_subscripts(nodes, 1) AS index
    FROM osm.occ_sql_postgis_ways
),
first_last_index AS (
    -- please provide the index of the first and last node for every way based on way_nodes:
    -- FIELDS: way_id, index_min, index_max
),
first_last_nodes AS (
    -- please provide per way the first and last node ID:
    -- FIELDS: way_id, first_node_id, last_node_id
),
middle_nodes AS (
    -- please provide per way all nodes which are not the first or last ones
    -- FIELDS: way_id, node_id
),
first_or_last_nodes AS (
    -- please provide per link the first and last node ID per way as a flat list
    -- FIELDS: way_id, node_id
),
intersection_first_or_last_with_middle AS (
    -- please provide a list of nodes where the first or last node of a way is also a middle node of another way
    -- FIELDS: way_id, node_id
),
intersection_middle_with_middle AS (
    -- please provide a list of nodes where a middle node of a way is also a middle node of another way
    -- FIELDS: way_id, node_id
),
split_nodes AS (
    -- please combine the two lists intersection_first_or_last_with_middle and intersection_middle_with_middle
    -- FIELDS: way_id, node_id, true AS split
),
new_nodes AS (
    -- now we create a list of all the new first and end points of the links once we have transformed the ways to links
    -- please add FIELD 'geom' to the nodes
    SELECT DISTINCT nn.way_id, nn.node_id, nn.split, --add field 'geom' here
    FROM (
        SELECT way_id, node_id, split
        FROM split_nodes
        UNION
        SELECT sen.way_id, sen.node_id, false AS split
        FROM first_or_last_nodes sen
     ) AS nn
    JOIN -- please get the geom from some source...
)
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
    -- collect the ways which do not have to be split (hint: the list should contain 4798 ways)
    -- FIELDS: way_id, geometry (polyline)
),
way_nodes AS (
	SELECT id AS way_id, unnest(nodes) AS node_id, generate_subscripts(nodes, 1) AS index
    FROM osm.occ_sql_postgis_ways w
),
self_intersecting AS (
    -- please identify ways and nodes which intersect itself (this means that a node is not present only once per way)
    -- FIELDS: way_id, node_id
),
first_last_index AS (
    -- please re-use your query from above (first_last_index)
),
first_last_nodes AS (
	-- please re-use your query from above (first_last_nodes)
),
split_nodes AS (
    -- now it is getting interesting. Please put together a list of nodes which define the future shape of the links
    -- and add again some geometry to the node IDs
    -- FIELDS: way_id, index, node_id, geom
    SELECT DISTINCT sn.way_id, sn.index, sn.node_id, --add field 'geom' here
    FROM (
        -- adding split nodes
        SELECT sw.way_id, wn.index, sw.node_id
        FROM split_ways sw
        -- something is missing here, but what?
        UNION
        -- adding first node
        SELECT fli.way_id, index_min AS index, w.node_id
        FROM first_last_index fli
        -- something is missing here, but what?
        JOIN split_ways sw ON sw.way_id = w.way_id
        UNION
        -- adding last node
        SELECT fli.way_id, index_max AS index, w.node_id
        FROM first_last_index fli
        -- something is missing here, but what?
        JOIN split_ways sw ON sw.way_id = w.way_id
    ) AS sn
    JOIN -- please get the geom from some source...
),
splitted_ways AS (
    -- in this step we will do some interesting stuff. We will have to create pairs of 'one node and the next node'.
    -- we will have to make use of the node index for this challenge.
    -- You will get some help, but three conditions got lost - please find the correct conditions
    SELECT
        sn1.way_id
        , sn1.node_id AS ref_node_id
        , sn2.node_id AS non_ref_node_id
        , sn1.geom  AS ref_node_geometry
        , sn2.geom  AS non_ref_node_geometry
    FROM split_nodes AS sn1
    LEFT JOIN split_nodes AS sn2 ON sn1.way_id = sn2.way_id AND sn1.index < sn2.index
    LEFT JOIN split_nodes AS sn3 ON sn2.way_id = sn3.way_id AND sn3.index > sn1.index AND sn3.index < sn2.index
    WHERE -- condition no. 1 is missing
        AND -- condition no. 2 is missing
        AND -- condition no. 3 is missing
    order by sn1.way_id, sn1.index, sn2.index
),
sub_linestring AS (
    -- this step is tricky, since we have to disassemble some ways. Please identify the correct PostGIS functions for it
	SELECT (_POSTGIS_FUNCTIONALITY_) AS geometry, -- << hint: some help is provided by the LEFT JOIN - you will need it!
	sw.way_id,
	ref_node_id,
	non_ref_node_id
	FROM splitted_ways sw
	JOIN osm.occ_sql_postgis_ways wa ON wa.id = sw.way_id
	LEFT JOIN self_intersecting non_ref_intersect ON non_ref_intersect.node_id = sw.non_ref_node_id
),
split_links AS (
    -- in this step please only calculate the length of the new links in centimeters
    SELECT
        _CALCULATE_THE_LENGTH_IN_CENTIMETERS_::integer AS length_cm,
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
    -- the same for the ways where no splitting was needed
    SELECT
       _CALCULATE_THE_LENGTH_IN_CENTIMETERS_::integer AS length_cm,
        w.way_id,
        fln.first_node_id AS ref_node_id,
        fln.last_node_id AS non_ref_node_id,
        w.geometry AS way_geometry
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
    -- there are a lot of links which are no roads. Please specify a suitable filter in order to come to a good result
    select *
    from results.links road
    WHERE -- please specify a filter so that we only process roads
),
node_link_count AS (
    -- please create a query which returns the information how many links reference a certain node ID
    -- FIELDS: node_id, count
),
one_way_nodes AS (
    -- we want to filter out some certain links (intersection internal) which are present at intersections
    SELECT distinct nn.node_id
    FROM results.new_nodes nn
    JOIN roads r on ref_node_id = nn.node_id or non_ref_node_id = nn.node_id
    where r.oneway = 'yes'
),
intersection_internal_links AS (
    -- please add the conditions which filter out intersections with less than three links
    select r.*
    from roads r
    join node_link_count nlc_ref on nlc_ref.node_id = ref_node_id
    join node_link_count nlc_non_ref on nlc_non_ref.node_id = non_ref_node_id
    where length_cm < 3000
    and -- please add condition
    and -- please add condition
    and ref_node_id in (select node_id from one_way_nodes)
    and non_ref_node_id in (select node_id from one_way_nodes)
),
link_not_intersection_internal AS (
    -- now please remove the intersection_internal_links from the roads query. Return all fields of the road
),
bus_stops AS (
    -- please add a buffer of 30 meters around each bus stop
    select
           id as sign_id,
           geom,
           _ADD_BUFFER_OF_30_METERS_ as buffer
    from mapillary.bus_stops
),
distances AS (
    -- please calculate the distance in centimeters between the bus stop and the links which intersect the buffer
    -- please add the intersection condition (links within the 30 meters buffer of the bus stop)
	select
	       r.link_id as link_id,
	       r.geometry,
	       bus_stops.sign_id,
	       _DISTANCE_BETWEEN_BUS_STOP_AND_LINK_IN_CENTIMETERS::integer as dist_cm
	from link_not_intersection_internal r, bus_stops
	where -- please add the intersection condition (links within the buffer of the bus stop)
	order by sign_id, dist_cm asc
),
bus_stop_link AS (
    -- now please select the distance record with the shortest distance per bus stop
    select d.*
    from distances d
    join (
        -- find the record with the shortest distance here
        -- FIELDS: dist_cm, sign_id
        SELECT -- ...
        FROM distances
        GROUP BY --...
    ) as shortest on d.sign_id = shortest.sign_id and d.dist_cm = shortest.dist_cm
)
-- add the end we store one link per bus stop.
-- Some bus stop have no links within the specified distance and therefore no record is created
select *
into results.bus_stop_link
from bus_stop_link;

/*
 ONCE WE HAVE IDENTIFIED THE CORRECT LINKS FOR THE BUS STOPS WE SHOULD ALSO CREATE THE SHORTEST LINE
 FROM THE BUS STOP SIGN TO THE LINK
 */
DROP TABLE IF EXISTS  results.connection;
-- add the end of this challenge please create table results.connection
-- which shall contain the shortest line between the bus stop and the selected link stored in results.bus_stop_link
-- FIELDS: link_id, sign_id, length_cm, geometry
WITH connection AS (
	-- put your query here
)
SELECT -- put your SELECT here
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
