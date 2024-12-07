const std = @import("std");
const Snek = @import("snek");
const command = @import("command.zig");

pub const structType = enum(usize) {
    data_type = 0,
    message = 1,
    command = 2,
    undefined = 3,
};

pub const StructInstance = struct {
    message_id: usize,
    type: structType,
    start_idx: usize,
    identifier_idx: usize,
    end_idx: usize,
    fields: []FieldInstance,
};

pub const FieldInstance = struct {
    identifier_idx: usize,
    type_idx: usize,
    value_idx: usize,
};

fn foundMatch(needle: []const std.zig.Token.Tag, tag: std.zig.Token.Tag, count: *usize) bool {
    if (tag == needle[count.*]) count.* += 1 else count.* = 0;
    const has_match = count.* == needle.len;
    if (has_match) {
        count.* = 0;
        return true;
    } else {
        return false;
    }
}

const TagIterator = struct {
    index: usize,
    slice: []std.zig.Token.Tag,

    pub fn next(self: *@This()) ?std.zig.Token.Tag {
        if (self.index >= self.slice.len) return null;
        defer self.index += 1;
        return self.slice[self.index];
    }

    pub fn init(slice: []std.zig.Token.Tag) TagIterator {
        return TagIterator{ .index = 0, .slice = slice };
    }
};

fn appendStructAndFieldInstance(tree: *std.zig.Ast, tag_slice: []std.zig.Token.Tag, structList: *std.ArrayList(StructInstance), field_list: *std.ArrayList(FieldInstance)) !void {
    const struct_seq = [_]std.zig.Token.Tag{ .keyword_pub, .keyword_const, .identifier, .equal, .keyword_struct };
    var struct_seq_count: usize = 0;

    const const_field_tags = [_]std.zig.Token.Tag{ .keyword_pub, .keyword_const, .identifier, .equal, .number_literal };
    var const_field_count: usize = 0;

    const field_tag_sequence = [_]std.zig.Token.Tag{ .identifier, .colon, .identifier, .comma };
    var field_tag_count: usize = 0;

    const function_tags = [_]std.zig.Token.Tag{ .keyword_pub, .keyword_const, .identifier, .colon, .keyword_fn, .l_paren, .identifier, .r_paren, .identifier };
    var function_tag_count: usize = 0;

    var brace_depth: usize = 0;
    var prev_field_len: usize = 0;

    var iter = TagIterator.init(tag_slice);

    while (iter.next()) |tag| {
        const i = iter.index - 1;
        switch (tag) {
            .l_brace => {
                brace_depth += 1;

                // skip over anything that isn't a struct
                const prev_tag = iter.slice[i - 1];
                if (prev_tag != .keyword_struct) {
                    const starting_depth: usize = brace_depth - 1;
                    while (iter.next()) |t| {
                        switch (t) {
                            .l_brace => {
                                brace_depth += 1;
                            },
                            .r_brace => {
                                brace_depth -= 1;
                                if (brace_depth == starting_depth) {
                                    break;
                                }
                            },
                            else => {},
                        }
                    }
                }
            },
            .r_brace => {
                brace_depth -= 1;

                if (brace_depth == 0) {
                    var index: usize = structList.items.len;

                    // Loop from the end of the list until it find a struct without an end id
                    while (i > 0 and structList.items[index - 1].end_idx != 0) index -= 1;

                    if (structList.items[index - 1].end_idx == 0) {
                        structList.items[index - 1].end_idx = i - 1;
                        structList.items[index - 1].fields = field_list.items[prev_field_len..field_list.items.len];
                        prev_field_len = field_list.items.len;
                    }
                }
            },
            else => {
                // Ignore everything other than root structs/fields
                if (brace_depth > 1) continue;

                if (foundMatch(struct_seq[0..], tag, &struct_seq_count)) {
                    try structList.append(StructInstance{
                        .start_idx = i + 2,
                        .identifier_idx = i - 2,
                        .type = .undefined,
                        .end_idx = 0,
                        .fields = undefined,
                        .message_id = 0,
                    });
                }

                if (foundMatch(const_field_tags[0..], tag, &const_field_count)) {
                    structList.items[structList.items.len - 1].type = .message;

                    // Sets the message ID
                    const field_name = tree.tokenSlice(@intCast(i - 2));
                    if (std.mem.eql(u8, "message_id", field_name)) {
                        const value = tree.tokenSlice(@intCast(i));
                        structList.items[structList.items.len - 1].message_id = try std.fmt.parseInt(usize, value, 10);
                    }
                }

                if (foundMatch(field_tag_sequence[0..], tag, &field_tag_count)) {
                    try field_list.append(FieldInstance{
                        .identifier_idx = i - 3,
                        .type_idx = i - 1,
                        .value_idx = 0,
                    });
                }

                if (foundMatch(function_tags[0..], tag, &function_tag_count)) {
                    try field_list.append(FieldInstance{
                        .identifier_idx = i - 6,
                        .type_idx = i - 2,
                        .value_idx = i,
                    });

                    // Set the struct type to be a command
                    structList.items[structList.items.len - 1].type = .command;
                }
            },
        }
    }
}

