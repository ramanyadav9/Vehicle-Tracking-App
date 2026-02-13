import asyncio
from contextlib import asynccontextmanager
from fastapi import FastAPI
from config import Settings
from redis_client import RedisManager
from services.bus_service import BusService
from routers.buses import create_bus_router
from routers.ws import router as ws_router

settings = Settings()
redis_manager = RedisManager(settings)
bus_service = BusService(settings, redis_manager)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Store bus_service on app state so ws.py can access the SAME instance
    app.state.bus_service = bus_service
    print(f"[BusTracker] bus_service id={id(bus_service)}")
    task = asyncio.create_task(bus_service.run_loop())
    print(f"[BusTracker] Backend started | Demo mode: {settings.use_demo_data}")
    print(f"[BusTracker] REST: http://localhost:{settings.port}/api/buses")
    print(f"[BusTracker] WebSocket: ws://localhost:{settings.port}/ws/buses")
    yield
    task.cancel()
    await redis_manager.close()


app = FastAPI(title="Bus Tracker API", lifespan=lifespan)
app.include_router(create_bus_router(redis_manager))
app.include_router(ws_router)


@app.get("/")
async def root():
    return {"status": "running", "service": "Bus Tracker API"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
