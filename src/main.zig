const std = @import("std");
const cli = @import("cli.zig");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;

    cli.run(allocator, args, stdout, stderr) catch |err| {
        try stderr.print("Error: {}\n", .{err});
        try stderr.flush();
        std.process.exit(1);
    };

    try stdout.flush();
}

test {
    _ = @import("cli.zig");
    _ = @import("git.zig");
    _ = @import("config.zig");
    _ = @import("copy.zig");
    _ = @import("hooks.zig");
    _ = @import("editors.zig");
    _ = @import("metadata.zig");
}
