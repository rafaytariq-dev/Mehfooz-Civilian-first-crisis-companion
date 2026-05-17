/**
 * Firestore trigger: when a new report is created, POST to the
 * Orchestrator Agent to run the full chain:
 * ingestion → detection → planning → simulation → comms.
 *
 * Previously this triggered ingestion only; M6 moves ownership
 * of the full chain to the orchestrator.
 */
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions';

const ORCHESTRATOR_AGENT_URL = process.env.ORCHESTRATOR_AGENT_URL
  || 'http://localhost:8085';

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

    // Skip if already processed (idempotency guard)
    if (data._orchestrated_at) {
      logger.info(`Report ${reportId} already orchestrated, skipping.`);
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
      // Pass city if available for scoped detection
      city: data.city || null,
    };

    logger.info(`Forwarding report ${reportId} to Orchestrator Agent`, { payload });

    try {
      const response = await fetch(`${ORCHESTRATOR_AGENT_URL}/orchestrate/run`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(payload),
      });

      if (!response.ok) {
        const errorText = await response.text();
        logger.error(
          `Orchestrator Agent returned ${response.status} for report ${reportId}`,
          { error: errorText }
        );
        return;
      }

      const result = await response.json();
      logger.info(`Report ${reportId} orchestrated successfully`, {
        outcome: result.outcome,
        events: result.event_ids,
        notifications: result.notifications_sent,
      });
    } catch (error) {
      logger.error(`Failed to call Orchestrator Agent for report ${reportId}`, {
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }
);
