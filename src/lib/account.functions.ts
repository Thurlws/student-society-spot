import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

/**
 * Deletes the caller's own account. The profile and everything that belongs to it cascade
 * (memberships, registrations, messages, requests); society records keep running without the name
 * (migration 0012). A suspended account can't delete itself.
 */
export const deleteMyAccount = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    // Deleting and signing up again would shake off a suspension (migration 0025).
    const { data: member } = await supabaseAdmin
      .from("university_members")
      .select("suspended_at")
      .eq("user_id", context.userId)
      .maybeSingle();
    if (member?.suspended_at)
      throw new Error(
        "Your account is suspended, so it can't be deleted here. Ask your university.",
      );
    const { error } = await supabaseAdmin.auth.admin.deleteUser(context.userId);
    if (error)
      throw new Error("Couldn't delete your account. Try again, or contact the SocConnect team.");
    return { ok: true };
  });
