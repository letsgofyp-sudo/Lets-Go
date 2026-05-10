from __future__ import annotations

from typing import Optional

from .helpers import normalize_text
from .state import ConversationState


def maybe_toggle_agentic(st: ConversationState, text: str) -> Optional[str]:
    t = normalize_text(text)
    _ = st
    if t in {
        'agentic on',
        'enable agentic',
        'enable agentic mode',
        'agentic mode on',
        'agentic off',
        'disable agentic',
        'disable agentic mode',
        'agentic mode off',
    }:
        return 'Agentic mode is not available.'
    return None


def agentic_required_reply(intent: str) -> str:
    _ = intent
    return "\n".join(
        [
            'This action is not available in support chat.',
            'Please use the app UI to continue.',
        ]
    )
