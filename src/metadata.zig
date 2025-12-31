const std = @import("std");

pub const WorktreeMetadata = struct {
    note: ?[]const u8 = null,
    locked: bool = false,
    created_at: ?i64 = null,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *WorktreeMetadata) void {
        if (self.note) |n| self.allocator.free(n);
    }
};

pub fn getMetadataDir(allocator: std.mem.Allocator, repo_root: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}/.gwa", .{repo_root});
}

pub fn loadMetadata(allocator: std.mem.Allocator, repo_root: []const u8, branch: []const u8) !WorktreeMetadata {
    var metadata = WorktreeMetadata{ .allocator = allocator };

    const meta_dir = try getMetadataDir(allocator, repo_root);
    defer allocator.free(meta_dir);

    // Load note
    const note_path = try std.fmt.allocPrint(allocator, "{s}/notes/{s}.txt", .{ meta_dir, branch });
    defer allocator.free(note_path);

    if (std.fs.openFileAbsolute(note_path, .{})) |file| {
        defer file.close();
        metadata.note = file.deprecatedReader().readAllAlloc(allocator, 1024 * 64) catch null;
    } else |_| {}

    // Check lock
    const lock_path = try std.fmt.allocPrint(allocator, "{s}/locks/{s}.lock", .{ meta_dir, branch });
    defer allocator.free(lock_path);

    metadata.locked = std.fs.accessAbsolute(lock_path, .{}) != error.FileNotFound;

    return metadata;
}

pub fn saveNote(allocator: std.mem.Allocator, repo_root: []const u8, branch: []const u8, note: []const u8) !void {
    const meta_dir = try getMetadataDir(allocator, repo_root);
    defer allocator.free(meta_dir);

    const notes_dir = try std.fmt.allocPrint(allocator, "{s}/notes", .{meta_dir});
    defer allocator.free(notes_dir);

    // Create directories
    std.fs.makeDirAbsolute(meta_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    std.fs.makeDirAbsolute(notes_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const note_path = try std.fmt.allocPrint(allocator, "{s}/{s}.txt", .{ notes_dir, branch });
    defer allocator.free(note_path);

    const file = try std.fs.createFileAbsolute(note_path, .{});
    defer file.close();
    _ = try file.write(note);
}

pub fn lockWorktree(allocator: std.mem.Allocator, repo_root: []const u8, branch: []const u8) !void {
    const meta_dir = try getMetadataDir(allocator, repo_root);
    defer allocator.free(meta_dir);

    const locks_dir = try std.fmt.allocPrint(allocator, "{s}/locks", .{meta_dir});
    defer allocator.free(locks_dir);

    // Create directories
    std.fs.makeDirAbsolute(meta_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    std.fs.makeDirAbsolute(locks_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const lock_path = try std.fmt.allocPrint(allocator, "{s}/{s}.lock", .{ locks_dir, branch });
    defer allocator.free(lock_path);

    const file = try std.fs.createFileAbsolute(lock_path, .{});
    defer file.close();

    // Write timestamp
    const timestamp = std.time.timestamp();
    var buf: [32]u8 = undefined;
    const ts_str = std.fmt.bufPrint(&buf, "{d}", .{timestamp}) catch "0";
    _ = try file.write(ts_str);
}

pub fn unlockWorktree(allocator: std.mem.Allocator, repo_root: []const u8, branch: []const u8) !void {
    const meta_dir = try getMetadataDir(allocator, repo_root);
    defer allocator.free(meta_dir);

    const lock_path = try std.fmt.allocPrint(allocator, "{s}/locks/{s}.lock", .{ meta_dir, branch });
    defer allocator.free(lock_path);

    std.fs.deleteFileAbsolute(lock_path) catch |err| {
        if (err != error.FileNotFound) return err;
    };
}

pub fn isLocked(allocator: std.mem.Allocator, repo_root: []const u8, branch: []const u8) !bool {
    const meta_dir = try getMetadataDir(allocator, repo_root);
    defer allocator.free(meta_dir);

    const lock_path = try std.fmt.allocPrint(allocator, "{s}/locks/{s}.lock", .{ meta_dir, branch });
    defer allocator.free(lock_path);

    return std.fs.accessAbsolute(lock_path, .{}) != error.FileNotFound;
}

pub const WorktreeRef = struct {
    path: []const u8,
    branch: []const u8,
};

pub const GcCandidate = struct {
    branch: []const u8,
    path: []const u8,
    reason: []const u8,
};

pub fn findGcCandidates(allocator: std.mem.Allocator, worktrees: []const WorktreeRef) ![]GcCandidate {
    var candidates: std.ArrayListUnmanaged(GcCandidate) = .empty;
    errdefer candidates.deinit(allocator);

    for (worktrees) |wt| {
        // Check if directory exists
        const dir_exists = std.fs.accessAbsolute(wt.path, .{}) != error.FileNotFound;
        if (!dir_exists) {
            try candidates.append(allocator, .{
                .branch = wt.branch,
                .path = wt.path,
                .reason = "directory missing",
            });
            continue;
        }

        // Check if branch is merged (would need git check, simplified here)
        // For now, just check if worktree is in detached state
        if (std.mem.eql(u8, wt.branch, "(detached)")) {
            try candidates.append(allocator, .{
                .branch = wt.branch,
                .path = wt.path,
                .reason = "detached HEAD",
            });
        }
    }

    return candidates.toOwnedSlice(allocator);
}

// Tests
test "getMetadataDir returns correct path" {
    const allocator = std.testing.allocator;
    const result = try getMetadataDir(allocator, "/home/user/project");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("/home/user/project/.gwa", result);
}
