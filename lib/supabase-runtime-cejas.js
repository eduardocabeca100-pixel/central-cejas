require("dotenv").config();

const { createClient } = require("@supabase/supabase-js");

let cachedAdmin = null;
let cachedSignature = "";

function cleanEnv(value) {
  return String(value || "")
    .trim()
    .replace(/^["']|["']$/g, "");
}

function getRuntimeEnv() {
  const url =
    cleanEnv(process.env.SUPABASE_URL) ||
    cleanEnv(process.env.NEXT_PUBLIC_SUPABASE_URL) ||
    cleanEnv(process.env.PUBLIC_SUPABASE_URL);

  const serviceRole =
    cleanEnv(process.env.SUPABASE_SERVICE_ROLE_KEY) ||
    cleanEnv(process.env.SUPABASE_SERVICE_KEY) ||
    cleanEnv(process.env.SUPABASE_SERVICE_ROLE);

  const bucket =
    cleanEnv(process.env.SUPABASE_STORAGE_BUCKET) ||
    cleanEnv(process.env.SUPABASE_BUCKET) ||
    "servidor-cejas";

  return {
    url,
    serviceRole,
    bucket
  };
}

function getSupabaseRuntimeStatus() {
  const env = getRuntimeEnv();

  return {
    ok: Boolean(env.url && env.serviceRole && env.bucket),
    bucket: env.bucket,
    resolvedUrl: Boolean(env.url),
    resolvedServiceRole: Boolean(env.serviceRole),
    resolvedBucket: Boolean(env.bucket),
    has_SUPABASE_URL: Boolean(process.env.SUPABASE_URL),
    has_NEXT_PUBLIC_SUPABASE_URL: Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL),
    has_SUPABASE_SERVICE_ROLE_KEY: Boolean(process.env.SUPABASE_SERVICE_ROLE_KEY),
    has_SUPABASE_STORAGE_BUCKET: Boolean(process.env.SUPABASE_STORAGE_BUCKET),
    lengths: {
      url: env.url ? env.url.length : 0,
      serviceRole: env.serviceRole ? env.serviceRole.length : 0,
      bucket: env.bucket ? env.bucket.length : 0
    }
  };
}

function getSupabaseAdmin() {
  const env = getRuntimeEnv();

  if (!env.url || !env.serviceRole) {
    throw new Error(
      "Supabase Storage não configurado no runtime. Status: " +
      JSON.stringify(getSupabaseRuntimeStatus())
    );
  }

  const signature = `${env.url}::${env.serviceRole.slice(0, 12)}::${env.bucket}`;

  if (!cachedAdmin || cachedSignature !== signature) {
    cachedAdmin = createClient(env.url, env.serviceRole, {
      auth: {
        persistSession: false,
        autoRefreshToken: false
      }
    });

    cachedSignature = signature;
  }

  return cachedAdmin;
}

function getStorageBucket() {
  return getRuntimeEnv().bucket || "servidor-cejas";
}

module.exports = {
  getRuntimeEnv,
  getSupabaseRuntimeStatus,
  getSupabaseAdmin,
  getStorageBucket
};
