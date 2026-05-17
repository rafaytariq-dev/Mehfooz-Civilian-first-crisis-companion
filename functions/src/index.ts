import * as admin from 'firebase-admin';

admin.initializeApp();

export { mockPdmaDispatch, mockRescue1122, mockTrafficReroute, mockSmsBlast } from './mock_endpoints';
