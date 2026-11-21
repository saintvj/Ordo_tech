const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { createApp } = require('../app');
const { validateMenuData } = require('../schema');
const {
  extractMenuFromImage,
  isRetryableError,
  isTimeoutError,
  calculateBackoffDelay,
} = require('../gemini');

describe('Menu Scanner Proxy API Tests', () => {
  const dummyJpegBuffer = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46]);

  test('GET /health returns 200 and model status without secrets', async () => {
    const app = createApp({
      getModel: () => 'gemini-3.5-flash-lite',
      getApiKey: () => 'secret-12345',
    });

    const res = await request(app).get('/health');
    assert.equal(res.status, 200);
    assert.equal(res.body.status, 'ok');
    assert.equal(res.body.model, 'gemini-3.5-flash-lite');
    assert.equal(res.text.includes('secret-12345'), false);
  });



  test('POST /api/menu/scan fails with 400 when no image is uploaded', async () => {
    const app = createApp({
      getApiKey: () => 'valid-key',
    });

    const res = await request(app)
      .post('/api/menu/scan')
      .field('dummy', 'value');

    assert.equal(res.status, 400);
    assert.equal(res.body.success, false);
    assert.match(res.body.error, /No image file uploaded/i);
  });

  test('POST /api/menu/scan fails with 400 on unsupported image type', async () => {
    const app = createApp({
      getApiKey: () => 'valid-key',
    });

    const res = await request(app)
      .post('/api/menu/scan')
      .attach('image', Buffer.from('hello plain text'), {
        filename: 'menu.txt',
        contentType: 'text/plain',
      });

    assert.equal(res.status, 400);
    assert.equal(res.body.success, false);
    assert.match(res.body.error, /Unsupported image type/i);
  });

  test('POST /api/menu/scan fails with 400 when image exceeds 10MB limit', async () => {
    const app = createApp({
      getApiKey: () => 'valid-key',
    });

    // Create an oversized 10.5 MB buffer
    const oversizedBuffer = Buffer.alloc(10.5 * 1024 * 1024);

    const res = await request(app)
      .post('/api/menu/scan')
      .attach('image', oversizedBuffer, {
        filename: 'huge_menu.jpg',
        contentType: 'image/jpeg',
      });

    assert.equal(res.status, 400);
    assert.equal(res.body.success, false);
    assert.match(res.body.error, /exceeds limit of 10MB/i);
  });

  test('POST /api/menu/scan fails with 500 when Gemini API key is missing', async () => {
    const app = createApp({
      getApiKey: () => '', // empty/unconfigured key
    });

    const res = await request(app)
      .post('/api/menu/scan')
      .attach('image', dummyJpegBuffer, {
        filename: 'menu.jpg',
        contentType: 'image/jpeg',
      });

    assert.equal(res.status, 500);
    assert.equal(res.body.success, false);
    assert.match(res.body.error, /GEMINI_API_KEY is not configured/i);
  });

  test('POST /api/menu/scan successfully parses and returns valid Gemini JSON response', async () => {
    const mockMenuData = {
      categories: [
        {
          name: 'Pizza World',
          items: [
            {
              name: 'Capsicum Onion Pizza',
              description: null,
              variants: [
                { name: '6 inch', price: 90 },
                { name: '10 inch', price: 150 },
              ],
              vegetarian_status: 'unknown',
              add_ons: [],
              confidence: 'high',
              needs_review: false,
            },
          ],
        },
      ],
      warnings: [],
      unreadable_text: [],
    };

    const mockExtractor = async () => mockMenuData;

    const app = createApp({
      getApiKey: () => 'test-valid-key',
      geminiExtractor: mockExtractor,
    });

    const res = await request(app)
      .post('/api/menu/scan')
      .attach('image', dummyJpegBuffer, {
        filename: 'menu.jpg',
        contentType: 'image/jpeg',
      });

    assert.equal(res.status, 200);
    assert.equal(res.body.success, true);
    assert.deepEqual(res.body.data, mockMenuData);
  });

  test('POST /api/menu/scan returns 502 on malformed Gemini JSON / schema validation failure', async () => {
    const mockExtractor = async () => {
      const err = new Error('Gemini output failed schema validation: Missing or invalid "categories" array');
      err.statusCode = 502;
      throw err;
    };

    const app = createApp({
      getApiKey: () => 'test-valid-key',
      geminiExtractor: mockExtractor,
    });

    const res = await request(app)
      .post('/api/menu/scan')
      .attach('image', dummyJpegBuffer, {
        filename: 'menu.jpg',
        contentType: 'image/jpeg',
      });

    assert.equal(res.status, 502);
    assert.equal(res.body.success, false);
    assert.match(res.body.error, /failed schema validation/i);
  });

  test('POST /api/menu/scan handles upstream Gemini API errors and redacts secrets', async () => {
    const secretKey = 'secret-gemini-key-999';
    const mockExtractor = async () => {
      const err = new Error(`Gemini upstream 503 error with key ${secretKey}`);
      err.statusCode = 502;
      throw err;
    };

    const app = createApp({
      getApiKey: () => secretKey,
      geminiExtractor: mockExtractor,
    });

    const res = await request(app)
      .post('/api/menu/scan')
      .attach('image', dummyJpegBuffer, {
        filename: 'menu.jpg',
        contentType: 'image/jpeg',
      });

    assert.equal(res.status, 502);
    assert.equal(res.body.success, false);
    assert.equal(res.text.includes(secretKey), false);
    assert.match(res.body.error, /\[REDACTED_API_KEY\]/);
  });

  test('POST /api/menu/scan returns 504 when upstream Gemini call times out', async () => {
    const mockExtractor = async () => {
      const err = new Error('Gemini API error (all 3 attempts failed): This operation was aborted');
      err.statusCode = 504;
      err.code = 'TIMEOUT';
      throw err;
    };

    const app = createApp({
      getApiKey: () => 'valid-key',
      geminiExtractor: mockExtractor,
    });

    const res = await request(app)
      .post('/api/menu/scan')
      .attach('image', dummyJpegBuffer, {
        filename: 'menu.jpg',
        contentType: 'image/jpeg',
      });

    assert.equal(res.status, 504);
    assert.equal(res.body.success, false);
    assert.match(res.body.error, /This operation was aborted/i);
  });

  test('POST /api/menu/scan returns 503 when all retries are exhausted on transient 503', async () => {
    const mockExtractor = async () => {
      const err = new Error('Gemini API error (all 3 attempts failed): The model is overloaded. Please try again later.');
      err.statusCode = 503;
      err.code = 'SERVICE_UNAVAILABLE';
      throw err;
    };

    const app = createApp({
      getApiKey: () => 'valid-key',
      geminiExtractor: mockExtractor,
    });

    const res = await request(app)
      .post('/api/menu/scan')
      .attach('image', dummyJpegBuffer, {
        filename: 'menu.jpg',
        contentType: 'image/jpeg',
      });

    assert.equal(res.status, 503);
    assert.equal(res.body.success, false);
    assert.match(res.body.error, /overloaded/i);
  });
});


