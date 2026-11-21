import { verifyCompanyCamKey } from './companycam.ts';

try {
  await verifyCompanyCamKey();
  console.log('CompanyCam accepted the application key. Test project creation and a photo upload next.');
} catch (error) {
  console.error(error instanceof Error ? error.message : 'CompanyCam key verification failed.');
  process.exitCode = 1;
}
