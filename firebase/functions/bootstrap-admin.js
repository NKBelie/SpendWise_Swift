import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
const [projectID, uid] = process.argv.slice(2);
if (!projectID || !uid || uid.includes('/')) throw new Error('Usage: node bootstrap-admin.js PROJECT_ID EXISTING_UID');
initializeApp({ credential: applicationDefault(), projectId: projectID });
const user = await getAuth().getUser(uid);
const db = getFirestore();
await db.runTransaction(async tx => {
  const profileRef = db.doc(`users/${uid}`), accessRef = db.doc(`access/${uid}`);
  const profile = await tx.get(profileRef);
  if (!profile.exists) throw new Error('Sign in once to initialize this account before bootstrapping.');
  tx.set(accessRef, { id: uid, role: 'ADMIN', status: 'ACTIVE' });
  tx.update(profileRef, { role: 'ADMIN', status: 'ACTIVE' });
  const audit = db.collection('audit').doc();
  tx.set(audit, { id: audit.id, actorId: 'trusted-bootstrap', targetId: uid, action: 'admin.bootstrap', createdAt: Math.floor(Date.now() / 1000) });
});
console.log(`Administrator access initialized for ${user.uid} in ${projectID}.`);
