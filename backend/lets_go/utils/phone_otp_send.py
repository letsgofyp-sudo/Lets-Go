import requests
import os
import time
from requests.exceptions import HTTPError, Timeout
import logging

logger = logging.getLogger(__name__)

BASE_URL = (os.getenv("TEXTBEE_BASE_URL") or 'https://api.textbee.dev').strip()
API_KEY = (os.getenv("TEXTBEE_API_KEY") or '').strip()
DEVICE_ID = (os.getenv("TEXTBEE_DEVICE_ID") or '').strip()
# Endpoint path template

SEND_SMS_PATH = "/api/v1/gateway/devices/{device_id}/send-sms"


def _get_textbee_timeout_seconds() -> float:
    try:
        v = float(os.getenv('TEXTBEE_TIMEOUT_SECONDS', '8'))
        if v <= 0:
            return 8.0
        return v
    except Exception:
        return 8.0


def _get_textbee_retries() -> int:
    try:
        v = int(os.getenv('TEXTBEE_RETRIES', '0'))
        if v < 0:
            return 0
        return v
    except Exception:
        return 0


def send_sms_message(phone_number: str, message: str) -> bool:
    if not phone_number or not message:
        return False
    if not API_KEY or not DEVICE_ID:
        logger.error("SMS credentials missing (TEXTBEE_API_KEY/TEXTBEE_DEVICE_ID)")
        return False

    phone_number = str(phone_number).strip()
    if not phone_number.startswith("+"):
        phone_number = f"+{phone_number}"

    url = f"{BASE_URL}{SEND_SMS_PATH.format(device_id=DEVICE_ID)}"
    headers = {
        "x-api-key": API_KEY,
        "Content-Type": "application/json",
    }
    payload = {
        "recipients": [phone_number],
        "message": message,
    }

    timeout_seconds = _get_textbee_timeout_seconds()
    retries = _get_textbee_retries()
    attempts = max(1, 1 + retries)

    for attempt in range(attempts):
        try:
            resp = requests.post(url, json=payload, headers=headers, timeout=timeout_seconds)
            resp.raise_for_status()
            return True
        except Timeout as err:
            logger.error(f"Failed to send SMS: {err}")
            if attempt < attempts - 1:
                time.sleep(0.25)
                continue
            return False
        except HTTPError as err:
            logger.error(f"Failed to send SMS: {err}")
            return False
        except Exception as err:
            logger.error(f"An unexpected error occurred while sending SMS: {err}")
            return False

def send_phone_otp(phone_number:str, otp_code: str) -> bool:
    """
    Send a single SMS via TextBee.
    :param phone_number: E.164 format, e.g. "+923316963802"
    :param otp_code:      The OTP code to send, e.g. "3453"
    :returns: True on HTTP 2xx, False on failure.
    """
    app_name = os.getenv("APP_NAME", "LETS GO")
    expiry_minutes = int(os.getenv("OTP_EXPIRY_MINUTES", 5))
    msg = (
        f"{app_name}: Your verification code is {otp_code}. "
        f"Expires in {expiry_minutes} min. Do not share this code."
    )
    return send_sms_message(phone_number, msg)
    

def send_phone_otp_for_reset(phone_number: str, otp_code: str) -> bool:
    """
    Sends a password reset OTP via SMS using TextBee.
    """
    app_name = os.getenv("APP_NAME", "LETS GO")
    expiry_minutes = int(os.getenv("OTP_EXPIRY_MINUTES", 5))
    msg = (
        f"{app_name}: Your password reset code is {otp_code}. "
        f"Expires in {expiry_minutes} min. If you didn't request this, ignore."
    )
    return send_sms_message(phone_number, msg)


def send_incident_sms(phone_number: str, message: str) -> bool:
    return send_sms_message(phone_number, message)
