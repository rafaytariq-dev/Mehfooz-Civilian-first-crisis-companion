"""
Comms Agent — Tools.

Three tools as specified in M6:
  1. render_message  — Gemini Flash call to produce localized push text
  2. send_fcm        — Firebase Admin SDK push notification
  3. enqueue_sms_fallback — write to sms_queue if user has stale FCM
"""
from __future__ import annotations

import logging
import os
import time
from datetime import datetime, timedelta, timezone
from typing import Any

from config import GEMINI_FLASH, PROJECT_ID, SMS_FALLBACK_INACTIVE_HOURS, SOS_HIGH_MAX_CHARS
from models import FCMResult, RenderedMessage, SMSResult, UserActionPayload, UserProfile
from notification_channels import ChannelConfig, get_channel_config

logger = logging.getLogger("orchestrator.comms_tools")


# ─────────────────────────────────────────────────────────────────────────────
# Firestore client (lazy init)
# ─────────────────────────────────────────────────────────────────────────────

_db = None


def _get_db():
    global _db
    if _db is None:
        from google.cloud import firestore
        _db = firestore.AsyncClient(project=PROJECT_ID)
    return _db


# ─────────────────────────────────────────────────────────────────────────────
# Firebase Admin init (lazy, singleton)
# ─────────────────────────────────────────────────────────────────────────────

_firebase_initialized = False


def _init_firebase():
    """Initialize Firebase Admin SDK (idempotent)."""
    global _firebase_initialized
    if _firebase_initialized:
        return
    import firebase_admin
    from firebase_admin import credentials
    if not firebase_admin._apps:
        # Use Application Default Credentials in Cloud Run
        # or GOOGLE_APPLICATION_CREDENTIALS locally
        cred = credentials.ApplicationDefault()
        firebase_admin.initialize_app(cred, {"projectId": PROJECT_ID})
    _firebase_initialized = True


# ─────────────────────────────────────────────────────────────────────────────
# Tool 1: render_message
# ─────────────────────────────────────────────────────────────────────────────

# System prompt for Gemini Flash message rendering
_RENDER_SYSTEM_PROMPT = """You are the Mehfooz (محفوظ) notification writer.
Your job: produce a push notification title and body for a crisis alert.

RULES:
- Use the user's preferred language: {language}
- For Urdu (ur): use simple, conversational register. NOT literary/formal Urdu.
  Example good: "ابھی نکلیں! G-10 میں پانی تیزی سے بڑھ رہا ہے۔"
  Example bad: "فوری طور پر انخلا کریں، سیلابی صورتحال نہایت سنگین ہے۔"
- For Roman Urdu (roman_ur): write in Roman script, conversational.
  Example good: "Abhi niklen! G-10 mein paani barh rha hai."
- For English (en): clear, direct, no jargon.
- For SOS/high urgency: LEAD WITH THE ACTION, not the explanation.
  Good: "EVACUATE NOW — water rising at G-10 Markaz"
  Bad: "Due to heavy rainfall, flooding is occurring..."
- Title format: "[VERB] — Mehfooz" (e.g., "EVACUATE — Mehfooz")
  For Urdu: "[VERB اردو] — محفوظ"
- Body: {max_chars} characters MAX. Be concise.
- Never claim authority endorsement.
- Never invent helpline numbers.
- Include source info if provided (e.g., "12 reports in 20 min").

OUTPUT FORMAT (JSON):
{{"title": "...", "body": "..."}}
"""

# Urdu verb translations for notification titles
_URDU_VERBS = {
    "EVACUATE": "فوری انخلا",
    "REROUTE": "راستہ بدلیں",
    "SHELTER_IN_PLACE": "جگہ پر رہیں",
    "CONTACT_HELPLINE": "ہیلپ لائن",
    "CHECK_ON_FAMILY": "خاندان سے رابطہ",
    "AVOID_AREA": "علاقے سے دور رہیں",
    "SEEK_COOLING": "ٹھنڈی جگہ جائیں",
    "SEEK_MEDICAL": "طبی مدد",
}

_ROMAN_URDU_VERBS = {
    "EVACUATE": "NIKLEN ABHI",
    "REROUTE": "RASTA BADLEN",
    "SHELTER_IN_PLACE": "JAGAH PAR RAHEN",
    "CONTACT_HELPLINE": "HELPLINE",
    "CHECK_ON_FAMILY": "GHAR WALON KO CALL",
    "AVOID_AREA": "DOOR RAHEN",
    "SEEK_COOLING": "THANDI JAGAH",
    "SEEK_MEDICAL": "MEDICAL HELP",
}


