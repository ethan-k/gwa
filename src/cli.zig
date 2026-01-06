const std = @import("std");
const git = @import("git.zig");
const config = @import("config.zig");
const copy = @import("copy.zig");
const hooks = @import("hooks.zig");
const editors = @import("editors.zig");
const metadata = @import("metadata.zig");

pub const Command = enum {
    list,
    new,
    rm,
    status,
    sync,
    apply,
    editor,
    ai,
    run_cmd,
    note,
    info,
    lock,
    unlock,
    gc,
    cd,
    exec,
    config,
    help,
    version,
};

pub const ParseError = error{
    UnknownCommand,
    MissingArgument,
};

pub fn parseCommand(arg: []const u8) ParseError!Command {
    const commands = .{
        .{ "list", .list },
        .{ "ls", .list },
        .{ "new", .new },
        .{ "add", .new },
        .{ "a", .new },
        .{ "rm", .rm },
        .{ "del", .rm },
        .{ "d", .rm },
        .{ "status", .status },
        .{ "st", .status },
        .{ "sync", .sync },
        .{ "sy", .sync },
        .{ "apply", .apply },
        .{ "merge", .apply },
        .{ "ap", .apply },
        .{ "editor", .editor },
        .{ "ai", .ai },
        .{ "run", .run_cmd },
        .{ "note", .note },
        .{ "n", .note },
        .{ "info", .info },
        .{ "i", .info },
        .{ "lock", .lock },
        .{ "unlock", .unlock },
        .{ "gc", .gc },
        .{ "cd", .cd },
        .{ "exec", .exec },
        .{ "config", .config },
        .{ "help", .help },
        .{ "-h", .help },
        .{ "--help", .help },
        .{ "version", .version },
        .{ "-v", .version },
        .{ "--version", .version },
    };

    inline for (commands) |cmd| {
        if (std.mem.eql(u8, arg, cmd[0])) {
            return cmd[1];
        }
    }
    return ParseError.UnknownCommand;
}

