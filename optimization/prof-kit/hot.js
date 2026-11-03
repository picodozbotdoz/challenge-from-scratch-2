// hot.js — profiling variant of bench/load.js: same request mix (feed -> post ->
// 15% like -> 2% create) but WITHOUT think times, to keep the server CPU-busy
// so sampling actually sees hot code. NOT the official scoring shape.
import http from 'k6/http';
import { check } from 'k6';
import { SharedArray } from 'k6/data';

const BASE_URL = __ENV.BASE_URL || 'http://127.0.0.1:3457';
const VUS = Number(__ENV.VUS || 300);
const LIKE_PROB = 0.15;
const POST_PROB = 0.02;
const tokens = new SharedArray('tokens', () => JSON.parse(open(__ENV.TOKENS)));

export const options = {
  scenarios: {
    hot: {
      executor: 'constant-vus',
      vus: VUS,
      duration: __ENV.DURATION || '60s',
    },
  },
  summaryTrendStats: ['avg', 'med', 'p(95)', 'p(99)', 'max'],
};

export default function () {
  const user = tokens[(__VU - 1) % tokens.length];
  const auth = { headers: { Authorization: `Bearer ${user.token}`, 'Content-Type': 'application/json' } };

  const feed = http.get(`${BASE_URL}/feed`, { tags: { name: 'GET /feed' } });
  if (!check(feed, { 'feed 200': (r) => r.status === 200 })) return;
  const posts = feed.json('posts');
  const post = posts[Math.floor(Math.random() * posts.length)];

  check(http.get(`${BASE_URL}/posts/${post.id}`, { tags: { name: 'GET /posts/:id' } }), { 'post 200': (r) => r.status === 200 });

  if (Math.random() < LIKE_PROB) {
    const r = http.post(`${BASE_URL}/posts/${post.id}/like`, null, { ...auth, tags: { name: 'like' } });
    check(r, { 'like 200/201': (r) => r.status === 200 || r.status === 201 });
  }
  if (Math.random() < POST_PROB) {
    const body = JSON.stringify({ body: `hot ${user.username} ${__VU} ${__ITER} ${Math.random()}` });
    check(http.post(`${BASE_URL}/posts`, body, { ...auth, tags: { name: 'create' } }), { 'create 201': (r) => r.status === 201 });
  }
}
