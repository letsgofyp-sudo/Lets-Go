from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from typing import Any, Optional


_CURRENT_USER: dict[str, Any] = {}


def set_current_user(user: dict[str, Any]) -> None:
    _CURRENT_USER.clear()
    if isinstance(user, dict):
        _CURRENT_USER.update(user)


def current_user_name() -> str:
    return str(_CURRENT_USER.get('name') or '').strip()


@dataclass
class BotContext:
    user_id: int


@dataclass
class BookingDraft:
    passenger_id: Optional[int] = None
    from_stop_raw: Optional[str] = None
    to_stop_raw: Optional[str] = None
    trip_date: Optional[date] = None
    departure_time: Optional[str] = None
    number_of_seats: Optional[int] = None
    proposed_fare: Optional[int] = None
    selected_trip_id: Optional[str] = None
    selected_from_stop_order: Optional[int] = None
    selected_to_stop_order: Optional[int] = None
    selected_from_stop_name: Optional[str] = None
    selected_to_stop_name: Optional[str] = None
    selected_base_fare: Optional[int] = None
    selected_trip_date: Optional[str] = None
    selected_departure_time: Optional[str] = None
    selected_route_name: Optional[str] = None
    selected_driver_id: Optional[int] = None
    selected_driver_name: Optional[str] = None
    candidates: Optional[list[dict]] = None


@dataclass
class CreateRideDraft:
    route_id: Optional[str] = None
    route_name: Optional[str] = None
    route_candidates: Optional[list[dict]] = None
    vehicle_candidates: Optional[list[dict]] = None
    vehicle_id: Optional[int] = None
    trip_date: Optional[date] = None
    departure_time: Optional[str] = None
    total_seats: Optional[int] = None
    custom_price: Optional[int] = None
    estimated_price_per_seat: Optional[int] = None
    gender_preference: Optional[str] = None
    notes: Optional[str] = None
    is_negotiable: Optional[bool] = None


@dataclass
class MessageDraft:
    trip_id: Optional[str] = None
    recipient_id: Optional[int] = None
    sender_role: Optional[str] = None
    message_text: Optional[str] = None


@dataclass
class NegotiateDraft:
    trip_id: Optional[str] = None
    booking_id: Optional[int] = None
    action: Optional[str] = None
    counter_fare: Optional[int] = None
    note: Optional[str] = None


@dataclass
class CancelBookingDraft:
    booking_id: Optional[int] = None
    reason: Optional[str] = None


@dataclass
class ProfileDraft:
    name: Optional[str] = None
    address: Optional[str] = None
    gender: Optional[str] = None
    bankname: Optional[str] = None
    accountno: Optional[str] = None
    iban: Optional[str] = None


@dataclass
class PaymentDraft:
    booking_id: Optional[int] = None
    role: Optional[str] = None
    payment_method: Optional[str] = None
    driver_rating: Optional[float] = None
    driver_feedback: Optional[str] = None
    passenger_rating: Optional[float] = None
    passenger_feedback: Optional[str] = None


@dataclass
class ConversationState:
    ctx: BotContext
    user_name: str = ''
    last_trip_id: Optional[str] = None
    last_booking_id: Optional[int] = None
    last_listed_trip_ids: Optional[list[str]] = None
    active_flow: Optional[str] = None
    awaiting_field: Optional[str] = None
    booking: BookingDraft = None
    create_ride: CreateRideDraft = None
    message: MessageDraft = None
    negotiate: NegotiateDraft = None
    cancel_booking: CancelBookingDraft = None
    profile: ProfileDraft = None
    payment: PaymentDraft = None
    pending_action: Optional[dict] = None
    history: list[dict] = None
    llm_last_text: Optional[str] = None
    llm_last_extract: Optional[dict] = None
    agent_last_plan: Optional[dict] = None
    agent_last_tools: Optional[list[dict]] = None

    def __post_init__(self):
        if self.booking is None:
            self.booking = BookingDraft(passenger_id=int(self.ctx.user_id))
        if self.create_ride is None:
            self.create_ride = CreateRideDraft()
        if self.message is None:
            self.message = MessageDraft()
        if self.negotiate is None:
            self.negotiate = NegotiateDraft()
        if self.cancel_booking is None:
            self.cancel_booking = CancelBookingDraft()
        if self.profile is None:
            self.profile = ProfileDraft()
        if self.payment is None:
            self.payment = PaymentDraft()
        if self.history is None:
            self.history = []
        if self.llm_last_extract is None:
            self.llm_last_extract = {}
        if self.agent_last_tools is None:
            self.agent_last_tools = []

        if self.last_listed_trip_ids is None:
            self.last_listed_trip_ids = []


_SESSIONS: dict[int, ConversationState] = {}


def get_state(user_id: int) -> ConversationState:
    st = _SESSIONS.get(int(user_id))
    if st is not None:
        return st
    ctx = BotContext(user_id=int(user_id))
    st = ConversationState(ctx=ctx)
    st.user_name = current_user_name()
    _SESSIONS[int(user_id)] = st
    return st


def reset_flow(st: ConversationState) -> None:
    st.active_flow = None
    st.awaiting_field = None
    st.pending_action = None
    st.booking = BookingDraft(passenger_id=int(st.ctx.user_id))
    st.create_ride = CreateRideDraft()
    st.message = MessageDraft()
    st.negotiate = NegotiateDraft()
    st.cancel_booking = CancelBookingDraft()
    st.profile = ProfileDraft()
    st.payment = PaymentDraft()
