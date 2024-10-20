const std = @import("std");
const snek = @import("snek").Snek;

// Binary is also compiled for showcasing how to use the API
const T = struct {
    file_path: []const u8,
};

// Example command after compilation:
// ./zig-out/bin/snek -name="test mctest" -location=420 -exists=true
pub fn main() !void {
    var cli = try snek(T).init(std.heap.page_allocator);
    const parsed_cli = try cli.parse();

    // Necessary is skipped here to showcase optional values being ignored
    std.debug.print("file_path: {s}\n", .{parsed_cli.file_path});
}
