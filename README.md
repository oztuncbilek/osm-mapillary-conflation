# OSM Mapillary Conflation Project

This project aims to conflate OpenStreetMap (OSM) data with Mapillary observations using PostGIS. The goal is to normalize OSM ways, correct topological errors, and connect bus stops observed in Mapillary imagery to the nearest OSM road links.

## Technologies Used
- **PostgreSQL** (v14) with **PostGIS** extension
- **Docker** for containerized database setup
- **pgAdmin** for database management
- **Git** for version control

## Project Structure
The project consists of three main parts:
1. **Environment Preparation**: Setting up PostgreSQL with PostGIS and restoring the provided database backup.
2. **Data Normalization**: Correcting OSM ways to ensure topological correctness and splitting them into smaller links.
3. **Data Conflation**: Connecting Mapillary bus stop observations to the nearest OSM road links.

## Next Steps
1. **Data Normalization**:
   - Identify and split OSM ways at intersection points.
   - Create topologically correct links from the normalized ways.
   - Store the results in the `results.links` table.

2. **Data Conflation**:
   - Filter out non-road links (e.g., bicycle paths) to focus on the true road network.
   - Find the nearest road link for each Mapillary bus stop.
   - Create artificial geometries representing the shortest path from bus stops to their corresponding links.

3. **Visualization**:
   - Export the results as GeoJSON or Shapefile for visualization in GIS software.
   - Create maps to showcase the conflated data.

## Docker Setup
To set up the environment using Docker, follow these steps:
1. Pull the PostGIS Docker image:
   ```bash
   docker pull postgis/postgis:14-3.3
   ```
2. Run the container:
   ```bash
   docker run --name postgis_db -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=yourpassword -e POSTGRES_DB=osm_mapillary -p 5432:5432 -d postgis/postgis:14-3.3
   ```
3. Use pgAdmin to connect to the database and restore the provided backup.

## License
This project is licensed under the MIT License. 

