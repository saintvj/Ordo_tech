const express = require('express');
const multer = require('multer');
const { extractMenuFromImage } = require('./gemini');

const MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024; // 10 MB
const ALLOWED_MIME_TYPES = ['image/jpeg', 'image/png', 'image/webp'];

function createApp(options = {}) {
  const app = express();
  const extractor = options.geminiExtractor || extractMenuFromImage;
  const getApiKey = options.getApiKey || (() => process.env.GEMINI_API_KEY);
  const getModel = options.getModel || (() => process.env.GEMINI_MODEL || 'gemini-3.5-flash-lite');

  const upload = multer({
    storage: multer.memoryStorage(),
    limits: {
      fileSize: MAX_FILE_SIZE_BYTES,
    },
    fileFilter: (req, file, cb) => {
      if (ALLOWED_MIME_TYPES.includes(file.mimetype)) {
        cb(null, true);
      } else {
        const error = new Error(`Unsupported image type "${file.mimetype}". Supported types: JPEG, PNG, WebP.`);
        error.code = 'UNSUPPORTED_MEDIA_TYPE';
        cb(error, false);
      }
    },
  });

  // Health check endpoint
  app.get('/health', (req, res) => {
    res.status(200).json({
      status: 'ok',
      model: getModel(),
    });
  });

  // Menu scan endpoint
  app.post('/api/menu/scan', (req, res, next) => {
    console.log(`[${new Date().toISOString()}] Incoming request: POST /api/menu/scan`);
    upload.single('image')(req, res, (uploadErr) => {
      if (uploadErr) {
        const errorCode = uploadErr.code || 'UPLOAD_ERROR';
        const message = uploadErr.code === 'LIMIT_FILE_SIZE'
          ? 'File size exceeds limit of 10MB.'
          : uploadErr.message || 'File upload error';
        console.error(`[${new Date().toISOString()}] Upload error: status 400, code ${errorCode}, message: ${message}`);
        return res.status(400).json({
          success: false,
          error: message,
        });
      }

      if (req.file) {
        console.log(`[${new Date().toISOString()}] Upload processed: image received=true, mimeType=${req.file.mimetype}, size=${req.file.size} bytes`);
      } else {
        console.warn(`[${new Date().toISOString()}] Upload processed: image received=false, size=0 bytes`);
      }

      next();
    });
  }, async (req, res) => {
    try {
      if (!req.file) {
        console.error(`[${new Date().toISOString()}] Request failed: status 400, code MISSING_IMAGE, message: No image file uploaded.`);
        return res.status(400).json({
          success: false,
          error: 'No image file uploaded. Expected field name: "image".',
        });
      }

      const apiKey = getApiKey();
      if (!apiKey || apiKey.trim() === '') {
        console.error(`[${new Date().toISOString()}] Request failed: status 500, code MISSING_API_KEY, message: GEMINI_API_KEY is not configured on the server.`);
        return res.status(500).json({
          success: false,
          error: 'GEMINI_API_KEY is not configured on the server.',
        });
      }

      const model = getModel();
      console.log(`[${new Date().toISOString()}] Calling Gemini with model: ${model}`);
      const scanStartTime = Date.now();

      const menuData = await extractor({
        buffer: req.file.buffer,
        mimeType: req.file.mimetype,
        apiKey,
        model,
      });

      const scanDurationMs = Date.now() - scanStartTime;
      console.log(`[${new Date().toISOString()}] Gemini extraction completed in ${scanDurationMs}ms (categories: ${menuData.categories?.length || 0})`);

      return res.status(200).json({
        success: true,
        data: menuData,
      });
    } catch (err) {
      const statusCode = err.statusCode || 500;
      const errorCode = err.code || (statusCode >= 500 ? 'GEMINI_UPSTREAM_ERROR' : 'SCAN_ERROR');
      let safeMessage = err.message || 'Internal server error';

      const apiKey = getApiKey();
      if (apiKey && safeMessage.includes(apiKey)) {
        safeMessage = safeMessage.replaceAll(apiKey, '[REDACTED_API_KEY]');
      }

      console.error(`[${new Date().toISOString()}] Request failed: status ${statusCode}, code ${errorCode}, message: ${safeMessage}`);

      return res.status(statusCode).json({
        success: false,
        error: safeMessage,
      });
    }
  });

  // Fallback error handler to ensure client never hangs indefinitely
  app.use((err, req, res, next) => {
    const statusCode = err.statusCode || err.status || 500;
    const errorCode = err.code || 'UNHANDLED_ERROR';
    let safeMessage = err.message || 'Internal server error';

    const apiKey = getApiKey();
    if (apiKey && safeMessage.includes(apiKey)) {
      safeMessage = safeMessage.replaceAll(apiKey, '[REDACTED_API_KEY]');
    }

    console.error(`[${new Date().toISOString()}] Unhandled server error: status ${statusCode}, code ${errorCode}, message: ${safeMessage}`);

    if (!res.headersSent) {
      res.status(statusCode).json({
        success: false,
        error: safeMessage,
      });
    }
  });

  return app;

}

module.exports = {
  createApp,
};

