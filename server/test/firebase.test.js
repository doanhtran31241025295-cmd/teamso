import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
// Tests use unique records in the LOCAL emulator and clean up only those records. No cloud calls.
process.env.USE_FIREBASE_EMULATORS = 'true';
process.env.FIREBASE_PROJECT_ID = 'demo-teamup-local';
process.env.FIREBASE_WEB_API_KEY = 'demo-test-key';
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
const { createApp } = await import('../src/app.js');
const { db, auth } = await import('../src/firebase/client.js');
const app = createApp();
const username = `test_${Date.now()}`;
const account = { username, email: `${username}@example.com`, password: 'Test-pass-123', displayName: 'Firebase Nghi', major: 'Flutter', phone: '0912345678' };
let credentials;
let projectId;
let taskId;
let outsiderUsername;
let outsiderCredentials;
const workspaceRecords = { documents: [], meetings: [], votes: [] };
before(async () => { await db.collection('_test').limit(1).get(); });
after(async () => {
  if (projectId) {
    for (const [kind, ids] of Object.entries(workspaceRecords)) {
      await Promise.all(ids.map(id =>
        db.collection('projects').doc(projectId).collection(`workspace_${kind}`).doc(id).delete(),
      ));
    }
  }
  if (taskId) await db.collection('tasks').doc(taskId).delete();
  if (projectId) await db.collection('projects').doc(projectId).delete();
  if (outsiderUsername) {
    const outsiderMapping = await db.collection('usernames').doc(outsiderUsername).get();
    if (outsiderMapping.data()?.uid) {
      const uid = outsiderMapping.data().uid;
      await auth.deleteUser(uid);
      await db.collection('users').doc(uid).delete();
    }
    await outsiderMapping.ref.delete();
  }
  const mapping = await db.collection('usernames').doc(username).get();
  if (mapping.data()?.uid) { const uid = mapping.data().uid; await auth.deleteUser(uid); await db.collection('users').doc(uid).delete(); }
  await mapping.ref.delete();
  await db.terminate();
});
const bearer = token => `Bearer ${token}`;
test('signup uses Firebase Auth and writes profile without hashPassword; duplicates and injection are rejected', async () => {
  await request(app).post('/api/auth/signup').send({ ...account, password: 'short' }).expect(400);
  await request(app).post('/api/auth/signup').send({ ...account, username: { $ne: null } }).expect(400);
  await request(app).post('/api/auth/signup').send(account).expect(201);
  await request(app).post('/api/auth/signup').send(account).expect(409);
  const mapping = (await db.collection('usernames').doc(username).get()).data();
  const profile = (await db.collection('users').doc(mapping.uid).get()).data();
  assert.equal(profile.hashPassword, undefined);
  assert.equal((await auth.getUser(mapping.uid)).email, account.email);
});
test('signin returns Firebase tokens and protected profile updates preserve whitelist', async () => {
  await request(app).post('/api/auth/signin').send({ username, password: 'wrong-pass-123' }).expect(401);
  credentials = (await request(app).post('/api/auth/signin').send({ username, password: account.password }).expect(200)).body;
  const claims = await auth.verifyIdToken(credentials.accessToken);
  assert.equal(claims.aud, 'demo-teamup-local'); assert.equal(claims.uid, credentials.user.id);
  assert.equal(claims.exp - claims.iat, 3600);
  await request(app).get('/api/users/me').expect(401);
  await request(app).put('/api/users/profile').set('Authorization', bearer(credentials.accessToken)).send({ username: 'hacked' }).expect(400);
  await request(app).put('/api/users/profile').set('Authorization', bearer(credentials.accessToken)).send({ bio: 'x'.repeat(501) }).expect(400);
  const saved = await request(app).put('/api/users/profile').set('Authorization', bearer(credentials.accessToken)).send({ displayName: 'Updated Firebase', bio: 'Firestore profile' }).expect(200);
  assert.equal(saved.body.user.displayName, 'Updated Firebase');
});
test('projects and task routes enforce membership and support task workflow', async () => {
  const headers = { Authorization: bearer(credentials.accessToken) };
  const project = await request(app).post('/api/projects').set(headers).send({ name: 'API test project', description: 'temporary', rules: 'Review before merging.' }).expect(201);
  projectId = project.body.project.id;
  assert.equal(project.body.project.leaderId, credentials.user.id);
  assert.equal(project.body.project.rules, 'Review before merging.');
  const listed = await request(app).get('/api/projects').set(headers).expect(200);
  assert.ok(listed.body.projects.some(item => item.id === projectId));
  await request(app).get(`/api/projects/${projectId}`).set(headers).expect(200);

  outsiderUsername = `outsider_${Date.now()}`;
  const outsider = { username: outsiderUsername, email: `${outsiderUsername}@example.com`, password: 'Test-pass-123', displayName: 'Outsider' };
  await request(app).post('/api/auth/signup').send(outsider).expect(201);
  outsiderCredentials = (await request(app).post('/api/auth/signin').send({ username: outsiderUsername, password: outsider.password }).expect(200)).body;
  const addedMember = await request(app).post(`/api/projects/${projectId}/members`).set(headers).send({ username: outsiderUsername }).expect(201);
  assert.ok(addedMember.body.project.memberIds.includes(outsiderCredentials.user.id));
  assert.equal(addedMember.body.project.members[1].role, 'Member');
  await request(app).post(`/api/projects/${projectId}/members`).set(headers).send({ username: outsiderUsername }).expect(200);
  const outsiderHeaders = { Authorization: bearer(outsiderCredentials.accessToken) };
  await request(app).get(`/api/projects/${projectId}`).set(outsiderHeaders).expect(200);
  await request(app).post(`/api/projects/${projectId}/members`).set(outsiderHeaders).send({ username }).expect(403);
  await request(app).post(`/api/projects/${projectId}/tasks`).set(outsiderHeaders).send({ title: 'Forbidden task', assigneeId: outsiderCredentials.user.id }).expect(403);
  const task = await request(app).post(`/api/projects/${projectId}/tasks`).set(headers).send({
    title: 'API test task', assigneeId: outsiderCredentials.user.id, priority: 'high', outputType: 'docs', outputRequired: true,
  }).expect(201);
  taskId = task.body.task.id;
  assert.equal(task.body.task.status, 'Cần làm');
  assert.equal(task.body.task.priority, 'Cao');
  const tasks = await request(app).get(`/api/projects/${projectId}/tasks`).set(headers).expect(200);
  assert.ok(tasks.body.tasks.some(item => item.id === taskId));

  const initialDueDate = new Date(Date.now() + 2 * 86400000).toISOString();
  const edited = await request(app).patch(`/api/tasks/${taskId}`).set(headers).send({ description: 'Updated description', dueDate: initialDueDate }).expect(200);
  assert.equal(edited.body.task.description, 'Updated description');
  await request(app).patch(`/api/tasks/${taskId}`).set(outsiderHeaders).send({ title: 'Unauthorized edit' }).expect(403);
  const requestedDueDate = new Date(Date.parse(initialDueDate) + 86400000).toISOString();
  const deadlineRequest = await request(app).post(`/api/tasks/${taskId}/deadline-requests`).set(outsiderHeaders).send({ requestedDueDate, reason: 'Waiting for research data.' }).expect(201);
  assert.equal(deadlineRequest.body.task.deadlineRequest.status, 'pending');
  await request(app).post(`/api/tasks/${taskId}/deadline-requests`).set(outsiderHeaders).send({ requestedDueDate, reason: 'Duplicate request.' }).expect(409);
  const approvedDeadline = await request(app).post(`/api/tasks/${taskId}/deadline-requests/approve`).set(headers).send({}).expect(200);
  assert.equal(approvedDeadline.body.task.dueDate, requestedDueDate);
  assert.equal(approvedDeadline.body.task.deadlineRequest.status, 'approved');
  const secondRequestDate = new Date(Date.parse(requestedDueDate) + 86400000).toISOString();
  await request(app).post(`/api/tasks/${taskId}/deadline-requests`).set(outsiderHeaders).send({ requestedDueDate: secondRequestDate, reason: 'Need another day.' }).expect(201);
  await request(app).post(`/api/tasks/${taskId}/deadline-requests/reject`).set(headers).send({}).expect(200);
  const taskAfterRejection = (await db.collection('tasks').doc(taskId).get()).data();
  assert.equal(taskAfterRejection.deadlineRequest.status, 'rejected');
  assert.equal(taskAfterRejection.dueDate, requestedDueDate);

  await request(app).patch(`/api/tasks/${taskId}/start`).set(outsiderHeaders).send({}).expect(200);
  const submitted = await request(app).post(`/api/tasks/${taskId}/submit`).set(outsiderHeaders).send({ outputLink: 'https://example.com/result' }).expect(200);
  assert.equal(submitted.body.task.status, 'Chờ duyệt');
  const changes = await request(app).post(`/api/tasks/${taskId}/request-changes`).set(headers).send({ comment: 'Please revise' }).expect(200);
  assert.equal(changes.body.task.status, 'Cần sửa');
  assert.equal(typeof changes.body.task.reviewedAt, 'string');
  await request(app).patch(`/api/tasks/${taskId}/start`).set(outsiderHeaders).send({}).expect(200);
  await request(app).post(`/api/tasks/${taskId}/submit`).set(outsiderHeaders).send({ outputLink: 'https://example.com/result' }).expect(200);
  const approved = await request(app).post(`/api/tasks/${taskId}/approve`).set(headers).send({}).expect(200);
  assert.equal(approved.body.task.status, 'Hoàn thành');
  assert.equal(typeof approved.body.task.reviewedAt, 'string');
  await request(app).get(`/api/projects/${projectId}`).expect(401);
});
test('workspace APIs persist project documents, meetings, and one vote per member', async () => {
  const headers = { Authorization: bearer(credentials.accessToken) };
  const outsiderHeaders = { Authorization: bearer(outsiderCredentials.accessToken) };
  const base = `/api/projects/${projectId}/workspace`;

  await request(app).get(base).expect(401);
  const initial = await request(app).get(base).set(headers).expect(200);
  assert.deepEqual(initial.body.documents, []);
  assert.deepEqual(initial.body.meetings, []);
  assert.deepEqual(initial.body.votes, []);

  const document = await request(app).post(`${base}/documents`).set(headers).send({
    title: 'Meeting notes',
  }).expect(201);
  workspaceRecords.documents.push(document.body.document.id);
  assert.equal(document.body.document.title, 'Meeting notes');
  await request(app).delete(`${base}/documents/${document.body.document.id}`).set(outsiderHeaders).expect(403);

  const meeting = await request(app).post(`${base}/meetings`).set(outsiderHeaders).send({
    title: 'Friday, 19:00',
  }).expect(201);
  workspaceRecords.meetings.push(meeting.body.meeting.id);
  assert.equal(meeting.body.meeting.createdBy, outsiderCredentials.user.id);
  await request(app).delete(`${base}/meetings/${meeting.body.meeting.id}`).set(headers).expect(200);

  const invalidVote = await request(app).post(`${base}/votes`).set(headers).send({
    question: 'When should we meet?',
    options: ['Friday', 'Friday'],
  }).expect(400);
  assert.equal(invalidVote.body.code, 'VALIDATION_ERROR');
  const vote = await request(app).post(`${base}/votes`).set(headers).send({
    question: 'When should we meet?',
    options: ['Friday', 'Saturday'],
  }).expect(201);
  workspaceRecords.votes.push(vote.body.vote.id);
  assert.deepEqual(vote.body.vote.voteCounts, [0, 0]);

  await request(app).post(`${base}/votes/${vote.body.vote.id}/vote`).set(outsiderHeaders).send({
    optionIndex: 1,
  }).expect(200);
  await request(app).post(`${base}/votes/${vote.body.vote.id}/vote`).set(outsiderHeaders).send({
    optionIndex: 0,
  }).expect(409);

  const asMember = await request(app).get(base).set(outsiderHeaders).expect(200);
  const memberVote = asMember.body.votes.find(item => item.id === vote.body.vote.id);
  assert.deepEqual(memberVote.voteCounts, [0, 1]);
  assert.equal(memberVote.selectedOption, 1);
  assert.equal(Object.hasOwn(memberVote, 'voters'), false);

  const asLeader = await request(app).get(base).set(headers).expect(200);
  const leaderVote = asLeader.body.votes.find(item => item.id === vote.body.vote.id);
  assert.equal(leaderVote.selectedOption, null);
});
test('Firebase refresh returns token pair; signout revokes refresh and invalid tokens do not authenticate', async () => {
  const refresh = (await request(app).post('/api/auth/refresh').send({ refreshToken: credentials.refreshToken }).expect(200)).body;
  assert.ok(refresh.accessToken && refresh.refreshToken);
  await request(app).post('/api/auth/refresh').send({ refreshToken: 'invalid' }).expect(401);
  // Firebase revocation timestamps have one-second precision.
  await new Promise(resolve => setTimeout(resolve, 1100));
  await request(app).post('/api/auth/signout').send({ refreshToken: refresh.refreshToken }).expect(200);
  await request(app).post('/api/auth/refresh').send({ refreshToken: refresh.refreshToken }).expect(401);
  await request(app).get('/api/users/me').set('Authorization', bearer(refresh.accessToken)).expect(401);
});
test('change password verifies old password and requires a fresh login', async () => {
  const signed = (await request(app).post('/api/auth/signin').send({ username, password: account.password }).expect(200)).body;
  await request(app).put('/api/users/change-password').set('Authorization', bearer(signed.accessToken)).send({ currentPassword: 'wrong-pass-123', newPassword: 'New-pass-456' }).expect(400);
  await new Promise(resolve => setTimeout(resolve, 1100));
  await request(app).put('/api/users/change-password').set('Authorization', bearer(signed.accessToken)).send({ currentPassword: account.password, newPassword: 'New-pass-456' }).expect(200);
  await request(app).post('/api/auth/signin').send({ username, password: account.password }).expect(401);
  await request(app).post('/api/auth/signin').send({ username, password: 'New-pass-456' }).expect(200);
});