describe('Menu Schema Validation Unit Tests', () => {
  test('validates and normalizes valid menu JSON', () => {
    const raw = {
      categories: [
        {
          name: 'Desserts',
          items: [
            {
              name: 'Brownie',
              description: 'Chocolate brownie',
              variants: [{ name: 'Regular', price: 45 }],
              vegetarian_status: 'egg',
              add_ons: ['Ice cream'],
              confidence: 'high',
              needs_review: false,
            },
          ],
        },
      ],
      warnings: [],
      unreadable_text: [],
    };

    const res = validateMenuData(raw);
    assert.equal(res.valid, true);
    assert.equal(res.normalized.categories.length, 1);
    assert.equal(res.normalized.categories[0].items[0].name, 'Brownie');
    assert.equal(res.normalized.categories[0].items[0].variants[0].price, 45);
  });

  test('marks needs_review true if variant price is null', () => {
    const raw = {
      categories: [
        {
          name: 'Main',
          items: [
            {
              name: 'Chef Special',
              variants: [{ name: 'Regular', price: null }],
              vegetarian_status: 'unknown',
              confidence: 'high',
              needs_review: false,
            },
          ],
        },
      ],
    };

    const res = validateMenuData(raw);
    assert.equal(res.valid, true);
    assert.equal(res.normalized.categories[0].items[0].needs_review, true);
  });

  test('rejects non-object or missing categories', () => {
    assert.equal(validateMenuData(null).valid, false);
    assert.equal(validateMenuData('bad string').valid, false);
    assert.equal(validateMenuData({ categories: 'not an array' }).valid, false);
  });
});

