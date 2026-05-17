"""
Notification urgency → channel mapping.

Implements the M6 spec tier table:

| Tier | FCM Priority | Android Channel    | Sound        | Vibration       | iOS Interruption |
|------|--------------|--------------------|-------------|-----------------|------------------|
| sos  | high         | mehfooz_sos        | loud alarm  | strong, repeat  | critical         |
| high | high         | mehfooz_high       | distinct    | standard        | time-sensitive   |
| med  | normal       | mehfooz_med        | default     | standard        | active           |
| low  | normal       | mehfooz_low        | silent      | none            | passive          |
"""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ChannelConfig:
    """Configuration for a single notification tier."""
    tier: str
    # FCM priority: 'high' or 'normal'
    fcm_priority: str
    # Android notification channel ID (must match app-side channel creation)
    android_channel_id: str
    # Android sound resource name (without extension)
    android_sound: str
    # Android vibration pattern (milliseconds): [wait, vibrate, wait, vibrate, ...]
    android_vibration_pattern: list[int]
    # iOS interruption level
    ios_interruption_level: str
    # iOS sound name
    ios_sound: str
    # Whether to also enqueue SMS fallback
    sms_fallback: bool
    # Whether this tier triggers full-screen intent on Android
    full_screen_intent: bool


# ─── Tier definitions ───

SOS = ChannelConfig(
    tier="sos",
    fcm_priority="high",
    android_channel_id="mehfooz_sos",
    android_sound="alarm_sos",
    android_vibration_pattern=[0, 500, 200, 500, 200, 500, 200, 500],
    ios_interruption_level="critical",
    ios_sound="alarm_sos.caf",
    sms_fallback=True,
    full_screen_intent=True,
)

HIGH = ChannelConfig(
    tier="high",
    fcm_priority="high",
    android_channel_id="mehfooz_high",
    android_sound="alert_high",
    android_vibration_pattern=[0, 400, 200, 400],
    ios_interruption_level="time-sensitive",
    ios_sound="alert_high.caf",
    sms_fallback=False,
    full_screen_intent=False,
)

MED = ChannelConfig(
    tier="med",
    fcm_priority="normal",
    android_channel_id="mehfooz_med",
    android_sound="default",
    android_vibration_pattern=[0, 300, 150, 300],
    ios_interruption_level="active",
    ios_sound="default",
    sms_fallback=False,
    full_screen_intent=False,
)

LOW = ChannelConfig(
    tier="low",
    fcm_priority="normal",
    android_channel_id="mehfooz_low",
    android_sound="",  # silent
    android_vibration_pattern=[],  # no vibration
    ios_interruption_level="passive",
    ios_sound="",
    sms_fallback=False,
    full_screen_intent=False,
)

# ─── Lookup ───

_TIER_MAP: dict[str, ChannelConfig] = {
    "sos": SOS,
    "high": HIGH,
    "med": MED,
    "low": LOW,
}


def get_channel_config(urgency: str) -> ChannelConfig:
    """Get the notification channel configuration for a given urgency tier.

    Falls back to MED if the tier is unrecognized.
    """
    return _TIER_MAP.get(urgency, MED)
