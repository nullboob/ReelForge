FORBIDDEN_OPEN = (
    "welcome back",
    "welcome to",
    "hey guys",
    "what's up",
    "whats up",
    "in this video",
    "today we",
    "let's talk about",
    "let us talk",
    "thanks for watching",
)


def is_forbidden_open(text: str) -> bool:
    spoken = text.strip().lower()
    if not spoken:
        return True
    return any(spoken.startswith(needle) for needle in FORBIDDEN_OPEN)
