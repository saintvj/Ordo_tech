const { Type } = require('@google/genai');

const menuResponseSchema = {
  type: Type.OBJECT,
  properties: {
    categories: {
      type: Type.ARRAY,
      description: 'List of menu categories extracted from the menu.',
      items: {
        type: Type.OBJECT,
        properties: {
          name: {
            type: Type.STRING,
            description: 'Name of the category, e.g. Starters, Main Course, Pizza World.',
          },
          items: {
            type: Type.ARRAY,
            description: 'List of dishes/drinks under this category.',
            items: {
              type: Type.OBJECT,
              properties: {
                name: {
                  type: Type.STRING,
                  description: 'Dish name as printed on the menu.',
                },
                description: {
                  type: Type.STRING,
                  nullable: true,
                  description: 'Short description or ingredients listed on the menu, or null if none.',
                },
                variants: {
                  type: Type.ARRAY,
                  description: 'Price variants. Single-price items must have one variant named "Regular". Multiple sizes (Half, Full, 6 inch, etc.) must be split into separate variants.',
                  items: {
                    type: Type.OBJECT,
                    properties: {
                      name: {
                        type: Type.STRING,
                        description: 'Variant name, e.g. "Regular", "Small", "Large", "6 inch".',
                      },
                      price: {
                        type: Type.NUMBER,
                        nullable: true,
                        description: 'Numeric price. Null if unreadable or missing. Never guess.',
                      },
                    },
                    required: ['name'],
                  },
                },
                vegetarian_status: {
                  type: Type.STRING,
                  description: 'Vegetarian classification. Must be "vegetarian", "non_vegetarian", "egg", "vegan", or "unknown". If not clearly indicated, must be "unknown".',
                },
                add_ons: {
                  type: Type.ARRAY,
                  description: 'Optional add-ons or extras explicitly listed for this dish.',
                  items: {
                    type: Type.STRING,
                  },
                },
                confidence: {
                  type: Type.STRING,
                  description: 'Extraction confidence: "high", "medium", or "low".',
                },
                needs_review: {
                  type: Type.BOOLEAN,
                  description: 'True if any price, name, or detail is uncertain, occluded, or ambiguous.',
                },
              },
              required: ['name', 'variants', 'vegetarian_status', 'add_ons', 'confidence', 'needs_review'],
            },
          },
        },
        required: ['name', 'items'],
      },
    },
    warnings: {
      type: Type.ARRAY,
      description: 'Warnings regarding poor lighting, folded sections, or partial crops.',
      items: { type: Type.STRING },
    },
    unreadable_text: {
      type: Type.ARRAY,
      description: 'Snippets of text that could not be confidently identified.',
      items: { type: Type.STRING },
    },
  },
  required: ['categories', 'warnings', 'unreadable_text'],
};

/**
 * Validates that an object conforms to the expected Menu Scan JSON schema.
 * @param {any} data
 * @returns {{ valid: boolean, error?: string, normalized?: object }}
 */
function validateMenuData(data) {
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    return { valid: false, error: 'Expected root JSON object' };
  }

  if (!Array.isArray(data.categories)) {
    return { valid: false, error: 'Missing or invalid "categories" array' };
  }

  const warnings = Array.isArray(data.warnings) ? data.warnings.map(String) : [];
  const unreadable_text = Array.isArray(data.unreadable_text) ? data.unreadable_text.map(String) : [];

  const normalizedCategories = [];

  for (let cIdx = 0; cIdx < data.categories.length; cIdx++) {
    const cat = data.categories[cIdx];
    if (!cat || typeof cat !== 'object') {
      return { valid: false, error: `Invalid category at index ${cIdx}` };
    }
    const catName = typeof cat.name === 'string' && cat.name.trim().length > 0 ? cat.name.trim() : 'General';
    if (!Array.isArray(cat.items)) {
      return { valid: false, error: `Category "${catName}" has invalid "items" array` };
    }

    const normalizedItems = [];

    for (let iIdx = 0; iIdx < cat.items.length; iIdx++) {
      const item = cat.items[iIdx];
      if (!item || typeof item !== 'object') {
        return { valid: false, error: `Category "${catName}" has invalid item at index ${iIdx}` };
      }

      if (typeof item.name !== 'string' || item.name.trim().length === 0) {
        return { valid: false, error: `Item at index ${iIdx} in category "${catName}" is missing a name` };
      }

      const rawVariants = Array.isArray(item.variants) && item.variants.length > 0 ? item.variants : null;
      let normalizedVariants = [];

      if (!rawVariants) {
        // Fallback for missing variants: single Regular variant
        normalizedVariants = [{ name: 'Regular', price: null }];
      } else {
        for (let vIdx = 0; vIdx < rawVariants.length; vIdx++) {
          const v = rawVariants[vIdx];
          if (!v || typeof v !== 'object') {
            normalizedVariants.push({ name: 'Regular', price: null });
            continue;
          }
          const vName = typeof v.name === 'string' && v.name.trim().length > 0 ? v.name.trim() : 'Regular';
          let vPrice = null;
          if (typeof v.price === 'number' && !Number.isNaN(v.price)) {
            vPrice = v.price;
          } else if (typeof v.price === 'string' && v.price.trim().length > 0) {
            const parsed = parseFloat(v.price.replace(/[^0-9.]/g, ''));
            if (!Number.isNaN(parsed)) vPrice = parsed;
          }
          normalizedVariants.push({ name: vName, price: vPrice });
        }
      }

      let vegStatus = 'unknown';
      if (typeof item.vegetarian_status === 'string') {
        const lower = item.vegetarian_status.toLowerCase().trim();
        if (['vegetarian', 'non_vegetarian', 'egg', 'vegan', 'unknown'].includes(lower)) {
          vegStatus = lower;
        }
      }

      const addOns = Array.isArray(item.add_ons) ? item.add_ons.map(String) : [];
      let confidence = 'medium';
      if (typeof item.confidence === 'string' && ['high', 'medium', 'low'].includes(item.confidence.toLowerCase())) {
        confidence = item.confidence.toLowerCase();
      }

      const needsReview = Boolean(
        item.needs_review ||
        confidence === 'low' ||
        normalizedVariants.some((v) => v.price === null)
      );

      normalizedItems.push({
        name: item.name.trim(),
        description: typeof item.description === 'string' && item.description.trim().length > 0 ? item.description.trim() : null,
        variants: normalizedVariants,
        vegetarian_status: vegStatus,
        add_ons: addOns,
        confidence,
        needs_review: needsReview,
      });
    }

    normalizedCategories.push({
      name: catName,
      items: normalizedItems,
    });
  }

  return {
    valid: true,
    normalized: {
      categories: normalizedCategories,
      warnings,
      unreadable_text,
    },
  };
}

module.exports = {
  menuResponseSchema,
  validateMenuData,
};

