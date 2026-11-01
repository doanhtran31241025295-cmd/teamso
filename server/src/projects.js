import { randomUUID } from 'node:crypto';
import { FieldValue } from 'firebase-admin/firestore';
import { z } from 'zod';
import { db } from './firebase/client.js';

const projectSchema = z.object({
  name: z.string().trim().min(1).max(120).optional(),
  title: z.string().trim().min(1).max(120).optional(),
  description: z.string().trim().max(4000).optional().default(''),
  rules: z.string().trim().max(4000).optional().default(''),
  tag: z.string().trim().max(80).optional().default(''),
}).strict().refine(value => value.name || value.title, 'Vui lòng nhập tên dự án.');
const projectMemberSchema = z.object({
  username: z.string().trim().toLowerCase().regex(/^[a-z0-9_]{3,30}$/),
}).strict();

const taskSchema = z.object({
  title: z.string().trim().min(1).max(160),
  description: z.string().trim().max(4000).optional().default(''),
  assigneeId: z.string().trim().min(1).max(128),
  priority: z.enum(['low', 'medium', 'high']).default('medium'),
  dueDate: z.union([z.string().datetime({ offset: true }), z.null()]).optional(),
  outputType: z.enum(['docs', 'drive', 'sheet', 'file', 'none']).default('docs'),
  outputRequired: z.boolean().default(true),
}).strict();

const taskUpdateSchema = taskSchema.partial().strict().refine(value => Object.keys(value).length > 0, 'Không có thông tin cần cập nhật.');
const submitSchema = z.object({ outputLink: z.string().trim().max(2048).optional().default('') }).strict();
const reviewSchema = z.object({ comment: z.string().trim().max(2000).optional().default('') }).strict();
const deadlineRequestSchema = z.object({
  requestedDueDate: z.string().datetime({ offset: true }),
  reason: z.string().trim().min(1).max(1000),
}).strict();
const priorityLabels = { low: 'Thấp', medium: 'Trung bình', high: 'Cao' };

function badRequest(schema, body) {
  const parsed = schema.safeParse(body ?? {});
  if (!parsed.success) {
    const error = new Error(parsed.error.issues[0]?.message ?? 'Dữ liệu không hợp lệ.');
    error.status = 400;
    error.code = 'VALIDATION_ERROR';
    throw error;
  }
  return parsed.data;
}

function httpError(status, message, code) {
  return Object.assign(new Error(message), { status, code });
}

function memberEntries(project) {
  return [...(Array.isArray(project.members) ? project.members : []), ...(Array.isArray(project.projectMembers) ? project.projectMembers : [])];
}

function memberId(member) {
  if (typeof member === 'string') return member;
  if (!member || typeof member !== 'object') return '';
  return member.id ?? member.userId ?? member.user_id ?? '';
}

function isProjectMember(project, userId) {
  return project.leaderId === userId || project.ownerId === userId ||
    (Array.isArray(project.memberIds) && project.memberIds.includes(userId)) ||
    memberEntries(project).some(member => memberId(member) === userId);
}

function isProjectLeader(project, userId) {
  return project.leaderId === userId || project.ownerId === userId ||
    memberEntries(project).some(member => memberId(member) === userId &&
      ['leader', 'owner', 'admin'].includes(String(member.role ?? '').toLowerCase()));
}

function serialize(doc) {
  const data = doc.data();
  const timestamp = value => value?.toDate instanceof Function ? value.toDate().toISOString() : value ?? null;
  return {
    ...data,
    id: doc.id,
    createdAt: timestamp(data.createdAt),
    updatedAt: timestamp(data.updatedAt),
  };
}

async function projectForUser(projectId, userId, { leader = false } = {}) {
  const snapshot = await db.collection('projects').doc(projectId).get();
  if (!snapshot.exists) throw httpError(404, 'Không tìm thấy dự án.', 'PROJECT_NOT_FOUND');
  const project = snapshot.data();
  if (!isProjectMember(project, userId)) throw httpError(403, 'Bạn không thuộc dự án này.', 'PROJECT_FORBIDDEN');
  if (leader && !isProjectLeader(project, userId)) throw httpError(403, 'Chỉ Leader của dự án mới được thực hiện thao tác này.', 'PROJECT_LEADER_REQUIRED');
  return { ref: snapshot.ref, project, snapshot };
}

