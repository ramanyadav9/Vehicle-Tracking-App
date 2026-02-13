import json
import math
import time
from pathlib import Path
from models import BusPosition


# Real bus stops along ISBT Kashmere Gate → AIIMS route
BUS_STOPS = [
    {"name": "ISBT Kashmere Gate", "lat": 28.6674, "lng": 77.2274, "waypoint_idx": 0},
    {"name": "Pul Bangash", "lat": 28.6600, "lng": 77.2276, "waypoint_idx": 54},
    {"name": "Lahori Gate", "lat": 28.6503, "lng": 77.2301, "waypoint_idx": 123},
    {"name": "Delhi Main Station", "lat": 28.6473, "lng": 77.2251, "waypoint_idx": 150},
    {"name": "Ajmeri Gate", "lat": 28.6436, "lng": 77.2270, "waypoint_idx": 190},
    {"name": "New Delhi Station", "lat": 28.6426, "lng": 77.2273, "waypoint_idx": 199},
    {"name": "Barakhamba Road", "lat": 28.6326, "lng": 77.2210, "waypoint_idx": 250},
    {"name": "Connaught Place", "lat": 28.6315, "lng": 77.2195, "waypoint_idx": 263},
    {"name": "Janpath", "lat": 28.6260, "lng": 77.2236, "waypoint_idx": 350},
    {"name": "India Gate", "lat": 28.6152, "lng": 77.2335, "waypoint_idx": 400},
    {"name": "Lala Lajpat Rai Marg", "lat": 28.6057, "lng": 77.2307, "waypoint_idx": 450},
    {"name": "Jor Bagh", "lat": 28.5920, "lng": 77.2270, "waypoint_idx": 506},
    {"name": "Safdarjung Tomb", "lat": 28.5845, "lng": 77.2125, "waypoint_idx": 550},
    {"name": "Ring Road - AIIMS", "lat": 28.5700, "lng": 77.2080, "waypoint_idx": 583},
    {"name": "AIIMS Hospital", "lat": 28.5654, "lng": 77.2102, "waypoint_idx": 627},
]


class DemoGenerator:
    def __init__(self):
        data_path = Path(__file__).parent.parent / "data" / "delhi_routes.json"
        with open(data_path) as f:
            self.routes = json.load(f)

        route_name = "ISBT Kashmere Gate - AIIMS"
        waypoints = self.routes[route_name]

        self.bus_state = {
            "bus_id": "DL-01",
            "route_name": route_name,
            "waypoints": waypoints,
            "index": 0,
            "progress": 0.0,
            "finished": False,
        }

        # Build set of waypoint indices that are near stops (for detection)
        self.stop_indices = {}
        for stop in BUS_STOPS:
            self.stop_indices[stop["waypoint_idx"]] = stop["name"]

        # Track which stops have been visited
        self.visited_stops = set()
        self.last_stop_event = None  # filled when bus reaches a new stop

    def tick(self) -> list[BusPosition]:
        state = self.bus_state
        wp = state["waypoints"]
        idx = state["index"]

        # Bus reached the end — restart from beginning
        if idx >= len(wp) - 1:
            state["index"] = 0
            state["finished"] = False
            self.visited_stops.clear()
            self.last_stop_event = None
            idx = 0

        next_idx = idx + 1

        lat = wp[idx][0]
        lng = wp[idx][1]

        dlat = wp[next_idx][0] - wp[idx][0]
        dlng = wp[next_idx][1] - wp[idx][1]
        heading = math.degrees(math.atan2(dlng, dlat)) % 360

        # Compute speed based on distance to next waypoint
        dist_m = math.sqrt(dlat**2 + dlng**2) * 111000
        speed = max(15.0, min(45.0, dist_m / 5.0 * 3.6))

        # Check if bus passes through any stop in the advancement range
        self.last_stop_event = None
        new_idx = min(idx + 6, len(wp) - 1)
        for check_idx in range(idx, new_idx + 1):
            if check_idx in self.stop_indices and check_idx not in self.visited_stops:
                stop_name = self.stop_indices[check_idx]
                self.visited_stops.add(check_idx)
                self.last_stop_event = {
                    "stop_name": stop_name,
                    "stop_lat": wp[check_idx][0],
                    "stop_lng": wp[check_idx][1],
                    "stop_index": list(self.stop_indices.keys()).index(check_idx),
                    "total_stops": len(BUS_STOPS),
                }
                break  # one stop event per tick

        # Advance by 6 waypoints per tick (~100m per 5s) for visible movement
        state["index"] = new_idx

        status = "at_stop" if self.last_stop_event else "running"

        return [BusPosition(
            bus_id=state["bus_id"],
            route_name=state["route_name"],
            latitude=round(lat, 6),
            longitude=round(lng, 6),
            heading=round(heading, 1),
            speed_kmh=round(speed, 1),
            timestamp=time.time(),
            status=status,
        )]
