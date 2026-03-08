import os


email_password = (os.getenv('SENDER_PASSWORD') or '').strip()
email = (os.getenv('SENDER_EMAIL') or '').strip()
BASE_URL = (os.getenv("TEXTBEE_BASE_URL") or '').strip()
API_KEY = (os.getenv("TEXTBEE_API_KEY") or '').strip()
DEVICE_ID = (os.getenv("TEXTBEE_DEVICE_ID") or '').strip()
