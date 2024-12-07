const std = @import("std");

test "load file comptime" {
    comptime {
        const dir = try std.fs.cwd().openDir("./", .{ .iterate = true });
        defer dir.close();

        std.log.warn("{any}", .{dir});
    }
}
