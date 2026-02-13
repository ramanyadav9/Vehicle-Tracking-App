import json
import redis.asyncio as aioredis
from config import Settings
from models import BusPosition


class RedisManager:
    def __init__(self, settings: Settings):
        self.redis = aioredis.from_url(settings.redis_url, decode_responses=True)
        self.ttl = settings.bus_ttl_seconds

    async def write_bus(self, bus: BusPosition):
        key = f"bus:{bus.bus_id}"
        data = bus.model_dump()
        data["timestamp"] = str(data["timestamp"])
        data["latitude"] = str(data["latitude"])
        data["longitude"] = str(data["longitude"])
        data["heading"] = str(data["heading"])
        data["speed_kmh"] = str(data["speed_kmh"])
        await self.redis.hset(key, mapping=data)
        await self.redis.expire(key, self.ttl)
        await self.redis.sadd("bus:active_ids", bus.bus_id)

    async def get_all_buses(self) -> list[dict]:
        ids = await self.redis.smembers("bus:active_ids")
        if not ids:
            return []
        pipe = self.redis.pipeline()
        for bid in ids:
            pipe.hgetall(f"bus:{bid}")
        results = await pipe.execute()
        buses = []
        for r in results:
            if r:
                r["latitude"] = float(r["latitude"])
                r["longitude"] = float(r["longitude"])
                r["heading"] = float(r["heading"])
                r["speed_kmh"] = float(r["speed_kmh"])
                r["timestamp"] = float(r["timestamp"])
                buses.append(r)
        return buses

    async def close(self):
        await self.redis.close()