describe('Gemini Timeout and Retry Unit Tests', () => {
  const dummyBuffer = Buffer.from([0xff, 0xd8, 0xff, 0xe0]);

  test('isRetryableError correctly identifies retryable vs non-retryable errors', () => {
    assert.equal(isRetryableError({ status: 503 }), true);
    assert.equal(isRetryableError({ status: 429 }), true);
    assert.equal(isRetryableError({ status: 502 }), true);
    assert.equal(isRetryableError({ status: 504 }), true);
    assert.equal(isRetryableError({ status: 500 }), true);
    assert.equal(isRetryableError({ status: 408 }), true);
    assert.equal(isRetryableError({ name: 'AbortError' }), true);
    assert.equal(isRetryableError({ name: 'TimeoutError' }), true);
    assert.equal(isRetryableError({ code: 'ETIMEDOUT' }), true);
    assert.equal(isRetryableError({ message: 'The model is overloaded. Please try again later.' }), true);

    // Non-retryable
    assert.equal(isRetryableError({ status: 400 }), false);
    assert.equal(isRetryableError({ status: 401 }), false);
    assert.equal(isRetryableError({ status: 403 }), false);
    assert.equal(isRetryableError({ status: 404 }), false);
  });

  test('isTimeoutError detects various abort/timeout signatures', () => {
    assert.equal(isTimeoutError({ name: 'AbortError' }), true);
    assert.equal(isTimeoutError({ name: 'TimeoutError' }), true);
    assert.equal(isTimeoutError({ code: 'ETIMEDOUT' }), true);
    assert.equal(isTimeoutError({ message: 'This operation was aborted' }), true);
    assert.equal(isTimeoutError({ message: 'request timed out after 100000ms' }), true);

    assert.equal(isTimeoutError({ name: 'TypeError', message: 'other error' }), false);
  });

  test('calculateBackoffDelay produces bounded exponential backoff with jitter', () => {
    const delay1 = calculateBackoffDelay(1, { initialDelayMs: 1000, expBase: 2, maxDelayMs: 10000, maxJitterMs: 0 });
    assert.equal(delay1, 1000);

    const delay2 = calculateBackoffDelay(2, { initialDelayMs: 1000, expBase: 2, maxDelayMs: 10000, maxJitterMs: 0 });
    assert.equal(delay2, 2000);

    const delay3 = calculateBackoffDelay(3, { initialDelayMs: 1000, expBase: 2, maxDelayMs: 10000, maxJitterMs: 0 });
    assert.equal(delay3, 4000);

    const delayCapped = calculateBackoffDelay(10, { initialDelayMs: 1000, expBase: 2, maxDelayMs: 10000, maxJitterMs: 0 });
    assert.equal(delayCapped, 10000);
  });

  test('extractMenuFromImage retries on transient 503 and succeeds on next attempt', async () => {
    let callCount = 0;
    const mockAiClientFactory = () => ({
      models: {
        generateContent: async () => {
          callCount++;
          if (callCount === 1) {
            const err = new Error('The model is overloaded. Please try again later.');
            err.status = 503;
            throw err;
          }
          return {
            text: JSON.stringify({
              categories: [
                {
                  name: 'Drinks',
                  items: [
                    {
                      name: 'Iced Tea',
                      variants: [{ name: 'Regular', price: 40 }],
                      vegetarian_status: 'vegetarian',
                      add_ons: [],
                      confidence: 'high',
                      needs_review: false,
                    },
                  ],
                },
              ],
              warnings: [],
              unreadable_text: [],
            }),
          };
        },
      },
    });

    const result = await extractMenuFromImage({
      buffer: dummyBuffer,
      mimeType: 'image/jpeg',
      apiKey: 'test-key',
      maxAttempts: 3,
      backoffOptions: { initialDelayMs: 5, maxDelayMs: 10, expBase: 1.5, maxJitterMs: 0 },
      aiClientFactory: mockAiClientFactory,
    });

    assert.equal(callCount, 2);
    assert.equal(result.categories.length, 1);
    assert.equal(result.categories[0].name, 'Drinks');
    assert.equal(result.categories[0].items[0].name, 'Iced Tea');
  });

  test('extractMenuFromImage exhausts retries on repeated 503 errors and fails cleanly', async () => {
    let callCount = 0;
    const mockAiClientFactory = () => ({
      models: {
        generateContent: async () => {
          callCount++;
          const err = new Error('503 Service Unavailable');
          err.status = 503;
          throw err;
        },
      },
    });

    await assert.rejects(
      async () => {
        await extractMenuFromImage({
          buffer: dummyBuffer,
          mimeType: 'image/jpeg',
          apiKey: 'test-key',
          maxAttempts: 3,
          backoffOptions: { initialDelayMs: 5, maxDelayMs: 10, expBase: 1.5, maxJitterMs: 0 },
          aiClientFactory: mockAiClientFactory,
        });
      },
      (err) => {
        assert.equal(callCount, 3);
        assert.equal(err.statusCode, 503);
        assert.match(err.message, /all 3 attempts failed/i);
        return true;
      }
    );
  });

  test('extractMenuFromImage handles timeout (AbortError) and retries', async () => {
    let callCount = 0;
    const mockAiClientFactory = () => ({
      models: {
        generateContent: async () => {
          callCount++;
          const err = new Error('This operation was aborted');
          err.name = 'AbortError';
          throw err;
        },
      },
    });

    await assert.rejects(
      async () => {
        await extractMenuFromImage({
          buffer: dummyBuffer,
          mimeType: 'image/jpeg',
          apiKey: 'test-key',
          maxAttempts: 2,
          backoffOptions: { initialDelayMs: 5, maxDelayMs: 10, expBase: 1.5, maxJitterMs: 0 },
          aiClientFactory: mockAiClientFactory,
        });
      },
      (err) => {
        assert.equal(callCount, 2);
        assert.equal(err.statusCode, 504);
        assert.equal(err.code, 'TIMEOUT');
        assert.match(err.message, /all 2 attempts failed/i);
        return true;
      }
    );
  });

  test('extractMenuFromImage does not retry non-retryable 400 Bad Request error', async () => {
    let callCount = 0;
    const mockAiClientFactory = () => ({
      models: {
        generateContent: async () => {
          callCount++;
          const err = new Error('Invalid argument: image format not supported');
          err.status = 400;
          throw err;
        },
      },
    });

    await assert.rejects(
      async () => {
        await extractMenuFromImage({
          buffer: dummyBuffer,
          mimeType: 'image/jpeg',
          apiKey: 'test-key',
          maxAttempts: 3,
          backoffOptions: { initialDelayMs: 5, maxDelayMs: 10, expBase: 1.5, maxJitterMs: 0 },
          aiClientFactory: mockAiClientFactory,
        });
      },
      (err) => {
        // Must fail immediately on attempt 1 without retrying
        assert.equal(callCount, 1);
        assert.equal(err.statusCode, 400);
        return true;
      }
    );
  });
});