export async function listProjects(userId) {
  const [memberProjects, ledProjects] = await Promise.all([
    db.collection('projects').where('memberIds', 'array-contains', userId).get(),
    db.collection('projects').where('leaderId', '==', userId).get(),
  ]);
  const docs = new Map([...memberProjects.docs, ...ledProjects.docs].map(doc => [doc.id, doc]));
  return [...docs.values()].filter(doc => isProjectMember(doc.data(), userId)).map(serialize);
}

export async function createProject(userId, user, body) {
  const data = badRequest(projectSchema, body);
  const id = randomUUID();
  const title = data.name ?? data.title;
  const ref = db.collection('projects').doc(id);
  const project = {
    name: title,
    title,
    description: data.description,
    rules: data.rules,
    tag: data.tag,
    leaderId: userId,
    ownerId: userId,
    memberIds: [userId],
    members: [{ id: userId, userId, displayName: user.displayName, username: user.username, avatarUrl: user.avatarUrl ?? '', role: 'Leader' }],
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
  await ref.create(project);
  return { ...project, id, createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() };
}

export async function addProjectMember(projectId, leaderId, body) {
  const { username } = badRequest(projectMemberSchema, body);
  const { ref, project, snapshot } = await projectForUser(projectId, leaderId, { leader: true });
  const mapping = await db.collection('usernames').doc(username).get();
  const userId = mapping.data()?.uid;
  if (!userId) throw httpError(404, 'Không tìm thấy tài khoản theo username.', 'USER_NOT_FOUND');
  if (isProjectMember(project, userId)) return { project: serialize(snapshot), added: false };
  const profileSnapshot = await db.collection('users').doc(userId).get();
  if (!profileSnapshot.exists) throw httpError(404, 'Không tìm thấy hồ sơ thành viên.', 'USER_NOT_FOUND');
  const profile = profileSnapshot.data();
  await ref.update({
    memberIds: FieldValue.arrayUnion(userId),
    members: FieldValue.arrayUnion({
      id: userId,
      userId,
      username: profile.username,
      displayName: profile.displayName,
      avatarUrl: profile.avatarUrl ?? '',
      role: 'Member',
    }),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return { project: await getProject(projectId, leaderId), added: true };
}

export async function getProject(projectId, userId) {
  const { snapshot } = await projectForUser(projectId, userId);
  return serialize(snapshot);
}

export async function listTasks(projectId, userId) {
  await projectForUser(projectId, userId);
  const snapshot = await db.collection('tasks').where('projectId', '==', projectId).get();
  return snapshot.docs.map(serialize).sort((a, b) => String(a.dueDate ?? '').localeCompare(String(b.dueDate ?? '')));
}

export async function createTask(projectId, userId, body) {
  const data = badRequest(taskSchema, body);
  const { project } = await projectForUser(projectId, userId, { leader: true });
  if (!isProjectMember(project, data.assigneeId)) throw httpError(400, 'Người thực hiện phải là thành viên dự án.', 'ASSIGNEE_NOT_IN_PROJECT');
  const id = randomUUID();
  const task = {
    ...data,
    priority: priorityLabels[data.priority],
    priorityCode: data.priority,
    projectId,
    status: 'Cần làm',
    createdBy: userId,
    outputLink: '',
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
  await db.collection('tasks').doc(id).create(task);
  return { ...task, id, createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() };
}

export async function editTask(taskId, userId, body) {
  const data = badRequest(taskUpdateSchema, body);
  const taskRef = db.collection('tasks').doc(taskId);
  return db.runTransaction(async transaction => {
    const taskSnapshot = await transaction.get(taskRef);
    if (!taskSnapshot.exists) throw httpError(404, 'Không tìm thấy công việc.', 'TASK_NOT_FOUND');
    const task = taskSnapshot.data();
    const projectRef = db.collection('projects').doc(task.projectId);
    const projectSnapshot = await transaction.get(projectRef);
    if (!projectSnapshot.exists) throw httpError(404, 'Không tìm thấy dự án.', 'PROJECT_NOT_FOUND');
    const project = projectSnapshot.data();
    if (!isProjectMember(project, userId)) throw httpError(403, 'Bạn không thuộc dự án này.', 'PROJECT_FORBIDDEN');
    if (!isProjectLeader(project, userId)) throw httpError(403, 'Chỉ Leader của dự án mới được sửa công việc.', 'PROJECT_LEADER_REQUIRED');
    if (data.assigneeId && !isProjectMember(project, data.assigneeId)) throw httpError(400, 'Người thực hiện phải là thành viên dự án.', 'ASSIGNEE_NOT_IN_PROJECT');
    const update = { ...data, updatedAt: FieldValue.serverTimestamp() };
    if (data.priority) {
      update.priorityCode = data.priority;
      update.priority = priorityLabels[data.priority];
    }
    transaction.update(taskRef, update);
    return { ...task, ...update, id: taskId, updatedAt: new Date().toISOString() };
  });
}

export async function requestTaskDeadline(taskId, userId, body) {
  const data = badRequest(deadlineRequestSchema, body);
  const taskRef = db.collection('tasks').doc(taskId);
  return db.runTransaction(async transaction => {
    const taskSnapshot = await transaction.get(taskRef);
    if (!taskSnapshot.exists) throw httpError(404, 'Không tìm thấy công việc.', 'TASK_NOT_FOUND');
    const task = taskSnapshot.data();
    const projectSnapshot = await transaction.get(db.collection('projects').doc(task.projectId));
    if (!projectSnapshot.exists) throw httpError(404, 'Không tìm thấy dự án.', 'PROJECT_NOT_FOUND');
    const project = projectSnapshot.data();
    if (!isProjectMember(project, userId)) throw httpError(403, 'Bạn không thuộc dự án này.', 'PROJECT_FORBIDDEN');
    if (!isProjectLeader(project, userId) && task.assigneeId !== userId) throw httpError(403, 'Chỉ người được giao việc mới có thể xin lùi deadline.', 'TASK_ASSIGNEE_REQUIRED');
    if (task.deadlineRequest?.status === 'pending') throw httpError(409, 'Đã có yêu cầu lùi deadline đang chờ duyệt.', 'DEADLINE_REQUEST_PENDING');
    const requestedDueDate = new Date(data.requestedDueDate);
    const currentDueDate = task.dueDate ? new Date(task.dueDate) : null;
    if (currentDueDate && requestedDueDate <= currentDueDate) throw httpError(400, 'Deadline mới phải sau deadline hiện tại.', 'INVALID_DEADLINE_EXTENSION');
    const now = new Date().toISOString();
    const deadlineRequest = {
      requestedDueDate: requestedDueDate.toISOString(),
      requestedBy: userId,
      reason: data.reason,
      status: 'pending',
      createdAt: FieldValue.serverTimestamp(),
    };
    transaction.update(taskRef, { deadlineRequest, updatedAt: FieldValue.serverTimestamp() });
    return { ...task, id: taskId, deadlineRequest: { ...deadlineRequest, createdAt: now }, updatedAt: now };
  });
}

export async function reviewTaskDeadline(taskId, userId, approve) {
  const taskRef = db.collection('tasks').doc(taskId);
  return db.runTransaction(async transaction => {
    const taskSnapshot = await transaction.get(taskRef);
    if (!taskSnapshot.exists) throw httpError(404, 'Không tìm thấy công việc.', 'TASK_NOT_FOUND');
    const task = taskSnapshot.data();
    const projectSnapshot = await transaction.get(db.collection('projects').doc(task.projectId));
    if (!projectSnapshot.exists) throw httpError(404, 'Không tìm thấy dự án.', 'PROJECT_NOT_FOUND');
    const project = projectSnapshot.data();
    if (!isProjectMember(project, userId)) throw httpError(403, 'Bạn không thuộc dự án này.', 'PROJECT_FORBIDDEN');
    if (!isProjectLeader(project, userId)) throw httpError(403, 'Chỉ Leader của dự án mới được duyệt deadline.', 'PROJECT_LEADER_REQUIRED');
    if (task.deadlineRequest?.status !== 'pending') throw httpError(409, 'Không có yêu cầu deadline đang chờ duyệt.', 'DEADLINE_REQUEST_NOT_PENDING');
    const now = new Date().toISOString();
    const deadlineRequest = { ...task.deadlineRequest, status: approve ? 'approved' : 'rejected', reviewedBy: userId, reviewedAt: FieldValue.serverTimestamp() };
    const update = {
      deadlineRequest,
      updatedAt: FieldValue.serverTimestamp(),
      ...(approve ? { dueDate: task.deadlineRequest.requestedDueDate } : {}),
    };
    transaction.update(taskRef, update);
    return {
      ...task,
      ...update,
      id: taskId,
      updatedAt: now,
      deadlineRequest: { ...deadlineRequest, reviewedAt: now },
    };
  });
}

async function updateTask(taskId, userId, action, body) {
  const taskRef = db.collection('tasks').doc(taskId);
  return db.runTransaction(async transaction => {
    const taskSnapshot = await transaction.get(taskRef);
    if (!taskSnapshot.exists) throw httpError(404, 'Không tìm thấy công việc.', 'TASK_NOT_FOUND');
    const task = taskSnapshot.data();
    const projectRef = db.collection('projects').doc(task.projectId);
    const projectSnapshot = await transaction.get(projectRef);
    if (!projectSnapshot.exists) throw httpError(404, 'Không tìm thấy dự án.', 'PROJECT_NOT_FOUND');
    const project = projectSnapshot.data();
    if (!isProjectMember(project, userId)) throw httpError(403, 'Bạn không thuộc dự án này.', 'PROJECT_FORBIDDEN');

    const leader = isProjectLeader(project, userId);
    let update;
    if (action === 'start') {
      if (!leader && task.assigneeId !== userId) throw httpError(403, 'Chỉ người được giao việc mới có thể bắt đầu.', 'TASK_ASSIGNEE_REQUIRED');
      if (!['Cần làm', 'Cần sửa', 'Đang làm'].includes(task.status)) throw httpError(409, 'Công việc không thể chuyển sang Đang làm ở trạng thái hiện tại.', 'INVALID_TASK_TRANSITION');
      update = { status: 'Đang làm' };
    } else if (action === 'submit') {
      if (!leader && task.assigneeId !== userId) throw httpError(403, 'Chỉ người được giao việc mới có thể gửi kết quả.', 'TASK_ASSIGNEE_REQUIRED');
      const { outputLink } = badRequest(submitSchema, body);
      if (outputLink) {
        let url;
        try { url = new URL(outputLink); } catch { throw httpError(400, 'Đường dẫn kết quả không hợp lệ.', 'INVALID_OUTPUT_LINK'); }
        if (!['http:', 'https:'].includes(url.protocol)) throw httpError(400, 'Đường dẫn kết quả phải dùng HTTP hoặc HTTPS.', 'INVALID_OUTPUT_LINK');
      } else if (task.outputRequired !== false && task.outputType !== 'none') {
        throw httpError(400, 'Vui lòng nhập đường dẫn kết quả.', 'OUTPUT_LINK_REQUIRED');
      }
      update = { outputLink, status: leader ? 'Hoàn thành' : 'Chờ duyệt' };
    } else {
      if (!leader) throw httpError(403, 'Chỉ Leader của dự án mới được duyệt công việc.', 'PROJECT_LEADER_REQUIRED');
      if (task.status !== 'Chờ duyệt') throw httpError(409, 'Chỉ có thể duyệt công việc đang chờ duyệt.', 'INVALID_TASK_TRANSITION');
      if (action === 'approve') {
        update = { status: 'Hoàn thành', reviewedBy: userId, reviewedAt: FieldValue.serverTimestamp() };
      } else {
        const { comment } = badRequest(reviewSchema, body);
        update = { status: 'Cần sửa', reviewComment: comment, reviewedBy: userId, reviewedAt: FieldValue.serverTimestamp() };
      }
    }
    update.updatedAt = FieldValue.serverTimestamp();
    transaction.update(taskRef, update);
    const now = new Date().toISOString();
    return { ...task, ...update, id: taskId, updatedAt: now, ...(update.reviewedBy ? { reviewedAt: now } : {}) };
  });
}

export const startTask = (taskId, userId) => updateTask(taskId, userId, 'start', {});
export const submitTask = (taskId, userId, body) => updateTask(taskId, userId, 'submit', body);
export const approveTask = (taskId, userId) => updateTask(taskId, userId, 'approve', {});
export const requestTaskChanges = (taskId, userId, body) => updateTask(taskId, userId, 'request-changes', body);