async def render_message(
    user: UserProfile,
    action: UserActionPayload,
) -> RenderedMessage:
    """Render a localized push notification using Gemini Flash.

    For SOS/high tiers, body is capped at 140 characters.
    Uses the user's preferred language from their profile.
    """
    t0 = time.monotonic()
    language = user.language or "en"
    urgency = action.urgency or "med"

    # Determine max characters based on urgency
    max_chars = SOS_HIGH_MAX_CHARS if urgency in ("sos", "high") else 280

    # Build the title deterministically (no LLM needed for title)
    verb = action.verb or "ALERT"
    if language == "ur":
        verb_local = _URDU_VERBS.get(verb, verb)
        title = f"{verb_local} — محفوظ"
    elif language == "roman_ur":
        verb_local = _ROMAN_URDU_VERBS.get(verb, verb)
        title = f"{verb_local} — Mehfooz"
    else:
        title = f"{verb} — Mehfooz"

    # For the body, use the pre-rendered message from the plan if available
    # and it's within length limits. Otherwise, call Gemini to render.
    pre_rendered = ""
    if language == "ur" and action.message_ur:
        pre_rendered = action.message_ur
    elif language == "roman_ur" and action.message_ur:
        # Plan provides Urdu script; we need Roman Urdu — use Gemini
        pre_rendered = ""
    elif language == "en" and action.message_en:
        pre_rendered = action.message_en
    else:
        pre_rendered = action.message_en or action.message_ur or ""

    # If pre-rendered message fits the length constraint, use it directly
    if pre_rendered and len(pre_rendered) <= max_chars:
        body = pre_rendered
    else:
        # Call Gemini Flash to render/compress the message
        body = await _gemini_render(
            language=language,
            verb=verb,
            message_en=action.message_en,
            message_ur=action.message_ur,
            max_chars=max_chars,
            urgency=urgency,
        )

    # Hard enforcement of character limit
    if len(body) > max_chars:
        body = body[:max_chars - 1] + "…"

    dur = int((time.monotonic() - t0) * 1000)
    logger.info(
        f"[render_message] user={user.uid} lang={language} "
        f"verb={verb} urgency={urgency} body_len={len(body)} dur={dur}ms"
    )

    return RenderedMessage(title=title, body=body, language=language)


async def _gemini_render(
    language: str,
    verb: str,
    message_en: str,
    message_ur: str,
    max_chars: int,
    urgency: str,
) -> str:
    """Call Gemini Flash to render/translate/compress a notification body."""
    try:
        from google import genai

        client = genai.Client()

        system_prompt = _RENDER_SYSTEM_PROMPT.format(
            language=language,
            max_chars=max_chars,
        )

        user_prompt = (
            f"Render this crisis notification.\n"
            f"Verb: {verb}\n"
            f"Urgency: {urgency}\n"
            f"English message: {message_en}\n"
            f"Urdu message: {message_ur}\n"
            f"Target language: {language}\n"
            f"Max body length: {max_chars} chars\n"
            f"Return ONLY the JSON with title and body."
        )

        response = client.models.generate_content(
            model=GEMINI_FLASH,
            contents=user_prompt,
            config={
                "system_instruction": system_prompt,
                "temperature": 0.3,
                "max_output_tokens": 256,
            },
        )

        text = response.text.strip()
        # Parse JSON response
        import json
        # Handle markdown code blocks if Gemini wraps the JSON
        if text.startswith("```"):
            text = text.split("\n", 1)[1].rsplit("```", 1)[0].strip()
        parsed = json.loads(text)
        return parsed.get("body", message_en or message_ur or "")

    except Exception as e:
        logger.warning(f"[_gemini_render] Gemini call failed: {e}. Using fallback.")
        # Fallback: use pre-rendered message, truncated
        fallback = message_en if language == "en" else (message_ur or message_en)
        if len(fallback) > max_chars:
            fallback = fallback[:max_chars - 1] + "…"
        return fallback


# ─────────────────────────────────────────────────────────────────────────────
# Tool 2: send_fcm
# ─────────────────────────────────────────────────────────────────────────────


