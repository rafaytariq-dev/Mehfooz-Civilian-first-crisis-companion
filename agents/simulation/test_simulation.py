"""
Simulation Agent — Test Suite.

Tests the M5 simulation pipeline:
- Impact estimation heuristics
- Notification counting
- Route flagging
- Summary generation
- Dispatch determination
- Test endpoint smoke test
"""

from __future__ import annotations

import time
import pytest
import pytest_asyncio
from unittest.mock import patch, MagicMock

from models import (
    ActionVerb,
    AgentTrace,
    DispatchRecord,
    EstimatedImpact,
    NotificationCounts,
    PushQueueEntry,
    SimulationReport,
    SimulationRequest,
    SimulationResult,
    ToolCall,
    Urgency,
)
from tools import (
    count_notifications,
    count_routes_flagged,
    estimate_impact,
    generate_summary,
    determine_dispatches,
)
from agent import run_test_simulation


# =============================================================================
# Test data fixtures
# =============================================================================


@pytest.fixture
def mock_user_actions_g10():
    """G-10 scenario: 5 users, mixed urgency tiers."""
    return {
        "u_001": {
            "verb": "EVACUATE",
            "urgency": "sos",
            "message_en": "EVACUATE: Level 4 flood nearby. Seek shelter.",
            "message_ur": "فوری نکلیں: سیلاب۔ محفوظ جگہ جائیں۔",
        },
        "u_002": {
            "verb": "REROUTE",
            "urgency": "high",
            "message_en": "REROUTE: Flooding on IJP Road. Use alternate.",
            "message_ur": "راستہ بدلیں: IJP روڈ بند ہے۔",
        },
        "u_003": {
            "verb": "AVOID_AREA",
            "urgency": "med",
            "message_en": "AVOID: Crisis 1km away. Avoid area.",
            "message_ur": "علاقہ سے بچیں۔",
        },
        "u_004": {
            "verb": "CHECK_ON_FAMILY",
            "urgency": "med",
            "message_en": "CHECK ON FAMILY: Contact in affected area.",
            "message_ur": "خاندان سے رابطہ کریں۔",
        },
        "u_005": {
            "verb": "EVACUATE",
            "urgency": "sos",
            "message_en": "EVACUATE: Level 4 flood. Seek shelter at PIMS.",
            "message_ur": "فوری نکلیں: PIMS جائیں۔",
        },
    }


@pytest.fixture
def mock_system_actions():
    """System actions from M4 planning."""
    return [
        {
            "type": "notify_helpline",
            "target": "rescue_1122_ict",
            "payload": {
                "helpline_name": "Rescue 1122 ICT",
                "phone": "1122",
                "crisis_type": "urban_flood",
                "city": "Islamabad",
                "severity": 4,
            },
            "urgency": "high",
        },
        {
            "type": "flag_route",
            "target": "major_roads_in_polygon",
            "payload": {
                "severity": 4,
                "reason": "Flooding detected; routes unsafe.",
            },
            "urgency": "high",
        },
        {
            "type": "flag_route",
            "target": "IJP_road_underpass",
            "payload": {
                "severity": 4,
                "reason": "Underpass flooded — divert traffic.",
            },
            "urgency": "high",
        },
        {
            "type": "broadcast_zone",
            "target": "radius_5km_Islamabad",
            "payload": {
                "radius_m": 5000,
                "message": "ALERT: Level 4 urban_flood event.",
                "severity": 4,
            },
            "urgency": "sos",
        },
    ]


@pytest.fixture
def mock_event_data():
    """Event data for G-10 scenario."""
    return {
        "event_id": "evt_g10_test",
        "type": "urban_flood",
        "severity": 4,
        "city": "Islamabad",
        "centroid": {"latitude": 33.7050, "longitude": 73.0075},
    }


# =============================================================================
# Test: Impact estimation heuristics
# =============================================================================


