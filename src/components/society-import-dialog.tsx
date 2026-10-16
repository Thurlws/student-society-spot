import { useQueryClient } from "@tanstack/react-query";
import { Download, FileUp, Loader2 } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { importSocieties } from "@/lib/api/admin";
import { importTemplate, readSocietyCsv, type ImportRow } from "@/lib/society-import";
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
} from "@/components/ui/dialog";

/** /admin: create or update a university's societies from a CSV file (migration 0028). */
export function SocietyImportDialog({
  universityId,
  universityName,
  onClose,
}: {
  universityId: string;
  universityName: string;
  onClose: () => void;
}) {
  const qc = useQueryClient();
  const [file, setFile] = useState<{ name: string; rows: ImportRow[]; problems: string[] }>();
  const [busy, setBusy] = useState(false);

  const read = async (f: File | undefined) => {
    if (!f) return setFile(undefined);
    const { rows, problems } = readSocietyCsv(await f.text());
    setFile({ name: f.name, rows, problems });
  };
  const blocking = file?.problems.filter((p) => !p.startsWith("Columns that will be ignored"));

  const run = async () => {
    if (!file || blocking?.length) return;
    setBusy(true);
    const o = await importSocieties(universityId, file.rows);
    setBusy(false);
    if (!o.ok) return void toast.error(o.error);
    toast.success(
      `${o.result.created} new ${o.result.created === 1 ? "society" : "societies"}, ${o.result.updated} updated`,
    );
    void qc.invalidateQueries({ queryKey: ["admin"] });
    void qc.invalidateQueries({ queryKey: ["app-data"] });
    onClose();
  };

  const template = () => {
    const a = Object.assign(document.createElement("a"), {
      href: URL.createObjectURL(new Blob([importTemplate()], { type: "text/csv" })),
      download: "societies-template.csv",
    });
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  };

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Import {universityName} societies</DialogTitle>
          <DialogDescription>
            A CSV file with one society per row, saved from a spreadsheet. Importing the same file
            again updates the societies instead of adding them twice. Taglines, descriptions and
            meeting times a committee has changed are kept, and no society is ever deleted.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <Button type="button" variant="outline" size="sm" onClick={template}>
            <Download />
            Download a template
          </Button>
          <div className="space-y-1.5">
            <Label htmlFor="import-file">File</Label>
            <Input
              id="import-file"
              type="file"
              accept=".csv,text/csv"
              onChange={(e) => void read(e.target.files?.[0])}
            />
          </div>
          {file && (
            <div className="space-y-2 text-sm">
              <p>
                {file.rows.length} {file.rows.length === 1 ? "society" : "societies"} in {file.name}
                {file.rows.length > 0 &&
                  `: ${file.rows
                    .slice(0, 3)
                    .map((r) => r.name)
                    .join(", ")}${file.rows.length > 3 ? " and more" : ""}`}
                .
              </p>
              {file.problems.length > 0 && (
                <ul className="list-disc space-y-1 pl-5 text-destructive">
                  {file.problems.slice(0, 8).map((p) => (
                    <li key={p}>{p}</li>
                  ))}
                  {file.problems.length > 8 && <li>And {file.problems.length - 8} more.</li>}
                </ul>
              )}
            </div>
          )}
        </div>
        <DialogFooter>
          <Button type="button" variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button onClick={run} disabled={!file || !!blocking?.length || busy}>
            {busy ? <Loader2 className="animate-spin" /> : <FileUp />}
            Import
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
