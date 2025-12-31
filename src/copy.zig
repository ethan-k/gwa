const std = @import("std");

pub fn copyFiles(allocator: std.mem.Allocator, patterns: []const []const u8, src_dir: []const u8, dst_dir: []const u8) !usize {
    var copied: usize = 0;

    for (patterns) |pattern| {
        // Handle glob patterns or direct file paths
        if (std.mem.indexOf(u8, pattern, "*")) |_| {
            // Glob pattern - expand and copy matching files
            copied += try copyGlobPattern(allocator, pattern, src_dir, dst_dir);
        } else {
            // Direct file path
            const src_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ src_dir, pattern });
            defer allocator.free(src_path);

            const dst_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dst_dir, pattern });
            defer allocator.free(dst_path);

            if (copyFile(src_path, dst_path)) {
                copied += 1;
            } else |_| {}
        }
    }

    return copied;
}

pub fn copyDirs(allocator: std.mem.Allocator, dirs: []const []const u8, src_dir: []const u8, dst_dir: []const u8) !usize {
    var copied: usize = 0;

    for (dirs) |dir_name| {
        const src_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ src_dir, dir_name });
        defer allocator.free(src_path);

        const dst_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dst_dir, dir_name });
        defer allocator.free(dst_path);

        if (copyDirRecursive(allocator, src_path, dst_path)) {
            copied += 1;
        } else |_| {}
    }

    return copied;
}

fn copyGlobPattern(allocator: std.mem.Allocator, pattern: []const u8, src_dir: []const u8, dst_dir: []const u8) !usize {
    // Simple glob: only handle *.ext patterns for now
    var copied: usize = 0;

    const dir = std.fs.openDirAbsolute(src_dir, .{ .iterate = true }) catch return 0;
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;

        if (matchGlob(pattern, entry.name)) {
            const src_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ src_dir, entry.name });
            defer allocator.free(src_path);

            const dst_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dst_dir, entry.name });
            defer allocator.free(dst_path);

            if (copyFile(src_path, dst_path)) {
                copied += 1;
            } else |_| {}
        }
    }

    return copied;
}

fn matchGlob(pattern: []const u8, name: []const u8) bool {
    // Simple glob matching for *.ext or prefix*
    if (std.mem.startsWith(u8, pattern, "*.")) {
        const ext = pattern[1..]; // includes the dot
        return std.mem.endsWith(u8, name, ext);
    } else if (std.mem.endsWith(u8, pattern, "*")) {
        const prefix = pattern[0 .. pattern.len - 1];
        return std.mem.startsWith(u8, name, prefix);
    } else if (std.mem.indexOf(u8, pattern, "*")) |star_pos| {
        const prefix = pattern[0..star_pos];
        const suffix = pattern[star_pos + 1 ..];
        return std.mem.startsWith(u8, name, prefix) and std.mem.endsWith(u8, name, suffix);
    }
    return std.mem.eql(u8, pattern, name);
}

fn copyFile(src: []const u8, dst: []const u8) !void {
    const src_file = try std.fs.openFileAbsolute(src, .{});
    defer src_file.close();

    // Create parent directory if needed
    if (std.fs.path.dirname(dst)) |parent| {
        std.fs.makeDirAbsolute(parent) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
    }

    const dst_file = try std.fs.createFileAbsolute(dst, .{});
    defer dst_file.close();

    var buf: [8192]u8 = undefined;
    while (true) {
        const bytes_read = try src_file.read(&buf);
        if (bytes_read == 0) break;
        _ = try dst_file.write(buf[0..bytes_read]);
    }
}

fn copyDirRecursive(allocator: std.mem.Allocator, src: []const u8, dst: []const u8) !void {
    // Create destination directory
    std.fs.makeDirAbsolute(dst) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const src_dir = try std.fs.openDirAbsolute(src, .{ .iterate = true });
    defer src_dir.close();

    var iter = src_dir.iterate();
    while (try iter.next()) |entry| {
        const src_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ src, entry.name });
        defer allocator.free(src_path);

        const dst_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dst, entry.name });
        defer allocator.free(dst_path);

        switch (entry.kind) {
            .file => try copyFile(src_path, dst_path),
            .directory => try copyDirRecursive(allocator, src_path, dst_path),
            else => {},
        }
    }
}

// Tests
test "matchGlob matches *.env pattern" {
    try std.testing.expect(matchGlob("*.env", ".env"));
    try std.testing.expect(matchGlob("*.env", "test.env"));
    try std.testing.expect(!matchGlob("*.env", ".envrc"));
}

test "matchGlob matches prefix* pattern" {
    try std.testing.expect(matchGlob(".env*", ".env"));
    try std.testing.expect(matchGlob(".env*", ".envrc"));
    try std.testing.expect(matchGlob(".env*", ".env.local"));
    try std.testing.expect(!matchGlob(".env*", "config.env"));
}
