#!/usr/bin/env bun
/**
 * Build a small PNG thumbnail for the compressor UI preview.
 *
 * Usage:
 *   bun run scripts/preview.ts --input <path> [--size 192]
 *
 * Writes raw PNG bytes to stdout (kept small for fx.spawn collect).
 */

type Args = {
  input: string;
  size: number;
};

function usage(message?: string): never {
  if (message) console.error(message);
  console.error("Usage: bun run scripts/preview.ts --input <path> [--size 192]");
  process.exit(1);
}

function parseArgs(argv: string[]): Args {
  let input = "";
  let size = 192;

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const next = argv[i + 1];
    if (arg === "--input" || arg === "-i") {
      if (!next) usage("Missing value for --input");
      input = next;
      i++;
    } else if (arg === "--size" || arg === "-s") {
      if (!next) usage("Missing value for --size");
      size = Number(next);
      i++;
    } else if (arg === "--help" || arg === "-h") {
      usage();
    } else {
      usage(`Unknown argument: ${arg}`);
    }
  }

  if (!input) usage("Missing --input");
  if (!Number.isFinite(size) || size < 32 || size > 512) {
    usage("--size must be an integer from 32 to 512");
  }

  return { input, size: Math.round(size) };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const inputFile = Bun.file(args.input);
  if (!(await inputFile.exists())) {
    console.error(`Input file not found: ${args.input}`);
    process.exit(2);
  }

  try {
    const bytes = await Bun.file(args.input)
      .image()
      .resize(args.size, args.size, { fit: "inside", withoutEnlargement: true })
      .png()
      .bytes();
    if (bytes.length === 0) {
      console.error("Preview encode produced empty output");
      process.exit(3);
    }
    process.stdout.write(bytes);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`Failed to build preview: ${message}`);
    process.exit(3);
  }
}

main();
