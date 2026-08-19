from __future__ import annotations

import re
from typing import Any

from reelforge.hooks import is_forbidden_open

POINT_BANKS = {
    "viral": [
        "{s} costs less energy than the version you keep postponing",
        "tiny consistency beats a heroic session you skip",
        "your brain trusts a ritual it can finish before breakfast",
        "the compounding starts on day three, not day thirty",
        "you actually recover, which is the hidden advantage",
    ],
    "facts": [
        "most people overestimate intensity and underestimate frequency",
        "daylight plus movement changes attention more than another playlist",
        "a short outdoor loop is easier to repeat than a commute to a building",
        "low-friction habits survive busy weeks",
        "the body keeps score of what you repeat, not what you plan",
    ],
    "product": [
        "the first screen shows the outcome, not the settings",
        "setup takes a minute so you can judge it on real work",
        "the boring parts are automated so you stay on the decision",
        "it stays out of the way once it is configured",
        "export is one click, because the last mile is the product",
    ],
    "tutorial": [
        "write the outcome in one sentence so the rest has a target",
        "gather only the footage or notes you will actually use",
        "cut anything that does not move the story forward",
        "add captions and a bed only after the spine is right",
        "export, watch once on mute, then once with sound",
    ],
    "news": [
        "Here is what changed: {s}",
        "Why it matters is the second-order effect, not the headline",
        "Watch the next move, not the noise around it",
    ],
    "travel": [
        "arrive before the postcard hour and let the streets wake up",
        "trade one landmark for a long walk with no route",
        "eat where the lunch line is local, not photographed",
        "leave room for the wrong turn — that is usually the frame",
    ],
    "listicle": [
        "the cheap version you can start tonight",
        "the mistake that looks productive",
        "the test that tells you if it is working by Friday",
        "the tool you can ignore until month two",
        "the habit that survives travel and bad sleep",
        "the one thing to cut so the rest fits",
    ],
    "explainer": [
        "start with the outcome, not the jargon",
        "the mechanism is simpler than the think-pieces",
        "here is the tradeoff people skip",
        "use this check before you spend a weekend on it",
        "if it still fails, the input was wrong, not you",
    ],
    "podcast": [
        "the guest said the quiet part without dressing it up",
        "the example is more useful than the theory",
        "this is the line you can steal for your own week",
    ],
}


def write(topic: str, preset_id: str, duration_sec: int = 30, source: str = "template") -> dict[str, Any]:
    clean = collapse_whitespace(topic)
    counted = extract_count(clean, 12 if duration_sec >= 180 else 6)
    subject = counted[1] if counted else clean
    n = counted[0] if counted else default_point_count(preset_id, duration_sec)

    writers = {
        "product-demo": lambda: _templated("product", clean, subject, max(3, n), source,
                                           f"You have been doing {lowercase(subject)} the hard way.",
                                           "If this solves the annoying part, it is already worth a look."),
        "tutorial-steps": lambda: _templated("tutorial", clean, subject, max(3, n), source,
                                             f"Skip the 40-minute version. {capitalize(subject)} is {max(3, n)} moves.",
                                             "Replay it once, then do the first step before you overthink it."),
        "youtube-short-news": lambda: _templated("news", clean, subject, max(3, n), source,
                                                 f"The headline skipped this: {lowercase(subject)}.",
                                                 "That is the cut. Follow for the next briefing."),
        "news-roundup": lambda: _templated("news", clean, subject, max(4, n), source,
                                           f"The headline skipped this: {lowercase(subject)}.",
                                           "That is the cut. Follow for the next briefing."),
        "luxury-brand": lambda: {
            "hook": f"Quiet rooms. Slow light. {capitalize(subject)}.",
            "body": [
                "Nothing here is rushed, because rush is the cheapest material you can use.",
                "The detail is the product: weight, finish, the pause before you speak.",
                "If it needs a shout, it is not finished.",
            ],
            "cta": "Look closer. Then decide if it belongs with you.",
            "source": source,
        },
        "cinematic-story": lambda: {
            "hook": f"It starts smaller than the story you tell later. {capitalize(subject)}.",
            "body": [
                "First, the ordinary hour — the one nobody films.",
                "Then the turn: a choice that looks tiny until it is not.",
                "By the end you are not selling a tip. You are leaving a feeling that sticks.",
            ],
            "cta": "If this landed, sit with it. Then go make the next scene.",
            "source": source,
        },
        "travel-vlog": lambda: _templated("travel", clean, subject, max(3, n), source,
                                          f"Pack lighter. {capitalize(subject)} is a route, not a checklist.",
                                          "Go while the light is still interesting. Map the next one after."),
        "faceless-facts": lambda: _templated("facts", clean, subject, max(3, n), source,
                                             f"Most people still get {lowercase(subject)} backward. Here is the cut.",
                                             "Save this so you remember it later. More facts incoming."),
        "listicle": lambda: _templated("listicle", clean, subject, max(5, n), source,
                                       f"Stop ranking this by vibes. The honest list on {lowercase(subject)} starts now.",
                                       "Which one are you trying first? Comment the number and subscribe for the next list."),
        "explainer": lambda: _templated("explainer", clean, subject, max(4, n), source,
                                        f"Forget the 20-minute explainer. {capitalize(subject)} is one mechanism.",
                                        "Replay the middle if you need it. Subscribe if you want the next explainer."),
        "storytime": lambda: {
            "hook": f"I did not plan to tell this. Then {lowercase(subject)} happened.",
            "body": [
                "It started as an ordinary Tuesday, the kind you do not bother filming.",
                "The first crack was small: a choice I almost shrugged off.",
                "Then the cost showed up, and I could not pretend it was a coincidence.",
                "Here is the part I would tell a friend if we had ten quiet minutes.",
                "I still would not go back, but I would start sooner.",
            ],
            "cta": "If you needed this story, stay. The next one is already in the draft.",
            "source": source,
        },
        "motivational": lambda: {
            "hook": f"Nobody is coming to rescue {lowercase(subject)}. That is the good news.",
            "body": [
                "You do not need a new personality. You need a smaller first move.",
                "The gym, the page, the walk — they all work when they are boring enough to repeat.",
                "Stop waiting for the cinematic morning. Start in the messy one you already have.",
                "Keep the streak ugly and alive. Pretty streaks die on day four.",
            ],
            "cta": "Do the first two minutes now. Then come back tomorrow.",
            "source": source,
        },
        "podcast-clip": lambda: _templated("podcast", clean, subject, max(3, n), source,
                                           f"This is the minute they hoped you would skip: {lowercase(subject)}.",
                                           "Full conversation is on the channel. Subscribe so you do not miss the next cut."),
    }
    writer = writers.get(preset_id)
    if writer:
        return writer()
    return _templated(
        "viral",
        clean,
        subject,
        max(3, n),
        source,
        f"Stop scrolling. {capitalize(subject)} is about to make the usual advice look expensive.",
        "Try it once this week, then tell me I am wrong. Follow for the next one.",
    )


