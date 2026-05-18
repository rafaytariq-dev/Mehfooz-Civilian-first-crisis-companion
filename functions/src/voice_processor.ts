/**
 * M8 — Voice Report Processing Cloud Function.
 *
 * Triggered by Firestore onDocumentWritten on reports/{reportId}.
 * When a report with voice_url but no text_normalized is detected:
 *
 * 1. Download audio from Firebase Storage
 * 2. Call Google Cloud Speech-to-Text (ur-PK + en-US + en-PK)
 * 3. Call Gemini Flash to normalize: detect language, translate to English,
 *    extract crisis_type, severity, location hints
 * 4. Update the report doc with all extracted fields
 *
 * Architecture: Option B (Two-stage) per CIRO spec.
 * Option A (Gemini Live) is layered on the Flutter side.
 */

import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';

const db = getFirestore();

// ─── Environment config ───
const GEMINI_API_KEY = process.env.GEMINI_API_KEY || '';
const GEMINI_FLASH_MODEL = process.env.GEMINI_FLASH_MODEL || 'gemini-2.5-flash';
const GEMINI_API_URL = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_FLASH_MODEL}:generateContent`;

// ─── Crisis taxonomy (from GEMINI.md) ───
const CRISIS_TYPES = [
  'flood', 'urban_flood', 'flash_flood', 'heatwave', 'road_incident',
  'fire', 'building_collapse', 'power_outage', 'air_quality', 'glof',
];

// ─── Normalization prompt (Gemini Flash) ───
const NORMALIZATION_PROMPT = `You are a crisis report normalizer for Mehfooz, a civilian crisis companion for Pakistan.

Given a transcribed voice report (which may be in Urdu, Roman Urdu, English, or code-mixed), extract:

1. **text_normalized**: English translation of the report (clear, concise)
2. **language_detected**: One of "ur" (Urdu script), "roman_ur" (Roman Urdu), "en" (English), "code_mixed"
3. **crisis_type_inferred**: One of: ${CRISIS_TYPES.join(', ')}
4. **severity_user**: Integer 1-5 based on this rubric:
   - 1: Minor disruption (light water on road, passable)
   - 2: Localized issue (ankle-deep water, slow traffic)
   - 3: Significant (knee-deep water, vehicles stuck)
   - 4: Severe (roads impassable, evacuation advised)
   - 5: Life-threatening (rapid water rise, rescue needed)
5. **location_hints**: Any location names mentioned (sector names, road names, landmarks)