pub fn run(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    stdout: anytype,
    stderr: anytype,
) !void {
    _ = stderr;

    if (args.len < 2) {
        try printHelp(stdout);
        return;
    }

    const cmd = parseCommand(args[1]) catch {
        try stdout.print("Unknown command: {s}\n\n", .{args[1]});
        try printHelp(stdout);
        return;
    };

    switch (cmd) {
        .list => try cmdList(allocator, stdout),
        .help => try printHelp(stdout),
        .version => try stdout.print("gwa version 0.1.0\n", .{}),
        .status => try cmdStatus(allocator, stdout),
        .new => {
            if (args.len < 3) {
                try stdout.print("Usage: gwa new <branch-name> [base-branch]\n", .{});
                return;
            }
            const base_branch = if (args.len >= 4) args[3] else null;
            try cmdNew(allocator, args[2], base_branch, stdout);
        },
        .rm => {
            if (args.len < 3) {
                try stdout.print("Usage: gwa rm <branch-name>\n", .{});
                return;
            }
            try cmdRm(allocator, args[2], stdout);
        },
        .sync => {
            if (args.len < 3) {
                try stdout.print("Usage: gwa sync <branch-name> [--base <base-branch>] [--merge|--rebase]\n", .{});
                return;
            }
            const base = if (args.len >= 5 and std.mem.eql(u8, args[3], "--base")) args[4] else "main";
            const strategy = parseStrategy(args, "--merge", "--rebase", .rebase);
            try cmdSync(allocator, args[2], base, strategy, stdout);
        },
        .apply => {
            if (args.len < 3) {
                try stdout.print("Usage: gwa apply <branch-name> [--to <target-branch>] [--merge|--squash|--rebase]\n", .{});
                return;
            }
            const target = if (args.len >= 5 and std.mem.eql(u8, args[3], "--to")) args[4] else "main";
            const strategy = parseApplyStrategy(args);
            try cmdApply(allocator, args[2], target, strategy, stdout);
        },
        .editor => {
            if (args.len < 3) {
                try stdout.print("Usage: gwa editor <branch-name> [editor-name]\n", .{});
                return;
            }
            const editor_name = if (args.len >= 4) args[3] else "code";
            try cmdEditor(allocator, args[2], editor_name, stdout);
        },
        .ai => {
            if (args.len < 3) {
                try stdout.print("Usage: gwa ai <branch-name> [tool-name]\n", .{});
                return;
            }
            const tool_name = if (args.len >= 4) args[3] else "claude";
            try cmdAi(allocator, args[2], tool_name, stdout);
        },
        .run_cmd => {
            if (args.len < 4) {
                try stdout.print("Usage: gwa run <branch-name> <command>\n", .{});
                return;
            }
            // Join remaining args as the command
            var cmd_parts: std.ArrayListUnmanaged(u8) = .empty;
            defer cmd_parts.deinit(allocator);
            for (args[3..]) |part| {
                if (cmd_parts.items.len > 0) try cmd_parts.append(allocator, ' ');
                try cmd_parts.appendSlice(allocator, part);
            }
            try cmdRun(allocator, args[2], cmd_parts.items, stdout);
        },
        .cd => {
            if (args.len < 3) {
                try stdout.print("Usage: gwa cd <branch-name>\n", .{});
                return;
            }
            try cmdCd(allocator, args[2], stdout);
        },
        .note => {
            if (args.len < 4) {
                try stdout.print("Usage: gwa note <branch-name> \"<note text>\"\n", .{});
                return;
            }
            try cmdNote(allocator, args[2], args[3], stdout);
        },
        .info => {
            if (args.len < 3) {
                try stdout.print("Usage: gwa info <branch-name>\n", .{});
                return;
            }
            try cmdInfo(allocator, args[2], stdout);
        },
        .lock => {
            if (args.len < 3) {
                try stdout.print("Usage: gwa lock <branch-name>\n", .{});
                return;
            }
            try cmdLock(allocator, args[2], stdout);
        },
        .unlock => {
            if (args.len < 3) {
                try stdout.print("Usage: gwa unlock <branch-name>\n", .{});
                return;
            }
            try cmdUnlock(allocator, args[2], stdout);
        },
        .gc => {
            try cmdGc(allocator, stdout);
        },
        .exec => {
            if (args.len < 3) {
                try stdout.print("Usage: gwa exec <command>\n", .{});
                return;
            }
            // Join remaining args as the command
            var cmd_parts: std.ArrayListUnmanaged(u8) = .empty;
            defer cmd_parts.deinit(allocator);
            for (args[2..]) |part| {
                if (cmd_parts.items.len > 0) try cmd_parts.append(allocator, ' ');
                try cmd_parts.appendSlice(allocator, part);
            }
            try cmdExec(allocator, cmd_parts.items, stdout);
        },
        .config => {
            const subcommand = if (args.len >= 3) args[2] else "edit";
            const is_global = hasFlag(args, "--global") or hasFlag(args, "-g");
            const editor_override = getFlagValue(args, "--editor") orelse getFlagValue(args, "-e");
            try cmdConfig(allocator, subcommand, is_global, editor_override, stdout);
        },
    }
}

fn cmdList(allocator: std.mem.Allocator, stdout: anytype) !void {
    const worktrees = try git.listWorktrees(allocator);
    defer {
        for (worktrees) |wt| {
            allocator.free(wt.path);
            allocator.free(wt.branch);
        }
        allocator.free(worktrees);
    }

    if (worktrees.len == 0) {
        try stdout.print("No worktrees found\n", .{});
        return;
    }

    try stdout.print("{s:<40} {s}\n", .{ "PATH", "BRANCH" });
    try stdout.print("{s:-<40} {s:-<20}\n", .{ "", "" });

    for (worktrees) |wt| {
        try stdout.print("{s:<40} {s}\n", .{ wt.path, wt.branch });
    }
}

