/**
 * Firestore trigger: when a new report is created, POST to the
 * Ingestion Agent for normalization and photo verification.
 */
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions';

const INGESTION_AGENT_URL = process.env.INGESTION_AGENT_URL
  || 'http://localhost:8081';

export const onReportCreated = onDocumentCreated(
  {
    document: 'reports/{reportId}',
    region: 'asia-south1',
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) {
      logger.warn('onReportCreated fired with no data');
      return;
    }

    const reportId = event.params.reportId;

    // Skip if already normalized (idempotency guard)
    if (data.text_normalized && data._ingested_at) {
      logger.info(`Report ${reportId} already ingested, skipping.`);
      return;
    }

    const payload = {
      report_id: reportId,
      user_id: data.user_id || '',
      text_raw: data.text_raw || '',
      voice_url: data.voice_url || null,
      photo_urls: data.photo_urls || [],
      location: {
        latitude: data.location?.latitude || 0,
        longitude: data.location?.longitude || 0,
      },
      geo_accuracy_m: data.geo_accuracy_m || 50,
      crisis_type_user: data.crisis_type_user || null,
      severity_user: data.severity_user || null,
      created_at: data.created_at?.toDate?.()?.toISOString() || null,
    };

    logger.info(`Forwarding report ${reportId} to Ingestion Agent`, { payload });

    try {
      // In production, use authenticated Cloud Run invoke
      // For now, use a simple POST
      const response = await fetch(`${INGESTION_AGENT_URL}/ingest/report`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(payload),
      });

      if (!response.ok) {
        const errorText = await response.text();
        logger.error(
          `Ingestion Agent returned ${response.status} for report ${reportId}`,
          { error: errorText }
        );
        return;
      }

      const result = await response.json();
      logger.info(`Report ${reportId} ingested successfully`, { result });
    } catch (error) {
      logger.error(`Failed to call Ingestion Agent for report ${reportId}`, {
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }
);
