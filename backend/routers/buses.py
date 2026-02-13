import json
from pathlib import Path
from fastapi import APIRouter
from services.demo_generator import BUS_STOPS

router = APIRouter(prefix="/api", tags=["buses"])


def create_bus_router(redis_manager):
    @router.get("/buses")
    async def get_all_buses():
        buses = await redis_manager.get_all_buses()
        return {"buses": buses, "count": len(buses)}

    @router.get("/stops")
    async def get_stops():
        """Return all bus stops for the route."""
        return {"stops": BUS_STOPS}

    return router
