const std = @import("std");

pub const Editor = enum {
    code,
    cursor,
    zed,
    vim,
    nvim,
    antigravity,
    kiro,
    windsurf,
    fleet,
    sublime,
    helix,
    idea,
    lapce,
    custom,

    pub fn fromString(name: []const u8) Editor {
        if (std.mem.eql(u8, name, "code") or std.mem.eql(u8, name, "vscode")) return .code;
        if (std.mem.eql(u8, name, "cursor")) return .cursor;
        if (std.mem.eql(u8, name, "zed")) return .zed;
        if (std.mem.eql(u8, name, "vim")) return .vim;
        if (std.mem.eql(u8, name, "nvim") or std.mem.eql(u8, name, "neovim")) return .nvim;
        if (std.mem.eql(u8, name, "antigravity") or std.mem.eql(u8, name, "ag")) return .antigravity;
        if (std.mem.eql(u8, name, "kiro")) return .kiro;
        if (std.mem.eql(u8, name, "windsurf")) return .windsurf;
        if (std.mem.eql(u8, name, "fleet")) return .fleet;
        if (std.mem.eql(u8, name, "sublime") or std.mem.eql(u8, name, "subl")) return .sublime;
        if (std.mem.eql(u8, name, "helix") or std.mem.eql(u8, name, "hx")) return .helix;
        if (std.mem.eql(u8, name, "idea") or std.mem.eql(u8, name, "intellij")) return .idea;
        if (std.mem.eql(u8, name, "lapce")) return .lapce;
        return .custom;
    }

    pub fn getCommand(self: Editor, custom_cmd: ?[]const u8) []const u8 {
        return switch (self) {
            .code => "code",
            .cursor => "cursor",
            .zed => "zed",
            .vim => "vim",
            .nvim => "nvim",
            .antigravity => "antigravity",
            .kiro => "kiro",
            .windsurf => "windsurf",
            .fleet => "fleet",
            .sublime => "subl",
            .helix => "hx",
            .idea => "idea",
            .lapce => "lapce",
            .custom => custom_cmd orelse "code",
        };
    }
};

pub const AiTool = enum {
    claude,
    aider,
    copilot,
    opencode,
    gemini,
    codex,
    cody,
    cont,
    amazonq,
    cline,
    custom,

    pub fn fromString(name: []const u8) AiTool {
        if (std.mem.eql(u8, name, "claude") or std.mem.eql(u8, name, "claude-code")) return .claude;
        if (std.mem.eql(u8, name, "aider")) return .aider;
        if (std.mem.eql(u8, name, "copilot")) return .copilot;
        if (std.mem.eql(u8, name, "opencode") or std.mem.eql(u8, name, "oc")) return .opencode;
        if (std.mem.eql(u8, name, "gemini") or std.mem.eql(u8, name, "gemini-cli")) return .gemini;
        if (std.mem.eql(u8, name, "codex") or std.mem.eql(u8, name, "openai-codex")) return .codex;
        if (std.mem.eql(u8, name, "cody") or std.mem.eql(u8, name, "sourcegraph")) return .cody;
        if (std.mem.eql(u8, name, "continue") or std.mem.eql(u8, name, "cont")) return .cont;
        if (std.mem.eql(u8, name, "amazonq") or std.mem.eql(u8, name, "q")) return .amazonq;
        if (std.mem.eql(u8, name, "cline")) return .cline;
        return .custom;
    }

    pub fn getCommand(self: AiTool, custom_cmd: ?[]const u8) []const u8 {
        return switch (self) {
            .claude => "claude",
            .aider => "aider",
            .copilot => "gh copilot",
            .opencode => "opencode",
            .gemini => "gemini",
            .codex => "codex",
            .cody => "cody",
            .cont => "continue",
            .amazonq => "q",
            .cline => "cline",
            .custom => custom_cmd orelse "claude",
        };
    }
};

pub fn openEditor(allocator: std.mem.Allocator, editor_name: []const u8, path: []const u8) !void {
    const editor = Editor.fromString(editor_name);
    const cmd = editor.getCommand(if (editor == .custom) editor_name else null);

    var argv: std.ArrayListUnmanaged([]const u8) = .empty;
    defer argv.deinit(allocator);

    try argv.append(allocator, cmd);
    try argv.append(allocator, path);

    var child = std.process.Child.init(argv.items, allocator);
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    try child.spawn();
    // Don't wait - editor runs in background
}

