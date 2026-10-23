	ReadInputSchema$1 = object({
		path: string().describe("Path to a text file. Relative paths resolve against the working directory; a path outside the working directory must be absolute. Directories are not supported; use `ls` via Bash for a known directory, or Glob for pattern search."),
		line_offset: union([PositiveLineOffsetSchema$1, TailLineOffsetSchema$1]).optional().describe(`The line number to start reading from. Omit to start at line 1. Negative values read from the end of the file; the absolute value cannot exceed ${String(MAX_LINES$2)}.`),
		n_lines: number$1().int().positive().optional().describe(`The number of lines to read; the tool also applies its internal cap. Omit to read up to the internal cap of ${String(MAX_LINES$2)} lines.`)
	});

	ReadMediaFileInputSchema$1 = object({
		path: string().describe("Path to an image or video file. Relative paths resolve against the working directory; a path outside the working directory must be absolute. Directories and text files are not supported."),
		region: object({
			x: number$1().int().min(0).describe("Left edge of the crop, in original-image pixels."),
			y: number$1().int().min(0).describe("Top edge of the crop, in original-image pixels."),
			width: number$1().int().min(1).describe("Crop width, in original-image pixels."),
			height: number$1().int().min(1).describe("Crop height, in original-image pixels.")
		}).optional().describe("Images only: view just this rectangle of the image (original-image pixel coordinates). Use after a downsampled full view to inspect fine detail — a region within the size limits is delivered at full fidelity."),
		full_resolution: boolean$1().optional().describe("Images only: skip the default downscaling and view at native resolution. Fails with an explicit error when the payload would exceed the per-image byte limit; use region for files that large.")
	});

	GlobInputSchema$1 = object({
		pattern: string().describe("Glob pattern to match files."),
		path: string().optional().describe("Directory to search. Accepts an absolute path, or a path relative to the current working directory. Defaults to the current working directory."),
		include_ignored: boolean$1().optional().describe("Also match files excluded by ignore files such as `.gitignore`, `.ignore`, and `.rgignore` (for example `node_modules` or build outputs). Sensitive files (such as `.env`) remain filtered out for safety. VCS metadata directories (`.git` and similar) are always skipped, even when this is true. Defaults to false."),
		include_dirs: boolean$1().optional().describe("Deprecated and ignored. Results are always files-only — directories are never listed. Accepted only so older calls that still pass this flag are not rejected by parameter validation.")
	});

	GrepInputSchema$1 = object({
		pattern: string().describe("Regular expression to search for."),
		path: string().optional().describe("File or directory to search. Accepts an absolute path, or a path relative to the current working directory. Omit to search the current working directory. Use Read instead when you already know a concrete file path and need its contents."),
		glob: string().optional().describe("Optional glob filter for which files to search, e.g. `*.ts`. Matched against each file's full absolute path, so a path-anchored pattern like `src/**/*.ts` silently matches nothing — use a basename pattern (`*.ts`), or anchor with `**/` (`**/src/**/*.ts`). To scope the search to a directory, use `path` instead."),
		type: string().optional().describe("Optional ripgrep file type filter, such as ts or py. Prefer this over `glob` when filtering by language or file kind: it is more efficient and less error-prone than an equivalent glob pattern."),
		output_mode: _enum([
			"content",
			"files_with_matches",
			"count_matches"
		]).optional().describe("Shape of the result. `content` shows matching lines (honors `-A`, `-B`, `-C`, `-n`, and `head_limit`); `files_with_matches` shows only the paths of files that contain a match, most-recently-modified first (honors `head_limit`); `count_matches` shows per-file match counts as `path:count` lines, preceded by an aggregate total line. Defaults to `files_with_matches`."),
		"-i": boolean$1().optional().describe("Perform a case-insensitive search. Defaults to false."),
		"-n": boolean$1().optional().describe("Prefix each matching line with its line number. Applies only when `output_mode` is `content`. Defaults to true."),
		"-A": number$1().int().nonnegative().optional().describe("Number of lines to show after each match. Applies only when `output_mode` is `content`."),
		"-B": number$1().int().nonnegative().optional().describe("Number of lines to show before each match. Applies only when `output_mode` is `content`."),
		"-C": number$1().int().nonnegative().optional().describe("Number of lines to show before and after each match. Applies only when `output_mode` is `content`; takes precedence over `-A` and `-B`."),
		head_limit: number$1().int().nonnegative().optional().describe("Limit output to the first N lines/entries after offset. Defaults to 250. Pass 0 for unlimited."),
		offset: number$1().int().nonnegative().optional().describe("Number of leading lines/entries to skip before applying `head_limit`. Use it together with `head_limit` to page through large result sets. Defaults to 0."),
		multiline: boolean$1().optional().describe("Enable multiline matching, where the pattern can span line boundaries and `.` also matches newlines. Defaults to false."),
		include_ignored: boolean$1().optional().describe("Also search files excluded by ignore files such as `.gitignore`, `.ignore`, and `.rgignore` (for example `node_modules` or build outputs). Sensitive files (such as `.env`) remain filtered out for safety. VCS metadata directories (`.git` and similar) are always skipped, even when this is true. Defaults to false.")
	});
