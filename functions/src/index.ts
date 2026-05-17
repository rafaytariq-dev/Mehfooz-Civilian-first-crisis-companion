import * as admin from 'firebase-admin';

admin.initializeApp();

// Mock dispatch endpoints (M5 simulation targets)
export { mockPdmaDispatch, mockRescue1122, mockTrafficReroute, mockSmsBlast } from './mock_endpoints';

// Report ingestion trigger (M2)
export { onReportCreated } from './report_trigger';