async def send_fcm(
    user_id: str,
    title: str,
    body: str,
    data: dict[str, str],
    urgency: str = "med",
    fcm_token: str | None = None,
) -> FCMResult:
    """Send an FCM push notification to a user.

    Maps urgency tier to the correct Android notification channel,
    FCM priority, sound, vibration, and iOS interruption level.
    """
    t0 = time.monotonic()
    channel = get_channel_config(urgency)

    if not fcm_token:
        # Try to look up from Firestore
        fcm_token = await _get_user_fcm_token(user_id)

    if not fcm_token:
        logger.warning(f"[send_fcm] No FCM token for user {user_id}")
        return FCMResult(success=False, error="no_fcm_token")

    try:
        _init_firebase()
        from firebase_admin import messaging

        # Build Android-specific config
        android_notification = messaging.AndroidNotification(
            title=title,
            body=body,
            channel_id=channel.android_channel_id,
            sound=channel.android_sound if channel.android_sound else None,
            priority="max" if urgency == "sos" else "high" if urgency == "high" else "default",
        )

        android_config = messaging.AndroidConfig(
            priority="high" if channel.fcm_priority == "high" else "normal",
            notification=android_notification,
        )

        # Build iOS (APNs) config
        apns_headers = {}
        if channel.fcm_priority == "high":
            apns_headers["apns-priority"] = "10"
        else:
            apns_headers["apns-priority"] = "5"

        # iOS interruption level
        apns_payload_data: dict[str, Any] = {}
        if channel.ios_interruption_level == "critical":
            apns_payload_data["interruption-level"] = "critical"
        elif channel.ios_interruption_level == "time-sensitive":
            apns_payload_data["interruption-level"] = "time-sensitive"
        elif channel.ios_interruption_level == "passive":
            apns_payload_data["interruption-level"] = "passive"
        # 'active' is the default, no need to set

        apns_alert = messaging.ApsAlert(title=title, body=body)
        aps = messaging.Aps(
            alert=apns_alert,
            sound=channel.ios_sound if channel.ios_sound else None,
            content_available=True,
        )

        apns_config = messaging.APNSConfig(
            headers=apns_headers,
            payload=messaging.APNSPayload(aps=aps, custom_data=apns_payload_data),
        )

        # Build the message
        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in data.items()},
            android=android_config,
            apns=apns_config,
            token=fcm_token,
        )

        # Send
        message_id = messaging.send(message)

        dur = int((time.monotonic() - t0) * 1000)
        logger.info(
            f"[send_fcm] Sent to user={user_id} "
            f"tier={urgency} channel={channel.android_channel_id} "
            f"msg_id={message_id} dur={dur}ms"
        )

        # Update last active timestamp
        await _update_fcm_last_active(user_id)

        return FCMResult(success=True, message_id=message_id)

    except Exception as e:
        dur = int((time.monotonic() - t0) * 1000)
        logger.error(f"[send_fcm] Failed for user={user_id}: {e} dur={dur}ms")
        return FCMResult(success=False, error=str(e))


async def _get_user_fcm_token(user_id: str) -> str | None:
    """Look up a user's FCM token from Firestore."""
    try:
        db = _get_db()
        doc = await db.collection("users").document(user_id).get()
        if doc.exists:
            return doc.to_dict().get("fcm_token")
    except Exception as e:
        logger.warning(f"[_get_user_fcm_token] Failed for {user_id}: {e}")
    return None


async def _update_fcm_last_active(user_id: str) -> None:
    """Update the user's FCM last active timestamp."""
    try:
        db = _get_db()
        await db.collection("users").document(user_id).update({
            "fcm_last_active": datetime.now(timezone.utc),
        })
    except Exception as e:
        logger.warning(f"[_update_fcm_last_active] Failed for {user_id}: {e}")


# ─────────────────────────────────────────────────────────────────────────────
# Tool 3: enqueue_sms_fallback
# ─────────────────────────────────────────────────────────────────────────────


async def enqueue_sms_fallback(
    phone: str,
    body: str,
    user_id: str = "",
    event_id: str = "",
) -> SMSResult:
    """Write to sms_queue collection if user has no FCM activity in last 48h.

    Checks whether the user's FCM token has been active recently.
    If not (or if no token exists), enqueues an SMS for the gateway.
    """
    if not phone:
        return SMSResult(enqueued=False, reason="no_phone_number")

    # Check FCM activity
    should_sms = await _should_sms_fallback(user_id)
    if not should_sms:
        return SMSResult(
            enqueued=False,
            reason=f"fcm_active_within_{SMS_FALLBACK_INACTIVE_HOURS}h"
        )

    try:
        db = _get_db()
        sms_doc = {
            "phone": phone,
            "body": body,
            "user_id": user_id,
            "event_id": event_id,
            "status": "pending",
            "created_at": datetime.now(timezone.utc),
        }
        await db.collection("sms_queue").add(sms_doc)

        logger.info(
            f"[enqueue_sms_fallback] SMS queued for phone={phone[:6]}*** "
            f"user={user_id} event={event_id}"
        )
        return SMSResult(enqueued=True, reason="fcm_inactive")

    except Exception as e:
        logger.error(f"[enqueue_sms_fallback] Failed: {e}")
        return SMSResult(enqueued=False, reason=f"error: {e}")


async def _should_sms_fallback(user_id: str) -> bool:
    """Check if a user's FCM has been inactive long enough to warrant SMS."""
    if not user_id:
        return True  # No user ID → assume SMS needed

    try:
        db = _get_db()
        doc = await db.collection("users").document(user_id).get()
        if not doc.exists:
            return True

        data = doc.to_dict()
        fcm_token = data.get("fcm_token")
        if not fcm_token:
            return True

        last_active = data.get("fcm_last_active")
        if not last_active:
            return True  # Never been active → SMS

        # Check if inactive for too long
        cutoff = datetime.now(timezone.utc) - timedelta(hours=SMS_FALLBACK_INACTIVE_HOURS)
        if isinstance(last_active, datetime):
            return last_active < cutoff
        return True

    except Exception as e:
        logger.warning(f"[_should_sms_fallback] Check failed for {user_id}: {e}")
        return True  # Fail open — send SMS if we can't check
