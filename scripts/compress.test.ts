import { describe, expect, test } from "bun:test";
import { mkdirSync, rmSync } from "node:fs";
import { join } from "node:path";

const root = join(import.meta.dir, "..");
const fixture = join(root, "uiexample.webp");
const outDir = join(root, ".tmp-compress-test");

async function runCompress(args: string[]) {
  const proc = Bun.spawn({
    cmd: ["bun", "run", join(root, "scripts/compress.ts"), ...args],
    stdout: "pipe",
    stderr: "pipe",
    cwd: root,
  });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  return { stdout, stderr, exitCode };
}

describe("compress.ts", () => {
  test("converts webp with quality and reports sizes", async () => {
    rmSync(outDir, { recursive: true, force: true });
    mkdirSync(outDir, { recursive: true });
    const out = join(outDir, "out-q80.webp");

    const { stdout, stderr, exitCode } = await runCompress([
      "--input",
      fixture,
      "--output",
      out,
      "--quality",
      "80",
    ]);

    expect(exitCode).toBe(0);
    expect(stderr).toBe("");
    const result = JSON.parse(stdout.trim());
    expect(result.ok).toBe(true);
    expect(result.quality).toBe(80);
    expect(result.inputBytes).toBeGreaterThan(0);
    expect(result.outputBytes).toBeGreaterThan(0);
    expect(await Bun.file(out).exists()).toBe(true);
  });

  test("lower quality yields smaller or equal files", async () => {
    mkdirSync(outDir, { recursive: true });
    const hi = join(outDir, "hi.webp");
    const lo = join(outDir, "lo.webp");

    const a = await runCompress([
      "--input",
      fixture,
      "--output",
      hi,
      "--quality",
      "95",
    ]);
    const b = await runCompress([
      "--input",
      fixture,
      "--output",
      lo,
      "--quality",
      "20",
    ]);

    expect(a.exitCode).toBe(0);
    expect(b.exitCode).toBe(0);
    const hiSize = JSON.parse(a.stdout.trim()).outputBytes as number;
    const loSize = JSON.parse(b.stdout.trim()).outputBytes as number;
    expect(loSize).toBeLessThanOrEqual(hiSize);
  });

  test("rejects missing input", async () => {
    const { exitCode } = await runCompress([
      "--input",
      join(outDir, "missing.png"),
      "--output",
      join(outDir, "x.webp"),
      "--quality",
      "80",
    ]);
    expect(exitCode).not.toBe(0);
  });
});