fn cmdStatus(allocator: std.mem.Allocator, stdout: anytype) !void {
    const worktrees = try git.listWorktrees(allocator);
    defer {
        for (worktrees) |wt| {
            allocator.free(wt.path);
            allocator.free(wt.branch);
        }
        allocator.free(worktrees);
    }

    if (worktrees.len == 0) {
        try stdout.print("No worktrees found\n", .{});
        return;
    }

    try stdout.print("{s:<30} {s:<20} {s:<8} {s}\n", .{ "PATH", "BRANCH", "DIRTY", "LAST COMMIT" });
    try stdout.print("{s:-<30} {s:-<20} {s:-<8} {s:-<40}\n", .{ "", "", "", "" });

    for (worktrees) |wt| {
        const status = git.getWorktreeStatus(allocator, wt.path) catch |err| {
            try stdout.print("{s:<30} {s:<20} {s:<8} error: {}\n", .{ wt.path, wt.branch, "?", err });
            continue;
        };
        defer allocator.free(status.last_commit);

        const dirty_str = if (status.is_dirty) "yes" else "no";
        try stdout.print("{s:<30} {s:<20} {s:<8} {s}\n", .{ wt.path, wt.branch, dirty_str, status.last_commit });
    }
}

fn cmdNew(allocator: std.mem.Allocator, branch: []const u8, base_branch: ?[]const u8, stdout: anytype) !void {
    try git.createWorktree(allocator, branch, base_branch);
    if (base_branch) |base| {
        try stdout.print("Created worktree for branch: {s} (from {s})\n", .{ branch, base });
    } else {
        try stdout.print("Created worktree for branch: {s}\n", .{branch});
    }
}

fn cmdRm(allocator: std.mem.Allocator, branch: []const u8, stdout: anytype) !void {
    try git.removeWorktree(allocator, branch);
    try stdout.print("Removed worktree for branch: {s}\n", .{branch});
}

fn cmdSync(allocator: std.mem.Allocator, branch: []const u8, base: []const u8, strategy: git.SyncStrategy, stdout: anytype) !void {
    const strategy_str = switch (strategy) {
        .rebase => "rebase",
        .merge => "merge",
    };
    try stdout.print("Syncing {s} with {s} using {s}...\n", .{ branch, base, strategy_str });

    const result = git.syncWorktree(allocator, branch, base, strategy) catch |err| {
        switch (err) {
            error.WorktreeNotFound => {
                try stdout.print("Error: Worktree for branch '{s}' not found\n", .{branch});
                return;
            },
            error.HasUncommittedChanges => {
                try stdout.print("Error: Worktree has uncommitted changes. Commit or stash first.\n", .{});
                return;
            },
            else => return err,
        }
    };
    defer allocator.free(result);
    try stdout.print("Done: {s}\n", .{result});
}

fn cmdApply(allocator: std.mem.Allocator, branch: []const u8, target: []const u8, strategy: git.ApplyStrategy, stdout: anytype) !void {
    const strategy_str = switch (strategy) {
        .merge => "merge",
        .squash => "squash",
        .rebase => "rebase",
    };
    try stdout.print("Applying {s} to {s} using {s}...\n", .{ branch, target, strategy_str });

    const result = git.applyWorktree(allocator, branch, target, strategy) catch |err| {
        switch (err) {
            error.WorktreeNotFound => {
                try stdout.print("Error: No worktrees found\n", .{});
                return;
            },
            error.HasUncommittedChanges => {
                try stdout.print("Error: Target worktree has uncommitted changes. Commit or stash first.\n", .{});
                return;
            },
            else => return err,
        }
    };
    defer allocator.free(result);
    try stdout.print("Done: {s}\n", .{result});
}

fn parseStrategy(args: []const []const u8, merge_flag: []const u8, rebase_flag: []const u8, default: git.SyncStrategy) git.SyncStrategy {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, merge_flag)) return .merge;
        if (std.mem.eql(u8, arg, rebase_flag)) return .rebase;
    }
    return default;
}

fn parseApplyStrategy(args: []const []const u8) git.ApplyStrategy {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--squash")) return .squash;
        if (std.mem.eql(u8, arg, "--rebase")) return .rebase;
        if (std.mem.eql(u8, arg, "--merge")) return .merge;
    }
    return .merge; // default
}

