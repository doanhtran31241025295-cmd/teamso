import { randomUUID } from 'node:crypto';
import { FieldValue } from 'firebase-admin/firestore';
import { z } from 'zod';
import { db } from './firebase/client.js';
import { getProject } from './projects.js';

const documentSchema = z.object({
  title: z.string().trim().min(1).max(200),
}).strict();
const meetingSchema = z.object({
  title: z.string().trim().min(1).max(200),
}).strict();
const voteSchema = z.object({
  question: z.string().trim().min(1).max(300),
  options: z.array(z.string().trim().min(1).max(160)).min(2).max(8),
}).strict().refine(value => new Set(value.options).size === value.options.length, {
  message: 'Các phương án bình chọn không được trùng nhau.',
});
const voteSelectionSchema = z.object({
  optionIndex: z.number().int().min(0).max(7),
}).strict();

function parse(schema, body) {
  const result = schema.safeParse(body ?? {});
  if (!result.success) {
    throw Object.assign(new Error(result.error.issues[0]?.message ?? 'Dữ liệu không hợp lệ.'), {
      status: 400,
      code: 'VALIDATION_ERROR',
    });
  }
  return result.data;
}

function workspaceError(status, message, code) {
  return Object.assign(new Error(message), { status, code });
}

function dateValue(value) {
  return value?.toDate instanceof Function ? value.toDate().toISOString() : value ?? null;
}

function serialize(record, userId, isVote = false) {
  const data = record.data();
  const result = {
    id: record.id,
    ...data,
    createdAt: dateValue(data.createdAt),
    updatedAt: dateValue(data.updatedAt),
  };
  if (isVote) {
    result.selectedOption = data.voters?.[userId] ?? null;
    delete result.voters;
  }
  return result;
}

function workspaceCollection(projectId, kind) {
  return db.collection('projects').doc(projectId).collection(`workspace_${kind}`);
}

async function list(collection, userId, isVote = false) {
  const snapshot = await collection.orderBy('createdAt', 'desc').get();
  return snapshot.docs.map(record => serialize(record, userId, isVote));
}

export async function getWorkspace(projectId, userId) {
  await getProject(projectId, userId);
  const [documents, meetings, votes] = await Promise.all([
    list(workspaceCollection(projectId, 'documents'), userId),
    list(workspaceCollection(projectId, 'meetings'), userId),
    list(workspaceCollection(projectId, 'votes'), userId, true),
  ]);
  return { documents, meetings, votes };
}

async function createItem(projectId, userId, kind, schema, body) {
  await getProject(projectId, userId);
  const data = parse(schema, body);
  const ref = workspaceCollection(projectId, kind).doc(randomUUID());
  await ref.create({
    ...data,
    createdBy: userId,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return serialize(await ref.get(), userId);
}

export const createWorkspaceDocument = (projectId, userId, body) =>
  createItem(projectId, userId, 'documents', documentSchema, body);

export const createWorkspaceMeeting = (projectId, userId, body) =>
  createItem(projectId, userId, 'meetings', meetingSchema, body);

async function deleteItem(projectId, userId, kind, itemId) {
  const project = await getProject(projectId, userId);
  const ref = workspaceCollection(projectId, kind).doc(itemId);
  const snapshot = await ref.get();
  if (!snapshot.exists) throw workspaceError(404, 'Không tìm thấy mục Workspace.', 'WORKSPACE_ITEM_NOT_FOUND');
  const leader = project.leaderId === userId || project.ownerId === userId ||
    (Array.isArray(project.members) && project.members.some(member =>
      (member.id === userId || member.userId === userId) &&
      ['leader', 'owner', 'admin'].includes(String(member.role ?? '').toLowerCase())));
  if (snapshot.data().createdBy !== userId && !leader) {
    throw workspaceError(403, 'Bạn không có quyền xóa mục này.', 'WORKSPACE_FORBIDDEN');
  }
  await ref.delete();
  return { message: 'Đã xóa mục Workspace.' };
}

export const deleteWorkspaceDocument = (projectId, userId, itemId) =>
  deleteItem(projectId, userId, 'documents', itemId);

export const deleteWorkspaceMeeting = (projectId, userId, itemId) =>
  deleteItem(projectId, userId, 'meetings', itemId);

export async function createWorkspaceVote(projectId, userId, body) {
  await getProject(projectId, userId);
  const data = parse(voteSchema, body);
  const ref = workspaceCollection(projectId, 'votes').doc(randomUUID());
  await ref.create({
    ...data,
    voteCounts: data.options.map(() => 0),
    voters: {},
    createdBy: userId,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return serialize(await ref.get(), userId);
}

export async function submitWorkspaceVote(projectId, userId, voteId, body) {
  await getProject(projectId, userId);
  const { optionIndex } = parse(voteSelectionSchema, body);
  const ref = workspaceCollection(projectId, 'votes').doc(voteId);
  return db.runTransaction(async transaction => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) throw workspaceError(404, 'Không tìm thấy bình chọn.', 'WORKSPACE_VOTE_NOT_FOUND');
    const data = snapshot.data();
    if (optionIndex >= data.options.length) {
      throw workspaceError(400, 'Phương án bình chọn không hợp lệ.', 'VALIDATION_ERROR');
    }
    if (Object.hasOwn(data.voters ?? {}, userId)) {
      throw workspaceError(409, 'Bạn đã bình chọn cho câu hỏi này.', 'WORKSPACE_ALREADY_VOTED');
    }
    const voteCounts = [...data.voteCounts];
    voteCounts[optionIndex]++;
    transaction.update(ref, {
      voteCounts,
      [`voters.${userId}`]: optionIndex,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return serialize({
      id: snapshot.id,
      data: () => ({ ...data, voteCounts, voters: { ...(data.voters ?? {}), [userId]: optionIndex } }),
      ref,
    }, userId, true);
  });
}
