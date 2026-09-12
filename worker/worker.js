// Junkpile Tycoon —— 遠端 constants 覆寫 worker（Cloudflare Worker + KV）。
// 搬 yaing 嘅 meta/ + Worker + KV 模式（見 yaing repo store-api/worker.js
// 嘅 /config endpoint），但跟 ALTA-155 縮細咗嘅範圍剪到淨返一個 endpoint
// ——唔接 Firebase、唔做公告／強制更新：淨係派一份 GameConstants「# TUNE」
// 純量欄位嘅覆寫 JSON，App 開機 GET 一次，疊喺本機預設之上（見
// ../systems/remote_constants.gd + ../systems/remote_constants_loader.gd）。
//
// 公開 endpoint：
//   GET  /constants  → { overrides: {...}, updatedAt: <ISO8601 或 null> }
//
// 管理 endpoint（要 `x-admin-key: <ADMIN_KEY>` header；ADMIN_KEY 係 Worker
// 嘅 secret，喺 Cloudflare dashboard 設，唔會 commit 落 repo）：
//   POST /constants  { overrides: {...} } → 用下面 FIELD_TYPES 白名單洗一次，
//                                            存落 KV，回傳實際存低（洗好）嘅值
//
// 儲存：KV key "constants" 一個 JSON blob —— { overrides, updatedAt }。
// 部署步驟同 curl 例子見 README.md。
//
// 免費層：Workers Free（每日 10 萬 requests）+ KV Free（每日 10 萬讀／
// 1 千寫、1GB 儲存）對單一開發者嘅調數需求綽綽有餘——App 每次開機淨係
// 讀一次，寫入淨係開發者手動推新數值嗰陣先有。
//
// ⚠️ 下面 FIELD_TYPES 要同 ../data/constants.gd 嘅
// GameConstants.REMOTE_TUNABLE_FIELDS 手動同步。
// test/test_constants_remote_tunable.gd 淨係喺 GDScript 嗰邊對源碼註解
// 做自動檢查，呢份 JS 抄本冇跨語言自動對數——加／刪一個純量 TUNE 欄位記得
// 兩邊都要改。
const FIELD_TYPES = {
  ore_rate_per_miner: 'float',
  miner_cost_base: 'float',
  miner_cost_mult: 'float',
  starting_cash: 'float',
  miner_level_cost_base: 'float',
  miner_level_cost_mult: 'float',
  miner_level_speed_mult: 'float',
  belt_cap_lv1: 'float',
  belt_step: 'float',
  belt_level_cap: 'int',
  belt_cost_base: 'float',
  belt_cost_mult: 'float',
  refine_cost_base: 'float',
  refine_cost_mult: 'float',
  refine_value_mult: 'float',
  frenzy_duration_secs: 'float',
  frenzy_mult: 'float',
  frenzy_cooldown_secs: 'float',
  frenzy_first_cooldown_secs: 'float',
  gear_drop_interval_secs: 'float',
  frenzy_manual_eff: 'float',
  eco_gain_hazard_per_item: 'float',
  eco_gain_perfect_sort_bonus: 'float',
  eco_gain_daily_goal_bonus: 'float',
  car_capacity: 'int',
  car_speed: 'float',
  debris_rigidbody_cap: 'int',
  ai_driver_eff: 'float',
  trash_meter_decay_per_sec: 'float',
  offline_cap_secs: 'float',
  offline_min_gap_secs: 'float',
  unlock_mid_price: 'float',
  unlock_upper_price: 'float',
  prestige_base: 'float',
  prestige_growth: 'float',
  prestige_bonus_per_reset: 'float',
  rewarded_offline_x2_per_day: 'int',
  rewarded_extra_frenzy_per_day: 'int',
  pile_debris_spawn_interval_secs: 'float',
  belt_visual_travel_secs: 'float',
  yard_min_y: 'float',
  yard_spawn_y: 'float',
  car_descent_speed: 'float',
  scrap_coin_value: 'float',
  scrap_barrel_value: 'float',
  scrap_gold_value: 'float',
  barrel_spawn_ratio: 'float',
  debris_spawn_interval_secs: 'float',
  debris_fake_fall_speed: 'float',
  debris_gravity_scale: 'float',
  lava_bridge_y: 'float',
  lava_fall_overflow_amount: 'float',
  lava_fall_stun_secs: 'float',
  upgrade_pad_rearm_secs: 'float',
  gear_component_reward: 'float',
  gear_pickup_window_secs: 'float',
  frenzy_fps_sample_interval_secs: 'float',
  frenzy_fps_low_threshold: 'float',
  frenzy_fps_low_streak_to_degrade: 'int',
  frenzy_fake_physics_min_tier: 'int',
};

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
  'Access-Control-Allow-Headers': 'content-type,x-admin-key',
  'X-Content-Type-Options': 'nosniff',
};

// 同 yaing sanitizeConfig() 一樣嘅防守做法：淨係白名單內、數值合法（finite）
// 嘅 key 先會覆寫；其餘（唔喺白名單、型別唔啱、NaN／Infinity）直接忽略，
// 唔會令成個 request 一齊 400——一個壞 key 唔會累到其餘啱嘅 key。
function sanitizeOverrides(input) {
  const out = {};
  if (!input || typeof input !== 'object') return out;
  for (const key in FIELD_TYPES) {
    if (!(key in input)) continue;
    const raw = input[key];
    const num = typeof raw === 'number' ? raw : NaN;
    if (!Number.isFinite(num)) continue;
    out[key] = FIELD_TYPES[key] === 'int' ? Math.round(num) : num;
  }
  return out;
}

function json(data, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', ...CORS, ...extraHeaders },
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, '') || '/';

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CORS });
    }

    if (path === '/constants' && request.method === 'GET') {
      const stored = (await env.CONSTANTS.get('constants', 'json')) || { overrides: {}, updatedAt: null };
      // 每次開 app 都會叫一次，但底下個值淨係開發者手動推新數值先會變，
      // 短 Cache-Control 慳返 KV 讀（同 yaing /config 一樣嘅道理）。
      return json(stored, 200, { 'Cache-Control': 'public, max-age=60' });
    }

    if (path === '/constants' && request.method === 'POST') {
      if (!env.ADMIN_KEY || request.headers.get('x-admin-key') !== env.ADMIN_KEY) {
        return json({ error: 'unauthorized' }, 401);
      }
      let body;
      try {
        body = await request.json();
      } catch {
        return json({ error: 'bad_json' }, 400);
      }
      const overrides = sanitizeOverrides(body && body.overrides);
      const stored = { overrides, updatedAt: new Date().toISOString() };
      await env.CONSTANTS.put('constants', JSON.stringify(stored));
      return json(stored);
    }

    return json({ error: 'not_found' }, 404);
  },
};
