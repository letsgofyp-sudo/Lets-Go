import os


_HERE = os.path.dirname(__file__)


LETS_GO_API_BASE_URL = (os.getenv('LETS_GO_API_BASE_URL') or 'http://localhost:8000').strip()

# OpenRouteService (ORS) API key for geocoding/directions.
ORS_API_KEY = (os.getenv('LETS_GO_ORS_API_KEY') or os.getenv('ORS_API_KEY') or '').strip()

BOT_EMAIL = (os.getenv('LETS_GO_BOT_EMAIL') or '').strip()
BOT_PASSWORD = (os.getenv('LETS_GO_BOT_PASSWORD') or '').strip()

STOPS_GEO_JSON = os.path.join(_HERE, 'stops_geo.json')
