const std = @import("std");

pub const Config = struct {
    // Worktree settings
    worktrees_dir: ?[]const u8 = null, // Default: sibling to repo
    default_base: []const u8 = "main",

    // File copying
    copy_files: []const []const u8 = &.{},
    copy_dirs: []const []const u8 = &.{},

    // Editor settings
    editor: []const u8 = "code",

    // AI tool settings
    ai_tool: []const u8 = "claude",

    // Hooks
    post_create_hook: ?[]const u8 = null,
    pre_remove_hook: ?[]const u8 = null,

    allocator: std.mem.Allocator,

    pub fn deinit(self: *Config) void {
        if (self.worktrees_dir) |dir| self.allocator.free(dir);
        for (self.copy_files) |f| self.allocator.free(f);
        if (self.copy_files.len > 0) self.allocator.free(self.copy_files);
        for (self.copy_dirs) |d| self.allocator.free(d);
        if (self.copy_dirs.len > 0) self.allocator.free(self.copy_dirs);
        if (self.post_create_hook) |h| self.allocator.free(h);
        if (self.pre_remove_hook) |h| self.allocator.free(h);
    }
};

pub fn loadConfig(allocator: std.mem.Allocator, repo_root: ?[]const u8) !Config {
    var config = Config{ .allocator = allocator };

    // Try loading global config first
    const home = std.posix.getenv("HOME") orelse return config;
    const global_path = try std.fmt.allocPrint(allocator, "{s}/.gwa/config.toml", .{home});
    defer allocator.free(global_path);

    if (readConfigFile(allocator, global_path)) |global_cfg| {
        mergeConfig(&config, global_cfg, allocator);
    } else |_| {}

    // Then load project config (overrides global)
    if (repo_root) |root| {
        const project_path = try std.fmt.allocPrint(allocator, "{s}/.gwa/config.toml", .{root});
        defer allocator.free(project_path);

        if (readConfigFile(allocator, project_path)) |project_cfg| {
            mergeConfig(&config, project_cfg, allocator);
        } else |_| {}

        // Also try .gwaconfig in repo root
        const alt_path = try std.fmt.allocPrint(allocator, "{s}/.gwaconfig", .{root});
        defer allocator.free(alt_path);

        if (readConfigFile(allocator, alt_path)) |alt_cfg| {
            mergeConfig(&config, alt_cfg, allocator);
        } else |_| {}
    }

    return config;
}

const ParsedConfig = struct {
    worktrees_dir: ?[]const u8 = null,
    default_base: ?[]const u8 = null,
    copy_files: ?[][]const u8 = null,
    copy_dirs: ?[][]const u8 = null,
    editor: ?[]const u8 = null,
    ai_tool: ?[]const u8 = null,
    post_create_hook: ?[]const u8 = null,
    pre_remove_hook: ?[]const u8 = null,
};

fn readConfigFile(allocator: std.mem.Allocator, path: []const u8) !ParsedConfig {
    const file = std.fs.openFileAbsolute(path, .{}) catch return error.FileNotFound;
    defer file.close();

    const content = file.deprecatedReader().readAllAlloc(allocator, 1024 * 64) catch return error.ReadError;
    defer allocator.free(content);

    return parseToml(allocator, content);
}

fn parseToml(allocator: std.mem.Allocator, content: []const u8) !ParsedConfig {
    var config = ParsedConfig{};
    var copy_files_list: std.ArrayListUnmanaged([]const u8) = .empty;
    var copy_dirs_list: std.ArrayListUnmanaged([]const u8) = .empty;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#' or trimmed[0] == '[') continue;

        if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
            const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
            var value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t");

            // Remove quotes if present
            if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
                value = value[1 .. value.len - 1];
            }

            if (std.mem.eql(u8, key, "worktrees_dir")) {
                config.worktrees_dir = try allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, key, "default_base")) {
                config.default_base = try allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, key, "editor")) {
                config.editor = try allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, key, "ai_tool")) {
                config.ai_tool = try allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, key, "post_create_hook")) {
                config.post_create_hook = try allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, key, "pre_remove_hook")) {
                config.pre_remove_hook = try allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, key, "copy_files")) {
                // Parse array: ["file1", "file2"]
                try parseArray(allocator, value, &copy_files_list);
            } else if (std.mem.eql(u8, key, "copy_dirs")) {
                try parseArray(allocator, value, &copy_dirs_list);
            }
        }
    }

    if (copy_files_list.items.len > 0) {
        config.copy_files = try copy_files_list.toOwnedSlice(allocator);
    }
    if (copy_dirs_list.items.len > 0) {
        config.copy_dirs = try copy_dirs_list.toOwnedSlice(allocator);
    }

    return config;
}

fn parseArray(allocator: std.mem.Allocator, value: []const u8, list: *std.ArrayListUnmanaged([]const u8)) !void {
    // Simple array parser for ["item1", "item2"]
    const trimmed = std.mem.trim(u8, value, " \t[]");
    var items = std.mem.splitScalar(u8, trimmed, ',');
    while (items.next()) |item| {
        const clean = std.mem.trim(u8, item, " \t\"'");
        if (clean.len > 0) {
            try list.append(allocator, try allocator.dupe(u8, clean));
        }
    }
}

fn mergeConfig(target: *Config, source: ParsedConfig, allocator: std.mem.Allocator) void {
    if (source.worktrees_dir) |v| {
        if (target.worktrees_dir) |old| allocator.free(old);
        target.worktrees_dir = v;
    }
    if (source.default_base) |v| {
        target.default_base = v;
    }
    if (source.editor) |v| {
        target.editor = v;
    }
    if (source.ai_tool) |v| {
        target.ai_tool = v;
    }
    if (source.post_create_hook) |v| {
        if (target.post_create_hook) |old| allocator.free(old);
        target.post_create_hook = v;
    }
    if (source.pre_remove_hook) |v| {
        if (target.pre_remove_hook) |old| allocator.free(old);
        target.pre_remove_hook = v;
    }
    if (source.copy_files) |v| {
        for (target.copy_files) |f| allocator.free(f);
        if (target.copy_files.len > 0) allocator.free(target.copy_files);
        target.copy_files = v;
    }
    if (source.copy_dirs) |v| {
        for (target.copy_dirs) |d| allocator.free(d);
        if (target.copy_dirs.len > 0) allocator.free(target.copy_dirs);
        target.copy_dirs = v;
    }
}

// Tests
test "parseToml parses simple config" {
    const allocator = std.testing.allocator;
    const content =
        \\# Comment
        \\default_base = "main"
        \\editor = "cursor"
        \\copy_files = [".env", ".envrc"]
    ;

    const config = try parseToml(allocator, content);
    defer {
        if (config.default_base) |v| allocator.free(v);
        if (config.editor) |v| allocator.free(v);
        if (config.copy_files) |files| {
            for (files) |f| allocator.free(f);
            allocator.free(files);
        }
    }

    try std.testing.expectEqualStrings("main", config.default_base.?);
    try std.testing.expectEqualStrings("cursor", config.editor.?);
    try std.testing.expectEqual(@as(usize, 2), config.copy_files.?.len);
    try std.testing.expectEqualStrings(".env", config.copy_files.?[0]);
}
