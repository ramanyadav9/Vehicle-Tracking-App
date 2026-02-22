import json
from fastapi import APIRouter, WebSocket, WebSocketDisconnect

router = APIRouter()


@router.websocket("/ws/buses")
async def bus_websocket(websocket: WebSocket):
    bus_service = websocket.app.state.bus_service

    await websocket.accept()
    bus_service.ws_clients.add(websocket)
    print(f"[WS] Client connected. Total: {len(bus_service.ws_clients)} | svc_id={id(bus_service)}")

    # Send current data immediately on connect
    try:
        buses = await bus_service.redis.get_all_buses()
        if buses:
            await websocket.send_text(json.dumps({
                "buses": buses,
                "source": "demo" if bus_service.settings.use_demo_data else "gtfs",
            }))
    except Exception as e:
        print(f"[WS] Error sending initial data: {e}")

    try:
        while True:
            data = await websocket.receive_text()
            if data == "ping":
                await websocket.send_text("pong")
    except WebSocketDisconnect:
        bus_service.ws_clients.discard(websocket)
        print(f"[WS] Client disconnected. Total: {len(bus_service.ws_clients)}")
    except Exception as e:
        print(f"[WS] Client error: {e}")
        bus_service.ws_clients.discard(websocket)
