"""
Orchestrator + Comms Agent — Unit tests.

Tests the orchestration loop, comms rendering, notification channels,
and feedback loop behavior with mocked sub-agent calls.
"""
from __future__ import annotations

import json
import pytest
import pytest_asyncio
from unittest.mock import AsyncMock, MagicMock, patch

# ─────────────────────────────────────────────────────────────────────────────
# Test notification channel mapping
# ─────────────────────────────────────────────────────────────────────────────


def test_channel_config_sos():
    from notification_channels import get_channel_config
    ch = get_channel_config("sos")
    assert ch.tier == "sos"
    assert ch.fcm_priority == "high"
    assert ch.android_channel_id == "mehfooz_sos"
    assert ch.sms_fallback is True
    assert ch.full_screen_intent is True
    assert ch.ios_interruption_level == "critical"


def test_channel_config_high():
    from notification_channels import get_channel_config
    ch = get_channel_config("high")
    assert ch.fcm_priority == "high"
    assert ch.sms_fallback is False
    assert ch.ios_interruption_level == "time-sensitive"


def test_channel_config_med():
    from notification_channels import get_channel_config
    ch = get_channel_config("med")
    assert ch.fcm_priority == "normal"
    assert ch.ios_interruption_level == "active"


def test_channel_config_low():
    from notification_channels import get_channel_config
    ch = get_channel_config("low")
    assert ch.fcm_priority == "normal"
    assert ch.android_sound == ""
    assert ch.ios_interruption_level == "passive"


def test_channel_config_unknown_falls_back_to_med():
    from notification_channels import get_channel_config
    ch = get_channel_config("xyz")
    assert ch.tier == "med"


# ─────────────────────────────────────────────────────────────────────────────
# Test models
# ─────────────────────────────────────────────────────────────────────────────


def test_orchestrate_request_model():
    from models import OrchestrateRequest
    req = OrchestrateRequest(
        report_id="rpt-001",
        user_id="user-001",
        text_raw="G-10 mein paani",
        location={"latitude": 33.69, "longitude": 72.01},
        city="Islamabad",
    )
    assert req.report_id == "rpt-001"
    assert req.location.latitude == 33.69


def test_orchestrate_result_defaults():
    from models import OrchestrateResult, ChainOutcome
    r = OrchestrateResult()
    assert r.outcome == ChainOutcome.no_event
    assert r.notifications_sent == 0
    assert r.feedback_loops == 0


def test_user_profile_model():
    from models import UserProfile
    u = UserProfile(uid="u1", language="ur", phone="+923001234567")
    assert u.language == "ur"


def test_rendered_message_model():
    from models import RenderedMessage
    m = RenderedMessage(title="EVACUATE — Mehfooz", body="Niklen abhi", language="en")
    assert len(m.body) < 140


# ─────────────────────────────────────────────────────────────────────────────
# Test comms tools — render_message
# ─────────────────────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_render_message_english_uses_plan_message():
    """If plan already has a good English message within length, use it directly."""
    from comms_tools import render_message
    from models import UserProfile, UserActionPayload

    user = UserProfile(uid="u1", language="en")
    action = UserActionPayload(
        verb="EVACUATE",
        message_en="Leave G-10 now, water rising fast",
        message_ur="ابھی نکلیں",
        urgency="high",
    )
    result = await render_message(user, action)
    assert result.title == "EVACUATE — Mehfooz"
    assert result.body == "Leave G-10 now, water rising fast"
    assert result.language == "en"


@pytest.mark.asyncio
async def test_render_message_urdu_uses_plan_message():
    """For Urdu users, use the pre-rendered Urdu message."""
    from comms_tools import render_message
    from models import UserProfile, UserActionPayload

    user = UserProfile(uid="u2", language="ur")
    action = UserActionPayload(
        verb="EVACUATE",
        message_en="Leave now",
        message_ur="ابھی نکلیں، پانی بڑھ رہا ہے",
        urgency="sos",
    )
    result = await render_message(user, action)
    assert "محفوظ" in result.title  # Urdu title format
    assert result.language == "ur"
    assert len(result.body) <= 140  # SOS cap


@pytest.mark.asyncio
async def test_render_message_enforces_char_limit():
    """Body must be truncated for SOS/high urgency."""
    from comms_tools import render_message
    from models import UserProfile, UserActionPayload

    user = UserProfile(uid="u3", language="en")
    action = UserActionPayload(
        verb="EVACUATE",
        message_en="A" * 200,  # way too long
        message_ur="",
        urgency="sos",
    )
    result = await render_message(user, action)
    assert len(result.body) <= 140


# ─────────────────────────────────────────────────────────────────────────────
# Test orchestration loop with mocked sub-agents
# ─────────────────────────────────────────────────────────────────────────────


def _mock_ingestion_response():
    return {"reports_processed": 1, "traces_written": 1}


def _mock_detection_verified():
    return {
        "signals_read": 15,
        "clusters_found": 1,
        "events_created": 1,
        "verified_events": 1,
        "candidate_events": 0,
        "event_ids": ["evt-g10-001"],
    }


def _mock_detection_candidate_only():
    return {
        "signals_read": 5,
        "clusters_found": 1,
        "events_created": 1,
        "verified_events": 0,
        "candidate_events": 1,
        "event_ids": ["evt-candidate-001"],
    }