fn cmdEditor(allocator: std.mem.Allocator, branch: []const u8, editor_name: []const u8, stdout: anytype) !void {
    const worktrees = try git.listWorktrees(allocator);
    defer {
        for (worktrees) |wt| {
            allocator.free(wt.path);
            allocator.free(wt.branch);
        }
        allocator.free(worktrees);
    }

    for (worktrees) |wt| {
        if (std.mem.eql(u8, wt.branch, branch)) {
            try stdout.print("Opening {s} in {s}...\n", .{ wt.path, editor_name });
            try editors.openEditor(allocator, editor_name, wt.path);
            return;
        }
    }
    try stdout.print("Error: Worktree for branch '{s}' not found\n", .{branch});
}

fn cmdAi(allocator: std.mem.Allocator, branch: []const u8, tool_name: []const u8, stdout: anytype) !void {
    const worktrees = try git.listWorktrees(allocator);
    defer {
        for (worktrees) |wt| {
            allocator.free(wt.path);
            allocator.free(wt.branch);
        }
        allocator.free(worktrees);
    }

    for (worktrees) |wt| {
        if (std.mem.eql(u8, wt.branch, branch)) {
            try stdout.print("Launching {s} in {s}...\n", .{ tool_name, wt.path });
            try editors.launchAiTool(allocator, tool_name, wt.path);
            return;
        }
    }
    try stdout.print("Error: Worktree for branch '{s}' not found\n", .{branch});
}

fn cmdRun(allocator: std.mem.Allocator, branch: []const u8, command: []const u8, stdout: anytype) !void {
    const worktrees = try git.listWorktrees(allocator);
    defer {
        for (worktrees) |wt| {
            allocator.free(wt.path);
            allocator.free(wt.branch);
        }
        allocator.free(worktrees);
    }

    for (worktrees) |wt| {
        if (std.mem.eql(u8, wt.branch, branch)) {
            try stdout.print("Running in {s}: {s}\n", .{ wt.path, command });
            const output = try editors.runCommand(allocator, wt.path, command);
            defer allocator.free(output);
            if (output.len > 0) {
                try stdout.print("{s}", .{output});
            }
            return;
        }
    }
    try stdout.print("Error: Worktree for branch '{s}' not found\n", .{branch});
}

fn cmdCd(allocator: std.mem.Allocator, branch: []const u8, stdout: anytype) !void {
    const worktrees = try git.listWorktrees(allocator);
    defer {
        for (worktrees) |wt| {
            allocator.free(wt.path);
            allocator.free(wt.branch);
        }
        allocator.free(worktrees);
    }

    for (worktrees) |wt| {
        if (std.mem.eql(u8, wt.branch, branch)) {
            // Output the path for shell integration
            try stdout.print("{s}\n", .{wt.path});
            return;
        }
    }
    try stdout.print("Error: Worktree for branch '{s}' not found\n", .{branch});
}

fn cmdNote(allocator: std.mem.Allocator, branch: []const u8, note: []const u8, stdout: anytype) !void {
    // Get repo root
    const root_result = git.runGitCmd(allocator, &.{ "rev-parse", "--show-toplevel" }) catch {
        try stdout.print("Error: Not in a git repository\n", .{});
        return;
    };
    defer allocator.free(root_result);

    const repo_root = std.mem.trim(u8, root_result, "\n\r ");

    try metadata.saveNote(allocator, repo_root, branch, note);
    try stdout.print("Note saved for branch '{s}'\n", .{branch});
}

fn cmdInfo(allocator: std.mem.Allocator, branch: []const u8, stdout: anytype) !void {
    const worktrees = try git.listWorktrees(allocator);
    defer {
        for (worktrees) |wt| {
            allocator.free(wt.path);
            allocator.free(wt.branch);
        }
        allocator.free(worktrees);
    }

    var found = false;
    for (worktrees) |wt| {
        if (std.mem.eql(u8, wt.branch, branch)) {
            found = true;

            try stdout.print("Branch:    {s}\n", .{wt.branch});
            try stdout.print("Path:      {s}\n", .{wt.path});

            // Get status
            const status = git.getWorktreeStatus(allocator, wt.path) catch {
                try stdout.print("Status:    unknown\n", .{});
                break;
            };
            defer allocator.free(status.last_commit);

            try stdout.print("Dirty:     {s}\n", .{if (status.is_dirty) "yes" else "no"});
            try stdout.print("Commit:    {s}\n", .{status.last_commit});

            // Get metadata
            const meta = metadata.loadMetadata(allocator, wt.path, branch) catch {
                break;
            };
            defer @constCast(&meta).deinit();

            try stdout.print("Locked:    {s}\n", .{if (meta.locked) "yes" else "no"});
            if (meta.note) |n| {
                try stdout.print("Note:      {s}\n", .{std.mem.trim(u8, n, "\n\r ")});
            }
            break;
        }
    }

    if (!found) {
        try stdout.print("Error: Worktree for branch '{s}' not found\n", .{branch});
    }
}

