const std = @import("std");

pub const Worktree = struct {
    path: []const u8,
    branch: []const u8,
};

pub const WorktreeStatus = struct {
    is_dirty: bool,
    last_commit: []const u8,
};

pub const GitError = error{
    CommandFailed,
    NotAGitRepository,
    WorktreeNotFound,
    BranchAlreadyExists,
    OutOfMemory,
    HasUncommittedChanges,
};

pub const SyncStrategy = enum {
    rebase,
    merge,
};

pub const ApplyStrategy = enum {
    merge,
    squash,
    rebase,
};

pub fn listWorktrees(allocator: std.mem.Allocator) ![]Worktree {
    const result = runGitCommand(allocator, &.{ "worktree", "list", "--porcelain" }) catch |err| {
        if (err == error.CommandFailed) return GitError.NotAGitRepository;
        return err;
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    return parseWorktreeList(allocator, result.stdout);
}

pub fn getWorktreeStatus(allocator: std.mem.Allocator, path: []const u8) !WorktreeStatus {
    // Check if dirty
    const status_result = runGitCommandInDir(allocator, path, &.{ "status", "--porcelain" }) catch {
        return GitError.CommandFailed;
    };
    defer allocator.free(status_result.stdout);
    defer allocator.free(status_result.stderr);

    const is_dirty = status_result.stdout.len > 0;

    // Get last commit
    const log_result = runGitCommandInDir(allocator, path, &.{ "log", "-1", "--format=%s", "--no-walk" }) catch {
        return .{
            .is_dirty = is_dirty,
            .last_commit = try allocator.dupe(u8, "(no commits)"),
        };
    };
    defer allocator.free(log_result.stderr);

    // Trim the commit message
    const trimmed = std.mem.trim(u8, log_result.stdout, "\n\r ");
    const commit_msg = if (trimmed.len > 40)
        try std.fmt.allocPrint(allocator, "{s}...", .{trimmed[0..37]})
    else
        try allocator.dupe(u8, trimmed);

    // Free original stdout since we made a copy
    allocator.free(log_result.stdout);

    return .{
        .is_dirty = is_dirty,
        .last_commit = commit_msg,
    };
}

pub fn createWorktree(allocator: std.mem.Allocator, branch: []const u8, base_branch: ?[]const u8) !void {
    // Get the root directory
    const root_result = try runGitCommand(allocator, &.{ "rev-parse", "--show-toplevel" });
    defer allocator.free(root_result.stdout);
    defer allocator.free(root_result.stderr);

    const root = std.mem.trim(u8, root_result.stdout, "\n\r ");

    // Create worktree path as sibling directory
    const parent_dir = std.fs.path.dirname(root) orelse ".";
    const worktree_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ parent_dir, branch });
    defer allocator.free(worktree_path);

    // Create the worktree with a new branch
    // If base_branch is provided, use: git worktree add -b <branch> <path> <base_branch>
    // Otherwise use: git worktree add -b <branch> <path>
    const add_result = if (base_branch) |base|
        try runGitCommand(allocator, &.{ "worktree", "add", "-b", branch, worktree_path, base })
    else
        try runGitCommand(allocator, &.{ "worktree", "add", "-b", branch, worktree_path });
    allocator.free(add_result.stdout);
    allocator.free(add_result.stderr);
}

pub fn removeWorktree(allocator: std.mem.Allocator, branch: []const u8) !void {
    // Find the worktree path
    const worktrees = try listWorktrees(allocator);
    defer {
        for (worktrees) |wt| {
            allocator.free(wt.path);
            allocator.free(wt.branch);
        }
        allocator.free(worktrees);
    }

    var found_path: ?[]const u8 = null;
    for (worktrees) |wt| {
        if (std.mem.eql(u8, wt.branch, branch)) {
            found_path = wt.path;
            break;
        }
    }

    if (found_path) |path| {
        const rm_result = try runGitCommand(allocator, &.{ "worktree", "remove", path });
        allocator.free(rm_result.stdout);
        allocator.free(rm_result.stderr);
    } else {
        return GitError.WorktreeNotFound;
    }
}

