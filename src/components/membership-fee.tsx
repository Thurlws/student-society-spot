import { CreditCard, ExternalLink, Loader2 } from "lucide-react";
import { useState, type ReactNode } from "react";
import { toast } from "sonner";
import { useData } from "@/lib/api/store";
import { formatDate, formatEuro, toDublin } from "@/lib/format";
import type { FeePayment, Society } from "@/lib/types";
import { safeHref } from "@/lib/utils";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";

// SocConnect takes no real payments yet (migration 0035). Every place a fee can be "paid" says
// so, and committees see demo payments marked as demo, so nobody mistakes one for money.

/** How a paid fee reads, for the member and the committee alike. */
function feePaidLabel(fee: FeePayment) {
  return fee.how === "demo" ? "Paid (demo, no money taken)" : "Paid, confirmed by the committee";
}

function DemoNotice() {
  return (
    <div className="rounded-lg border border-dashed border-warning bg-warning/5 p-3 text-sm">
      <p className="font-semibold">Demo checkout</p>
      <p className="mt-1 text-muted-foreground">
        No money is taken and no card details are asked. SocConnect doesn't take real payments yet,
        so this only shows how paying will work.
      </p>
    </div>
  );
}

function PayForReal({ society }: { society: Society }) {
  const href = safeHref(society.joinUrl);
  if (!href) return null;
  return (
    <a
      href={href}
      target="_blank"
      rel="noreferrer"
      className="inline-flex items-center gap-1 text-sm text-primary underline"
    >
      Pay for real on the society's official page
      <ExternalLink className="size-3.5" />
    </a>
  );
}

/**
 * Joining a society with a fee: join and pay through the demo checkout, or join and pay later.
 * `children` is the button that opens it.
 */
