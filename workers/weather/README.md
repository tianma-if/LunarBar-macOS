# LunarBar Weather Worker

Cloudflare Worker backend for LunarBar weather data.

## Endpoints

```text
GET /health
GET /weather?location=101010100&cityName=北京
GET /weather?lat=39.9042&lon=116.4074&cityName=北京
```

The Worker prefers QWeather when credentials are configured. Coordinate queries can fall back to Open-Meteo.

## Secrets

```bash
wrangler secret put QWEATHER_CREDENTIAL_ID
wrangler secret put QWEATHER_PROJECT_ID
wrangler secret put QWEATHER_PRIVATE_KEY
```

Do not commit QWeather private keys to GitHub.
