# web (later)

React + Vite + TypeScript, with MapLibre GL JS for the map.

```fish
npm create vite@latest . -- --template react-ts
npm install maplibre-gl
```

Planned pieces:
- Base map from OpenStreetMap vector tiles (MapTiler, Stadia, or self-hosted Protomaps), with 3D building extrusions.
- A MapLibre `heatmap` layer fed by `GET /api/v1/heatmap?bbox=...` on every map move. Use the `score`
  property for `heatmap-weight` and a green, yellow, red `heatmap-color` ramp.
- Click a hotspot: call `GET /api/v1/trashes?lat=&lng=&radius=` and show a side panel with the photos,
  dates, trash types, and the uploader name or "anonymous".

Set `VITE_API_URL` to the Rails server, and add the web origin to `WEB_ORIGINS` in the API environment.