class TestEstimateImpact:
    """Test the transparent impact heuristics from M5 spec."""

    def test_severity_4_with_reroute(self, mock_user_actions_g10):
        """Severity >= 4 uses 22 min avg delay."""
        impact = estimate_impact(mock_user_actions_g10, severity=4)

        # u_002 is the only REROUTE → diverted = 1
        assert impact.users_diverted == 1
        # congestion_reduction = 1 * 0.3 * 22 = 6.6
        assert impact.congestion_reduction_min == pytest.approx(6.6, abs=0.1)
        # SOS actions exist (u_001, u_005) → response_time_saved = 8
        assert impact.response_time_saved_min == 8.0

    def test_severity_3_moderate(self):
        """Severity < 4 uses 12 min avg delay."""
        user_actions = {
            "u_001": {"verb": "REROUTE", "urgency": "med"},
            "u_002": {"verb": "REROUTE", "urgency": "med"},
            "u_003": {"verb": "AVOID_AREA", "urgency": "low"},
        }
        impact = estimate_impact(user_actions, severity=3)

        assert impact.users_diverted == 2
        # congestion_reduction = 2 * 0.3 * 12 = 7.2
        assert impact.congestion_reduction_min == pytest.approx(7.2, abs=0.1)
        # No SOS → response_time_saved = 0
        assert impact.response_time_saved_min == 0.0

    def test_no_reroutes(self):
        """If no REROUTE actions, diverted = 0 and congestion = 0."""
        user_actions = {
            "u_001": {"verb": "SHELTER_IN_PLACE", "urgency": "med"},
            "u_002": {"verb": "EVACUATE", "urgency": "sos"},
        }
        impact = estimate_impact(user_actions, severity=5)

        assert impact.users_diverted == 0
        assert impact.congestion_reduction_min == 0.0
        assert impact.response_time_saved_min == 8.0  # SOS exists

    def test_empty_user_actions(self):
        """Empty user actions → all zeros."""
        impact = estimate_impact({}, severity=4)

        assert impact.users_diverted == 0
        assert impact.congestion_reduction_min == 0.0
        assert impact.response_time_saved_min == 0.0

    def test_multiple_reroutes_severity_5(self):
        """Multiple REROUTE actions with severity 5."""
        user_actions = {
            f"u_{i:03d}": {"verb": "REROUTE", "urgency": "sos"}
            for i in range(10)
        }
        impact = estimate_impact(user_actions, severity=5)

        assert impact.users_diverted == 10
        # 10 * 0.3 * 22 = 66.0
        assert impact.congestion_reduction_min == pytest.approx(66.0, abs=0.1)
        assert impact.response_time_saved_min == 8.0


# =============================================================================
# Test: Notification counting
# =============================================================================


class TestCountNotifications:
    """Test notification tier counting."""

    def test_g10_scenario(self, mock_user_actions_g10):
        """G-10 scenario: 2 sos, 1 high, 2 med, 0 low."""
        counts = count_notifications(mock_user_actions_g10)

        assert counts.sos == 2
        assert counts.high == 1
        assert counts.med == 2
        assert counts.low == 0
        assert counts.total_users == 5

    def test_empty_actions(self):
        """Empty actions → all zeros."""
        counts = count_notifications({})

        assert counts.total_users == 0
        assert counts.sos == 0

    def test_all_sos(self):
        """All SOS → total_users matches sos count."""
        actions = {
            f"u_{i}": {"verb": "EVACUATE", "urgency": "sos"}
            for i in range(47)
        }
        counts = count_notifications(actions)

        assert counts.sos == 47
        assert counts.total_users == 47
        assert counts.high == 0

    def test_unknown_urgency_defaults_to_low(self):
        """Unknown urgency tier defaults to low."""
        actions = {
            "u_001": {"verb": "AVOID_AREA", "urgency": "unknown_tier"},
        }
        counts = count_notifications(actions)

        assert counts.low == 1
        assert counts.total_users == 1


# =============================================================================
# Test: Routes flagged
# =============================================================================


class TestCountRoutesFlagged:
    """Test route flagging count."""

    def test_g10_system_actions(self, mock_system_actions):
        """G-10 scenario has 2 flag_route actions."""
        count = count_routes_flagged(mock_system_actions)
        assert count == 2

    def test_no_flag_routes(self):
        """No flag_route actions → 0."""
        actions = [
            {"type": "notify_helpline", "target": "x", "payload": {}, "urgency": "med"},
        ]
        assert count_routes_flagged(actions) == 0

    def test_empty_actions(self):
        """Empty → 0."""
        assert count_routes_flagged([]) == 0