Respond ONLY with valid JSON, no markdown, no explanation:
{
  "text_normalized": "...",
  "language_detected": "...",
  "crisis_type_inferred": "...",
  "severity_user": N,
  "location_hints": ["..."]
}`;

/**
 * Firestore trigger: process voice reports.
 * Fires on reports/{reportId} creation.
 * Only processes docs with voice_url but no text_normalized.
 */
export const onVoiceReportCreated = onDocumentCreated(
  {
    document: 'reports/{reportId}',
    region: 'asia-south1',
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) {
      logger.warn('onVoiceReportCreated fired with no data');
      return;
    }

    const reportId = event.params.reportId;

    // ─── Guard: only process voice reports ───
    if (!data.voice_url) {
      logger.info(`Report ${reportId} has no voice_url, skipping voice processing.`);
      return;
    }
    if (data.text_normalized) {
      logger.info(`Report ${reportId} already normalized, skipping.`);
      return;
    }
    if (data._voice_processed) {
      logger.info(`Report ${reportId} already voice-processed, skipping.`);
      return;
    }

    logger.info(`Processing voice report ${reportId}`, {
      voice_url: data.voice_url,
      user_id: data.user_id,
    });

    const startTime = Date.now();

    try {
      // ─── Step 1: Download audio from Storage ───
      logger.info(`Step 1: Downloading audio for report ${reportId}`);

      const audioBuffer = await downloadAudioFromStorage(data.voice_url);
      if (!audioBuffer) {
        logger.error(`Failed to download audio for report ${reportId}`);
        await markProcessingError(reportId, 'Failed to download audio');
        return;
      }

      logger.info(`Audio downloaded: ${audioBuffer.byteLength} bytes`);

      // ─── Step 2: Speech-to-Text ───
      logger.info(`Step 2: Running STT for report ${reportId}`);

      const transcript = await speechToText(audioBuffer);
      if (!transcript) {
        logger.warn(`STT returned empty transcript for report ${reportId}`);
        await markProcessingError(reportId, 'Speech-to-text returned empty result');
        return;
      }

      logger.info(`STT result: "${transcript.substring(0, 100)}..."`);

      // ─── Step 3: Gemini normalization ───
      logger.info(`Step 3: Normalizing via Gemini for report ${reportId}`);

      const normalized = await normalizeWithGemini(transcript);

      // ─── Step 4: Update Firestore doc ───
      logger.info(`Step 4: Updating report ${reportId}`);

      const processingDurationMs = Date.now() - startTime;

      await event.data!.ref.update({
        text_raw: transcript,
        text_normalized: normalized.text_normalized || transcript,
        language_detected: normalized.language_detected || 'unknown',
        crisis_type_inferred: normalized.crisis_type_inferred || null,
        severity_user: normalized.severity_user || null,
        _voice_processed: true,
        _voice_processed_at: FieldValue.serverTimestamp(),
        _voice_processing_duration_ms: processingDurationMs,
        _location_hints: normalized.location_hints || [],
      });

      logger.info(
        `Voice report ${reportId} processed successfully in ${processingDurationMs}ms`,
        {
          language: normalized.language_detected,
          crisis_type: normalized.crisis_type_inferred,
          severity: normalized.severity_user,
          duration_ms: processingDurationMs,
        }
      );

      // ─── Write processing trace ───
      await db.collection('agent_traces').add({
        agent: 'voice_processor',
        step: 'voice_report_processing',
        input_summary: `Voice report ${reportId}: "${transcript.substring(0, 80)}..."`,
        output_summary: `Normalized: lang=${normalized.language_detected}, crisis=${normalized.crisis_type_inferred}, severity=${normalized.severity_user}`,
        reasoning: `Two-stage pipeline: STT (ur-PK + en) → Gemini Flash normalization. Processing time: ${processingDurationMs}ms.`,
        tools_called: [
          { name: 'speech_to_text', args: { language: 'ur-PK,en-US,en-PK' }, result: { transcript_length: transcript.length } },
          { name: 'gemini_normalize', args: { model: GEMINI_FLASH_MODEL }, result: normalized },
        ],
        duration_ms: processingDurationMs,
        created_at: FieldValue.serverTimestamp(),
      });
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(`Voice processing failed for report ${reportId}: ${errorMsg}`, { error });
      await markProcessingError(reportId, errorMsg);
    }
  }
);

/**
 * Download audio file from Firebase Storage URL.
 */
async function downloadAudioFromStorage(voiceUrl: string): Promise<Buffer | null> {
  try {
    // Extract bucket and path from the download URL
    // URL format: https://firebasestorage.googleapis.com/v0/b/{bucket}/o/{path}?...
    const url = new URL(voiceUrl);

    // Use fetch to download the audio directly from the URL
    const response = await fetch(voiceUrl);
    if (!response.ok) {
      logger.error(`Download failed: HTTP ${response.status}`);
      return null;
    }

    const arrayBuffer = await response.arrayBuffer();
    return Buffer.from(arrayBuffer);
  } catch (error) {
    logger.error('Failed to download audio from Storage', { error, voiceUrl });
    return null;
  }
}

/**
 * Google Cloud Speech-to-Text.
 *
 * Uses ur-PK as primary language with en-US and en-PK as alternates
 * for code-mixed input.
 */
async function speechToText(audioBuffer: Buffer): Promise<string | null> {
  try {
    // Use the REST API for Speech-to-Text v2
    const STT_API_KEY = process.env.GOOGLE_STT_API_KEY || GEMINI_API_KEY;
    const STT_URL = `https://speech.googleapis.com/v1/speech:recognize?key=${STT_API_KEY}`;

    const requestBody = {
      config: {
        encoding: 'MP4' as const,
        sampleRateHertz: 16000,
        languageCode: 'ur-PK',
        alternativeLanguageCodes: ['en-US', 'en-PK'],
        model: 'latest_long',
        enableAutomaticPunctuation: true,
        enableWordTimeOffsets: false,
      },
      audio: {
        content: audioBuffer.toString('base64'),
      },
    };

    const response = await fetch(STT_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(requestBody),
    });

    if (!response.ok) {
      const errorText = await response.text();
      logger.error(`STT API error: ${response.status}`, { error: errorText });

      // Fallback: use Gemini to transcribe (it handles audio natively)
      logger.info('Falling back to Gemini for transcription');
      return await transcribeWithGemini(audioBuffer);
    }

    const result = await response.json() as any;

    if (!result.results || result.results.length === 0) {
      logger.warn('STT returned no results');
      return null;
    }

    const transcript = result.results
      .map((r: any) => r.alternatives?.[0]?.transcript || '')
      .join(' ')
      .trim();

    return transcript || null;
  } catch (error) {
    logger.error('Speech-to-Text failed', { error });

    // Fallback to Gemini
    logger.info('Falling back to Gemini for transcription');
    return await transcribeWithGemini(audioBuffer);
  }
}