pub fn syncWorktree(allocator: std.mem.Allocator, branch: []const u8, base_branch: []const u8, strategy: SyncStrategy) ![]const u8 {
    // Find the worktree path
    const worktrees = try listWorktrees(allocator);
    defer {
        for (worktrees) |wt| {
            allocator.free(wt.path);
            allocator.free(wt.branch);
        }
        allocator.free(worktrees);
    }

    var worktree_path: ?[]const u8 = null;
    for (worktrees) |wt| {
        if (std.mem.eql(u8, wt.branch, branch)) {
            worktree_path = wt.path;
            break;
        }
    }

    const path = worktree_path orelse return GitError.WorktreeNotFound;

    // Check for uncommitted changes
    const status = try getWorktreeStatus(allocator, path);
    defer allocator.free(status.last_commit);
    if (status.is_dirty) {
        return GitError.HasUncommittedChanges;
    }

    // Fetch latest from remote
    const fetch_result = runGitCommandInDir(allocator, path, &.{ "fetch", "origin" }) catch {
        // Fetch might fail if no remote, continue anyway
        return try allocator.dupe(u8, "No remote to fetch from, synced locally");
    };
    allocator.free(fetch_result.stdout);
    allocator.free(fetch_result.stderr);

    // Sync with base branch using selected strategy
    switch (strategy) {
        .rebase => {
            const rebase_result = try runGitCommandInDir(allocator, path, &.{ "rebase", base_branch });
            defer allocator.free(rebase_result.stderr);
            const msg = try allocator.dupe(u8, std.mem.trim(u8, rebase_result.stdout, "\n\r "));
            allocator.free(rebase_result.stdout);
            return msg;
        },
        .merge => {
            const merge_result = try runGitCommandInDir(allocator, path, &.{ "merge", base_branch });
            defer allocator.free(merge_result.stderr);
            const msg = try allocator.dupe(u8, std.mem.trim(u8, merge_result.stdout, "\n\r "));
            allocator.free(merge_result.stdout);
            return msg;
        },
    }
}

pub fn applyWorktree(allocator: std.mem.Allocator, branch: []const u8, target_branch: []const u8, strategy: ApplyStrategy) ![]const u8 {
    // Find the main worktree (where target branch likely is)
    const worktrees = try listWorktrees(allocator);
    defer {
        for (worktrees) |wt| {
            allocator.free(wt.path);
            allocator.free(wt.branch);
        }
        allocator.free(worktrees);
    }

    // Find the main worktree (first one, usually the main repo)
    if (worktrees.len == 0) return GitError.WorktreeNotFound;
    const main_path = worktrees[0].path;

    // Check for uncommitted changes in main worktree
    const status = try getWorktreeStatus(allocator, main_path);
    defer allocator.free(status.last_commit);
    if (status.is_dirty) {
        return GitError.HasUncommittedChanges;
    }

    // Checkout target branch in main worktree
    const checkout_result = try runGitCommandInDir(allocator, main_path, &.{ "checkout", target_branch });
    allocator.free(checkout_result.stdout);
    allocator.free(checkout_result.stderr);

    // Apply using selected strategy
    switch (strategy) {
        .merge => {
            const merge_result = try runGitCommandInDir(allocator, main_path, &.{ "merge", branch });
            defer allocator.free(merge_result.stderr);
            const msg = try allocator.dupe(u8, std.mem.trim(u8, merge_result.stdout, "\n\r "));
            allocator.free(merge_result.stdout);
            return msg;
        },
        .squash => {
            const squash_result = try runGitCommandInDir(allocator, main_path, &.{ "merge", "--squash", branch });
            allocator.free(squash_result.stdout);
            allocator.free(squash_result.stderr);

            const commit_result = try runGitCommandInDir(allocator, main_path, &.{ "commit", "-m", "Squashed commit from worktree" });
            defer allocator.free(commit_result.stderr);
            const msg = try allocator.dupe(u8, std.mem.trim(u8, commit_result.stdout, "\n\r "));
            allocator.free(commit_result.stdout);
            return msg;
        },
        .rebase => {
            const rebase_result = try runGitCommandInDir(allocator, main_path, &.{ "rebase", branch });
            defer allocator.free(rebase_result.stderr);
            const msg = try allocator.dupe(u8, std.mem.trim(u8, rebase_result.stdout, "\n\r "));
            allocator.free(rebase_result.stdout);
            return msg;
        },
    }
}