# =============================================================================
# Test: Summary generation
# =============================================================================


class TestGenerateSummary:
    """Test English + Urdu summary card text generation."""

    def test_demo_summary_format(self):
        """Summary matches spec format with estimates disclaimer."""
        notifications = NotificationCounts(sos=2, high=1, med=2, low=0, total_users=5)
        dispatches = [
            DispatchRecord(
                authority="PDMA-Punjab",
                ticket_id="PDMA-123",
                endpoint="mock",
                payload_summary="test",
            ),
            DispatchRecord(
                authority="Rescue-1122-ICT",
                ticket_id="RES-456",
                endpoint="mock",
                payload_summary="test",
            ),
        ]
        impact = EstimatedImpact(
            congestion_reduction_min=6.6,
            users_diverted=1,
            response_time_saved_min=8.0,
        )

        summary_en, summary_ur = generate_summary(
            notifications, routes_flagged=3, dispatches=dispatches, impact=impact
        )

        # English summary checks
        assert "5 users alerted" in summary_en
        assert "3 routes flagged" in summary_en
        assert "2 tickets dispatched" in summary_en
        assert "PDMA-Punjab" in summary_en
        assert "Rescue-1122-ICT" in summary_en
        assert "Estimates" in summary_en
        assert "7 min congestion reduction" in summary_en  # 6.6 rounds to 7

        # Urdu summary checks
        assert "5 صارفین" in summary_ur
        assert "تخمینہ" in summary_ur  # "estimate" marker
        assert "ٹکٹ" in summary_ur

    def test_no_dispatches(self):
        """Summary handles zero dispatches gracefully."""
        notifications = NotificationCounts(total_users=0)
        impact = EstimatedImpact()

        summary_en, summary_ur = generate_summary(
            notifications, routes_flagged=0, dispatches=[], impact=impact
        )

        assert "0 users alerted" in summary_en
        assert "0 routes flagged" in summary_en
        assert "Estimates" in summary_en

    def test_response_time_in_summary(self):
        """When response_time_saved > 0, it appears in summary."""
        notifications = NotificationCounts(sos=1, total_users=1)
        impact = EstimatedImpact(response_time_saved_min=8.0)

        summary_en, _ = generate_summary(
            notifications, 0, [], impact
        )

        assert "8 min response time saved" in summary_en


# =============================================================================
# Test: Dispatch determination
# =============================================================================


class TestDetermineDispatches:
    """Test which mock endpoints get dispatched based on plan + event."""

    def test_severity_4_auto_dispatches(self, mock_system_actions, mock_event_data):
        """Severity 4 auto-dispatches PDMA + Rescue 1122."""
        plan_data = {
            "event_id": "evt_g10_test",
            "system_actions": mock_system_actions,
            "user_actions": {},
        }

        dispatches = determine_dispatches(plan_data, mock_event_data)

        endpoint_keys = [d["endpoint_key"] for d in dispatches]

        # notify_helpline → rescue_1122
        assert "rescue_1122" in endpoint_keys
        # flag_route → traffic_reroute
        assert "traffic_reroute" in endpoint_keys
        # broadcast_zone → sms_blast
        assert "sms_blast" in endpoint_keys
        # Auto-dispatch PDMA for severity >= 3
        assert "pdma_dispatch" in endpoint_keys

    def test_severity_2_no_auto_dispatch(self):
        """Severity 2 → no auto PDMA or Rescue dispatch."""
        plan_data = {
            "event_id": "evt_test",
            "system_actions": [],
            "user_actions": {},
        }
        event_data = {
            "event_id": "evt_test",
            "severity": 2,
            "type": "urban_flood",
            "city": "Islamabad",
        }

        dispatches = determine_dispatches(plan_data, event_data)

        # No system actions and severity < 3 → no auto dispatches
        assert len(dispatches) == 0

    def test_severity_3_pdma_only(self):
        """Severity 3 → auto PDMA, no auto Rescue 1122."""
        plan_data = {
            "event_id": "evt_test",
            "system_actions": [],
            "user_actions": {},
        }
        event_data = {
            "event_id": "evt_test",
            "severity": 3,
            "type": "urban_flood",
            "city": "Islamabad",
        }

        dispatches = determine_dispatches(plan_data, event_data)

        endpoint_keys = [d["endpoint_key"] for d in dispatches]
        assert "pdma_dispatch" in endpoint_keys
        assert "rescue_1122" not in endpoint_keys

    def test_no_duplicate_pdma(self, mock_event_data):
        """If system_actions already map to rescue_1122, don't duplicate."""
        plan_data = {
            "event_id": "evt_g10_test",
            "system_actions": [
                {"type": "notify_helpline", "target": "x", "payload": {}, "urgency": "high"},
            ],
            "user_actions": {},
        }

        dispatches = determine_dispatches(plan_data, mock_event_data)

        rescue_count = sum(1 for d in dispatches if d["endpoint_key"] == "rescue_1122")
        # 1 from system_action mapping + 0 duplicates (already present)
        assert rescue_count == 1


