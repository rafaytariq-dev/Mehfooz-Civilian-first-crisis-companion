import * as admin from 'firebase-admin';

admin.initializeApp();

// Mock dispatch endpoints (M5 simulation targets)
export { mockPdmaDispatch, mockRescue1122, mockTrafficReroute, mockSmsBlast } from './mock_endpoints';

// Report ingestion trigger (M2)
export { onReportCreated } from './report_trigger';

// Voice report processing (M8 — STT + Gemini normalization)
export { onVoiceReportCreated } from './voice_processor';

// Underpass Flood Radar (M9)
export { underpassRadar } from './underpass_radar';
