// main.mjs lines 128145-128152
function canonicalizePath$1(path, cwd, pathClass = DEFAULT_PATH_CLASS$1) {
	if (path === "") throw new PathSecurityError$1("PATH_INVALID", path, path, "Path cannot be empty");
	const normalizedPath = normalizeUserPath$1(path, pathClass);
	if (pathClass === "win32" && isWin32DriveRelative$1(normalizedPath)) throw new PathSecurityError$1("PATH_INVALID", path, normalizedPath, `"${path}" is a drive-relative Windows path. Use an absolute path like C:\\path or a path relative to the working directory.`);
	if (!isAbsolute$2(normalizedPath) && !isAbsolute$2(cwd)) throw new PathSecurityError$1("PATH_INVALID", path, normalizedPath, `Cannot resolve "${path}" against non-absolute cwd "${cwd}".`);
	const abs = isAbsolute$2(normalizedPath) ? normalizedPath : resolve$2(cwd, normalizedPath);
	return normalize$1(abs);
}

// main.mjs lines 128178-128183
function resolvePathAccess$1(path, cwd, config, options) {
	const pathClass = options.pathClass ?? DEFAULT_PATH_CLASS$1;
	const expandedPath = expandUserPath$3(normalizeUserPath$1(path, pathClass), options.homeDir, pathClass);
	const rawIsAbsolute = isAbsolute$2(expandedPath);
	const canonical = canonicalizePath$1(expandedPath, cwd, pathClass);
	const outsideWorkspace = !isWithinWorkspace$1(canonical, config, pathClass);

// main.mjs lines 128196-128205
}
function resolvePathAccessPath$1(path, options) {
	const { kaos, workspace, operation, policy, expandHome = true } = options;
	return resolvePathAccess$1(path, workspace.workspaceDir, workspace, {
		operation,
		policy,
		pathClass: kaos.pathClass(),
		homeDir: expandHome ? kaos.gethome() : void 0
	}).path;
}

// main.mjs lines 139632-139680
	} catch (error) {
		return error instanceof Error ? error.message : String(error);
	}
	return validateToolArgs$1(validator, args);
}
async function prepareToolCall(step, call) {
	const settleError = async (args, output, displayFields) => {
		await dispatchToolCall(step, call, args, displayFields);
		return { task: makeResolvedToolCallTask(makeErrorToolResult$1(call, args, output)) };
	};
	const settleSynthetic = async (args, result, displayFields) => {
		const coerced = coerceToolResult$1(result, call.toolName);
		await dispatchToolCall(step, call, args, displayFields);
		return {
			task: makeResolvedToolCallTask(makeToolResult(call, args, coerced)),
			stopBatchAfterThis: toolResultStopsTurn(coerced)
		};
	};
	if (call.kind === "rejected") return settleError(call.args, call.output);
	const decision = await runPrepareToolExecutionHook(step, call);
	if (decision.kind === "blocked" || decision.kind === "hookFailed") return settleError(decision.args, decision.output);
	if (decision.kind === "synthetic") return settleSynthetic(decision.args, decision.result);
	const validationError = validateExecutableToolArgs$1(call.tool, decision.args);
	if (validationError !== null) return settleError(decision.args, `Invalid args for tool "${call.toolName}" after prepareToolExecution hook: ${validationError}`);
	const effectiveArgs = decision.args;
	let execution;
	try {
		execution = await call.tool.resolveExecution(effectiveArgs);
	} catch (error) {
		if (!(error instanceof PathSecurityError$1)) step.log?.warn("tool execution setup failed", {
			toolName: call.toolName,
			toolCallId: call.toolCall.id,
			error
		});
		return settleError(effectiveArgs, error instanceof PathSecurityError$1 ? error.message : `Tool "${call.toolName}" failed to resolve execution: ${errorMessage$19(error)}`);
	}
	const displayFields = toolCallDisplayFieldsFromExecution$1(execution);
	const settleAborted = () => settleError(effectiveArgs, abortedToolOutput$1(call.toolName, step.signal), displayFields);
	if (step.signal.aborted) return settleAborted();
	if (execution.isError === true) return settleSynthetic(effectiveArgs, execution, displayFields);
	const authorization = await runAuthorizeToolExecutionHook(step, call, effectiveArgs, execution);
	if (step.signal.aborted) return settleAborted();
	if (authorization?.block === true) return settleError(effectiveArgs, authorization.reason ?? `Tool call "${call.toolName}" was blocked`, displayFields);
	if (authorization?.syntheticResult !== void 0) return settleSynthetic(effectiveArgs, authorization.syntheticResult, displayFields);
	const executionMetadata = authorization?.executionMetadata ?? decision.metadata;
	await dispatchToolCall(step, call, effectiveArgs, displayFields);
	return {
		task: {
			accesses: execution.accesses ?? ToolAccesses$1.all(),

// main.mjs lines 139949-139955
}
function makeErrorToolResult$1(call, args, output) {
	return makeToolResult(call, args, {
		output,
		isError: true
	});
}

// main.mjs lines 159453-159481
		}
		resolveExecution(args) {
			let path;
			if (args.path !== void 0) path = resolvePathAccessPath$1(args.path, {
				kaos: this.kaos,
				workspace: this.workspace,
				operation: "search",
				policy: {
					guardMode: "absolute-outside-allowed",
					checkSensitive: false
				}
			});
			const searchPaths = [path ?? this.workspace.workspaceDir];
			const searchPath = args.path ?? this.workspace.workspaceDir;
			return {
				accesses: ToolAccesses$1.searchTree(searchPaths[0]),
				description: `Searching for '${args.pattern}' in ${searchPath}`,
				display: {
					kind: "file_io",
					operation: "grep",
					path: searchPaths[0]
				},
				approvalRule: literalRulePattern$1(this.name, args.pattern),
				matchesRule: (ruleArgs) => matchesGlobRuleSubject$1(ruleArgs, args.pattern),
				execute: ({ signal }) => this.execution(args, signal, searchPaths)
			};
		}
		async execution(args, signal, searchPaths) {
			if (signal.aborted) return {
