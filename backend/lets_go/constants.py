import os

url = (os.getenv('LETS_GO_API_BASE_URL') or os.getenv('LETS_GO_BASE_URL') or 'http://localhost:8000').strip()
SUPABASE_EDGE_API_KEY = (os.getenv('SUPABASE_EDGE_API_KEY') or '').strip()
orsApiKey = (os.getenv('LETS_GO_ORS_API_KEY') or os.getenv('ORS_API_KEY') or '').strip()