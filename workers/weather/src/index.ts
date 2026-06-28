export interface Env {
  WEATHER_CACHE: KVNamespace;
  QWEATHER_CREDENTIAL_ID?: string;
  QWEATHER_PROJECT_ID?: string;
  QWEATHER_PRIVATE_KEY?: string;
  QWEATHER_API_HOST?: string;
  CACHE_TTL_SECONDS?: string;
  STALE_TTL_SECONDS?: string;
}

type WeatherPayload = {
  cityName: string;
  condition: string;
  temperature: string;
  symbolName: string;
  reportTime: string;
  providerName: string;
  cached: boolean;
  stale: boolean;
};

type CachedWeather = {
  payload: Omit<WeatherPayload, "cached" | "stale">;
  expiresAt: number;
  staleUntil: number;
};

const DEFAULT_CACHE_TTL_SECONDS = 30 * 60;
const DEFAULT_STALE_TTL_SECONDS = 6 * 60 * 60;

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/health") {
      return json({ ok: true });
    }

    if (url.pathname !== "/weather") {
      return json({ error: "Not Found" }, 404);
    }

    if (request.method !== "GET") {
      return json({ error: "Method Not Allowed" }, 405);
    }

    return handleWeather(url, env, ctx);
  }
};

async function handleWeather(url: URL, env: Env, ctx: ExecutionContext): Promise<Response> {
  const query = parseWeatherQuery(url);

  if (!query) {
    return json({ error: "Missing location. Use ?location=101010100 or ?lat=39.9&lon=116.4" }, 400);
  }

  const now = Date.now();
  const cacheKey = `weather:${query.cacheKey}`;
  const cached = await readCache(env, cacheKey);

  if (cached && cached.expiresAt > now) {
    return weatherResponse({ ...cached.payload, cached: true, stale: false });
  }

  try {
    const fresh = await fetchFreshWeather(query, env);
    const ttl = seconds(env.CACHE_TTL_SECONDS, DEFAULT_CACHE_TTL_SECONDS);
    const staleTtl = seconds(env.STALE_TTL_SECONDS, DEFAULT_STALE_TTL_SECONDS);
    const nextCache: CachedWeather = {
      payload: fresh,
      expiresAt: now + ttl * 1000,
      staleUntil: now + (ttl + staleTtl) * 1000
    };

    ctx.waitUntil(writeCache(env, cacheKey, nextCache, ttl + staleTtl));

    return weatherResponse({ ...fresh, cached: false, stale: false });
  } catch (error) {
    if (cached && cached.staleUntil > now) {
      return weatherResponse({ ...cached.payload, cached: true, stale: true });
    }

    return json({
      error: "Weather unavailable",
      reason: error instanceof Error ? error.message : "Unknown error"
    }, 502);
  }
}

function parseWeatherQuery(url: URL): WeatherQuery | null {
  const location = url.searchParams.get("location")?.trim();
  const cityName = url.searchParams.get("cityName")?.trim();
  const lat = url.searchParams.get("lat")?.trim();
  const lon = url.searchParams.get("lon")?.trim();

  if (location) {
    return {
      kind: "location",
      location,
      cityName: cityName || location,
      cacheKey: `location:${location}`
    };
  }

  if (lat && lon && isFinite(Number(lat)) && isFinite(Number(lon))) {
    const normalizedLat = Number(lat).toFixed(4);
    const normalizedLon = Number(lon).toFixed(4);

    return {
      kind: "coordinates",
      lat: normalizedLat,
      lon: normalizedLon,
      cityName: cityName || `${normalizedLat},${normalizedLon}`,
      cacheKey: `coordinates:${normalizedLat},${normalizedLon}`
    };
  }

  return null;
}

async function fetchFreshWeather(query: WeatherQuery, env: Env): Promise<Omit<WeatherPayload, "cached" | "stale">> {
  if (env.QWEATHER_CREDENTIAL_ID && env.QWEATHER_PROJECT_ID && env.QWEATHER_PRIVATE_KEY) {
    try {
      return await fetchQWeather(query, env);
  } catch (error) {
      if (query.kind === "location") {
        throw error;
      }
    }
  }

  if (query.kind === "coordinates") {
    return fetchOpenMeteo(query);
  }

  throw new Error("No available weather provider");
}

async function fetchQWeather(query: WeatherQuery, env: Env): Promise<Omit<WeatherPayload, "cached" | "stale">> {
  const location = query.kind === "location" ? query.location : `${query.lon},${query.lat}`;
  const jwt = await createQWeatherJWT(env);
  const apiHost = env.QWEATHER_API_HOST || "https://devapi.qweather.com";
  const url = new URL("/v7/weather/now", apiHost);
  url.searchParams.set("location", location);
  url.searchParams.set("lang", "zh");

  const response = await fetch(url, {
    headers: {
      Authorization: `Bearer ${jwt}`
    }
  });

  if (!response.ok) {
    throw new Error(`QWeather HTTP ${response.status}`);
  }

  const data = await response.json<QWeatherNowResponse>();

  if (data.code !== "200" || !data.now) {
    throw new Error(`QWeather code ${data.code}`);
  }

  return {
    cityName: query.cityName,
    condition: data.now.text,
    temperature: data.now.temp,
    symbolName: symbolNameForCondition(data.now.text),
    reportTime: data.updateTime || data.now.obsTime,
    providerName: "QWeather"
  };
}

