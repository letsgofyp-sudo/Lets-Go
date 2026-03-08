import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import logging
import os

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Load environment variables (optional for security)
SENDER_EMAIL = (os.getenv("SENDER_EMAIL") or '').strip()
SENDER_PASSWORD = (os.getenv("SENDER_PASSWORD") or '').strip()
SMTP_SERVER = (os.getenv("SMTP_SERVER") or 'smtp.gmail.com').strip()
SMTP_PORT = int(os.getenv("SMTP_PORT", 587))

APP_NAME = os.getenv("APP_NAME", "LETS GO")
OTP_EXPIRY_MINUTES = int(os.getenv("OTP_EXPIRY_MINUTES", 5))


def send_email_message(subject: str, body: str, recipients: list[str]) -> bool:
    recipients = [r for r in recipients if isinstance(r, str) and r.strip()]
    if not recipients:
        return False
    if not SENDER_EMAIL or not SENDER_PASSWORD:
        logger.error("Email credentials missing (SENDER_EMAIL/SENDER_PASSWORD)")
        return False

    message = MIMEMultipart()
    message["From"] = SENDER_EMAIL 
    message["To"] = ",".join(recipients)
    message["Subject"] = subject
    message.attach(MIMEText(body, "plain"))

    try:
        with smtplib.SMTP(SMTP_SERVER, SMTP_PORT) as server:
            server.starttls()
            server.login(SENDER_EMAIL, SENDER_PASSWORD)
            server.send_message(message)
        return True
    except Exception as e:
        logger.error(f"Failed to send email. Error: {e}")
        return False


def send_email_otp(recipient_email: str, otp_code: str) -> bool:
    """
    Sends a One-Time Password (OTP) to the specified email address.

    Args:
        recipient_email (str): The recipient's email address.
        otp_code (str): The OTP code to send.

    Returns:
        bool: True if the email was sent successfully, False otherwise.
    """

    subject = f"{APP_NAME} Verification Code"
    body = (
        f"Hello,\n\n"
        f"Your {APP_NAME} verification code is:\n\n"
        f"{otp_code}\n\n"
        f"This code will expire in {OTP_EXPIRY_MINUTES} minutes.\n\n"
        f"If you did not request this code, you can ignore this message. "
        f"For your security, do not share this code with anyone.\n\n"
        f"Regards,\n"
        f"{APP_NAME} Team"
    )

    ok = send_email_message(subject, body, [recipient_email])
    if ok:
        logger.info(f"OTP email sent successfully to {recipient_email}")
    return ok

def send_email_otp_for_reset(recipient_email: str, otp_code: str) -> bool:
    """
    Sends a password reset OTP to the specified email address.
    """
    subject = f"{APP_NAME} Password Reset Code"
    body = (
        f"Hello,\n\n"
        f"We received a request to reset your {APP_NAME} account password.\n\n"
        f"Your password reset code is:\n\n"
        f"{otp_code}\n\n"
        f"This code will expire in {OTP_EXPIRY_MINUTES} minutes.\n\n"
        f"If you did not request a password reset, please ignore this message. "
        f"For your security, do not share this code with anyone.\n\n"
        f"Regards,\n"
        f"{APP_NAME} Team"
    )

    ok = send_email_message(subject, body, [recipient_email])
    if ok:
        logger.info(f"Reset password OTP email sent to {recipient_email}")
    return ok


def send_incident_email(recipients: list[str], subject: str, body: str) -> bool:
    return send_email_message(subject, body, recipients)
