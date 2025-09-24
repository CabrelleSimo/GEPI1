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

// Deno / Supabase Edge Function
// deno-lint-ignore-file no-explicit-any
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceKey  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (req) => {
  // CORS simple
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: cors() });
  }

  try {
    const body = await req.json().catch(() => ({}));
    const action: string = body?.action ?? "";

    // client pour lire le user appelant (avec son JWT)
    const supabaseUserClient = createClient(
      supabaseUrl,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
    );
    const { data: me } = await supabaseUserClient.auth.getUser();
    const meId = me?.user?.id;
    if (!meId) return json({ error: "Unauthorized" }, 401);

    // vérifier super-admin via la table applicative
    const { data: meRow, error: roleErr } = await supabaseUserClient
      .from("users").select("role").eq("id", meId).maybeSingle();
    if (roleErr) return json({ error: roleErr.message }, 500);
    if ((meRow?.role ?? "") !== "super-admin") {
      return json({ error: "Forbidden (super-admin only)" }, 403);
    }

    // client admin (service role) pour agir sur auth.users
    const admin = createClient(supabaseUrl, serviceKey);

    if (action === "create") {
      const email: string = body.email ?? "";
      const password: string = body.password ?? "";
      const role: string = body.role ?? "visiteur";
      if (!email || !password) return json({ error: "email & password required" }, 400);

      const { data: created, error } = await admin.auth.admin.createUser({
        email, password, email_confirm: true, user_metadata: { role },
      });
      if (error) return json({ error: error.message }, 400);

      const uid = created.user?.id;
      if (!uid) return json({ error: "no user id returned" }, 500);

      // sync table applicative
      const { error: insErr } = await admin.from("users").insert({
        id: uid, email, role,
      });
      if (insErr) return json({ error: insErr.message }, 400);

      return json({ ok: true, id: uid });
    }

    if (action === "update") {
      const userId: string = body.userId ?? "";
      if (!userId) return json({ error: "userId required" }, 400);

      const password: string | undefined = body.password;
      const role: string | undefined = body.role;

      // maj auth
      if (password || role) {
        const { error: upAuthErr } = await admin.auth.admin.updateUserById(userId, {
          password: password,
          user_metadata: role ? { role } : undefined,
        });
        if (upAuthErr) return json({ error: upAuthErr.message }, 400);
      }

      // maj table applicative
      if (role) {
        const { error: upTblErr } = await admin.from("users")
          .update({ role }).eq("id", userId);
        if (upTblErr) return json({ error: upTblErr.message }, 400);
      }

      return json({ ok: true });
    }

    if (action === "delete") {
      const userId: string = body.userId ?? "";
      if (!userId) return json({ error: "userId required" }, 400);

      // ne pas permettre de se supprimer soi-même
      if (userId === meId) return json({ error: "cannot delete self" }, 400);

      const { error: delAuthErr } = await admin.auth.admin.deleteUser(userId);
      if (delAuthErr) return json({ error: delAuthErr.message }, 400);

      const { error: delTblErr } = await admin.from("users").delete().eq("id", userId);
      if (delTblErr) return json({ error: delTblErr.message }, 400);

      return json({ ok: true });
    }

    return json({ error: "Unknown action" }, 400);
  } catch (e) {
    return json({ error: e?.message ?? "Unexpected error" }, 500);
  }
}, { onListen: () => console.log("admin-create-user running") });

function cors() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}

function json(obj: any, status = 200) {
  return new Response(JSON.stringify(obj), { status, headers: { "content-type": "application/json", ...cors() } });
}
