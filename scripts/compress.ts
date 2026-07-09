#!/usr/bin/env bun
/**
 * Convert any supported image to WebP using Bun's native file + image APIs.
 *
 * Usage:
 *   bun run scripts/compress.ts --input <path> --output <path> [--quality 80]
 *
 * Prints one JSON line to stdout on success:
 *   { "ok": true, "input": "...", "output": "...", "inputBytes": N, "outputBytes": N, "quality": 80 }
 */

const IMAGE_EXT = new Set([
  ".jpg",
  ".jpeg",
  ".png",
  ".webp",
  ".gif",
  ".bmp",
  ".tif",
  ".tiff",
  ".heic",
  ".heif",
  ".avif",
]);

type Args = {
  input: string;
  output: string;
  quality: number;
};

function usage(message?: string): never {
  if (message) console.error(message);
  console.error(
    "Usage: bun run scripts/compress.ts --input <path> --output <path> [--quality 80]",
  );
  process.exit(1);
}

function parseArgs(argv: string[]): Args {
  let input = "";
  let output = "";
  let quality = 80;

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const next = argv[i + 1];
    if (arg === "--input" || arg === "-i") {
      if (!next) usage("Missing value for --input");
      input = next;
      i++;
    } else if (arg === "--output" || arg === "-o") {
      if (!next) usage("Missing value for --output");
      output = next;
      i++;
    } else if (arg === "--quality" || arg === "-q") {
      if (!next) usage("Missing value for --quality");
      quality = Number(next);
      i++;
    } else if (arg === "--help" || arg === "-h") {
      usage();
    } else {
      usage(`Unknown argument: ${arg}`);
    }
  }

  if (!input) usage("Missing --input");
  if (!output) usage("Missing --output");
  if (!Number.isFinite(quality) || quality < 1 || quality > 100) {
    usage("--quality must be an integer from 1 to 100");
  }

  return { input, output, quality: Math.round(quality) };
}

function extensionOf(path: string): string {
  const base = path.split(/[/\\]/).pop() ?? path;
  const dot = base.lastIndexOf(".");
  if (dot <= 0) return "";
  return base.slice(dot).toLowerCase();
}

function defaultOutputPath(input: string): string {
  const ext = extensionOf(input);
  if (ext === ".webp") {
    return input.slice(0, -ext.length) + ".compressed.webp";
  }
  if (ext) {
    return input.slice(0, -ext.length) + ".webp";
  }
  return input + ".webp";
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const inputPath = args.input;
  const outputPath = args.output || defaultOutputPath(inputPath);
  const quality = args.quality;

  const ext = extensionOf(inputPath);
  if (ext && !IMAGE_EXT.has(ext)) {
    console.error(`Unsupported image extension: ${ext}`);
    process.exit(2);
  }

  const inputFile = Bun.file(inputPath);
  if (!(await inputFile.exists())) {
    console.error(`Input file not found: ${inputPath}`);
    process.exit(2);
  }

  const inputBytes = inputFile.size;
  if (inputBytes === 0) {
    console.error(`Input file is empty: ${inputPath}`);
    process.exit(2);
  }

  try {
    await Bun.file(inputPath)
      .image()
      .webp({ quality })
      .write(outputPath);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`Failed to convert image: ${message}`);
    process.exit(3);
  }

  const outputFile = Bun.file(outputPath);
  if (!(await outputFile.exists()) || outputFile.size === 0) {
    console.error("WebP output was not written");
    process.exit(3);
  }

  const result = {
    ok: true as const,
    input: inputPath,
    output: outputPath,
    inputBytes,
    outputBytes: outputFile.size,
    quality,
  };

  process.stdout.write(JSON.stringify(result) + "\n");
}

main();
