# RELINK — Off-Grid Disaster Intelligence & Emergency Response Platform

> **CODIO** | *.hack'26 Project*  
> **Team Members:** Razin M, Harikrishnan S, Steve Sony Jacob, Navneeth Krishna B

---

##  Overview

**RELINK** is an integrated disaster-response ecosystem that combines offline-first peer-to-peer (P2P) mesh networking with predictive geospatial machine learning and encrypted telemetry. Designed to operate when traditional cell towers, power grids, and internet lines completely fail, RELINK enables real-time emergency communication, automated hazard clustering, early warnings, and rescue dispatch.

---

##  Key Features & Capabilities

- **Offline-First P2P Mesh Network:** Uses Bluetooth Low Energy (BLE 5.0) and Wi-Fi Direct via Google Nearby Connections to exchange SOS alerts, hazard reports, missing-person tracking, and shelter details without cellular coverage.
- **Geospatial Hazard Intelligence & ML:** Ingests satellite imagery and terrain rasters onto a 30m UTM grid to output landslide susceptibility maps (`risk_regions.geojson`) using an XGBoost ML pipeline.
- **Spatial Hazard Clustering:** In-flight deduplication and spatial grouping using scikit-learn DBSCAN (500m Haversine) to reduce noise and enhance situational confidence.
- **Medical Record Security:** AES-256-GCM end-to-end encryption for sensitive victim and medical telemetry with break-glass in-memory decryption on the responder dashboard.
- **Unified Command Console:** React 19 + Leaflet GIS console featuring live dispatch queues, hydrological charts, and real-time incident mapping for disaster response teams (NDMA/SDMA, NGOs).
- **Multi-Source Ingestion:** Ingests alerts from Open-Meteo GloFAS, NASA EONET, and NDMA Sachet CAP/RSS government feeds.

---

##  System Architecture

```
                       +-----------------------------------+
                       |    Android Client (Flutter)       |
                       |  - Offline P2P Mesh (BLE/Wi-Fi)   |
                       |  - Local SQLite Queue             |
                       |  - AES-256-GCM Encryption         |
                       +-----------------+-----------------+
                                         |
                       (Opportunistic Sync / Data Mule)
                                         |
                                         v
+-----------------------+     +----------+----------+     +------------------------+
|  External Data Feeds  |     |   FastAPI Backend   |     |    Command Console     |
| - NASA EONET / NDMA   |---->| - DBSCAN Clustering |<--->|  (React 19 + Leaflet)  |
| - Open-Meteo Telemetry|     | - PostgreSQL / GIS  |     | - Real-time Dispatch   |
+-----------------------+     +---------------------+     +------------------------+
                                         ^
                                         |
                              +----------+----------+
                              | Geospatial ML Core  |
                              | XGBoost + Rasterio  |
                              +---------------------+
```

---

##  Tech Stack

| Layer | Technologies & Tools |
| :--- | :--- |
| **Mobile Edge (Frontend)** | Flutter (Dart), Google Nearby Connections (`P2P_CLUSTER`), SQLite (`sqflite`), AES-256-GCM |
| **Command Console** | React 19, Vite, Leaflet GIS, Tailwind CSS, Chart.js |
| **Backend API** | Python, FastAPI, SQLAlchemy, `asyncpg`, APScheduler |
| **Database** | PostgreSQL with `pgcrypto` |
| **Geospatial ML Core** | Python, XGBoost, Rasterio, Scikit-learn (DBSCAN) |
| **Integrations** | NASA EONET, Open-Meteo GloFAS, NDMA Sachet CAP/RSS |

---

##  Repository Structure

```
.
├── backend/                # FastAPI backend service & DB models
│   ├── app/                # Main application package
│   │   ├── api/            # API endpoints (SOS, hazards, alerts)
│   │   ├── core/           # Config and AES decryption utilities
│   │   ├── ml/             # DBSCAN clustering & raster processing
│   │   └── models/         # SQLAlchemy schemas
│   └── main.py             # Entry point
├── ml_engine/              # Landslide susceptibility ML pipeline
│   ├── train.py            # Model training on 30m UTM grid
│   └── inference.py        # Generates risk_regions.geojson
├── mobile/                 # Flutter mobile application
│   ├── lib/                # App code (mesh logic, P2P handlers, SQLite)
│   └── pubspec.yaml
├── web_console/            # React 19 + Vite responder dashboard
│   ├── src/                # GIS mapping, dispatch queue components
│   └── package.json
└── README.md
```

---

##  Getting Started

### Prerequisites

- **Python 3.11+**
- **Node.js 18+** & `npm` / `pnpm`
- **Flutter SDK 3.x**
- **PostgreSQL 15+** (with `pgcrypto` extension enabled)

---

### Backend Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/codio/relink.git
   cd relink/backend
   ```

2. **Create and activate virtual environment:**
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

3. **Install dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

4. **Environment Configuration:**
   Create a `.env` file in `backend/`:
   ```env
   DATABASE_URL=postgresql+asyncpg://user:password@localhost:5432/relink_db
   SECRET_KEY=your_aes_256_key_here
   ```

5. **Run Database Migrations & Server:**
   ```bash
   uvicorn main:app --reload --port 8000
   ```

---

### Mobile Client (Flutter) Setup

1. **Navigate to the mobile directory:**
   ```bash
   cd ../mobile
   ```

2. **Fetch packages & run app:**
   ```bash
   flutter pub get
   flutter run
   ```

---

### Command Console Setup

1. **Navigate to `web_console`:**
   ```bash
   cd ../web_console
   ```

2. **Install dependencies & start development server:**
   ```bash
   npm install
   npm run dev
   ```

---

##  Roadmap & Future Expansions

- [ ] **Missing Person Triangulation:** Spatial graph routing over mesh network signals to track missing persons.
- [ ] **IoT & Drone Telemetry:** Direct ingestion of river-level sensors and aerial drone imagery via Wi-Fi Direct.
- [ ] **Localized Vernacular Support:** Multi-language adaptation for regional populations in high-risk areas.

---

##  License

Distributed under the MIT License. See `LICENSE` for more information.
