import { MAILPIT, adminClient, isoDate, people, societies } from "./support";

const check = (r: { error: { message: string } | null }, what: string) => {
  if (r.error) throw new Error(`${what}: ${r.error.message}`);
};

/** Fresh accounts, societies and an event for every run, so journeys never depend on leftovers. */
export default async function globalSetup() {
  const admin = adminClient();

  const { data: list } = await admin.auth.admin.listUsers({ perPage: 1000 });
  for (const u of list.users.filter((u) => u.email?.startsWith("e2e-")))
    check(await admin.auth.admin.deleteUser(u.id), "delete old account");
  check(await admin.from("societies").delete().like("slug", "e2e-%"), "delete old societies");
  await fetch(`${MAILPIT}/api/v1/messages`, { method: "DELETE" });

  const tud = await admin.from("universities").select("id").eq("slug", "tudublin").single();
  check(tud, "find TU Dublin");
  const university = tud.data!.id;

  check(
    await admin.from("societies").insert([
      {
        university_id: university,
        slug: societies.open.slug,
        name: societies.open.name,
        short_name: societies.open.shortName,
        category: "Community",
        tagline: "Everyone welcome",
        description: "A society for the journey tests.",
        requires_approval: false,
      },
      {
        university_id: university,
        slug: societies.approval.slug,
        name: societies.approval.name,
        short_name: societies.approval.shortName,
        category: "Community",
        tagline: "Ask to join",
        description: "A society that reviews new members.",
        requires_approval: true,
      },
    ]),
    "create societies",
  );
  const rows = await admin.from("societies").select("id, slug").like("slug", "e2e-%");
  check(rows, "read societies");
  const id = (slug: string) => rows.data!.find((r) => r.slug === slug)!.id;
  const open = id(societies.open.slug);
  const approval = id(societies.approval.slug);
  // Claimed when the chair's account is created below.
  check(
    await admin.from("role_invites").insert([
      { email: people.chair.email, society_id: open, role: "committee", position: "Chair" },
      { email: people.chair.email, society_id: approval, role: "committee", position: "Chair" },
    ]),
    "invite the chair",
  );

  for (const p of [
    people.chair,
    people.member,
    people.student,
    people.returning,
    people.uniadmin,
  ]) {
    const created = await admin.auth.admin.createUser({ email: p.email, email_confirm: true });
    check(created, `create ${p.email}`);
    const uid = created.data.user!.id;
    check(
      await admin
        .from("profiles")
        .update({
          display_name: p.name,
          course: "TU856 — Computer Science",
          year: "Year 2",
          onboarded_at: new Date().toISOString(),
        })
        .eq("id", uid),
      "set up profile",
    );
    if (p === people.member)
      check(
        await admin
          .from("society_memberships")
          .insert({ society_id: open, user_id: uid, status: "member" }),
        "add member",
      );
    if (p === people.uniadmin)
      check(
        await admin.from("university_admins").insert({ university_id: university, user_id: uid }),
        "make a university admin",
      );
  }

  check(
    await admin.from("events").insert({
      society_id: open,
      title: "E2E quiz night",
      description: "Teams of four.",
      venue: "Aungier St, room 2.01",
      category: "Social",
      starts_at: `${isoDate(10)}T19:00:00Z`,
      capacity: 30,
      tags: ["Social"],
    }),
    "create an event",
  );
}
