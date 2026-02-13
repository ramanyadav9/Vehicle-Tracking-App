from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    redis_url: str = "redis://localhost:6379/0"
    bus_ttl_seconds: int = 30
    refresh_interval_seconds: float = 5.0
    use_demo_data: bool = True
    gtfs_realtime_url: str = ""
    gtfs_api_key: str = ""
    host: str = "0.0.0.0"
    port: int = 8000

    class Config:
        env_file = ".env"