async function fetchOpenMeteo(query: CoordinatesWeatherQuery): Promise<Omit<WeatherPayload, "cached" | "stale">> {
  const url = new URL("https://api.open-meteo.com/v1/forecast");
  url.searchParams.set("latitude", query.lat);
  url.searchParams.set("longitude", query.lon);
  url.searchParams.set("current", "temperature_2m,weather_code");
  url.searchParams.set("timezone", "auto");

  const response = await fetch(url);

  if (!response.ok) {
    throw new Error(`Open-Meteo HTTP ${response.status}`);
  }

  const data = await response.json<OpenMeteoResponse>();
  const weatherCode = data.current?.weather_code ?? 0;
  const condition = openMeteoCondition(weatherCode);

  return {
    cityName: query.cityName,
    condition,
    temperature: String(Math.round(data.current?.temperature_2m ?? 0)),
    symbolName: symbolNameForCondition(condition),
    reportTime: data.current?.time ?? new Date().toISOString(),
    providerName: "Open-Meteo"
  };
}

async function createQWeatherJWT(env: Env): Promise<string> {
  const credentialId = env.QWEATHER_CREDENTIAL_ID;
  const projectId = env.QWEATHER_PROJECT_ID;
  const privateKey = env.QWEATHER_PRIVATE_KEY;

  if (!credentialId || !projectId || !privateKey) {
    throw new Error("Missing QWeather credentials");
  }

  const encoder = new TextEncoder();
  const now = Math.floor(Date.now() / 1000);
  const header = base64URL(JSON.stringify({ alg: "EdDSA", kid: credentialId }));
  const payload = base64URL(JSON.stringify({
    sub: projectId,
    iat: now - 30,
    exp: now + 900
  }));
  const signingInput = `${header}.${payload}`;
  const key = await importEd25519PrivateKey(privateKey);
  const signature = await crypto.subtle.sign("Ed25519", key, encoder.encode(signingInput));

  return `${signingInput}.${base64URL(signature)}`;
}

async function importEd25519PrivateKey(pem: string): Promise<CryptoKey> {
  const der = pemToArrayBuffer(pem);
  return crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "Ed25519" },
    false,
    ["sign"]
  );
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s/g, "");
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);

  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }

  return bytes.buffer;
}

function base64URL(value: string | ArrayBuffer): string {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : new Uint8Array(value);
  let binary = "";

  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }

  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

async function readCache(env: Env, key: string): Promise<CachedWeather | null> {
  const value = await env.WEATHER_CACHE.get(key, "json");
  return value as CachedWeather | null;
}

async function writeCache(env: Env, key: string, value: CachedWeather, expirationTtl: number): Promise<void> {
  await env.WEATHER_CACHE.put(key, JSON.stringify(value), { expirationTtl });
}

function seconds(value: string | undefined, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function weatherResponse(payload: WeatherPayload): Response {
  return json(payload, 200, {
    "Cache-Control": payload.stale ? "public, max-age=60" : "public, max-age=300"
  });
}

function json(payload: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Access-Control-Allow-Origin": "*",
      ...headers
    }
  });
}

function symbolNameForCondition(condition: string): string {
  if (condition.includes("雷")) return "cloud.bolt.rain.fill";
  if (condition.includes("雨")) return "cloud.rain.fill";
  if (condition.includes("雪")) return "snowflake";
  if (condition.includes("雾") || condition.includes("霾")) return "cloud.fog.fill";
  if (condition.includes("阴")) return "smoke.fill";
  if (condition.includes("云")) return "cloud.sun.fill";
  return "sun.max.fill";
}

function openMeteoCondition(code: number): string {
  if ([0, 1].includes(code)) return "晴";
  if ([2, 3].includes(code)) return "多云";
  if ([45, 48].includes(code)) return "雾";
  if ([51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82].includes(code)) return "雨";
  if ([71, 73, 75, 77, 85, 86].includes(code)) return "雪";
  if ([95, 96, 99].includes(code)) return "雷阵雨";
  return "多云";
}

type WeatherQuery = LocationWeatherQuery | CoordinatesWeatherQuery;

type LocationWeatherQuery = {
  kind: "location";
  location: string;
  cityName: string;
  cacheKey: string;
};

type CoordinatesWeatherQuery = {
  kind: "coordinates";
  lat: string;
  lon: string;
  cityName: string;
  cacheKey: string;
};

type QWeatherNowResponse = {
  code: string;
  updateTime?: string;
  now?: {
    obsTime: string;
    temp: string;
    text: string;
  };
};

type OpenMeteoResponse = {
  current?: {
    time: string;
    temperature_2m: number;
    weather_code: number;
  };
};
