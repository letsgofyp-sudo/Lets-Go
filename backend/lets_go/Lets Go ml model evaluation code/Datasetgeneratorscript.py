import json
import random
from datetime import datetime, timedelta, timezone
import pandas as pd

random.seed(42)

CITIES = ["Lahore", "Karachi", "Islamabad"]
STOPS = [
    "Gulberg", "DHA", "Johar Town", "Model Town", "Wapda Town", "Bahria Town",
    "Saddar", "Clifton", "G-10", "F-11", "I-8", "Blue Area"
]
VEHICLES = [
    {"vehicle_company": "Honda", "vehicle_type": "Car", "vehicle_color": "White", "vehicle_seats": 4, "vehicle_fuel_type": "Petrol"},
    {"vehicle_company": "Toyota", "vehicle_type": "Car", "vehicle_color": "Black", "vehicle_seats": 4, "vehicle_fuel_type": "Petrol"},
    {"vehicle_company": "Suzuki", "vehicle_type": "Car", "vehicle_color": "Silver", "vehicle_seats": 4, "vehicle_fuel_type": "Petrol"},
    {"vehicle_company": "Yamaha", "vehicle_type": "Bike", "vehicle_color": "Red", "vehicle_seats": 2, "vehicle_fuel_type": "Petrol"},
]

def pick_route():
    a, b = random.sample(STOPS, 2)
    return a, b

def iso(dt):
    return dt.replace(microsecond=0).isoformat()

def make_history(user_id, now, n=10):
    # Create a biased history: repeat a few routes + vehicles
    fav_from, fav_to = pick_route()
    fav_vehicle = random.choice(VEHICLES)

    bookings = []
    for i in range(n):
        dt = now - timedelta(days=random.randint(1, 30), hours=random.randint(0, 23))
        if random.random() < 0.7:
            fr, to = fav_from, fav_to
            veh = fav_vehicle
        else:
            fr, to = pick_route()
            veh = random.choice(VEHICLES)

        bookings.append({
            "trip_id": f"H{user_id}_{i}",
            "from_stop_name": fr,
            "to_stop_name": to,
            "total_fare": random.randint(200, 800),
            "number_of_seats": random.choice([1, 1, 1, 2]),
            "finalized_at": iso(dt),
            **veh
        })
    return bookings, (fav_from, fav_to), fav_vehicle

def stop_breakdown_for(fr, to, price):
    # minimal breakdown with 1 segment (fine for your model)
    return [{"from_stop_name": fr, "to_stop_name": to, "price": int(price)}]


def _pick_gender_preference_for_user(user_gender: str | None, *, positive: bool) -> str:
    ug = (user_gender or "").strip().title()
    if ug not in ("Male", "Female"):
        ug = ""

    if positive:
        # Positive must be feasible to book for this user.
        # Prefer "Any" (most common in real data), otherwise allow same-gender only.
        if ug:
            return random.choices(["Any", ug], weights=[0.85, 0.15])[0]
        return "Any"

    # Negatives can be anything; include some restricted trips
    return random.choices(["Any", "Male", "Female"], weights=[0.80, 0.10, 0.10])[0]


def make_candidate(
    trip_id,
    now,
    fr,
    to,
    user_gender: str | None,
    good=False,
    fav_vehicle=None,
    fixed_is_negotiable: bool | None = None,
    positive: bool = False,
    same_route_negative: bool = False,
):
    dep = now + timedelta(hours=random.randint(1, 12))
    base_price = random.randint(250, 750)
    if good:
        driver_rating = round(random.uniform(4.2, 5.0), 1)
        price = base_price
        veh = fav_vehicle if fav_vehicle else random.choice(VEHICLES)
    else:
        driver_rating = round(random.uniform(2.5, 4.8), 1)
        price = base_price + random.randint(-200, 250)
        veh = random.choice(VEHICLES)

        if same_route_negative:
            penalty = random.choice(["rating", "late", "price"])
            if penalty == "rating":
                driver_rating = min(driver_rating, 4.0)
            elif penalty == "late":
                dep = now + timedelta(hours=random.randint(8, 18))
            else:
                price = price + random.randint(120, 260)

    gender_pref = _pick_gender_preference_for_user(user_gender, positive=positive)
    is_negotiable = fixed_is_negotiable if fixed_is_negotiable is not None else bool(random.getrandbits(1))
    cand = {
        "trip_id": trip_id,
        "origin": fr,
        "destination": to,
        "departure_time": iso(dep),
        "price_per_seat": max(100, int(price)),
        "available_seats": random.randint(1, 4),
        "gender_preference": gender_pref,
        "is_negotiable": is_negotiable,
        "driver_rating": float(driver_rating),
        "stop_breakdown": stop_breakdown_for(fr, to, max(100, int(price/3))),
        **veh
    }
    return cand

def generate_csv(
    out_path="rank_eval.csv",
    num_events=5000,
    candidates_per_event=50,
    history_len=15
):
    rows = []
    for e in range(num_events):
        event_id = f"E{e}"
        user_id = random.randint(1, 400)  # reuse users to create stronger preferences
        user_gender = random.choice(["Male", "Female"])
        passenger_rating = round(random.uniform(3.0, 5.0), 1)

        now = datetime.now(timezone.utc) - timedelta(days=random.randint(0, 60))
        history, (fav_from, fav_to), fav_vehicle = make_history(user_id, now, n=history_len)

        # Positive candidate should match favorite route+vehicle and be soon + good rating
        pos_trip_id = f"T_POS_{event_id}"
        # Prevent trivial rank failures:
        # - Positive must be feasible w.r.t. gender.
        # - Lock is_negotiable per-event so negatives cannot beat the positive purely via negotiable bonus.
        event_is_negotiable = bool(random.getrandbits(1))
        pos = make_candidate(
            pos_trip_id,
            now,
            fav_from,
            fav_to,
            user_gender=user_gender,
            good=True,
            fav_vehicle=fav_vehicle,
            fixed_is_negotiable=event_is_negotiable,
            positive=True,
        )

        candidates = [pos]
        # Negatives: mix of route mismatches, vehicle mismatches, time mismatch, etc.
        for i in range(candidates_per_event - 1):
            if random.random() < 0.3:
                fr, to = fav_from, fav_to  # same route but worse other attributes
                same_route_negative = True
            else:
                fr, to = pick_route()
                same_route_negative = False
            cand = make_candidate(
                f"T_NEG_{event_id}_{i}",
                now,
                fr,
                to,
                user_gender=user_gender,
                good=False,
                fav_vehicle=fav_vehicle,
                fixed_is_negotiable=event_is_negotiable,
                positive=False,
                same_route_negative=same_route_negative,
            )
            candidates.append(cand)

        # Write one row per candidate
        for c in candidates:
            label = 1 if c["trip_id"] == pos_trip_id else 0
            rows.append({
                "event_id": event_id,
                "user_id": user_id,
                "user_gender": user_gender,
                "passenger_rating": passenger_rating,
                "now_iso": iso(now),
                "history_bookings_json": json.dumps(history),
                "candidate_json": json.dumps(c),
                "label": label
            })

    df = pd.DataFrame(rows)
    df.to_csv(out_path, index=False)
    print("Saved:", out_path, "rows:", len(df), "events:", num_events)

if __name__ == "__main__":
    generate_csv(out_path="rank_eval.csv", num_events=5000, candidates_per_event=50, history_len=15)