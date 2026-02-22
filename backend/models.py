from pydantic import BaseModel


class BusPosition(BaseModel):
    bus_id: str
    route_name: str
    latitude: float
    longitude: float
    heading: float
    speed_kmh: float
    timestamp: float
    status: str
    current_stop_idx: int = -1  # index of last visited stop (-1 = before first stop)
