"""Unit tests for M10 helpline resolver (local mode)."""

from helpline import resolve_helpline


def test_resolve_islamabad_flood():
    result = resolve_helpline(city="Islamabad", crisis_type="flood", use_firestore=False)
    assert result.get("name") == "CARES 1122 Islamabad"


def test_resolve_lahore_fire():
    result = resolve_helpline(city="Lahore", crisis_type="fire", use_firestore=False)
    assert result.get("name") == "Rescue 1122 Punjab"


def test_resolve_karachi_urban_flood():
    result = resolve_helpline(city="Karachi", crisis_type="urban_flood", use_firestore=False)
    assert result.get("name") == "Chhipa Emergency"


def test_resolve_unknown_fallback():
    result = resolve_helpline(city="Unknown", crisis_type="unknown", use_firestore=False)
    assert result.get("name") == "Edhi Foundation"


def test_resolve_city_specific_over_wildcard():
    result = resolve_helpline(city="Karachi", crisis_type="medical", use_firestore=False)
    assert result.get("name") == "Chhipa Emergency"