test "append struct instance and fields" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const src: [:0]const u8 =
        \\  pub const Header = struct {
        \\      message_id: u8,
        \\      hardware_address: u8,
        \\  }
    ;

    // Convert the src content into tokens
    var tree = std.zig.Ast.parse(allocator, src, .zig) catch {
        std.debug.print("failed to parse source file.", .{});
        return;
    };
    defer tree.deinit(allocator);

    const token_tags: []std.zig.Token.Tag = tree.tokens.items(.tag);

    var structList = try std.ArrayList(StructInstance).initCapacity(allocator, 8);
    defer structList.deinit();

    var field_list = std.ArrayList(FieldInstance).init(allocator);
    defer field_list.deinit();

    try appendStructAndFieldInstance(&tree, token_tags[0..], &structList, &field_list);

    var expected_field_list = [_]FieldInstance{
        FieldInstance{ .identifier_idx = 8, .type_idx = 0, .value_idx = 10 },
        FieldInstance{ .identifier_idx = 14, .type_idx = 16, .value_idx = 0 },
        FieldInstance{ .identifier_idx = 26, .type_idx = 0, .value_idx = 28 },
        FieldInstance{ .identifier_idx = 32, .type_idx = 34, .value_idx = 0 },
    };

    const expected_structList = [_]StructInstance{
        StructInstance{ .message_id = 10, .type = .undefined, .start_idx = 6, .end_idx = 15, .identifier_idx = 2, .fields = expected_field_list[0..2] },
        StructInstance{ .message_id = 11, .type = .undefined, .start_idx = 24, .end_idx = 33, .identifier_idx = 20, .fields = expected_field_list[2..4] },
    };

    // Make sure it gets all of the structs correct
    try std.testing.expectEqualSlices(StructInstance, expected_structList[0..], structList.items[0..]);

    try std.testing.expectEqualSlices(FieldInstance, expected_field_list[0..], field_list.items[0..]);
}

pub fn allocFileContents(allocator: std.mem.Allocator, path: []const u8) ![:0]u8 {
    // Open the file
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const file_size = try file.getEndPos();

    // Allocate the memory
    var contents = try allocator.alloc(u8, file_size);
    defer allocator.free(contents);

    // Read the file contents
    _ = try file.readAll(contents[0..]);

    // Make a copy that is zero terminated
    const contents_zero_terminated: [:0]u8 = try allocator.dupeZ(u8, contents[0..]);

    return contents_zero_terminated;
}

pub const cli_args = struct {
    file_path: []const u8,
    client: []const u8,
};

fn getCliArgs(allocator: std.mem.Allocator) !cli_args {
    var cli = try Snek.Snek(cli_args).init(allocator);
    defer cli.deinit();
    return try cli.parse();
}

