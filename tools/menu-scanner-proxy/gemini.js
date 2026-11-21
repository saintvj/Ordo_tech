const { GoogleGenAI } = require('@google/genai');
const { menuResponseSchema, validateMenuData } = require('./schema');

// Configurable bounded timeout: default 100,000ms (100s, within 90-120s range)
const DEFAULT_TIMEOUT_MS = parseInt(process.env.GEMINI_TIMEOUT_MS, 10) || 100000;
const DEFAULT_MAX_ATTEMPTS = parseInt(process.env.GEMINI_MAX_RETRIES, 10) || 3;
const DEFAULT_BACKOFF_OPTIONS = {
  initialDelayMs: 1000,
  maxDelayMs: 10000,
  expBase: 2,
  maxJitterMs: 1000,
};

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isTimeoutError(error) {
  if (!error) return false;
  return (
    error.name === 'AbortError' ||
    error.name === 'TimeoutError' ||
    error.code === 'ETIMEDOUT' ||
    (error.message && (
      error.message.includes('aborted') ||
      error.message.includes('timed out') ||
      error.message.includes('timeout')
    ))
  );
}

function isRetryableError(error) {
  if (!error) return false;
  const status = error.status || error.statusCode;
  if (status && [408, 429, 500, 502, 503, 504].includes(status)) {
    return true;
  }
  if (isTimeoutError(error)) {
    return true;
  }
  if (error.name === 'TypeError' && error.message === 'fetch failed') {
    return true;
  }
  const msg = (error.message || '').toLowerCase();
  if (
    msg.includes('503') ||
    msg.includes('unavailable') ||
    msg.includes('overloaded') ||
    msg.includes('resource_exhausted')
  ) {
    return true;
  }
  return false;
}

function calculateBackoffDelay(attempt, options = {}) {
  const {
    initialDelayMs = DEFAULT_BACKOFF_OPTIONS.initialDelayMs,
    maxDelayMs = DEFAULT_BACKOFF_OPTIONS.maxDelayMs,
    expBase = DEFAULT_BACKOFF_OPTIONS.expBase,
    maxJitterMs = DEFAULT_BACKOFF_OPTIONS.maxJitterMs,
  } = options;
  const exponential = initialDelayMs * Math.pow(expBase, attempt - 1);
  const bounded = Math.min(exponential, maxDelayMs);
  const jitter = maxJitterMs > 0 ? Math.floor(Math.random() * maxJitterMs) : 0;
  return bounded + jitter;
}

const SYSTEM_INSTRUCTION = `You are an expert restaurant menu digitizer.
Analyze the provided menu photograph carefully and extract all visible categories, dishes/items, prices, and variants.

Rules:
1. Every menu item must use the exact required structure.
2. For single-price items, create a single variant named "Regular".
3. When multiple sizes/portions/options are listed (e.g. Small / Large, Half / Full, 6" / 10"), create separate variants for each with their respective prices.
4. Never invent or guess missing prices. If a price cannot be determined or is missing, set price to null and add a note to warnings or unreadable_text.
5. Preserve original dish names, capitalization, and spelling as closely as visible.
6. Do not guess vegetarian status. Unless explicit markers (green veg icon, red non-veg icon, "Veg", "Non-Veg", "Vegan", "Contains Egg") exist, set vegetarian_status to "unknown".
7. Mark uncertain, blurry, occluded or ambiguous items with needs_review: true and set confidence to "medium" or "low".
8. Set confidence to "high" only for clearly legible items.
9. Do not merge separate dishes into one.
10. Extract every visible category and dish.
11. Output ONLY valid JSON adhering to the schema.`;

/**
 * Calls Gemini API with bounded timeout, retry handling for transient errors (503, 429, timeout),
 * and exponential backoff with jitter.
 *
 * @param {object} params
 * @param {Buffer} params.buffer - Image file buffer
 * @param {string} params.mimeType - Image MIME type (image/jpeg, image/png, image/webp)
 * @param {string} params.apiKey - Gemini API key
 * @param {string} [params.model] - Gemini model name (default: gemini-3.5-flash-lite)
 * @param {number} [params.timeoutMs] - Request timeout in ms (default: 100000)
 * @param {number} [params.maxAttempts] - Max attempts before failure (default: 3)
 * @param {object} [params.backoffOptions] - Exponential backoff settings
 * @param {Function} [params.aiClientFactory] - Optional client factory for testing
 * @returns {Promise<object>} The normalized menu data
 */
