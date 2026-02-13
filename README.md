# Vehicle Tracking App

Real-time bus tracking app built with **Flutter** (frontend) and **FastAPI + Redis** (backend).

## Project Structure

```
bus-tracker/
├── backend/
│   ├── main.py                 # FastAPI app entry point
│   ├── config.py               # App settings
│   ├── models.py               # BusPosition data model
│   ├── redis_client.py         # Async Redis manager
│   ├── requirements.txt        # Python dependencies
│   ├── data/
│   │   └── delhi_routes.json   # 628-point OSRM route data
│   ├── routers/
│   │   ├── buses.py            # REST API endpoints
│   │   └── ws.py               # WebSocket endpoint
│   └── services/
│       ├── bus_service.py      # Background loop + WS broadcast
│       ├── demo_generator.py   # Simulated bus movement + stop detection
│       └── gtfs_fetcher.py     # GTFS-RT parser (for live API integration)
│
└── frontend/
    └── lib/
        ├── main.dart               # App entry point
        ├── models/
        │   └── bus_position.dart    # Bus data model
        ├── screens/
        │   └── map_screen.dart      # Main map with bus marker
        ├── services/
        │   └── websocket_service.dart  # WS + HTTP polling
        └── widgets/
            ├── bus_detail_sheet.dart    # Bottom info panel
            ├── connection_indicator.dart # LIVE/SYNC badge
            └── stop_notification.dart   # Stop arrival flash
```

## Prerequisites

- **Flutter SDK** (3.27+)
- **Python** (3.12+)
- **Redis** server running on localhost:6379
- **Android Studio** with emulator or physical device

## How to Run

### 1. Start Redis

```bash
sudo service redis-server start
redis-cli ping  # Should return PONG
```

### 2. Start Backend

```bash
cd backend
python -m venv venv
.\venv\Scripts\Activate       # Windows
# source venv/bin/activate    # Linux/Mac
pip install -r requirements.txt
python main.py
```

### 3. Run Flutter App

```bash
cd frontend
flutter pub get
flutter run
```

## API Endpoints

| Endpoint | Method | Description |
|---|---|---|
| `/api/buses` | GET | Current bus position |
| `/api/stops` | GET | All 15 bus stops |
| `/ws/buses` | WebSocket | Real-time position stream |
