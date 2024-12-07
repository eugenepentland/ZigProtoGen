const std = @import("std");
const mustache = @import("mustache");
const Template = @import("main.zig").Template;

pub const Struct = struct {
    name: []const u8,
    id: usize,

    request_fields: []Field,
    response_fields: []Field,

    pub fn deinit(self: *Struct) void {
        self.fields.deinit();
    }

    pub fn init() !Struct {
        return Struct{
            .id = 0,
            .name = "",
            .request_fields = undefined,
            .response_fields = undefined,
        };
    }
};

pub const Message = struct {
    name: []const u8,
    id: usize,
    fields: []Field,

    pub fn init() !Struct {
        return Struct{
            .id = 0,
            .name = "",
            .request_fields = undefined,
            .response_fields = undefined,
        };
    }
};

pub const fieldType = enum(u8) {
    u8,
    u16,
    u32,
    structs,
    constant,
};

pub const Field = struct {
    field_name: []const u8,
    field_type: fieldType,
    field_value: []const u8,
    is_u8: bool,
    is_u16: bool,
    is_const: bool,
};

fn field_type_to_enum(T: type) !fieldType {
    const type_info = @typeInfo(T);
    switch (type_info) {
        .Int => |i| {
            switch (i.bits) {
                8 => return fieldType.u8,
                16 => return fieldType.u16,
                32 => return fieldType.u32,
                else => return fieldType.u32,
            }
        },
        else => return error.InvalidType,
    }
}

const template_folder_struct = struct {
    folder_name: []const u8,
    template_names: [][]const u8,
    partial_names: [][]const u8,
};

const JsonConfig = struct {
    file_extension: []const u8,
};

pub fn allocJsonConfig(dir: []const u8, allocator: std.mem.Allocator) !std.json.Parsed(JsonConfig) {
    // get the config path
    const partials_folder_path = try std.fmt.allocPrint(allocator, "{s}/config.json", .{dir});
    defer allocator.free(partials_folder_path);

    // Open the file
    const file = try std.fs.cwd().openFile(partials_folder_path, .{});
    defer file.close();
    const file_size = try file.getEndPos();

    // allocate the memory
    const buffer = try allocator.alloc(u8, @intCast(file_size));
    defer allocator.free(buffer);

    // Put the text into the buffer
    _ = try file.readAll(buffer);
    return try std.json.parseFromSlice(JsonConfig, allocator, buffer, .{ .allocate = .alloc_always });
}

test "allocate json config" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const config = try allocJsonConfig("/home/epentland/ai/embedded/ZigProtoGen/src/templates/python-client", allocator);
    defer config.deinit();
    std.log.warn("{s}", .{config.value.file_extension});
}

fn getMustacheTemplate(allocator: std.mem.Allocator, template: Template) !mustache.Template {
    const result = try mustache.parseText(allocator, template.contents, .{}, .{ .copy_strings = false, .features = .{} });
    switch (result) {
        .parse_error => {
            return error.ParseError;
        },
        .success => |temp| {
            return temp;
        },
    }
}

pub fn get_template_file_names(template: Template, file_extension: []const u8, generated_folder_path: []const u8, allocator: std.mem.Allocator, data: anytype) !void {
    // Create an empty hashmap of the partial templates
    var partials = std.StringHashMap(mustache.Template).init(allocator);
    defer partials.deinit();

    if (template.partials) |partials_template| {
        // Load all of the partials into the hashmap
        for (partials_template) |t| {
            const mustache_template = try getMustacheTemplate(allocator, t);
            try partials.put(t.filename, mustache_template);
        }
    }

    // Load the main template
    const mustache_template = try getMustacheTemplate(allocator, template);

    // Render the template
    const contents = try mustache.allocRenderPartials(allocator, mustache_template, partials, data);

    // Create a file
    const filename = template.filename[0 .. template.filename.len - 9];
    const file_path = try std.fmt.allocPrint(allocator, "{s}/{s}.{s}", .{ generated_folder_path, filename, file_extension });
    const file = try std.fs.cwd().createFile(file_path, .{});
    defer allocator.free(file_path);
    defer file.close();

    try file.writeAll(contents);
}