fn cmdLock(allocator: std.mem.Allocator, branch: []const u8, stdout: anytype) !void {
    const worktrees = try git.listWorktrees(allocator);
    defer {
        for (worktrees) |wt| {
            allocator.free(wt.path);
            allocator.free(wt.branch);
        }
        allocator.free(worktrees);
    }

    for (worktrees) |wt| {
        if (std.mem.eql(u8, wt.branch, branch)) {
            try metadata.lockWorktree(allocator, wt.path, branch);
            try stdout.print("Locked worktree '{s}'\n", .{branch});
            return;
        }
    }
    try stdout.print("Error: Worktree for branch '{s}' not found\n", .{branch});
}

fn cmdUnlock(allocator: std.mem.Allocator, branch: []const u8, stdout: anytype) !void {
    const worktrees = try git.listWorktrees(allocator);
    defer {
        for (worktrees) |wt| {
            allocator.free(wt.path);
            allocator.free(wt.branch);
        }
        allocator.free(worktrees);
    }

    for (worktrees) |wt| {
        if (std.mem.eql(u8, wt.branch, branch)) {
            try metadata.unlockWorktree(allocator, wt.path, branch);
            try stdout.print("Unlocked worktree '{s}'\n", .{branch});
            return;
        }
    }
    try stdout.print("Error: Worktree for branch '{s}' not found\n", .{branch});
}

fn cmdGc(allocator: std.mem.Allocator, stdout: anytype) !void {
    const worktrees = try git.listWorktrees(allocator);
    defer {
        for (worktrees) |wt| {
            allocator.free(wt.path);
            allocator.free(wt.branch);
        }
        allocator.free(worktrees);
    }

    // Convert to the format expected by findGcCandidates
    var wt_list: std.ArrayListUnmanaged(metadata.WorktreeRef) = .empty;
    defer wt_list.deinit(allocator);

    for (worktrees) |wt| {
        try wt_list.append(allocator, .{ .path = wt.path, .branch = wt.branch });
    }

    const candidates = try metadata.findGcCandidates(allocator, wt_list.items);
    defer allocator.free(candidates);

    if (candidates.len == 0) {
        try stdout.print("No cleanup candidates found\n", .{});
        return;
    }

    try stdout.print("Cleanup candidates:\n", .{});
    for (candidates) |c| {
        try stdout.print("  {s} ({s}): {s}\n", .{ c.branch, c.path, c.reason });
    }
    try stdout.print("\nUse 'gw rm <branch>' to remove worktrees\n", .{});
}

fn hasFlag(args: []const []const u8, flag: []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, flag)) return true;
    }
    return false;
}

fn getFlagValue(args: []const []const u8, flag: []const u8) ?[]const u8 {
    for (args, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, flag) and i + 1 < args.len) {
            return args[i + 1];
        }
    }
    return null;
}

