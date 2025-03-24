import { config } from './config.js';

mapboxgl.accessToken = config.MAPBOX_TOKEN;

const map = new mapboxgl.Map({
    container: 'map',
    style: 'mapbox://styles/mapbox/streets-v11',
    center: [11.5345, 48.1789], // Munich coordinates [lng, lat]
    zoom: 12.5
});

map.addControl(new mapboxgl.NavigationControl());

async function loadGeoJSON(url) {
    try {
        const response = await fetch(url);
        if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
        return await response.json();
    } catch (error) {
        console.error('GeoJSON yükleme hatası:', error);
        return { type: 'FeatureCollection', features: [] };
    }
}

function createLayerControl() {
    const layerControl = document.createElement('div');
    layerControl.className = 'layer-control';
    layerControl.innerHTML = `
        <h3>Layers</h3>
        <label><input type="checkbox" checked id="links-checkbox"> Roads</label><br>
        <label><input type="checkbox" checked id="bus-checkbox"> Bus Stops</label><br>
        <label><input type="checkbox" checked id="conn-checkbox"> Connections</label>
    `;
    document.body.appendChild(layerControl);

    document.getElementById('links-checkbox').addEventListener('change', (e) => {
        map.setLayoutProperty('links-layer', 'visibility', e.target.checked ? 'visible' : 'none');
    });
    
    document.getElementById('bus-checkbox').addEventListener('change', (e) => {
        map.setLayoutProperty('bus-stops-layer', 'visibility', e.target.checked ? 'visible' : 'none');
    });
    
    document.getElementById('conn-checkbox').addEventListener('change', (e) => {
        map.setLayoutProperty('connections-layer', 'visibility', e.target.checked ? 'visible' : 'none');
    });
}

map.on('load', async () => {
    // 1. roads
    const linksData = await loadGeoJSON('results/links.geojson');
    map.addSource('links', { type: 'geojson', data: linksData });
    map.addLayer({
        id: 'links-layer',
        type: 'line',
        source: 'links',
        paint: {
            'line-color': '#3a86ff',
            'line-width': 1,
            'line-opacity': 0.9
        }
    });

    // 2. bus stops
    const busStopsData = await loadGeoJSON('results/bus_stop_link.geojson');
    map.addSource('bus-stops', { type: 'geojson', data: busStopsData });
    map.addLayer({
        id: 'bus-stops-layer',
        type: 'circle',
        source: 'bus-stops',
        paint: {
            'circle-radius': 6,
            'circle-color': '#ff006e',
            'circle-stroke-width': 1,
            'circle-stroke-color': '#fff'
        }
    });

    // 3. connections
    const connectionsData = await loadGeoJSON('results/connection.geojson');
    map.addSource('connections', { type: 'geojson', data: connectionsData });
    map.addLayer({
        id: 'connections-layer',
        type: 'line',
        source: 'connections',
        paint: {
            'line-color': '#38b000',
            'line-width': 5,
            'line-dasharray': [2, 1]
        }
    });

    createLayerControl();
});