def _mock_detection_empty():
    return {
        "signals_read": 2,
        "clusters_found": 0,
        "events_created": 0,
        "verified_events": 0,
        "candidate_events": 0,
        "event_ids": [],
    }


def _mock_planning_response():
    return {
        "plan_id": "plan-g10-001",
        "event_id": "evt-g10-001",
        "system_actions_count": 3,
        "user_actions_count": 5,
    }


def _mock_simulation_response():
    return {
        "report_id": "simrpt-g10-001",
        "plan_id": "plan-g10-001",
        "event_id": "evt-g10-001",
        "dispatches_sent": 2,
        "notifications_queued": 5,
    }


def _mock_social_response():
    return {"social_signals_enriched": 3, "traces_written": 1}


class MockResponse:
    """Mock httpx response."""
    def __init__(self, data, status_code=200):
        self._data = data
        self.status_code = status_code

    def json(self):
        return self._data

    def raise_for_status(self):
        if self.status_code >= 400:
            raise Exception(f"HTTP {self.status_code}")


@pytest.mark.asyncio
async def test_orchestrate_full_chain_happy_path():
    """Happy path: ingestion → detection (verified) → planning → sim → comms."""
    from models import OrchestrateRequest, ChainOutcome

    trigger = OrchestrateRequest(
        report_id="rpt-test-001",
        user_id="demo-aisha-001",
        text_raw="G-10 mein paani bhar gaya",
        location={"latitude": 33.692, "longitude": 72.013},
        city="Islamabad",
    )

    mock_plan_doc = {
        "plan_id": "plan-g10-001",
        "event_id": "evt-g10-001",
        "user_actions": {
            "demo-aisha-001": {
                "verb": "EVACUATE",
                "message_en": "Leave G-10 now",
                "message_ur": "ابھی نکلیں",
                "urgency": "sos",
            }
        },
    }

    with patch("loop._get_db") as mock_db, \
         patch("loop.httpx.AsyncClient") as MockClient, \
         patch("comms.process_comms", new_callable=AsyncMock) as mock_comms:

        # Mock Firestore
        mock_db_instance = MagicMock()
        mock_db.return_value = mock_db_instance

        # Mock trace writes
        mock_doc_ref = AsyncMock()
        mock_db_instance.collection.return_value.document.return_value = mock_doc_ref
        mock_doc_ref.set = AsyncMock()
        mock_doc_ref.get = AsyncMock(return_value=MagicMock(
            exists=True, to_dict=lambda: mock_plan_doc
        ))

        # Mock HTTP client
        async def mock_post(url, **kwargs):
            if "/ingest/report" in url:
                return MockResponse(_mock_ingestion_response())
            elif "/detect/run" in url:
                return MockResponse(_mock_detection_verified())
            elif "/plan/run" in url:
                return MockResponse(_mock_planning_response())
            elif "/simulate/run" in url:
                return MockResponse(_mock_simulation_response())
            return MockResponse({}, 404)

        mock_client = AsyncMock()
        mock_client.post = mock_post
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)
        MockClient.return_value = mock_client

        # Mock comms
        from models import CommsResult
        mock_comms.return_value = CommsResult(notifications_sent=1, sms_enqueued=1)

        # Reimport to pick up patches
        import loop
        result = await loop.orchestrate(trigger)

        assert result.outcome == ChainOutcome.completed
        assert len(result.event_ids) > 0
        assert len(result.plan_ids) > 0
        assert result.feedback_loops == 0


@pytest.mark.asyncio
async def test_orchestrate_no_events():
    """Detection finds nothing → outcome is no_event."""
    from models import OrchestrateRequest, ChainOutcome

    trigger = OrchestrateRequest(
        report_id="rpt-empty",
        user_id="u1",
        text_raw="everything is fine",
        location={"latitude": 33.69, "longitude": 72.01},
    )

    with patch("loop._get_db") as mock_db, \
         patch("loop.httpx.AsyncClient") as MockClient:

        mock_db_instance = MagicMock()
        mock_db.return_value = mock_db_instance
        mock_doc_ref = AsyncMock()
        mock_db_instance.collection.return_value.document.return_value = mock_doc_ref
        mock_doc_ref.set = AsyncMock()

        async def mock_post(url, **kwargs):
            if "/ingest/report" in url:
                return MockResponse(_mock_ingestion_response())
            elif "/detect/run" in url:
                return MockResponse(_mock_detection_empty())
            return MockResponse({}, 404)

        mock_client = AsyncMock()
        mock_client.post = mock_post
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)
        MockClient.return_value = mock_client

        import loop
        result = await loop.orchestrate(trigger)

        assert result.outcome == ChainOutcome.no_event
        assert len(result.event_ids) == 0


# ─────────────────────────────────────────────────────────────────────────────
# Test config
# ─────────────────────────────────────────────────────────────────────────────


def test_config_defaults():
    from config import (
        INGESTION_AGENT_URL,
        DETECTION_AGENT_URL,
        PLANNING_AGENT_URL,
        SIMULATION_AGENT_URL,
        MAX_DETECTION_RETRIES,
        CONFIDENCE_THRESHOLD,
    )
    assert "8081" in INGESTION_AGENT_URL
    assert "8082" in DETECTION_AGENT_URL
    assert "8083" in PLANNING_AGENT_URL
    assert "8084" in SIMULATION_AGENT_URL
    assert MAX_DETECTION_RETRIES == 2
    assert CONFIDENCE_THRESHOLD == 0.6
