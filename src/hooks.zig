const std = @import("std");

pub const HookResult = struct {
    success: bool,
    output: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *HookResult) void {
        self.allocator.free(self.output);
    }
};

pub fn runHook(allocator: std.mem.Allocator, hook_cmd: []const u8, worktree_path: []const u8, branch: []const u8) !HookResult {
    // Expand variables in hook command
    const expanded = try expandVariables(allocator, hook_cmd, worktree_path, branch);
    defer allocator.free(expanded);

    // Run the hook using shell
    var argv: std.ArrayListUnmanaged([]const u8) = .empty;
    defer argv.deinit(allocator);

    try argv.append(allocator, "/bin/sh");
    try argv.append(allocator, "-c");
    try argv.append(allocator, expanded);

    var child = std.process.Child.init(argv.items, allocator);
    child.cwd = std.fs.cwd();
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    // Set working directory to worktree
    const cwd_path = try allocator.dupeZ(u8, worktree_path);
    defer allocator.free(cwd_path);
    child.cwd = std.fs.openDirAbsolute(worktree_path, .{}) catch null;

    try child.spawn();

    const stdout = try child.stdout.?.deprecatedReader().readAllAlloc(allocator, 1024 * 1024);
    errdefer allocator.free(stdout);

    const stderr = try child.stderr.?.deprecatedReader().readAllAlloc(allocator, 1024 * 1024);
    defer allocator.free(stderr);

    const term = try child.wait();

    const success = term.Exited == 0;
    const output = if (stdout.len > 0) stdout else try allocator.dupe(u8, stderr);

    if (stdout.len == 0) {
        allocator.free(stdout);
    }

    return .{
        .success = success,
        .output = output,
        .allocator = allocator,
    };
}

fn expandVariables(allocator: std.mem.Allocator, cmd: []const u8, worktree_path: []const u8, branch: []const u8) ![]u8 {
    // Replace $WORKTREE_PATH and $BRANCH with actual values
    var result = try allocator.alloc(u8, cmd.len * 2 + worktree_path.len + branch.len);
    var pos: usize = 0;
    var i: usize = 0;

    while (i < cmd.len) {
        if (i + 14 <= cmd.len and std.mem.eql(u8, cmd[i .. i + 14], "$WORKTREE_PATH")) {
            @memcpy(result[pos .. pos + worktree_path.len], worktree_path);
            pos += worktree_path.len;
            i += 14;
        } else if (i + 7 <= cmd.len and std.mem.eql(u8, cmd[i .. i + 7], "$BRANCH")) {
            @memcpy(result[pos .. pos + branch.len], branch);
            pos += branch.len;
            i += 7;
        } else {
            result[pos] = cmd[i];
            pos += 1;
            i += 1;
        }
    }

    const final = try allocator.realloc(result, pos);
    return final;
}

// Tests
test "expandVariables replaces WORKTREE_PATH" {
    const allocator = std.testing.allocator;
    const cmd = "cd $WORKTREE_PATH && npm install";
    const result = try expandVariables(allocator, cmd, "/path/to/worktree", "feature-x");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("cd /path/to/worktree && npm install", result);
}

test "expandVariables replaces BRANCH" {
    const allocator = std.testing.allocator;
    const cmd = "echo Creating $BRANCH";
    const result = try expandVariables(allocator, cmd, "/path", "my-branch");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("echo Creating my-branch", result);
}

test "expandVariables replaces both variables" {
    const allocator = std.testing.allocator;
    const cmd = "echo $BRANCH in $WORKTREE_PATH";
    const result = try expandVariables(allocator, cmd, "/home/project", "dev");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("echo dev in /home/project", result);
}
