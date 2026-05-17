"""
Manual M3 Detection Check WITHOUT Firestore.

Run:
python manual_m3_check.py

This does not read or write Firestore.
It only tests M3 detection logic using local fake signals.
"""

from datetime import datetime, timezone

from cluster import cluster_signals
from models import NormalizedSignal
from agent import (
    calculate_severity,
    calculate_confidence,
    build_contributing_signals,
    build_explanations,
)
from models import HistoricalPrior


def main():
    now = datetime.now(timezone.utc)

    signals = [
        # Citizen report 1
        NormalizedSignal(
            signal_id="report_1",
            source_collection="reports",
            modality="citizen_report",
            lat=33.6920,
            lon=72.0130,
            timestamp=now,
            city="Islamabad",
            crisis_type="urban_flood",
            severity=3,
            text="G-10 mein paani bhar gaya, gaariyan phans gayi hain",
            confidence=0.65,
        ),

        # Citizen report 2
        NormalizedSignal(
            signal_id="report_2",
            source_collection="reports",
            modality="citizen_report",
            lat=33.6922,
            lon=72.0131,
            timestamp=now,
            city="Islamabad",
            crisis_type="urban_flood",
            severity=3,
            text="Near G-10 Markaz water is knee deep",
            confidence=0.65,
        ),

        # Verified photo from report 2
        NormalizedSignal(
            signal_id="report_2:photo",
            source_collection="reports",
            modality="photo_verified",
            lat=33.6922,
            lon=72.0131,
            timestamp=now,
            city="Islamabad",
            crisis_type="urban_flood",
            severity=3,
            text="Verified flood photo evidence",
            confidence=0.87,
        ),

        # Weather signal
        NormalizedSignal(
            signal_id="weather_1",
            source_collection="signals_weather",
            modality="weather",
            lat=33.6921,
            lon=72.0131,
            timestamp=now,
            city="Islamabad",
            crisis_type="urban_flood",
            text="31mm rainfall in last hour",
            rainfall_mm_1h=31.0,
            rainfall_mm_24h=76.0,
            confidence=0.80,
        ),

        # Traffic signal
        NormalizedSignal(
            signal_id="traffic_1",
            source_collection="signals_traffic",
            modality="traffic",
            lat=33.6923,
            lon=72.0132,
            timestamp=now,
            city="Islamabad",
            crisis_type="urban_flood",
            text="Traffic delay is 3.5x near G-10",
            congestion_ratio=3.5,
            confidence=0.70,
        ),

        # Social signal
        NormalizedSignal(
            signal_id="social_1",
            source_collection="signals_social",
            modality="social",
            lat=33.6924,
            lon=72.0133,
            timestamp=now,
            city="Islamabad",
            crisis_type="urban_flood",
            text="G-10 Islamabad roads flooded badly after heavy rain.",
            confidence=0.55,
        ),
    ]

    print("\n========== M3 Manual Data Check ==========\n")

    print(f"Total local signals: {len(signals)}")

    clusters = cluster_signals(
        signals=signals,
        eps_km=0.5,
        min_samples=3,
        time_window_min=60,
    )

    print(f"Clusters found: {len(clusters)}")

    if not clusters:
        print("No cluster found.")
        return

    for index, cluster in enumerate(clusters, start=1):
        print(f"\n---------- Cluster {index} ----------")
        print(f"Cluster ID: {cluster.cluster_id}")
        print(f"Signal count: {len(cluster.signals)}")
        print(f"Modalities: {cluster.modalities}")
        print(f"Modality count: {cluster.modality_count}")
        print(f"Centroid: {cluster.centroid.latitude}, {cluster.centroid.longitude}")

        severity = calculate_severity(cluster)

        # Manual prior for local testing only.
        # This means we are pretending G-10 is flood-prone.
        prior = HistoricalPrior(
            is_flood_prone=True,
            matched_location_id="manual_g10_prior",
            matched_location_name="G-10/G-11 Low-Lying Road",
            threshold_mm_h=20,
            distance_m=120,
        )

        confidence = calculate_confidence(
            modality_count=cluster.modality_count,
            prior=prior,
            severity=severity,
        )

        status = "verified" if cluster.modality_count >= 2 else "candidate"

        explanation_en, explanation_ur = build_explanations(
            cluster=cluster,
            crisis_type="urban_flood",
            severity=severity,
            status=status,
            prior=prior,
        )

        contributing_signals = build_contributing_signals(cluster)

        print(f"Status: {status}")
        print(f"Severity: {severity}")
        print(f"Confidence: {confidence}")
        print(f"Explanation EN: {explanation_en}")
        print(f"Explanation UR: {explanation_ur}")
        print(f"Contributing signals: {contributing_signals}")

        print("\nExpected:")
        print("Status should be verified")
        print("Severity should be >= 3")
        print("Confidence should be >= 0.8")
        print("Modality count should be >= 2")

    print("\n========== Manual M3 Check Completed ✅ ==========\n")


if __name__ == "__main__":
    main()