export function JoinWithFeeDialog({
  society,
  children,
}: {
  society: Society;
  children: ReactNode;
}) {
  const { joinSociety, payMembershipFeeDemo } = useData();
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState<"pay" | "later" | null>(null);
  const fee = formatEuro(society.membershipFeeCents ?? 0);
  const joined = society.requiresApproval
    ? `Request sent to ${society.shortName}`
    : `Welcome to ${society.shortName}!`;
  const join = async (pay: boolean) => {
    setBusy(pay ? "pay" : "later");
    const o = await joinSociety(society.id);
    if (!o.ok) {
      setBusy(null);
      return void toast.error(o.error);
    }
    if (pay) {
      const p = await payMembershipFeeDemo(society.id);
      if (!p.ok) toast.error(`${joined}, but the demo payment failed: ${p.error}`);
      else toast.success(`${joined} Demo payment of ${fee} recorded, no money taken.`);
    } else toast.success(`${joined} You can pay the ${fee} fee later.`);
    setBusy(null);
    setOpen(false);
  };
  return (
    <Dialog open={open} onOpenChange={(o) => !busy && setOpen(o)}>
      <DialogTrigger asChild>{children}</DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>
            {society.requiresApproval ? "Ask to join" : "Join"} {society.shortName}
          </DialogTitle>
          <DialogDescription>
            Membership costs {fee}.
            {society.requiresApproval && " The committee still reviews your request."}
          </DialogDescription>
        </DialogHeader>
        <DemoNotice />
        <PayForReal society={society} />
        <DialogFooter className="gap-2">
          <Button variant="ghost" disabled={!!busy} onClick={() => join(false)}>
            {busy === "later" && <Loader2 className="animate-spin" />}
            Join, pay later
          </Button>
          <Button disabled={!!busy} onClick={() => join(true)}>
            {busy === "pay" ? <Loader2 className="animate-spin" /> : <CreditCard />}
            Join and pay {fee} (demo)
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/** The fee and whether you've paid it, for the society page. */
export function FeeStatus({ society }: { society: Society }) {
  const { membership, myFee, payMembershipFeeDemo, canManage } = useData();
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  if (!society.membershipFeeCents) return null;
  const fee = formatEuro(society.membershipFeeCents);
  const status = membership(society.id);
  const paid = myFee(society.id);
  // The committee holds no membership row, so it has nothing to pay.
  const canPay = status === "pending" || (status === "member" && !canManage(society.id));
  return (
    <div className="mt-3 space-y-2 border-t pt-3">
      <p>
        <span className="font-semibold">Membership fee: </span>
        <span className="text-muted-foreground">{fee}</span>
      </p>
      {paid ? (
        <p className="text-muted-foreground">
          {feePaidLabel(paid)}, {formatDate(toDublin(paid.paidAt).date)}.
        </p>
      ) : canPay ? (
        <>
          <p className="text-muted-foreground">Not paid yet.</p>
          <Button size="sm" onClick={() => setOpen(true)}>
            <CreditCard />
            Pay {fee} (demo)
          </Button>
        </>
      ) : null}
      {!paid && <PayForReal society={society} />}
      <Dialog open={open} onOpenChange={(o) => !busy && setOpen(o)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              Pay {fee} to {society.shortName}
            </DialogTitle>
            <DialogDescription>Your membership fee.</DialogDescription>
          </DialogHeader>
          <DemoNotice />
          <DialogFooter>
            <Button variant="ghost" disabled={busy} onClick={() => setOpen(false)}>
              Cancel
            </Button>
            <Button
              disabled={busy}
              onClick={async () => {
                setBusy(true);
                const o = await payMembershipFeeDemo(society.id);
                setBusy(false);
                if (!o.ok) return void toast.error(o.error);
                toast.success(`Demo payment of ${fee} recorded, no money taken.`);
                setOpen(false);
              }}
            >
              {busy ? <Loader2 className="animate-spin" /> : <CreditCard />}
              Complete demo payment
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

/** Whether a member paid the fee, as the committee sees it. A demo payment says so. */
export function FeeBadge({ fee }: { fee: FeePayment | undefined }) {
  return (
    <Badge variant={fee ? (fee.how === "demo" ? "warning" : "success") : "outline"}>
      {fee ? (fee.how === "demo" ? "Paid (demo)" : "Paid") : "Unpaid"}
    </Badge>
  );
}

const euros = (cents: number | undefined) =>
  cents ? (cents / 100).toFixed(2).replace(/\.00$/, "") : "";

/** The committee's view: set the fee, see who has paid and how, mark payments made elsewhere. */
export function CommitteeFees({ society }: { society: Society }) {
  const { feesEnabled, societyMembers, setMembershipFee, setMembershipFeePaid } = useData();
  const [amount, setAmount] = useState(() => euros(society.membershipFeeCents));
  const [busy, setBusy] = useState(false);
  if (!feesEnabled) return null;
  const members = societyMembers.filter((m) => m.societyId === society.id);
  const paid = members.filter((m) => m.fee);
  const demo = paid.filter((m) => m.fee?.how === "demo").length;
  return (
    <section className="rounded-xl border bg-card p-5 shadow-soft">
      <h2 className="font-semibold">Membership fee</h2>
      <p className="mt-1 text-sm text-muted-foreground">
        SocConnect doesn't take real payments yet. Members can use the demo checkout, which takes no
        money, and you can mark people who paid you another way.
      </p>
      <form
        className="mt-4 flex items-end gap-2"
        onSubmit={async (e) => {
          e.preventDefault();
          setBusy(true);
          const o = await setMembershipFee(society.id, amount);
          setBusy(false);
          if (!o.ok) return void toast.error(o.error);
          toast.success(
            amount.trim() ? "Membership fee saved" : `${society.shortName} is free to join`,
          );
        }}
      >
        <div className="space-y-1.5">
          <Label htmlFor="fee">Fee in euros</Label>
          <Input
            id="fee"
            inputMode="decimal"
            className="w-32"
            placeholder="Free"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
          />
        </div>
        <Button type="submit" variant="outline" disabled={busy}>
          {busy && <Loader2 className="animate-spin" />}
          Save fee
        </Button>
      </form>
      {!!society.membershipFeeCents && (
        <>
          <p className="mt-5 text-sm font-medium">
            {paid.length} of {members.length} paid
            {demo > 0 && `, ${demo} through the demo checkout`}
          </p>
          {members.length === 0 ? (
            <p className="py-4 text-center text-sm text-muted-foreground">No members yet.</p>
          ) : (
            <ul className="mt-2 divide-y">
              {members.map((m) => (
                <li key={m.membershipId} className="flex items-center justify-between gap-3 py-2">
                  <span className="text-sm">
                    {m.name}
                    {m.status === "pending" && (
                      <span className="ml-2 text-xs text-muted-foreground">waiting to join</span>
                    )}
                  </span>
                  <span className="flex shrink-0 items-center gap-2">
                    <FeeBadge fee={m.fee} />
                    <Button
                      size="sm"
                      variant="ghost"
                      aria-label={m.fee ? `Mark ${m.name} unpaid` : `Mark ${m.name} paid`}
                      onClick={async () => {
                        const o = await setMembershipFeePaid(m.membershipId, !m.fee);
                        if (!o.ok) toast.error(o.error);
                      }}
                    >
                      {m.fee ? "Undo" : "Mark paid"}
                    </Button>
                  </span>
                </li>
              ))}
            </ul>
          )}
        </>
      )}
    </section>
  );
}
