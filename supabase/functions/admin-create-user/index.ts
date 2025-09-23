// Follow this setup guide to integrate the Deno language server with your editor:
// https://deno.land/manual/getting_started/setup_your_environment
// This enables autocomplete, go to definition, etc.

// Setup type definitions for built-in Supabase Runtime APIs
/*import "jsr:@supabase/functions-js/edge-runtime.d.ts"

console.log("Hello from Functions!")

Deno.serve(async (req) => {
  const { name } = await req.json()
  const data = {
    message: `Hello ${name}!`,
  }

  return new Response(
    JSON.stringify(data),
    { headers: { "Content-Type": "application/json" } },
  )
})*/

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/admin-create-user' \
    --header 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0' \
    --header 'Content-Type: application/json' \
    --data '{"name":"Functions"}'

*/

// supabase/functions/admin-create-user/index.ts
// (Facultatif) Types pour l’auto-complétion dans l’éditeur
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

type Role = "visiteur" | "technicien" | "super-admin";
type Payload =
  | { action: "create"; email: string; password: string; role?: Role }
  | { action: "update"; userId: string; password?: string; role?: Role }
  | { action: "delete"; userId: string };

const URL   = Deno.env.get("APP_SUPABASE_URL")!;
const SROLE = Deno.env.get("SERVICE_ROLE_KEY")!; // clé service_role (SECRÈTE)

// CORS permissif (appel direct depuis Flutter/web)
const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
} as const;

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: CORS_HEADERS });
}
function isRole(v: unknown): v is Role {
  return v === "visiteur" || v === "technicien" || v === "super-admin";
}

Deno.serve(async (req) => {
  // Préflight CORS
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const admin = createClient(URL, SROLE);

  // AuthN: l’appelant doit être super-admin
  const auth = req.headers.get("Authorization") ?? "";
  const jwt  = auth.replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "Missing Authorization" }, 401);

  const { data: me, error: meErr } = await admin.auth.getUser(jwt);
  if (meErr || !me?.user) return json({ error: "Invalid or expired token" }, 401);

  // Rôle depuis metadata puis fallback table public.users
  let myRole: string | undefined = (me.user.user_metadata as any)?.role;
  if (!myRole) {
    const { data: row } = await admin.from("users").select("role").eq("id", me.user.id).maybeSingle();
    myRole = row?.role;
  }
  if (myRole !== "super-admin") return json({ error: "forbidden" }, 403);

  // Corps de requête
  let body: Partial<Payload>;
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400); }
  const action = body.action;
  if (!action) return json({ error: "Missing action" }, 400);

  // -------- Actions --------
  if (action === "create") {
    const email = (body.email ?? "").trim();
    const password = (body.password ?? "").trim();
    const role: Role = isRole(body.role) ? body.role! : "visiteur";
    if (!email || !password) return json({ error: "email & password required" }, 400);

    const { data: created, error: cErr } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { role },
    });
    if (cErr || !created?.user) return json({ error: cErr?.message ?? "createUser failed" }, 400);

    await admin.from("users").upsert({ id: created.user.id, email, role });
    return json({ ok: true, id: created.user.id, email, role });
  }

  if (action === "update") {
    const userId = (body.userId ?? "").trim();
    if (!userId) return json({ error: "userId required" }, 400);

    const updates: any = {};
    if (body.password && body.password.trim()) updates.password = body.password.trim();
    if (body.role) {
      if (!isRole(body.role)) return json({ error: "invalid role" }, 400);
      updates.user_metadata = { role: body.role };
    }
    if (Object.keys(updates).length === 0) return json({ error: "nothing to update" }, 400);

    const { error: uErr } = await admin.auth.admin.updateUserById(userId, updates);
    if (uErr) return json({ error: uErr.message }, 400);

    if (body.role) await admin.from("users").update({ role: body.role }).eq("id", userId);
    return json({ ok: true });
  }

  if (action === "delete") {
    const userId = (body.userId ?? "").trim();
    if (!userId) return json({ error: "userId required" }, 400);

    const { error: dErr } = await admin.auth.admin.deleteUser(userId);
    if (dErr) return json({ error: dErr.message }, 400);

    await admin.from("users").delete().eq("id", userId);
    return json({ ok: true });
  }

  return json({ error: "Unknown action" }, 400);
});