pub fn launchAiTool(allocator: std.mem.Allocator, tool_name: []const u8, path: []const u8) !void {
    const tool = AiTool.fromString(tool_name);
    const cmd = tool.getCommand(if (tool == .custom) tool_name else null);

    // For AI tools, we typically want to run them in the terminal
    // So we'll use the shell to change directory and run the tool
    const shell_cmd = try std.fmt.allocPrint(allocator, "cd \"{s}\" && {s}", .{ path, cmd });
    defer allocator.free(shell_cmd);

    var argv: std.ArrayListUnmanaged([]const u8) = .empty;
    defer argv.deinit(allocator);

    try argv.append(allocator, "/bin/sh");
    try argv.append(allocator, "-c");
    try argv.append(allocator, shell_cmd);

    var child = std.process.Child.init(argv.items, allocator);
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    child.stdin_behavior = .Inherit;

    try child.spawn();
    _ = try child.wait();
}

pub fn runCommand(allocator: std.mem.Allocator, path: []const u8, command: []const u8) ![]u8 {
    const shell_cmd = try std.fmt.allocPrint(allocator, "cd \"{s}\" && {s}", .{ path, command });
    defer allocator.free(shell_cmd);

    var argv: std.ArrayListUnmanaged([]const u8) = .empty;
    defer argv.deinit(allocator);

    try argv.append(allocator, "/bin/sh");
    try argv.append(allocator, "-c");
    try argv.append(allocator, shell_cmd);

    var child = std.process.Child.init(argv.items, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    const stdout = try child.stdout.?.deprecatedReader().readAllAlloc(allocator, 1024 * 1024);
    errdefer allocator.free(stdout);

    const stderr = try child.stderr.?.deprecatedReader().readAllAlloc(allocator, 1024 * 1024);
    defer allocator.free(stderr);

    _ = try child.wait();

    return stdout;
}

// Tests
test "Editor.fromString parses known editors" {
    try std.testing.expectEqual(Editor.code, Editor.fromString("code"));
    try std.testing.expectEqual(Editor.code, Editor.fromString("vscode"));
    try std.testing.expectEqual(Editor.cursor, Editor.fromString("cursor"));
    try std.testing.expectEqual(Editor.zed, Editor.fromString("zed"));
    try std.testing.expectEqual(Editor.antigravity, Editor.fromString("antigravity"));
    try std.testing.expectEqual(Editor.antigravity, Editor.fromString("ag"));
    try std.testing.expectEqual(Editor.kiro, Editor.fromString("kiro"));
    try std.testing.expectEqual(Editor.windsurf, Editor.fromString("windsurf"));
    try std.testing.expectEqual(Editor.fleet, Editor.fromString("fleet"));
    try std.testing.expectEqual(Editor.sublime, Editor.fromString("sublime"));
    try std.testing.expectEqual(Editor.sublime, Editor.fromString("subl"));
    try std.testing.expectEqual(Editor.helix, Editor.fromString("helix"));
    try std.testing.expectEqual(Editor.helix, Editor.fromString("hx"));
    try std.testing.expectEqual(Editor.idea, Editor.fromString("idea"));
    try std.testing.expectEqual(Editor.idea, Editor.fromString("intellij"));
    try std.testing.expectEqual(Editor.lapce, Editor.fromString("lapce"));
    try std.testing.expectEqual(Editor.custom, Editor.fromString("emacs"));
}

test "AiTool.fromString parses known tools" {
    try std.testing.expectEqual(AiTool.claude, AiTool.fromString("claude"));
    try std.testing.expectEqual(AiTool.claude, AiTool.fromString("claude-code"));
    try std.testing.expectEqual(AiTool.aider, AiTool.fromString("aider"));
    try std.testing.expectEqual(AiTool.opencode, AiTool.fromString("opencode"));
    try std.testing.expectEqual(AiTool.opencode, AiTool.fromString("oc"));
    try std.testing.expectEqual(AiTool.gemini, AiTool.fromString("gemini"));
    try std.testing.expectEqual(AiTool.gemini, AiTool.fromString("gemini-cli"));
    try std.testing.expectEqual(AiTool.codex, AiTool.fromString("codex"));
    try std.testing.expectEqual(AiTool.codex, AiTool.fromString("openai-codex"));
    try std.testing.expectEqual(AiTool.cody, AiTool.fromString("cody"));
    try std.testing.expectEqual(AiTool.cody, AiTool.fromString("sourcegraph"));
    try std.testing.expectEqual(AiTool.cont, AiTool.fromString("continue"));
    try std.testing.expectEqual(AiTool.cont, AiTool.fromString("cont"));
    try std.testing.expectEqual(AiTool.amazonq, AiTool.fromString("amazonq"));
    try std.testing.expectEqual(AiTool.amazonq, AiTool.fromString("q"));
    try std.testing.expectEqual(AiTool.cline, AiTool.fromString("cline"));
    try std.testing.expectEqual(AiTool.custom, AiTool.fromString("my-tool"));
}
