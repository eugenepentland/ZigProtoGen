const std = @import("std");
const mustache = @import("mustache");

pub const cmd_rotate_servo = struct {
    pub const id: u8 = 10;

    pub const request = struct {
        angle: u8,
    };
};

pub const cmd_goto_usb_bootloader = struct {
    pub const id: u8 = 125;
};

pub const cmd_set_led_level = struct {
    pub const id: u8 = 101;

    pub const request = struct {
        level: u8,
    };
};

const commandStruct = struct {
    name: []const u8,
    id: u8,

    request_fields: []commandFields,
    response_fields: []commandFields,

    pub fn deinit(self: *commandStruct) void {
        self.fields.deinit();
    }

    pub fn init() !commandStruct {
        return commandStruct{
            .id = 0,
            .name = "",
            .request_fields = undefined,
            .response_fields = undefined,
        };
    }
};

const fieldType = enum(u8) {
    u8,
    u16,
    u32,
};

const commandFields = struct {
    field_name: []const u8,
    field_type: fieldType,
    is_u8: bool,
    is_u16: bool,
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

fn logFieldNames(allocator: std.mem.Allocator, commands: []commandStruct, comptime TypeList: []const type) !void {
    inline for (TypeList, 0..) |T, i| {
        var cmd = try commandStruct.init();
        cmd.name = @typeName(T)[std.mem.indexOf(u8, @typeName(T), ".").? + 1 ..];

        var request_fields = std.ArrayList(commandFields).init(allocator);
        var response_fields = std.ArrayList(commandFields).init(allocator);

        // Get the id

        if (@hasDecl(T, "id")) {
            cmd.id = T.id;
        }

        if (@hasDecl(T, "request")) {
            const s = T.request;
            const s_type_info = @typeInfo(s);
            const sub_fields = s_type_info.Struct.fields;

            inline for (sub_fields) |sub_field| {
                try request_fields.append(commandFields{
                    .field_name = sub_field.name,
                    .field_type = try field_type_to_enum(sub_field.type),
                    .is_u8 = sub_field.type == u8,
                    .is_u16 = sub_field.type == u16,
                });
            }
        }

        if (@hasDecl(T, "response")) {
            const s = T.response;
            const s_type_info = @typeInfo(s);
            const sub_fields = s_type_info.Struct.fields;

            inline for (sub_fields) |sub_field| {
                try response_fields.append(commandFields{
                    .field_name = sub_field.name,
                    .field_type = try field_type_to_enum(sub_field.type),
                    .is_u8 = sub_field.type == u8,
                    .is_u16 = sub_field.type == u16,
                });
            }
        }

        cmd.request_fields = request_fields.items;
        cmd.response_fields = response_fields.items;
        commands[i] = cmd;
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
    std.log.warn("Folder path {s}", .{partials_folder_path});
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

pub fn get_template_file_names(path: []const u8, allocator: std.mem.Allocator, data: anytype) !void {
    // Get the number of folders
    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();
    var iter = dir.iterate();
    const current_path = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(current_path);

    // Create a generated folder
    std.fs.cwd().makeDir("src/generated") catch |err| {
        switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        }
    };

    // Itterate over all of the template folders
    while (try iter.next()) |entry| {
        switch (entry.kind) {
            .directory => {

                // Load the templates dir
                const templates_folder_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ path, entry.name });
                defer allocator.free(templates_folder_path);

                // Load the JSON config
                const config = try allocJsonConfig(templates_folder_path, allocator);
                defer config.deinit();

                // Create a generated folder
                const generated_folder_path = try std.fmt.allocPrint(allocator, "src/generated/{s}", .{entry.name});
                defer allocator.free(generated_folder_path);
                std.fs.cwd().makeDir(generated_folder_path) catch |err| {
                    switch (err) {
                        error.PathAlreadyExists => {},
                        else => return err,
                    }
                };

                // Get the partials folder path
                const partials_folder_path = try std.fmt.allocPrint(allocator, "{s}/{s}/partials", .{ path, entry.name });
                defer allocator.free(partials_folder_path);

                // Itterate over the partials dir
                var partials_dir = try std.fs.cwd().openDir(partials_folder_path, .{ .iterate = true });
                var iter_partials = partials_dir.iterate();
                defer partials_dir.close();

                // Create an empty hashmap of the partial templates
                var partials = std.StringHashMap(mustache.Template).init(allocator);
                defer partials.deinit();

                // Iterate over the contents of the folder and get all of the partials templates
                while (try iter_partials.next()) |partials_entry| {
                    switch (partials_entry.kind) {
                        .file => {
                            const partial_file_path = try std.mem.concat(allocator, u8, &[_][]const u8{ current_path, "/", partials_folder_path, "/", partials_entry.name });

                            const partialsResult = try mustache.parseFile(allocator, partial_file_path, .{}, .{});

                            switch (partialsResult) {
                                .parse_error => |err| {
                                    std.log.warn("Error parsing the {s} template {any}", .{ partials_entry.name, err });
                                },
                                .success => |result| {
                                    try partials.put(partials_entry.name, result);
                                },
                            }
                        },
                        else => {},
                    }
                }

                var templates_dir = try std.fs.cwd().openDir(templates_folder_path, .{ .iterate = true });
                var iter_templates = templates_dir.iterate();
                defer templates_dir.close();

                // Run the template and print the contents
                while (try iter_templates.next()) |templates_entry| {
                    switch (templates_entry.kind) {
                        .file => {
                            // Make sure the file has the correct file extension
                            _ = std.mem.indexOf(u8, templates_entry.name, "mustache") orelse continue;

                            const template_file_path = try std.mem.concat(allocator, u8, &[_][]const u8{ current_path, "/", templates_folder_path, "/", templates_entry.name });
                            defer allocator.free(template_file_path);

                            std.log.info("Template file: {s}", .{template_file_path});

                            // parse the template
                            const templateResult = try mustache.parseFile(allocator, template_file_path, .{}, .{});

                            switch (templateResult) {
                                .parse_error => |err| {
                                    std.log.warn("Error parsing the {s} template {any}", .{ templates_entry.name, err });
                                },
                                .success => |template| {
                                    defer template.deinit(allocator);
                                    const result = try mustache.allocRenderPartials(allocator, template, partials, data);

                                    // Create a file
                                    const filename = templates_entry.name[0..std.mem.indexOf(u8, templates_entry.name, ".").?];
                                    const file_path = try std.fmt.allocPrint(allocator, "{s}/{s}.{s}", .{ generated_folder_path, filename, config.value.file_extension });
                                    const file = try std.fs.cwd().createFile(file_path, .{});
                                    defer allocator.free(file_path);
                                    defer file.close();

                                    //std.log.info("Template Parsed: {s}", .{result});

                                    try file.writeAll(result);
                                },
                            }
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }
    }
}

pub fn main() !void {
    const structs = &[_]type{
        cmd_goto_usb_bootloader,
        cmd_set_led_level,
        cmd_rotate_servo,
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const commands = try allocator.alloc(commandStruct, structs.len);
    defer allocator.free(commands);

    try logFieldNames(allocator, commands, structs);

    const data = .{ .commands = commands };

    // convert the data to json
    var json_source = std.ArrayList(u8).init(allocator);
    defer json_source.deinit();

    try std.json.stringify(data, .{}, json_source.writer());

    // convert into the u8 arraylist
    var json = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json_source.items,
        .{},
    );
    defer json.deinit();

    std.log.info("JSON Data: {s}", .{json_source.items});

    // Get the folder/filenames
    try get_template_file_names("src/templates", allocator, &json);
}