def parse_user_script(text: str) -> dict[str, Any]:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if len(lines) >= 3:
        hook = rewrite_forbidden(strip_label(lines[0]), text)
        return {
            "hook": hook,
            "body": [strip_label(line) for line in lines[1:-1]],
            "cta": strip_label(lines[-1]),
            "source": "user",
        }
    sentences = split_sentences(text)
    if len(sentences) >= 3:
        return {
            "hook": rewrite_forbidden(sentences[0], text),
            "body": sentences[1:-1],
            "cta": sentences[-1],
            "source": "user",
        }
    return write(text, "viral-hook", source="user")


def parse_model_output(text: str, fallback_topic: str, preset_id: str) -> dict[str, Any]:
    hook = ""
    body: list[str] = []
    cta = ""
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        lower = line.lower()
        if lower.startswith("hook:"):
            hook = strip_label(line)
        elif lower.startswith("cta:") or lower.startswith("call to action:"):
            cta = strip_label(line)
        elif lower.startswith("body:") or lower.startswith("beat:") or numbered_prefix(line) is not None:
            body.append(strip_label(line))
        elif not hook:
            hook = strip_label(line)
        elif not cta and len(body) >= 2:
            cta = strip_label(line)
        else:
            body.append(strip_label(line))
    if not hook or not body:
        return write(fallback_topic, preset_id, source="template")
    if not cta:
        cta = write(fallback_topic, preset_id)["cta"]
    if is_forbidden_open(hook):
        hook = write(fallback_topic, preset_id)["hook"]
    return {"hook": hook, "body": body, "cta": cta, "source": "ollama"}


def looks_like_full_script(text: str) -> bool:
    trimmed = text.strip()
    if not trimmed:
        return False
    sentences = split_sentences(trimmed)
    if len(trimmed) >= 180 and len(sentences) >= 3:
        return True
    return "\n" in trimmed and len(sentences) >= 2


def full_text(script: dict[str, Any]) -> str:
    parts = [script.get("hook", "")] + list(script.get("body") or []) + [script.get("cta", "")]
    return " ".join(part.strip() for part in parts if part and part.strip())


def spoken_lines(script: dict[str, Any]) -> list[str]:
    parts = [script.get("hook", "")] + list(script.get("body") or []) + [script.get("cta", "")]
    return [part for part in parts if part and part.strip()]


