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
