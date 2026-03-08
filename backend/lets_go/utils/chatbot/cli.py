import os
import logging


def _load_env_file() -> None:
    backend_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
    env_path = os.path.join(backend_root, '.env')
    try:
        with open(env_path, 'r', encoding='utf-8') as f:
            lines = f.read().splitlines()
    except Exception:
        return
    for raw in lines:
        line = (raw or '').strip()
        if not line or line.startswith('#'):
            continue
        if line.lower().startswith('export '):
            line = line[7:].strip()
        if '=' not in line:
            continue
        k, v = line.split('=', 1)
        k = (k or '').strip()
        v = (v or '').strip()
        if not k:
            continue
        if (v.startswith('"') and v.endswith('"')) or (v.startswith("'") and v.endswith("'")):
            v = v[1:-1]
        if k not in os.environ:
            os.environ[k] = v


_load_env_file()


logger = logging.getLogger(__name__)


try:
    from .api import api_login
    from .config import BOT_EMAIL, BOT_PASSWORD
    from .engine import ask_bot
    from .llm import cloud_model, llm_base_url, llm_brain_mode, llm_debug_enabled, llm_provider
    from .state import set_current_user
except ImportError:  # pragma: no cover
    import sys

    _BACKEND_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
    if _BACKEND_ROOT not in sys.path:
        sys.path.insert(0, _BACKEND_ROOT)

    from lets_go.utils.chatbot.api import api_login
    from lets_go.utils.chatbot.config import BOT_EMAIL, BOT_PASSWORD
    from lets_go.utils.chatbot.engine import ask_bot
    from lets_go.utils.chatbot.llm import cloud_model, llm_base_url, llm_brain_mode, llm_debug_enabled, llm_provider
    from lets_go.utils.chatbot.state import set_current_user


def main() -> None:
    user, err = api_login(BOT_EMAIL, BOT_PASSWORD)
    if err:
        raise SystemExit(f'Login failed: {err}')
    set_current_user(user)
    user_id = int(user.get('id'))
    logger.debug("Logged in as user_id=%s (%s)", user_id, user.get('name', ''))

    prov = llm_provider()
    brain = llm_brain_mode()
    base = llm_base_url()
    model = cloud_model()
    debug = llm_debug_enabled()
    logger.debug("LLM: provider=%s brain_mode=%s debug=%s", prov, 'ON' if brain else 'OFF', 'ON' if debug else 'OFF')
    if prov == 'openai_compat':
        logger.debug("LLM: base_url=%s model=%s", base or '(missing)', model)

    while True:
        q = input('You: ').strip()
        if not q:
            continue
        if q.lower() in {'exit', 'quit'}:
            break
        ask_bot(user_id, q)


if __name__ == '__main__':
    main()
