const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');

const {
  asyncHandler,
  decodeNameParam,
  httpError,
  parsePositiveInt,
} = require('../route_utils');

test('parsePositiveInt accepts valid ids', () => {
  assert.equal(parsePositiveInt('10'), 10);
  assert.equal(parsePositiveInt(42), 42);
});

test('parsePositiveInt rejects non-numeric ids', () => {
  assert.throws(
    () => parsePositiveInt('raja'),
    (err) => err.status === 400 && /positive integer/.test(err.message),
  );
  assert.throws(() => parsePositiveInt(''), (err) => err.status === 400);
  assert.throws(() => parsePositiveInt('10abc'), (err) => err.status === 400);
  assert.throws(() => parsePositiveInt('0'), (err) => err.status === 400);
});

test('decodeNameParam trims and decodes names', () => {
  assert.equal(decodeNameParam('raja'), 'raja');
  assert.equal(decodeNameParam('raja%20kumar'), 'raja kumar');
});

test('decodeNameParam rejects empty names', () => {
  assert.throws(
    () => decodeNameParam(''),
    (err) => err.status === 400,
  );
  assert.throws(() => decodeNameParam('%20%20'), (err) => err.status === 400);
});

function listenServer(server) {
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      const { port } = server.address();
      resolve({
        baseUrl: `http://127.0.0.1:${port}`,
        close: () => new Promise((done) => server.close(done)),
      });
    });
  });
}

function request(baseUrl, method, path) {
  return new Promise((resolve, reject) => {
    const req = http.request(`${baseUrl}${path}`, { method }, (res) => {
      const chunks = [];
      res.on('data', (chunk) => chunks.push(chunk));
      res.on('end', () => {
        resolve({
          status: res.statusCode,
          body: Buffer.concat(chunks).toString('utf8'),
        });
      });
    });
    req.on('error', reject);
    req.end();
  });
}

function sendJson(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(body),
  });
  res.end(body);
}

test('delete by id returns 400 for non-numeric param without crashing', async () => {
  const queries = [];
  const handler = asyncHandler(async (req, res) => {
    const match = req.url.match(/^\/api\/customers\/([^/?]+)$/);
    if (req.method === 'DELETE' && match) {
      const id = parsePositiveInt(match[1], 'customer id');
      queries.push(['delete-by-id', id]);
      return sendJson(res, 200, { rowsAffected: 1 });
    }
    sendJson(res, 404, { error: 'not found' });
  });

  const server = http.createServer((req, res) => {
    handler(req, res, (err) => {
      if (!err) return;
      sendJson(res, err.status || 500, { error: err.message });
    });
  });

  const { baseUrl, close } = await listenServer(server);
  try {
    const res = await request(baseUrl, 'DELETE', '/api/customers/raja');
    assert.equal(res.status, 400);
    assert.match(res.body, /positive integer/);
    assert.deepEqual(queries, []);
  } finally {
    await close();
  }
});

test('delete by name removes all rows case-insensitively', async () => {
  const deletedNames = [];
  const handler = asyncHandler(async (req, res) => {
    const match = req.url.match(/^\/api\/customers\/by-name\/([^/?]+)$/);
    if (req.method === 'DELETE' && match) {
      const name = decodeNameParam(match[1]);
      deletedNames.push(name);
      return sendJson(res, 200, { rowsAffected: 2 });
    }
    sendJson(res, 404, { error: 'not found' });
  });

  const server = http.createServer((req, res) => {
    handler(req, res, (err) => {
      if (!err) return;
      sendJson(res, err.status || 500, { error: err.message });
    });
  });

  const { baseUrl, close } = await listenServer(server);
  try {
    const res = await request(baseUrl, 'DELETE', '/api/customers/by-name/raja');
    assert.equal(res.status, 200);
    assert.deepEqual(JSON.parse(res.body), { rowsAffected: 2 });
    assert.deepEqual(deletedNames, ['raja']);
  } finally {
    await close();
  }
});

test('async route errors are handled by middleware', async () => {
  const handler = asyncHandler(async () => {
    throw httpError(400, 'bad request');
  });

  const server = http.createServer((req, res) => {
    handler(req, res, (err) => {
      if (!err) return;
      sendJson(res, err.status || 500, { error: err.message });
    });
  });

  const { baseUrl, close } = await listenServer(server);
  try {
    const res = await request(baseUrl, 'GET', '/api/boom');
    assert.equal(res.status, 400);
    assert.deepEqual(JSON.parse(res.body), { error: 'bad request' });
  } finally {
    await close();
  }
});