def ollama_prompt(topic: str, preset: dict[str, Any], duration_sec: int) -> str:
    budget = "420-700" if duration_sec >= 180 else "40-90"
    bodies = 8 if duration_sec >= 180 else 3
    body_lines = "\n".join(["BODY: one spoken sentence"] * bodies)
    return (
        f"Write a spoken video script for a {duration_sec}-second {preset.get('aspect', '9:16')} video.\n"
        f"Style: {preset.get('name')} — {preset.get('tagline')}\n"
        f"Topic: {topic}\n\n"
        "Return plain text with these labeled lines and nothing else:\n"
        'HOOK: one pattern-interrupt sentence. Never start with "In this video", "Today we", "Welcome back", or "Let\'s talk about".\n'
        f"{body_lines}\n"
        "CTA: one short closing ask\n\n"
        f"Keep language spoken and concrete. About {budget} words. No hashtags, no emoji.\n"
    )


def rewrite_forbidden(hook: str, topic: str) -> str:
    if is_forbidden_open(hook):
        return write(topic, "viral-hook")["hook"]
    return hook


def _templated(flavor: str, topic: str, subject: str, count: int, source: str, hook: str, cta: str) -> dict[str, Any]:
    return {
        "hook": hook,
        "body": expand_points(subject, topic, count, flavor),
        "cta": cta,
        "source": source,
    }


def expand_points(subject: str, topic: str, count: int, flavor: str) -> list[str]:
    extracted = extract_list(topic)
    if extracted and len(extracted) >= 2:
        items = extracted[: max(count, len(extracted))]
        return [decorate(item, index, flavor) for index, item in enumerate(items)]
    bank = [line.format(s=lowercase(subject)) for line in POINT_BANKS[flavor]]
    return [decorate(bank[index % len(bank)], index, flavor) for index in range(count)]


def decorate(item: str, index: int, flavor: str) -> str:
    text = capitalize(item)
    prefixes = {
        "viral": f"Reason {index + 1}: {lowercase(text)}.",
        "facts": f"Fact {index + 1}: {lowercase(text)}.",
        "product": f"Feature {index + 1}: {lowercase(text)}.",
        "tutorial": f"Step {index + 1}: {lowercase(text)}.",
        "news": f"{text if text.endswith('.') else text + '.'}",
        "travel": f"Then this: {lowercase(text)}.",
        "listicle": f"Number {index + 1}: {lowercase(text)}.",
        "explainer": f"Next: {lowercase(text)}.",
        "podcast": f"And this is the cut that matters: {lowercase(text)}.",
    }
    return prefixes[flavor]


def default_point_count(preset_id: str, duration_sec: int) -> int:
    if duration_sec >= 180:
        return 8 if preset_id == "listicle" else 7
    if preset_id in {"luxury-brand", "cinematic-story", "storytime", "motivational"}:
        return 3
    if preset_id in {"tutorial-steps", "listicle", "explainer"}:
        return 5
    return 3


def extract_count(text: str, max_count: int) -> tuple[int, str] | None:
    match = re.match(
        r"^\s*(\d+)\s+(?:reasons?|ways?|tips?|steps?|things?|facts?|ideas?|features?)(?:\s+(?:why|that|to|for|your))?\s+(.+)$",
        text,
        re.I,
    )
    if not match:
        return None
    return min(max(int(match.group(1)), 2), max_count), match.group(2)


def extract_list(text: str) -> list[str] | None:
    parts = [strip_label(part) for part in re.split(r"[•\n;]", text) if part.strip()]
    return parts if len(parts) >= 3 else None


def split_sentences(text: str) -> list[str]:
    cleaned = collapse_whitespace(text)
    if not cleaned:
        return []
    sentences: list[str] = []
    current = ""
    for char in cleaned:
        current += char
        if char in ".!?":
            piece = current.strip()
            if len(piece) > 1:
                sentences.append(piece)
            current = ""
    tail = current.strip()
    if tail:
        sentences.append(tail)
    return sentences


def numbered_prefix(line: str) -> int | None:
    match = re.match(r"^\s*(?:body|beat|step|reason|fact)?\s*(\d+)[).:\-]", line, re.I)
    return int(match.group(1)) if match else None


def strip_label(line: str) -> str:
    s = line.strip()
    lower = s.lower()
    for label in ("hook:", "body:", "cta:", "call to action:", "beat:", "step:", "reason:", "fact:", "feature:"):
        if lower.startswith(label):
            s = s[len(label):].strip()
            break
    s = re.sub(r"^\s*\d+[).:\-]\s*", "", s).strip()
    if s and s[-1] not in ".?!":
        s += "."
    return capitalize(s)


def collapse_whitespace(text: str) -> str:
    return " ".join(text.split())


def capitalize(text: str) -> str:
    return text[:1].upper() + text[1:] if text else text


def lowercase(text: str) -> str:
    if not text:
        return text
    if len(text) > 1 and text[1:2].isupper():
        return text
    return text[:1].lower() + text[1:]
