import asyncio
import json
from config import Settings
from redis_client import RedisManager
from services.demo_generator import DemoGenerator
from services.gtfs_fetcher import GTFSFetcher


class BusService:
    def __init__(self, settings: Settings, redis: RedisManager):
        self.settings = settings
        self.redis = redis
        self.demo = DemoGenerator() if settings.use_demo_data else None
        self.gtfs = (
            GTFSFetcher(settings.gtfs_realtime_url, settings.gtfs_api_key)
            if not settings.use_demo_data
            else None
        )
        self.ws_clients: set = set()

    async def run_loop(self):
        while True:
            try:
                if self.settings.use_demo_data:
                    positions = self.demo.tick()
                else:
                    positions = await self.gtfs.fetch()

                for pos in positions:
                    await self.redis.write_bus(pos)

                payload = {
                    "buses": [p.model_dump() for p in positions],
                    "source": "demo" if self.settings.use_demo_data else "gtfs",
                }

                # Include stop event if bus just arrived at a stop
                if self.settings.use_demo_data and self.demo.last_stop_event:
                    stop = self.demo.last_stop_event
                    print(f"[STOP] >>> {stop['stop_name']} ({stop['stop_index']+1}/{stop['total_stops']}) <<<")
                    payload["stop_event"] = self.demo.last_stop_event

                payload_str = json.dumps(payload)

                dead = set()
                for ws in self.ws_clients:
                    try:
                        await ws.send_text(payload_str)
                        print(f"[WS] Sent to client OK | clients={len(self.ws_clients)} | svc_id={id(self)}")
                    except Exception as e:
                        print(f"[WS] Send FAILED: {e} — removing client")
                        dead.add(ws)
                if dead:
                    self.ws_clients -= dead
                if not self.ws_clients:
                    print(f"[WS] No clients connected")

            except Exception as e:
                print(f"[BusService] Error: {e}")

            await asyncio.sleep(self.settings.refresh_interval_seconds)
