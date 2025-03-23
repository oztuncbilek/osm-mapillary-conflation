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

## Prerequisites
- Docker and Docker Compose installed.
- PostgreSQL and pgAdmin (optional, but recommended for easier database management).
- Clone the repository

1. Start the Docker containers:
   ```bash
   docker-compose up -d
   ```
2. Use pgAdmin to connect to the database and restore the provided backup.

## Running the SQL Script
Execute the results.sql script in pgAdmin or via the psql command-line tool to perform data normalization and conflation.

## Current Status
1. **Data Normalization**:
   - Identify and split OSM ways at intersection points.
   - Create topologically correct links from the normalized ways.
2. **Data Conflation**:
   - Filter out non-road links (e.g., bicycle paths) to focus on the true road network.
   - Find the nearest road link for each Mapillary bus stop.

## Next Steps
1. **Test Scenario Fixes**:
   -The second test scenario is currently failing. 

2. **Visualization**:
   - Create maps to showcase the conflated data.

## Notes
The munich.osm file was not imported as the backup_OCC_PostGIS.backup already contained the necessary OSM data. It can be used for visualization step. 

## License
This project is licensed under the MIT License. 