fn parseWorktreeList(allocator: std.mem.Allocator, output: []const u8) ![]Worktree {
    var worktrees: std.ArrayListUnmanaged(Worktree) = .empty;
    errdefer {
        for (worktrees.items) |wt| {
            allocator.free(wt.path);
            allocator.free(wt.branch);
        }
        worktrees.deinit(allocator);
    }

    var current_path: ?[]const u8 = null;
    var lines = std.mem.splitScalar(u8, output, '\n');

    while (lines.next()) |line| {
        if (line.len == 0) {
            current_path = null;
            continue;
        }

        if (std.mem.startsWith(u8, line, "worktree ")) {
            current_path = try allocator.dupe(u8, line[9..]);
        } else if (std.mem.startsWith(u8, line, "branch refs/heads/")) {
            if (current_path) |path| {
                try worktrees.append(allocator, .{
                    .path = path,
                    .branch = try allocator.dupe(u8, line[18..]),
                });
                current_path = null;
            }
        } else if (std.mem.eql(u8, line, "bare")) {
            // Skip bare repository entry
            if (current_path) |path| {
                allocator.free(path);
                current_path = null;
            }
        } else if (std.mem.startsWith(u8, line, "detached")) {
            // Handle detached HEAD
            if (current_path) |path| {
                try worktrees.append(allocator, .{
                    .path = path,
                    .branch = try allocator.dupe(u8, "(detached)"),
                });
                current_path = null;
            }
        }
    }

    return worktrees.toOwnedSlice(allocator);
}

pub fn runGitCmd(allocator: std.mem.Allocator, args: []const []const u8) ![]u8 {
    const result = try runGitCommand(allocator, args);
    defer allocator.free(result.stderr);
    return result.stdout;
}

const CommandResult = struct {
    stdout: []u8,
    stderr: []u8,
    term: std.process.Child.Term,
};

fn runGitCommand(allocator: std.mem.Allocator, args: []const []const u8) !CommandResult {
    return runGitCommandInDir(allocator, null, args);
}

fn runGitCommandInDir(allocator: std.mem.Allocator, dir: ?[]const u8, args: []const []const u8) !CommandResult {
    var argv: std.ArrayListUnmanaged([]const u8) = .empty;
    defer argv.deinit(allocator);

    try argv.append(allocator, "git");
    if (dir) |d| {
        try argv.append(allocator, "-C");
        try argv.append(allocator, d);
    }
    for (args) |arg| {
        try argv.append(allocator, arg);
    }

    var child = std.process.Child.init(argv.items, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    // Use deprecatedReader for compatibility with 0.15 I/O changes
    const stdout = try child.stdout.?.deprecatedReader().readAllAlloc(allocator, 1024 * 1024);
    errdefer allocator.free(stdout);

    const stderr = try child.stderr.?.deprecatedReader().readAllAlloc(allocator, 1024 * 1024);
    errdefer allocator.free(stderr);

    const term = try child.wait();

    if (term.Exited != 0) {
        allocator.free(stdout);
        allocator.free(stderr);
        return GitError.CommandFailed;
    }

    return .{
        .stdout = stdout,
        .stderr = stderr,
        .term = term,
    };
}

// Tests
test "parseWorktreeList parses empty output" {
    const allocator = std.testing.allocator;
    const result = try parseWorktreeList(allocator, "");
    defer allocator.free(result);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "parseWorktreeList parses single worktree" {
    const allocator = std.testing.allocator;
    const output =
        \\worktree /path/to/repo
        \\HEAD abc123
        \\branch refs/heads/main
        \\
    ;
    const result = try parseWorktreeList(allocator, output);
    defer {
        for (result) |wt| {
            allocator.free(wt.path);
            allocator.free(wt.branch);
        }
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqualStrings("/path/to/repo", result[0].path);
    try std.testing.expectEqualStrings("main", result[0].branch);
}

test "parseWorktreeList parses multiple worktrees" {
    const allocator = std.testing.allocator;
    const output =
        \\worktree /path/to/main
        \\HEAD abc123
        \\branch refs/heads/main
        \\
        \\worktree /path/to/feature
        \\HEAD def456
        \\branch refs/heads/feature-x
        \\
    ;
    const result = try parseWorktreeList(allocator, output);
    defer {
        for (result) |wt| {
            allocator.free(wt.path);
            allocator.free(wt.branch);
        }
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 2), result.len);
    try std.testing.expectEqualStrings("main", result[0].branch);
    try std.testing.expectEqualStrings("feature-x", result[1].branch);
}

test "parseWorktreeList handles detached HEAD" {
    const allocator = std.testing.allocator;
    const output =
        \\worktree /path/to/detached
        \\HEAD abc123
        \\detached
        \\
    ;
    const result = try parseWorktreeList(allocator, output);
    defer {
        for (result) |wt| {
            allocator.free(wt.path);
            allocator.free(wt.branch);
        }
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqualStrings("(detached)", result[0].branch);
}