# =============================================================================
# Test: Test endpoint (smoke test)
# =============================================================================


class TestSmoke:
    """Test the /simulate/test endpoint logic."""

    @pytest.mark.asyncio
    async def test_run_test_simulation(self):
        """Smoke test returns complete result without Firestore."""
        result = await run_test_simulation()

        assert result["status"] == "ok"
        assert result["test"] == "simulation"
        assert "report_id" in result
        assert "plan_id" in result
        assert "event_id" in result
        assert "dispatches" in result
        assert len(result["dispatches"]) == 2
        assert "notifications" in result
        assert result["notifications"]["total_users"] == 5
        assert result["notifications"]["sos"] == 2
        assert result["notifications"]["high"] == 1
        assert result["notifications"]["med"] == 2
        assert result["routes_flagged"] >= 0
        assert "estimated_impact" in result
        assert result["estimated_impact"]["users_diverted"] == 1
        assert "summary_en" in result
        assert "summary_ur" in result
        assert "Estimates" in result["summary_en"]
        assert "تخمینہ" in result["summary_ur"]


# =============================================================================
# Test: Model validation
# =============================================================================


class TestModels:
    """Test Pydantic model construction."""

    def test_simulation_report_schema(self):
        """SimulationReport matches spec schema."""
        report = SimulationReport(
            report_id="simrpt_abc123",
            plan_id="plan_001",
            event_id="evt_001",
            executed_at="2025-09-01T12:00:00Z",
            dispatches=[
                DispatchRecord(
                    authority="PDMA-Punjab",
                    ticket_id="PDMA-123",
                    endpoint="http://mock/pdma",
                    payload_summary="test dispatch",
                ),
            ],
            notifications_queued=NotificationCounts(
                sos=2, high=1, med=2, low=0, total_users=5
            ),
            routes_flagged=3,
            estimated_impact=EstimatedImpact(
                congestion_reduction_min=6.6,
                users_diverted=1,
                response_time_saved_min=8.0,
            ),
            summary_en="5 users alerted...",
            summary_ur="5 صارفین...",
        )

        data = report.model_dump()
        assert data["report_id"] == "simrpt_abc123"
        assert data["plan_id"] == "plan_001"
        assert data["dispatches"][0]["authority"] == "PDMA-Punjab"
        assert data["notifications_queued"]["sos"] == 2
        assert data["estimated_impact"]["users_diverted"] == 1

    def test_push_queue_entry(self):
        """PushQueueEntry has all required fields."""
        entry = PushQueueEntry(
            user_id="u_001",
            event_id="evt_001",
            plan_id="plan_001",
            verb="EVACUATE",
            urgency="sos",
            message_en="EVACUATE now.",
            message_ur="فوری نکلیں۔",
        )
        assert entry.verb == "EVACUATE"
        assert entry.urgency == "sos"

    def test_simulation_request(self):
        """SimulationRequest parses correctly."""
        req = SimulationRequest(plan_id="plan_001", dry_run=True)
        assert req.plan_id == "plan_001"
        assert req.dry_run is True
