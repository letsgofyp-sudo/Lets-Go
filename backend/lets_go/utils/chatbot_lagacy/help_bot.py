import logging
from typing import Optional

from .helpers import capabilities_text, help_text, normalize_text, smalltalk_reply
from .state import ConversationState, reset_flow


logger = logging.getLogger(__name__)


def _fallback_faq_questions() -> list[str]:
    return [
        'How do I book a ride?',
        'How do I create a ride?',
        'How does fare calculation work?',
        'How do payments work?',
        'How do notifications work?',
        'What is the pickup code?',
        'Why can\'t I book a ride?',
        'Why can\'t I create a ride?',
        'How does fare negotiation work?',
        'How do I cancel a booking?',
        'How do I cancel a trip?',
        'How do I delete a trip?',
    ]


def _fallback_manual_headings() -> list[str]:
    return [
        'Booking a ride',
        'Creating a ride',
        'Selecting a route and stops',
        'Fare calculation and breakdown',
        'Payments and payment confirmation',
        'Messaging and chat',
        'Fare negotiation',
        'Cancel booking / cancel trip',
        'Deleting a trip',
        'Guest mode limitations',
        'Profile and verification requests',
        'SOS and safety',
    ]


HELP_INTENTS = {
    'help',
    'capabilities',
    'greet',
    'faq',
    'manual',
}


def maybe_handle_help(st: ConversationState, text: str, *, intent: str) -> Optional[str]:
    """Read-only help/FAQ handler.

    This module must not perform any mutating API calls (POST/PUT/PATCH/DELETE).
    """

    intent = (intent or '').strip()
    if intent not in HELP_INTENTS:
        return None

    low = normalize_text(text)

    if intent == 'help':
        reset_flow(st)
        return help_text()

    if intent == 'capabilities':
        reset_flow(st)
        return capabilities_text()

    if intent == 'greet':
        reset_flow(st)
        name = st.user_name or 'there'
        return f"Hi {name}. What would you like to do today—book a ride or create a ride?"

    if intent in {'faq', 'manual'}:
        reset_flow(st)
        try:
            if intent == 'faq':
                try:
                    from administration.models import SupportFAQ

                    qs = list(
                        SupportFAQ.objects.filter(is_active=True)
                        .order_by('priority', 'id')
                        .values_list('question', flat=True)
                    )
                except Exception:
                    qs = _fallback_faq_questions()
                if qs:
                    lines = ['Here are some FAQs you can ask about:']
                    for q in qs[:12]:
                        lines.append(f"- {q}")
                    return "\n".join(lines)
                return 'No FAQs available right now.'

            heads = _fallback_manual_headings()
            if heads:
                lines = ['User manual topics:']
                for h in heads[:16]:
                    lines.append(f"- {h}")
                lines.append("\nAsk a question like: 'How do I book a ride?'")
                return "\n".join(lines)
            return 'User manual is not available right now.'
        except Exception:
            logger.exception("Failed to render FAQ/manual headings")
            return "You can ask about user manual topics or FAQs. Try: 'show faqs' or 'user manual topics'."

    _ = low
    return None


def maybe_handle_smalltalk(st: ConversationState, text: str) -> Optional[str]:
    """Smalltalk responses that are safe/read-only."""

    _ = st
    return smalltalk_reply(text)
