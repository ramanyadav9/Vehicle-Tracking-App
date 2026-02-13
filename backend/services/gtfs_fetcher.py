import time
import aiohttp
from google.transit import gtfs_realtime_pb2
from models import BusPosition


class GTFSFetcher:
    def __init__(self, url: str, api_key: str = ""):
        self.url = url
        self.api_key = api_key

    async def fetch(self) -> list[BusPosition]:
        headers = {}
        if self.api_key:
            headers["api-key"] = self.api_key

        async with aiohttp.ClientSession() as session:
            async with session.get(self.url, headers=headers, timeout=aiohttp.ClientTimeout(total=10)) as resp:
                data = await resp.read()

        feed = gtfs_realtime_pb2.FeedMessage()
        feed.ParseFromString(data)

        positions = []
        for entity in feed.entity:
            if entity.HasField("vehicle"):
                v = entity.vehicle
                positions.append(BusPosition(
                    bus_id=v.vehicle.id or entity.id,
                    route_name=v.trip.route_id or "Unknown",
                    latitude=v.position.latitude,
                    longitude=v.position.longitude,
                    heading=v.position.bearing if v.position.bearing else 0.0,
                    speed_kmh=(v.position.speed or 0) * 3.6,
                    timestamp=v.timestamp or time.time(),
                    status="running",
                ))
        return positions
