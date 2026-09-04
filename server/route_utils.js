function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

function asyncHandler(fn) {
  return (req, res, next) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
}

function parsePositiveInt(value, label = 'id') {
  const raw = String(value ?? '').trim();
  if (!/^\d+$/.test(raw)) {
    throw httpError(400, `Invalid ${label}: must be a positive integer`);
  }
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    throw httpError(400, `Invalid ${label}: must be a positive integer`);
  }
  return parsed;
}

function decodeNameParam(raw) {
  const name = decodeURIComponent(String(raw ?? '')).trim();
  if (!name) {
    throw httpError(400, 'Name is required');
  }
  return name;
}

/** Wrap every async route handler so rejections reach the error middleware. */
function installAsyncRouteWrapper(app) {
  for (const method of ['get', 'post', 'put', 'delete', 'patch']) {
    const original = app[method].bind(app);
    app[method] = (path, ...handlers) => {
      const wrapped = handlers.map((handler) => {
        if (typeof handler !== 'function') return handler;
        if (handler.length === 4) return handler;
        return asyncHandler(handler);
      });
      return original(path, ...wrapped);
    };
  }
}

module.exports = {
  httpError,
  asyncHandler,
  parsePositiveInt,
  decodeNameParam,
  installAsyncRouteWrapper,
};