/**
 * Fallback: use Gemini to transcribe audio directly.
 * Gemini 2.5 has native audio understanding capabilities.
 */
async function transcribeWithGemini(audioBuffer: Buffer): Promise<string | null> {
  try {
    if (!GEMINI_API_KEY) {
      logger.error('GEMINI_API_KEY not set, cannot transcribe');
      return null;
    }

    const response = await fetch(`${GEMINI_API_URL}?key=${GEMINI_API_KEY}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [
          {
            parts: [
              {
                inlineData: {
                  mimeType: 'audio/mp4',
                  data: audioBuffer.toString('base64'),
                },
              },
              {
                text: 'Transcribe this audio exactly as spoken. The speaker may use Urdu, Roman Urdu (Urdu written in Latin script), English, or a mix. Output ONLY the transcription, nothing else.',
              },
            ],
          },
        ],
        generationConfig: {
          temperature: 0.1,
          maxOutputTokens: 500,
        },
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      logger.error(`Gemini transcription failed: ${response.status}`, { error: errorText });
      return null;
    }

    const result = await response.json() as any;
    return result.candidates?.[0]?.content?.parts?.[0]?.text?.trim() || null;
  } catch (error) {
    logger.error('Gemini transcription fallback failed', { error });
    return null;
  }
}

/**
 * Normalize transcript with Gemini Flash.
 *
 * Extracts: text_normalized, language_detected, crisis_type_inferred,
 * severity_user, location_hints.
 */
async function normalizeWithGemini(transcript: string): Promise<{
  text_normalized: string;
  language_detected: string;
  crisis_type_inferred: string | null;
  severity_user: number | null;
  location_hints: string[];
}> {
  const defaultResult = {
    text_normalized: transcript,
    language_detected: 'unknown',
    crisis_type_inferred: null,
    severity_user: null,
    location_hints: [],
  };

  if (!GEMINI_API_KEY) {
    logger.warn('GEMINI_API_KEY not set, returning raw transcript');
    return defaultResult;
  }

  try {
    const response = await fetch(`${GEMINI_API_URL}?key=${GEMINI_API_KEY}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [
          {
            parts: [
              { text: `${NORMALIZATION_PROMPT}\n\nTranscript to normalize:\n"${transcript}"` },
            ],
          },
        ],
        generationConfig: {
          temperature: 0.2,
          maxOutputTokens: 500,
          responseMimeType: 'application/json',
        },
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      logger.error(`Gemini normalization failed: ${response.status}`, { error: errorText });
      return defaultResult;
    }

    const result = await response.json() as any;
    const text = result.candidates?.[0]?.content?.parts?.[0]?.text?.trim();

    if (!text) {
      logger.warn('Gemini returned empty normalization');
      return defaultResult;
    }

    // Parse JSON response
    const parsed = JSON.parse(text);

    // Validate crisis_type
    if (parsed.crisis_type_inferred &&
        !CRISIS_TYPES.includes(parsed.crisis_type_inferred)) {
      logger.warn(`Invalid crisis_type: ${parsed.crisis_type_inferred}, defaulting to urban_flood`);
      parsed.crisis_type_inferred = 'urban_flood';
    }

    // Validate severity
    if (parsed.severity_user !== null &&
        (parsed.severity_user < 1 || parsed.severity_user > 5)) {
      parsed.severity_user = Math.max(1, Math.min(5, parsed.severity_user));
    }

    return {
      text_normalized: parsed.text_normalized || transcript,
      language_detected: parsed.language_detected || 'unknown',
      crisis_type_inferred: parsed.crisis_type_inferred || null,
      severity_user: parsed.severity_user || null,
      location_hints: parsed.location_hints || [],
    };
  } catch (error) {
    logger.error('Gemini normalization failed', { error });
    return defaultResult;
  }
}

/**
 * Mark a report as having a processing error.
 */
async function markProcessingError(reportId: string, errorMessage: string): Promise<void> {
  try {
    await db.collection('reports').doc(reportId).update({
      _voice_processed: true,
      _voice_processing_error: errorMessage,
      _voice_processed_at: FieldValue.serverTimestamp(),
    });
  } catch (e) {
    logger.error(`Failed to mark processing error on report ${reportId}`, { error: e });
  }
}