fn cmdConfig(allocator: std.mem.Allocator, subcommand: []const u8, is_global: bool, editor_override: ?[]const u8, stdout: anytype) !void {
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch {
        try stdout.print("Error: HOME environment variable not set\n", .{});
        return;
    };
    defer allocator.free(home);

    // Get repo root for project config
    const repo_root = git.runGitCmd(allocator, &.{ "rev-parse", "--show-toplevel" }) catch null;
    defer if (repo_root) |r| allocator.free(r);
    const root = if (repo_root) |r| std.mem.trim(u8, r, "\n\r ") else null;

    if (std.mem.eql(u8, subcommand, "edit")) {
        const config_path = if (is_global)
            try std.fmt.allocPrint(allocator, "{s}/.config/gwa/config.toml", .{home})
        else if (root) |r|
            try std.fmt.allocPrint(allocator, "{s}/.gwa/config.toml", .{r})
        else {
            try stdout.print("Error: Not in a git repository. Use --global for global config.\n", .{});
            return;
        };
        defer allocator.free(config_path);

        // Create parent directory if needed
        const dir_path = std.fs.path.dirname(config_path) orelse {
            try stdout.print("Error: Invalid config path\n", .{});
            return;
        };
        std.fs.makeDirAbsolute(dir_path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => {
                try stdout.print("Error: Could not create config directory: {}\n", .{err});
                return;
            },
        };

        // Create config file with template if it doesn't exist
        const file = std.fs.openFileAbsolute(config_path, .{}) catch |err| switch (err) {
            error.FileNotFound => blk: {
                const new_file = std.fs.createFileAbsolute(config_path, .{}) catch |e| {
                    try stdout.print("Error: Could not create config file: {}\n", .{e});
                    return;
                };
                const template =
                    \\# gwa configuration
                    \\# Global: ~/.config/gwa/config.toml
                    \\# Project: .gwa/config.toml
                    \\
                    \\# Default base branch for new worktrees
                    \\# default_base = "main"
                    \\
                    \\# Custom worktrees directory (default: sibling to repo)
                    \\# worktrees_dir = "/path/to/worktrees"
                    \\
                    \\# Editor for gwa editor command (default: vim)
                    \\# editor = "code"
                    \\
                    \\# AI tool for gwa ai command (default: claude)
                    \\# ai_tool = "cursor"
                    \\
                    \\# Files to copy to new worktrees
                    \\# copy_files = [".env", ".envrc"]
                    \\
                    \\# Directories to copy to new worktrees
                    \\# copy_dirs = ["node_modules"]
                    \\
                    \\# Hooks
                    \\# post_create_hook = "npm install"
                    \\# pre_remove_hook = "git stash"
                    \\
                ;
                new_file.writeAll(template) catch {};
                new_file.close();
                break :blk std.fs.openFileAbsolute(config_path, .{}) catch {
                    try stdout.print("Error: Could not open config file\n", .{});
                    return;
                };
            },
            else => {
                try stdout.print("Error: Could not access config file: {}\n", .{err});
                return;
            },
        };
        file.close();

        // Open in editor
        const editor_to_use = if (editor_override) |e| e else blk: {
            const cfg = config.loadConfig(allocator, root) catch {
                break :blk "vim";
            };
            defer @constCast(&cfg).deinit();
            break :blk cfg.editor;
        };

        try stdout.print("Opening {s} in {s}...\n", .{ config_path, editor_to_use });
        try editors.openEditor(allocator, editor_to_use, config_path);
    } else if (std.mem.eql(u8, subcommand, "path")) {
        const global_path = try std.fmt.allocPrint(allocator, "{s}/.config/gwa/config.toml", .{home});
        defer allocator.free(global_path);

        try stdout.print("Global: {s}\n", .{global_path});
        if (root) |r| {
            try stdout.print("Project: {s}/.gwa/config.toml\n", .{r});
        }
    } else if (std.mem.eql(u8, subcommand, "show")) {
        const cfg = config.loadConfig(allocator, root) catch {
            try stdout.print("Error: Could not load config\n", .{});
            return;
        };
        defer @constCast(&cfg).deinit();

        try stdout.print("default_base = \"{s}\"\n", .{cfg.default_base});
        try stdout.print("editor = \"{s}\"\n", .{cfg.editor});
        try stdout.print("ai_tool = \"{s}\"\n", .{cfg.ai_tool});
        if (cfg.worktrees_dir) |dir| {
            try stdout.print("worktrees_dir = \"{s}\"\n", .{dir});
        }
        if (cfg.copy_files.len > 0) {
            try stdout.print("copy_files = [", .{});
            for (cfg.copy_files, 0..) |f, i| {
                if (i > 0) try stdout.print(", ", .{});
                try stdout.print("\"{s}\"", .{f});
            }
            try stdout.print("]\n", .{});
        }
        if (cfg.copy_dirs.len > 0) {
            try stdout.print("copy_dirs = [", .{});
            for (cfg.copy_dirs, 0..) |d, i| {
                if (i > 0) try stdout.print(", ", .{});
                try stdout.print("\"{s}\"", .{d});
            }
            try stdout.print("]\n", .{});
        }
        if (cfg.post_create_hook) |h| {
            try stdout.print("post_create_hook = \"{s}\"\n", .{h});
        }
        if (cfg.pre_remove_hook) |h| {
            try stdout.print("pre_remove_hook = \"{s}\"\n", .{h});
        }
    } else {
        try stdout.print("Unknown config subcommand: {s}\n", .{subcommand});
        try stdout.print("Usage: gwa config [edit|show|path] [--global]\n", .{});
    }
}

