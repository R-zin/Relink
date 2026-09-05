/* Leaflet + OSM frontend (plan.md 9.2). Toggleable layers, clickable risk
 * polygons, geolocation "risk at my location", legend, disclaimer. */
(function () {
  const API = "";  // same origin
  const REGION = "kerala";

  const RISK_COLORS = {
    1: "#2ca02c", 2: "#ffff00", 3: "#ff7f0e", 4: "#d62728", 5: "#7b0177",
  };
  const RISK_NAMES = {
    1: "Very Low", 2: "Low", 3: "Moderate", 4: "High", 5: "Very High",
  };

  const map = L.map("map").setView([10.2, 76.5], 8);
  const osm = L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
    attribution: "&copy; OpenStreetMap contributors",
    maxZoom: 19,
  }).addTo(map);

  const info = document.getElementById("info");

  // ---- risk regions polygons -------------------------------------------
  const riskLayer = L.geoJSON(null, {
    style: (f) => ({
      color: RISK_COLORS[f.properties.risk_class] || "#d62728",
      weight: 1,
      fillColor: RISK_COLORS[f.properties.risk_class] || "#d62728",
      fillOpacity: 0.45,
    }),
    onEachFeature: (f, layer) => {
      const p = f.properties;
      layer.bindPopup(
        `<b>Potential landslide-prone region</b><br>` +
        `Risk: ${p.risk_name} (class ${p.risk_class})<br>` +
        `Mean P: ${p.prob_mean?.toFixed(3)} &nbsp; Max P: ${p.prob_max?.toFixed(3)}<br>` +
        `Area: ${p.area_km2} km&sup2;`
      );
    },
  });
  fetch(`${API}/api/risk-regions?region=${REGION}`)
    .then((r) => r.json())
    .then((gj) => { riskLayer.addData(gj); })
    .catch(() => { info.textContent = "risk regions unavailable (run pipeline first)"; });

  // ---- historical landslides -------------------------------------------
  const histLayer = L.geoJSON(null, {
    pointToLayer: (f, latlng) => L.circleMarker(latlng, {
      radius: 5, color: "#111", fillColor: "#000", fillOpacity: 0.8, weight: 1,
    }),
    onEachFeature: (f, layer) => {
      const p = f.properties || {};
      layer.bindPopup(
        `<b>Historical landslide</b><br>Date: ${p.date || "unknown"}<br>Source: ${p.source || "inventory"}`
      );
    },
  });
  fetch(`${API}/api/historical-landslides?region=${REGION}`)
    .then((r) => r.json())
    .then((gj) => { histLayer.addData(gj); })
    .catch(() => {});

  riskLayer.addTo(map);
  histLayer.addTo(map);

  // ---- layer toggles -----------------------------------------------------
  const controls = document.getElementById("layer-controls");
  const layers = [
    ["OpenStreetMap basemap", osm],
    ["Potential landslide regions", riskLayer],
    ["Historical landslides", histLayer],
  ];
  for (const [label, lyr] of layers) {
    const id = `lyr-${label.replace(/\W+/g, "-")}`;
    const el = document.createElement("label");
    el.innerHTML = `<input type="checkbox" id="${id}" checked> ${label}`;
    el.querySelector("input").addEventListener("change", (e) => {
      if (e.target.checked) lyr.addTo(map); else map.removeLayer(lyr);
    });
    controls.appendChild(el);
  }

  // ---- legend ------------------------------------------------------------
  const legend = document.getElementById("legend");
  legend.innerHTML = "<b>Risk classes</b><br>" + [1, 2, 3, 4, 5]
    .map((c) => `<span class="swatch" style="background:${RISK_COLORS[c]}"></span>${RISK_NAMES[c]}`)
    .join("<br>");

  // ---- click -> point risk ----------------------------------------------
  let clickMarker = null;
  map.on("click", (e) => {
    const { lat, lng } = e.latlng;
    fetch(`${API}/api/point-risk?lat=${lat.toFixed(6)}&lon=${lng.toFixed(6)}&region=${REGION}`)
      .then((r) => r.json())
      .then((d) => {
        if (clickMarker) map.removeLayer(clickMarker);
        clickMarker = L.marker([lat, lng]).addTo(map);
        info.innerHTML = d.in_region
          ? `Susceptibility ${d.susceptibility} &mdash; <b>${d.risk_name}</b> ` +
            `(potential landslide-prone region, not active detection)`
          : d.message;
      });
  });

  // ---- geolocation "you are here" ---------------------------------------
  if (navigator.geolocation) {
    navigator.geolocation.getCurrentPosition((pos) => {
      const { latitude: lat, longitude: lon } = pos.coords;
      const m = L.circleMarker([lat, lon], {
        radius: 7, color: "#1565c0", fillColor: "#1e88e5", fillOpacity: 0.9,
      }).addTo(map).bindPopup("You are here");
      fetch(`${API}/api/point-risk?lat=${lat}&lon=${lon}&region=${REGION}`)
        .then((r) => r.json())
        .then((d) => {
          if (d.in_region) {
            m.bindPopup(`You are here<br>Susceptibility ${d.susceptibility} &mdash; ${d.risk_name}`);
          }
        });
    });
  }
})();
