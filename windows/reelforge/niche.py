IMPERSONATION = (
    "as a doctor",
    "i'm a doctor",
    "i am a doctor",
    "trust me i'm a doctor",
    "as your doctor",
    "speaking as a physician",
    "as a lawyer",
    "i'm a lawyer",
    "i am a lawyer",
    "as your attorney",
    "legal advice from a lawyer",
    "financial advisor",
    "i'm a cfp",
    "as your advisor",
    "i am a fiduciary",
    "political analyst",
    "as a senator",
    "speaking as a judge",
    "as a political expert",
)


def warning_for(topic: str) -> str | None:
    lower = topic.lower()
    if any(needle in lower for needle in IMPERSONATION):
        return (
            "ReelForge will not write a script that impersonates a doctor, lawyer, "
            "finance advisor, or political expert. Rephrase as a personal story or a cited explainer."
        )
    return None
