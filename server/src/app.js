import { sendMessage, listenToMessages } from './firebase/messages.js';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { rateLimit } from 'express-rate-limit';
import { randomUUID } from 'node:crypto';
import { FieldValue } from 'firebase-admin/firestore';
import { auth, db, firebaseRest, profileFor, FirebaseRequestError } from './firebase/client.js';
import { validate, signupSchema, signinSchema, refreshSchema, profileSchema, changePasswordSchema } from './validation.js';
import { addProjectMember, approveTask, createProject, createTask, editTask, getProject, listProjects, listTasks, requestTaskChanges, requestTaskDeadline, reviewTaskDeadline, startTask, submitTask } from './projects.js';
import { createWorkspaceDocument, createWorkspaceMeeting, createWorkspaceVote, deleteWorkspaceDocument, deleteWorkspaceMeeting, getWorkspace, submitWorkspaceVote } from './workspace.js';

const fail = (status, message, code) => Object.assign(new Error(message), { status, code });
export function createApp() {
  const app = express();
  app.disable('x-powered-by'); app.use(helmet());
  app.use(cors({ origin(origin, cb) { cb(null, !origin || /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)); } }));
  app.use(express.json({ limit: '16kb' }));
  app.use('/api', (_req, res, next) => { res.set('Cache-Control', 'no-store'); next(); });
  app.use('/api/auth', rateLimit({ windowMs: 15 * 60 * 1000, limit: 100, standardHeaders: 'draft-8', legacyHeaders: false, handler: (_req, res) => res.status(429).json({ code: 'RATE_LIMIT', message: 'Quá nhiều yêu cầu. Vui lòng thử lại sau.' }) }));

  async function protectedRoute(req, _res, next) {
    const token = /^Bearer (\S+)$/.exec(req.get('Authorization') ?? '')?.[1];
    if (!token) throw fail(401, 'Vui lòng đăng nhập.', 'AUTH_REQUIRED');
    let decoded;
    try { decoded = await auth.verifyIdToken(token, true); }
    catch { throw fail(401, 'Phiên hết hạn. Vui lòng đăng nhập lại.', 'INVALID_ACCESS_TOKEN'); }
    req.uid = decoded.uid;
    req.user = await profileFor(decoded.uid);
    next();
  }
  const messageLimit = rateLimit({ windowMs: 60000, limit: 30, standardHeaders: 'draft-8', legacyHeaders: false,
    handler: (_req, res) => res.status(429).json({ code: 'RATE_LIMIT', message: 'Bạn gửi quá nhanh. Vui lòng chờ một chút.' }) });
  app.post('/api/messages', protectedRoute, messageLimit, async (req, res) => {
    const result = await sendMessage(req.body?.text, req.uid, req.user.displayName || req.user.username, req.user.avatarUrl);
    res.status(201).json(result);
  });
  app.get('/api/projects', protectedRoute, async (req, res) => {
    res.json({ projects: await listProjects(req.uid) });
  });
  app.post('/api/projects', protectedRoute, async (req, res) => {
    res.status(201).json({ project: await createProject(req.uid, req.user, req.body) });
  });
  app.post('/api/projects/:projectId/members', protectedRoute, async (req, res) => {
    const result = await addProjectMember(req.params.projectId, req.uid, req.body);
    res.status(result.added ? 201 : 200).json({ project: result.project });
  });
  app.get('/api/projects/:projectId', protectedRoute, async (req, res) => {
    res.json({ project: await getProject(req.params.projectId, req.uid) });
  });
  app.get('/api/projects/:projectId/tasks', protectedRoute, async (req, res) => {
    res.json({ tasks: await listTasks(req.params.projectId, req.uid) });
  });
  app.post('/api/projects/:projectId/tasks', protectedRoute, async (req, res) => {
    res.status(201).json({ task: await createTask(req.params.projectId, req.uid, req.body) });
  });
  app.get('/api/projects/:projectId/workspace', protectedRoute, async (req, res) => {
    res.json(await getWorkspace(req.params.projectId, req.uid));
  });
  app.post('/api/projects/:projectId/workspace/documents', protectedRoute, async (req, res) => {
    res.status(201).json({ document: await createWorkspaceDocument(req.params.projectId, req.uid, req.body) });
  });
  app.delete('/api/projects/:projectId/workspace/documents/:documentId', protectedRoute, async (req, res) => {
    res.json(await deleteWorkspaceDocument(req.params.projectId, req.uid, req.params.documentId));
  });
  app.post('/api/projects/:projectId/workspace/meetings', protectedRoute, async (req, res) => {
    res.status(201).json({ meeting: await createWorkspaceMeeting(req.params.projectId, req.uid, req.body) });
  });
  app.delete('/api/projects/:projectId/workspace/meetings/:meetingId', protectedRoute, async (req, res) => {
    res.json(await deleteWorkspaceMeeting(req.params.projectId, req.uid, req.params.meetingId));
  });
  app.post('/api/projects/:projectId/workspace/votes', protectedRoute, async (req, res) => {
    res.status(201).json({ vote: await createWorkspaceVote(req.params.projectId, req.uid, req.body) });
  });
  app.post('/api/projects/:projectId/workspace/votes/:voteId/vote', protectedRoute, async (req, res) => {
    res.json({ vote: await submitWorkspaceVote(req.params.projectId, req.uid, req.params.voteId, req.body) });
  });
  app.patch('/api/tasks/:taskId', protectedRoute, async (req, res) => {
    res.json({ task: await editTask(req.params.taskId, req.uid, req.body) });
  });
  app.patch('/api/tasks/:taskId/start', protectedRoute, async (req, res) => {
    res.json({ task: await startTask(req.params.taskId, req.uid) });
  });
  app.post('/api/tasks/:taskId/submit', protectedRoute, async (req, res) => {
    res.json({ task: await submitTask(req.params.taskId, req.uid, req.body) });
  });
  app.post('/api/tasks/:taskId/approve', protectedRoute, async (req, res) => {
    res.json({ task: await approveTask(req.params.taskId, req.uid) });
  });
  app.post('/api/tasks/:taskId/request-changes', protectedRoute, async (req, res) => {
    res.json({ task: await requestTaskChanges(req.params.taskId, req.uid, req.body) });
  });
  app.post('/api/tasks/:taskId/deadline-requests', protectedRoute, async (req, res) => {
    res.status(201).json({ task: await requestTaskDeadline(req.params.taskId, req.uid, req.body) });
  });
  app.post('/api/tasks/:taskId/deadline-requests/:decision', protectedRoute, async (req, res) => {
    if (!['approve', 'reject'].includes(req.params.decision)) throw fail(404, 'API không tồn tại.', 'NOT_FOUND');
    res.json({ task: await reviewTaskDeadline(req.params.taskId, req.uid, req.params.decision === 'approve') });
  });
  app.get('/api/messages/stream', protectedRoute, (req, res) => {
    res.set({ 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache, no-transform', 'X-Accel-Buffering': 'no' });
    res.flushHeaders();
    let unsubscribe = () => {};
    let closed = false;
    let heartbeat, renewal;
    function close() {
      if (closed) return;
      closed = true;
      clearInterval(heartbeat); clearTimeout(renewal); unsubscribe(); res.end();
    }
    res.on('close', close);
    const write = data => {
      if (!closed && !res.write(`data: ${JSON.stringify(data)}\n\n`)) close();
    };
    unsubscribe = listenToMessages(messages => write({ messages }), () => {
      write({ error: 'CHAT_UNAVAILABLE' }); close();
    });
    if (closed) { unsubscribe(); return; }
    heartbeat = setInterval(() => { if (!closed && !res.write(': heartbeat\n\n')) close(); }, 15000);
    // Reconnect with bearer verification, so revoked/expired sessions lose access.
    renewal = setTimeout(close, 60000);
  });

  app.get('/api/health', async (_req, res) => {
    await db.collection('_health').limit(1).get();
    res.json({ status: 'ok', authentication: 'Firebase Authentication', database: 'Cloud Firestore' });
  });
  app.post('/api/auth/signup', async (req, res) => {
    const data = validate(signupSchema, req);
    const reservation = db.collection('usernames').doc(data.username);
    const operationId = randomUUID();
    await db.runTransaction(async transaction => {
      if ((await transaction.get(reservation)).exists) throw fail(409, 'Tên đăng nhập đã được sử dụng.', 'DUPLICATE_USER');
      transaction.create(reservation, { operationId, createdAt: FieldValue.serverTimestamp() });
    });
    let uid;
    try {
      const record = await auth.createUser({ email: data.email, password: data.password, displayName: data.displayName });
      uid = record.uid;
      const batch = db.batch();
      batch.create(db.collection('users').doc(uid), { username: data.username, email: data.email, displayName: data.displayName,
        major: data.major ?? '', phone: data.phone ?? '', bio: '', avatarUrl: '',
        createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
      batch.set(reservation, { uid, email: data.email, createdAt: FieldValue.serverTimestamp() });
      await batch.commit();
    } catch (error) {
      if (uid) await auth.deleteUser(uid);
      await db.runTransaction(async transaction => {
        const claim = await transaction.get(reservation);
        if (claim.data()?.operationId === operationId) transaction.delete(reservation);
      });
      throw error;
    }
    res.status(201).json({ message: 'Đăng ký thành công. Bạn có thể đăng nhập.' });
  });
  app.post('/api/auth/signin', async (req, res) => {
    const data = validate(signinSchema, req);
    const mapping = (await db.collection('usernames').doc(data.username).get()).data();
    if (!mapping?.email) throw fail(401, 'Tên đăng nhập hoặc mật khẩu không đúng.', 'INVALID_CREDENTIALS');
    const tokens = await firebaseRest('accounts:signInWithPassword', { email: mapping.email, password: data.password, returnSecureToken: true });
    if (tokens.localId !== mapping.uid) throw fail(401, 'Thông tin tài khoản không hợp lệ.', 'INVALID_CREDENTIALS');
    await auth.verifyIdToken(tokens.idToken, true);
    res.json({ accessToken: tokens.idToken, refreshToken: tokens.refreshToken, user: await profileFor(tokens.localId) });
  });
  app.post('/api/auth/refresh', async (req, res) => {
    const data = validate(refreshSchema, req);
    const tokens = await firebaseRest('token', { grant_type: 'refresh_token', refresh_token: data.refreshToken }, { secureToken: true });
    await auth.verifyIdToken(tokens.id_token, true);
    await profileFor(tokens.user_id);
    res.json({ accessToken: tokens.id_token, refreshToken: tokens.refresh_token });
  });
  app.post('/api/auth/signout', async (req, res) => {
    const data = validate(refreshSchema, req);
    try {
      const tokens = await firebaseRest('token', { grant_type: 'refresh_token', refresh_token: data.refreshToken }, { secureToken: true });
      await auth.revokeRefreshTokens(tokens.user_id);
    } catch (error) { if (!(error instanceof FirebaseRequestError) || error.status !== 401) throw error; }
    res.json({ message: 'Đã đăng xuất và thu hồi phiên đăng nhập trên tất cả thiết bị.' });
  });
  app.get('/api/users/me', protectedRoute, (req, res) => res.json({ user: req.user }));
  app.put('/api/users/profile', protectedRoute, async (req, res) => {
    const fields = validate(profileSchema, req);
    // Profile is authoritative in Firestore. Never accept roles/username/email here.
    await db.collection('users').doc(req.uid).update({ ...fields, updatedAt: FieldValue.serverTimestamp() });
    res.json({ message: 'Đã lưu hồ sơ.', user: await profileFor(req.uid) });
  });
  app.put('/api/users/change-password', protectedRoute, async (req, res) => {
    const data = validate(changePasswordSchema, req);
    let verified;
    try { verified = await firebaseRest('accounts:signInWithPassword', { email: req.user.email, password: data.currentPassword, returnSecureToken: true }); }
    catch (error) { if (error.status === 401) throw fail(400, 'Mật khẩu hiện tại không đúng.', 'WRONG_PASSWORD'); throw error; }
    if (verified.localId !== req.uid) throw fail(401, 'Thông tin tài khoản không hợp lệ.', 'INVALID_CREDENTIALS');
    await auth.updateUser(req.uid, { password: data.newPassword });
    await auth.revokeRefreshTokens(req.uid);
    res.json({ message: 'Đã đổi mật khẩu. Vui lòng đăng nhập lại.' });
  });
  app.use((_req, res) => res.status(404).json({ code: 'NOT_FOUND', message: 'API không tồn tại.' }));
  app.use((error, _req, res, _next) => {
    if (['auth/email-already-exists', 'auth/uid-already-exists'].includes(error.code)) return res.status(409).json({ code: 'DUPLICATE_USER', message: 'Email đã được sử dụng.' });
    const tokenErrors = ['auth/id-token-revoked', 'auth/id-token-expired', 'auth/invalid-id-token', 'auth/user-disabled', 'auth/user-not-found'];
    const status = error.status || (tokenErrors.includes(error.code) ? 401 : error.code?.startsWith?.('auth/invalid-') ? 400 : 500);
    if (status >= 500) console.error('Firebase API error:', error.code ?? error.name);
    res.status(status).json({ code: typeof error.code === 'string' ? error.code : 'REQUEST_FAILED', message: status >= 500 ? 'Không kết nối được Firebase hoặc cấu hình Firebase chưa sẵn sàng.' : error.message });
  });
  return app;
}
