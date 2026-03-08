
![Lets Go Logo](assets/ride-sharing-logo-black-and-white.png)

# Lets Go — Ride Sharing + Live Tracking + SOS (Django + Flutter)

## Team
Update this section with your exact details.

- **Member 1**
  - **Name**: M. Fawad Saqlain
  - **Role no**: FA22-BSE-031
- **Member 2**
  - **Name**: Ali Raza
  - **Role NO**: FA22-BSE-116

---

## Project Overview
**Lets Go** is a ride-sharing application with:

- **Trip posting & booking**
- **In-ride live tracking** (driver & passenger)
- **Public live tracking share page** (web map)
- **SOS incident reporting + share page** (web)
- **Trip share deep link**:
  - Opens the Flutter app if installed
  - Otherwise redirects to an APK download link

The project contains:
- **Backend**: Django (API + public web share pages + admin portal)
- **Mobile App**: Flutter (Android)

---

## Live Links (Production / Vercel)
Base URL:
- **Backend Base**: `https://lets-go-bay.vercel.app`

Admin portals (confirm which one you use and keep only the correct one):
- **Django Admin (common)**: `https://lets-go-bay.vercel.app/admin/`
- **Custom Administration (if enabled)**: `https://lets-go-bay.vercel.app/administration/`

APK download:
- **APK Download**: [Download APK](assets/app-release.apk)

---

## Share Links Behavior (Expected)
### 1) Trip Share (opens app / else downloads APK)
- **Shared URL format**
  - `https://lets-go-bay.vercel.app/lets_go/trips/share-app/<token>/`
- **Behavior**
  - If app installed: opens Flutter app
  - If app not installed: redirects to APK download URL

### 2) Live Tracking Share (web page)
- **Shared URL format**
  - `https://lets-go-bay.vercel.app/lets_go/trips/share/<token>/`
- **Behavior**
  - Opens a public web page showing the map + live updates

### 3) SOS Share (web page)
- **Shared URL format**
  - `https://lets-go-bay.vercel.app/lets_go/incidents/sos/share/<token>/`
- **Behavior**
  - Opens SOS web page

---

## Core Modules
### Backend (Django)
- **Trip + Booking APIs**
- **Live location endpoints**
  - Driver app posts GPS updates
  - Public web page polls live endpoint to show movement
- **Trip share token minting**
  - Creates share tokens with expiry
- **Trip share public page**
  - Template: live map + route + tracking
- **SOS incident module**
  - Creates SOS record + share link
  - Notifies emergency contacts (email/SMS depending on configuration)

### Mobile App (Flutter)
- **Ride posting & browsing**
- **Ride booking**
- **Post-booking live tracking UI**
  - Driver + passenger screens
- **Background live tracking service**
  - Posts location updates while ride is active
- **Trip share**
  - Generates share URL from backend and shares via WhatsApp/SMS/etc
- **Deep linking**
  - Handles `/lets_go/trips/share-app/<token>/` and navigates to trip

---

## Repository Structure (Typical)
- `backend/`
  - Django project (API + templates + settings for Vercel)
- `lets_go/`
  - Flutter project (Android)

---

## Environment Variables (Backend)
Set these on Vercel (or `.env` locally):

- `SECRET_KEY` — Django secret key
- `DEBUG` — `0` or `1`
- `ALLOWED_HOSTS` — e.g. `lets-go-bay.vercel.app`
- `CSRF_TRUSTED_ORIGINS` — e.g. `https://lets-go-bay.vercel.app`
- `LETS_GO_APK_DOWNLOAD_URL` — the real APK link for fallback download
  - Example: `https://your-domain.com/downloads/lets-go.apk`

Email (if using Gmail SMTP):
- Configure SMTP + **App Password** (recommended) instead of normal password.

---

## Local Development (High Level)
### Backend
1. Create virtualenv
2. Install dependencies
3. Run migrations
4. Start server

### Flutter
1. `flutter pub get`
2. Run app on emulator/device

> Note: After changing Android intent-filters (deep links), you must **rebuild/reinstall** the APK.

---

## Minimal API Tests (cURL)
Mint a token that targets the app deep link:
```bash
curl -i -X POST "https://lets-go-bay.vercel.app/lets_go/trips/TRIP_ID_HERE/share/" \
  -H "Content-Type: application/json" \
  -d '{"role":"driver","target":"app"}'

# Open the returned share-app URL in a browser (should contain intent + fallback)
curl -i "https://lets-go-bay.vercel.app/lets_go/trips/share-app/TOKEN_HERE/"

# Open the web live tracking page
curl -i "https://lets-go-bay.vercel.app/lets_go/trips/share/TOKEN_HERE/"
```