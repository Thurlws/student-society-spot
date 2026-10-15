import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

/**
 * Deletes the caller's own account. The profile and everything that belongs to it cascade
 * (memberships, registrations, messages, requests); society records keep running without the name
 * (migration 0012).
 */
export const deleteMyAccount = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { error } = await supabaseAdmin.auth.admin.deleteUser(context.userId);
    if (error) throw new Error("Couldn't delete your account. Try again, or contact the SocConnect team.");
    return { ok: true };
  });
