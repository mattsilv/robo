import type { Context } from 'hono';
import type { Env, NutritionLookupResponse } from '../types';
import { NutritionLookupSchema } from '../types';

export const lookupNutrition = async (c: Context<{ Bindings: Env }>) => {
  const parsed = NutritionLookupSchema.safeParse({ upc: c.req.query('upc') });
  if (!parsed.success) {
    return c.json({ error: parsed.error.issues[0].message }, 400);
  }

  const { upc } = parsed.data;

  const resp = await fetch(
    `https://trackapi.nutritionix.com/v2/search/item?upc=${upc}`,
    {
      headers: {
        'x-app-id': c.env.NUTRITIONIX_APP_ID,
        'x-app-key': c.env.NUTRITIONIX_APP_KEY,
      },
    }
  );

  if (resp.status === 404) {
    const empty: NutritionLookupResponse = {
      found: false,
      food_name: null,
      brand_name: null,
      calories: null,
      protein: null,
      fat: null,
      carbs: null,
      fiber: null,
      sugars: null,
      sodium: null,
      serving_qty: null,
      serving_unit: null,
      serving_weight_grams: null,
      photo_thumb: null,
      photo_highres: null,
    };
    return c.json(empty);
  }

  if (!resp.ok) {
    console.error(`Nutritionix API error: ${resp.status} ${resp.statusText}`);
    return c.json({ error: 'Nutritionix API error' }, 502);
  }

  const body = (await resp.json()) as {
    foods?: Array<{
      food_name?: string;
      brand_name?: string;
      nf_calories?: number;
      nf_protein?: number;
      nf_total_fat?: number;
      nf_total_carbohydrate?: number;
      nf_dietary_fiber?: number;
      nf_sugars?: number;
      nf_sodium?: number;
      serving_qty?: number;
      serving_unit?: string;
      serving_weight_grams?: number;
      photo?: { thumb?: string; highres?: string };
    }>;
  };

  const food = body.foods?.[0];
  if (!food) {
    const empty: NutritionLookupResponse = {
      found: false,
      food_name: null,
      brand_name: null,
      calories: null,
      protein: null,
      fat: null,
      carbs: null,
      fiber: null,
      sugars: null,
      sodium: null,
      serving_qty: null,
      serving_unit: null,
      serving_weight_grams: null,
      photo_thumb: null,
      photo_highres: null,
    };
    return c.json(empty);
  }

  const result: NutritionLookupResponse = {
    found: true,
    food_name: food.food_name ?? null,
    brand_name: food.brand_name ?? null,
    calories: food.nf_calories ?? null,
    protein: food.nf_protein ?? null,
    fat: food.nf_total_fat ?? null,
    carbs: food.nf_total_carbohydrate ?? null,
    fiber: food.nf_dietary_fiber ?? null,
    sugars: food.nf_sugars ?? null,
    sodium: food.nf_sodium ?? null,
    serving_qty: food.serving_qty ?? null,
    serving_unit: food.serving_unit ?? null,
    serving_weight_grams: food.serving_weight_grams ?? null,
    photo_thumb: food.photo?.thumb ?? null,
    photo_highres: food.photo?.highres ?? null,
  };

  return c.json(result);
};