fn cmdExec(allocator: std.mem.Allocator, command: []const u8, stdout: anytype) !void {
    const worktrees = try git.listWorktrees(allocator);
    defer {
        for (worktrees) |wt| {
            allocator.free(wt.path);
            allocator.free(wt.branch);
        }
        allocator.free(worktrees);
    }

    if (worktrees.len == 0) {
        try stdout.print("No worktrees found\n", .{});
        return;
    }

    for (worktrees) |wt| {
        try stdout.print("=== {s} ({s}) ===\n", .{ wt.branch, wt.path });
        const output = editors.runCommand(allocator, wt.path, command) catch |err| {
            try stdout.print("Error: {}\n\n", .{err});
            continue;
        };
        defer allocator.free(output);
        if (output.len > 0) {
            try stdout.print("{s}\n", .{output});
        }
    }
}

fn printHelp(stdout: anytype) !void {
    try stdout.print(
        \\gwa - Git Worktree for AI
        \\
        \\Usage: gwa <command> [arguments]
        \\
        \\Commands:
        \\  list, ls               List all worktrees
        \\  new, add <name> [base] Create a new worktree (optionally from base branch)
        \\  rm, del <name>         Remove a worktree
        \\  status, st             Show worktree status
        \\  sync <name>            Sync worktree with base branch
        \\  apply <name>           Apply worktree changes to target
        \\  editor <name>          Open worktree in editor
        \\  ai <name>              Launch AI tool in worktree
        \\  run <name> <cmd>       Run command in worktree
        \\  note <name> <txt>      Add note to worktree
        \\  info <name>            Show worktree info
        \\  lock <name>            Lock worktree
        \\  unlock <name>          Unlock worktree
        \\  gc                     Cleanup candidates
        \\  cd <name>              Output worktree path
        \\  exec <cmd>             Run command across all worktrees
        \\  config [edit|show|path] Edit or show configuration
        \\  help                   Show this help
        \\  version                Show version
        \\
        \\Examples:
        \\  gwa new feature-x              # Create from current branch
        \\  gwa new feature-x origin/main  # Create from origin/main
        \\  gwa new feature-x main         # Create from main
        \\
    , .{});
}

// Tests
test "parseCommand recognizes list aliases" {
    try std.testing.expectEqual(Command.list, try parseCommand("list"));
    try std.testing.expectEqual(Command.list, try parseCommand("ls"));
}

test "parseCommand recognizes new aliases" {
    try std.testing.expectEqual(Command.new, try parseCommand("new"));
    try std.testing.expectEqual(Command.new, try parseCommand("add"));
    try std.testing.expectEqual(Command.new, try parseCommand("a"));
}

test "parseCommand recognizes rm aliases" {
    try std.testing.expectEqual(Command.rm, try parseCommand("rm"));
    try std.testing.expectEqual(Command.rm, try parseCommand("del"));
    try std.testing.expectEqual(Command.rm, try parseCommand("d"));
}

test "parseCommand recognizes status aliases" {
    try std.testing.expectEqual(Command.status, try parseCommand("status"));
    try std.testing.expectEqual(Command.status, try parseCommand("st"));
}

test "parseCommand returns error for unknown command" {
    try std.testing.expectError(ParseError.UnknownCommand, parseCommand("unknown"));
}

test "parseCommand recognizes help flags" {
    try std.testing.expectEqual(Command.help, try parseCommand("help"));
    try std.testing.expectEqual(Command.help, try parseCommand("-h"));
    try std.testing.expectEqual(Command.help, try parseCommand("--help"));
}