pub fn main() !void {
    // Init the allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    // Parse the cli args
    const args = try getCliArgs(allocator);

    // Read in the definition file to a slice
    const src = try allocFileContents(allocator, args.file_path);
    defer allocator.free(src);

    // Parse the content and load the tokens
    var tree = std.zig.Ast.parse(allocator, src, .zig) catch {
        std.debug.print("failed to parse source file.", .{});
        return;
    };
    defer tree.deinit(allocator);

    // Get the tokens from the tree
    const token_tags: []std.zig.Token.Tag = tree.tokens.items(.tag);

    // Init the struct with the indexes for the start/stop positions of the struct
    var structList = try std.ArrayList(StructInstance).initCapacity(allocator, 8);
    defer structList.deinit();

    // Init the struct with the indexes for the start/stop positions of the field
    var field_list = std.ArrayList(FieldInstance).init(allocator);
    defer field_list.deinit();

    try appendStructAndFieldInstance(&tree, token_tags, &structList, &field_list);

    var command_count: usize = 0;
    var message_count: usize = 0;

    // Get the total number of commands
    for (structList.items) |item| {
        switch (item.type) {
            .command => command_count += 1,
            .message => message_count += 1,
            else => {},
        }
    }

    std.log.info("Parsed {d} Messages", .{message_count});

    var map = std.StringHashMap(StructInstance).init(allocator);
    defer map.deinit();

    for (structList.items) |value| {
        const name = tree.tokenSlice(@intCast(value.identifier_idx));
        try map.put(name, value);
    }

    // Create the the messages
    var messages = try allocator.alloc(command.Message, message_count);
    defer allocator.free(messages);

    //var header_fields = try allocator.alloc(command.Field, 10);
    //defer allocator.free(header_fields);
    var header: ?command.Message = null;

    var message_index: usize = 0;
    // populate the commands
    for (structList.items) |item| {
        const struct_name = tree.tokenSlice(@intCast(item.identifier_idx));
        switch (item.type) {
            .message => {
                messages[message_index] = command.Message{
                    .fields = try allocFields(allocator, item.identifier_idx, &tree, &map),
                    .id = item.message_id,
                    .name = struct_name,
                };
                message_index += 1;
            },
            else => {
                // check to see if the name of struct is "Header"
                const name = tree.tokenSlice(@intCast(item.identifier_idx));
                if (!std.mem.eql(u8, "Header", name)) continue;

                header = command.Message{
                    .fields = try allocFields(allocator, item.identifier_idx, &tree, &map),
                    .id = 0,
                    .name = name,
                };
            },
        }
    }

    // Get the generated folder path from the cli arg
    var generated_folder_path: []const u8 = undefined;
    var filename: []const u8 = undefined;

    const split_index_opt = std.mem.lastIndexOf(u8, args.file_path, "/");
    if (split_index_opt) |index| {
        generated_folder_path = try std.fmt.allocPrint(allocator, "{s}/generated", .{args.file_path[0..index]});
        filename = args.file_path[index + 1 ..];
    } else {
        generated_folder_path = "./generated";
        filename = args.file_path[0..];
    }

    // Make sure the generated folder exists
    std.fs.cwd().makeDir(generated_folder_path) catch {};

    // Now do the code generation
    const data = .{ .messages = messages, .header = header, .filename = filename };

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

    if (std.mem.eql(u8, "zig", args.client)) {
        try command.get_template_file_names(zigTemplate, "zig", generated_folder_path, allocator, &json);
    }

    if (std.mem.eql(u8, "python", args.client)) {
        try command.get_template_file_names(pythonTemplate, "py", generated_folder_path, allocator, &json);
    }

    if (std.mem.eql(u8, "webserial", args.client)) {
        std.log.info("running", .{});
        try command.get_template_file_names(webserialHtmlTemplate, "html", generated_folder_path, allocator, &json);
        try command.get_template_file_names(webserialJsTemplate, "js", generated_folder_path, allocator, &json);
    }
}

pub const Template = struct {
    filename: []const u8,
    directory: []const u8,
    contents: []const u8,
    partials: ?[]const Template,

    pub fn init(directory: []const u8, filename: []const u8, partials: ?[]const Template) Template {
        const contents = @embedFile(directory ++ "/" ++ filename).*;
        return Template{
            .filename = filename,
            .directory = directory,
            .contents = &contents,
            .partials = partials,
        };
    }
};

const zigTemplate = Template.init(
    "/home/epentland/ai/embedded/ZigProtoGen/src/templates/zig",
    "commands.mustache",
    &[_]Template{
        Template.init("/home/epentland/ai/embedded/ZigProtoGen/src/templates/zig/partials", "args.mustache", null),
    },
);

const pythonTemplate = Template.init(
    "/home/epentland/ai/embedded/ZigProtoGen/src/templates/python",
    "commands.mustache",
    null,
);

const webserialHtmlTemplate = Template.init(
    "/home/epentland/ai/embedded/ZigProtoGen/src/templates/webserial",
    "index.mustache",
    null,
);

const webserialJsTemplate = Template.init(
    "/home/epentland/ai/embedded/ZigProtoGen/src/templates/webserial",
    "formGenerator.mustache",
    null,
);

fn allocFields(allocator: std.mem.Allocator, idx: usize, tree: *std.zig.Ast, map: *std.StringHashMap(StructInstance)) ![]command.Field {
    const name = tree.tokenSlice(@intCast(idx));

    // Check for a header
    if (map.get(name) == null) return error.StructNotFound;

    const cmd_struct = map.get(name).?;

    var cmd_fields = try allocator.alloc(command.Field, cmd_struct.fields.len);

    // Prepend the header
    var index: usize = 0;

    for (cmd_struct.fields) |field| {
        const f_name = tree.tokenSlice(@intCast(field.identifier_idx));
        const f_type = try getFieldType(tree.tokenSlice(@intCast(field.type_idx)));
        var f_value: []const u8 = "";

        if (field.value_idx != 0) {
            f_value = tree.tokenSlice(@intCast(field.value_idx));
        }

        var is_const = f_type == .constant;

        if (std.mem.eql(u8, "message_id", f_name)) {
            is_const = true;
        }

        cmd_fields[index] = command.Field{
            .field_name = f_name,
            .field_type = f_type,
            .field_value = f_value,
            .is_u16 = f_type == .u16,
            .is_u8 = f_type == .u8,
            .is_const = is_const,
        };
        index += 1;
    }

    return cmd_fields;
}

fn getFieldType(type_string: []const u8) !command.fieldType {
    if (std.mem.eql(u8, type_string, "u8")) return command.fieldType.u8;
    if (std.mem.eql(u8, type_string, "u16")) return command.fieldType.u16;
    if (std.mem.eql(u8, type_string, "u32")) return command.fieldType.u32;

    return command.fieldType.structs;
}
