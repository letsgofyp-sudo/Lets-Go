// supabase/functions/pre-ride-reminders/index.ts
import { serve } from "https://deno.land/std/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type TripRow = {
  id: number;
  trip_id: string;
  driver_id: number | string;
  trip_status: string;
  trip_date: string; // YYYY-MM-DD
  departure_time: string; // HH:MM:SS
  pre_ride_reminder_sent: boolean;
};

type BookingRow = {
  id: number;
  booking_id: string;
  trip_id: number; // FK to lets_go_trip.id
  passenger_id: number | string;
  booking_status: string;
  pre_ride_reminder_sent: boolean;
  from_stop_id: number | null;
};

type RouteStopRow = {
  id: number;
  estimated_time_from_start: number | null;
};

function toISODate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

// Treat trip_date + departure_time as Asia/Karachi local time (+05:00)
function parseLocalTripDateTime(tripDate: string, timeStr: string): Date {
  return new Date(`${tripDate}T${timeStr}+05:00`);
}

serve(async (_req) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  // Existing notification Edge Function + key
  // SUPABASE_FN_URL should point to send-ride-notification endpoint.
  const notifyFnUrl = Deno.env.get("_SUPABASE_FN_URL") ?? "";
  const notifyFnApiKey = Deno.env.get("_SUPABASE_FN_API_KEY") ?? "";

  if (!supabaseUrl || !serviceKey || !notifyFnUrl || !notifyFnApiKey) {
    console.error("Missing env vars", {
      hasSupabaseUrl: Boolean(supabaseUrl),
      hasServiceKey: Boolean(serviceKey),
      hasNotifyFnUrl: Boolean(notifyFnUrl),
      hasNotifyFnApiKey: Boolean(notifyFnApiKey),
    });
    return new Response("Config error", { status: 500 });
  }

  const supabase = createClient(supabaseUrl, serviceKey);

  const now = new Date();
  const windowMinutes = 5;
  const windowEnd = new Date(now.getTime() + windowMinutes * 60_000);

  // Limit to trips near today to avoid scanning the whole table
  const today = new Date();
  const yesterday = new Date(today);
  const tomorrow = new Date(today);
  yesterday.setDate(today.getDate() - 1);
  tomorrow.setDate(today.getDate() + 1);

  const yesterdayStr = toISODate(yesterday);
  const tomorrowStr = toISODate(tomorrow);

  async function callNotify(payload: Record<string, unknown>): Promise<boolean> {
    const resp = await fetch(notifyFnUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        // Match how your Django code calls the Edge Function
        apikey: notifyFnApiKey,
        Authorization: `Bearer ${notifyFnApiKey}`,
      },
      body: JSON.stringify(payload),
    });

    const txt = await resp.text();
    if (!resp.ok) {
      console.error("Notify fn failed:", {
        status: resp.status,
        body: txt.slice(0, 200),
        payload,
      });
      return false;
    }
    return true;
  }

  // Fetch eligible trips
  const { data: trips, error: tripsErr } = await supabase
    .from("lets_go_trip")
    .select(
      "id,trip_id,driver_id,trip_status,trip_date,departure_time,pre_ride_reminder_sent",
    )
    .eq("trip_status", "SCHEDULED")
    .eq("pre_ride_reminder_sent", false)
    .gte("trip_date", yesterdayStr)
    .lte("trip_date", tomorrowStr);

  if (tripsErr) {
    console.error("Trips query error:", tripsErr);
    return new Response("DB error (lets_go_trip)", { status: 500 });
  }

  if (!trips || trips.length === 0) {
    return new Response("No eligible trips", { status: 200 });
  }

  let driverSent = 0;
  let passengerSent = 0;

  // Cache stop ETA minutes
  const routeStopCache = new Map<number, number | null>();

  for (const t of trips as TripRow[]) {
    const tripDt = parseLocalTripDateTime(t.trip_date, t.departure_time);

    // Driver trigger: departure - 10 min
    const driverTriggerAt = new Date(tripDt.getTime() - 10 * 60_000);

    // DRIVER reminder (matches Django fire_pre_ride_reminder_notifications)
    if (driverTriggerAt <= now && now <= windowEnd) {
      const driverPayload = {
        user_id: String(t.driver_id),
        driver_id: String(t.driver_id),
        title: "Upcoming trip reminder",
        body:
          "Your LetsGo trip is starting in about 10 minutes. Please get ready to start the ride and make sure your location and internet are ON.",
        data: {
          type: "pre_ride_reminder_driver",
          trip_id: String(t.trip_id),
        },
      };

      const ok = await callNotify(driverPayload);
      if (ok) {
        const { error: updErr } = await supabase
          .from("lets_go_trip")
          .update({
            pre_ride_reminder_sent: true,
            updated_at: new Date().toISOString(),
          })
          .eq("id", t.id);

        if (updErr) {
          console.error("Failed updating trip pre_ride_reminder_sent:", {
            trip_id: t.trip_id,
            error: updErr,
          });
        } else {
          driverSent += 1;
        }
      }
    }

    // PASSENGER reminders (confirmed bookings on this trip)
    // Requires: lets_go_booking.pre_ride_reminder_sent boolean column
    const { data: bookings, error: bookingsErr } = await supabase
      .from("lets_go_booking")
      .select(
        "id,booking_id,trip_id,passenger_id,booking_status,pre_ride_reminder_sent,from_stop_id",
      )
      .eq("trip_id", t.id)
      .eq("booking_status", "CONFIRMED")
      .eq("pre_ride_reminder_sent", false);

    if (bookingsErr) {
      console.error("Bookings query error:", { trip_id: t.trip_id, error: bookingsErr });
      continue;
    }
    if (!bookings || bookings.length === 0) continue;

    for (const b of bookings as BookingRow[]) {
      // Passenger trigger: pickup_eta - 10 min if stop ETA exists, else fallback to driver trigger
      let passengerTriggerAt = driverTriggerAt;

      if (b.from_stop_id) {
        let estMinutes = routeStopCache.get(b.from_stop_id);

        if (estMinutes === undefined) {
          const { data: stop, error: stopErr } = await supabase
            .from("lets_go_routestop")
            .select("id,estimated_time_from_start")
            .eq("id", b.from_stop_id)
            .maybeSingle<RouteStopRow>();

          if (stopErr) {
            console.error("Route stop query error:", {
              from_stop_id: b.from_stop_id,
              error: stopErr,
            });
            estMinutes = null;
          } else {
            estMinutes = stop?.estimated_time_from_start ?? null;
          }

          routeStopCache.set(b.from_stop_id, estMinutes);
        }

        if (typeof estMinutes === "number") {
          const pickupEta = new Date(tripDt.getTime() + estMinutes * 60_000);
          passengerTriggerAt = new Date(pickupEta.getTime() - 10 * 60_000);
        }
      }

      if (passengerTriggerAt <= now && now <= windowEnd) {
        const passengerPayload = {
          user_id: String(b.passenger_id),
          driver_id: String(t.driver_id),
          title: "Pickup reminder",
          body:
            "Your LetsGo ride will pick you up in about 10 minutes near your selected pickup location. Please be ready outside and keep your location and internet ON.",
          data: {
            type: "pre_ride_reminder_passenger",
            trip_id: String(t.trip_id),
            booking_id: String(b.id), // matches Django: booking.id
          },
        };

        const ok = await callNotify(passengerPayload);
        if (ok) {
          const { error: updErr } = await supabase
            .from("lets_go_booking")
            .update({
              pre_ride_reminder_sent: true,
              updated_at: new Date().toISOString(),
            })
            .eq("id", b.id);

          if (updErr) {
            console.error("Failed updating booking pre_ride_reminder_sent:", {
              booking_id: b.booking_id,
              error: updErr,
            });
          } else {
            passengerSent += 1;
          }
        }
      }
    }
  }

  return new Response(
    `OK: driver_sent=${driverSent} passenger_sent=${passengerSent}`,
    { status: 200 },
  );
});