async function extractMenuFromImage({
  buffer,
  mimeType,
  apiKey,
  model = 'gemini-3.5-flash-lite',
  timeoutMs = DEFAULT_TIMEOUT_MS,
  maxAttempts = DEFAULT_MAX_ATTEMPTS,
  backoffOptions = DEFAULT_BACKOFF_OPTIONS,
  aiClientFactory,
}) {
  if (!apiKey || typeof apiKey !== 'string' || apiKey.trim() === '') {
    const err = new Error('Gemini API key is missing or not configured');
    err.statusCode = 500;
    throw err;
  }

  // Configure client with explicit bounded timeout and disable internal duplicate retries (attempts: 1)
  const ai = aiClientFactory
    ? aiClientFactory({ apiKey, timeoutMs })
    : new GoogleGenAI({
        apiKey,
        httpOptions: {
          timeout: timeoutMs,
          retryOptions: { attempts: 1 },
        },
      });

  let lastError;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const attemptStart = Date.now();
    console.log(`[${new Date().toISOString()}] Gemini attempt ${attempt}/${maxAttempts} starting (model: ${model}, timeout: ${timeoutMs}ms)...`);

    try {
      const response = await ai.models.generateContent({
        model,
        contents: [
          {
            inlineData: {
              data: buffer.toString('base64'),
              mimeType,
            },
          },
          'Extract all menu categories, dishes, variants, and prices from this menu photograph according to the schema.',
        ],
        config: {
          systemInstruction: SYSTEM_INSTRUCTION,
          responseMimeType: 'application/json',
          responseSchema: menuResponseSchema,
          temperature: 0.1,
        },
      });

      const elapsedMs = Date.now() - attemptStart;
      console.log(`[${new Date().toISOString()}] Gemini attempt ${attempt}/${maxAttempts} succeeded in ${elapsedMs}ms (HTTP 200)`);

      const rawText = response && response.text ? response.text.trim() : '';
      if (!rawText) {
        const err = new Error('Gemini returned an empty response');
        err.statusCode = 502;
        throw err;
      }

      let parsedJson;
      try {
        parsedJson = JSON.parse(rawText);
      } catch (jsonErr) {
        const err = new Error(`Gemini returned invalid JSON: ${jsonErr.message}`);
        err.statusCode = 502;
        throw err;
      }

      const validation = validateMenuData(parsedJson);
      if (!validation.valid) {
        const err = new Error(`Gemini output failed schema validation: ${validation.error}`);
        err.statusCode = 502;
        throw err;
      }

      return validation.normalized;
    } catch (error) {
      const elapsedMs = Date.now() - attemptStart;
      const isTimeout = isTimeoutError(error);
      const httpStatus = error.status || error.statusCode || (isTimeout ? 504 : 502);
      const errorCode = error.code || (isTimeout ? 'TIMEOUT' : 'GEMINI_ERROR');

      let safeMessage = error && error.message ? error.message : 'Unknown Gemini error';
      if (apiKey && safeMessage.includes(apiKey)) {
        safeMessage = safeMessage.replaceAll(apiKey, '[REDACTED_API_KEY]');
      }

      console.error(
        `[${new Date().toISOString()}] Gemini attempt ${attempt}/${maxAttempts} failed in ${elapsedMs}ms: ` +
        `status ${httpStatus}, code ${errorCode}, message: ${safeMessage}`
      );

      lastError = error;
      lastError.statusCode = httpStatus;
      lastError.code = errorCode;
      lastError.safeMessage = safeMessage;

      const retryable = isRetryableError(error);
      if (retryable && attempt < maxAttempts) {
        const delayMs = calculateBackoffDelay(attempt, backoffOptions);
        console.log(`[${new Date().toISOString()}] Transient Gemini error (${httpStatus}). Retrying in ${delayMs}ms (attempt ${attempt + 1}/${maxAttempts})...`);
        await sleep(delayMs);
        continue;
      }

      break;
    }
  }

  // All attempts exhausted or error is non-retryable
  const finalMessage = lastError && lastError.safeMessage
    ? lastError.safeMessage
    : 'All Gemini attempts failed';
  const finalError = new Error(`Gemini API error (all ${maxAttempts} attempts failed): ${finalMessage}`);
  finalError.statusCode = (lastError && lastError.statusCode) || 502;
  finalError.code = (lastError && lastError.code) || 'RETRIES_EXHAUSTED';
  throw finalError;
}

module.exports = {
  extractMenuFromImage,
  isRetryableError,
  isTimeoutError,
  calculateBackoffDelay,
  DEFAULT_TIMEOUT_MS,
  DEFAULT_MAX_ATTEMPTS,
};
