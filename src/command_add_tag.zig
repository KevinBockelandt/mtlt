const std = @import("std");

const ansi = @import("ansi_codes.zig");
const data_file_printer = @import("data_file_printer.zig");
const dfr = @import("data_file_reader.zig");
const dfw = @import("data_file_writer.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const it_helper = @import("integration_tests_helper.zig");
const string_helper = @import("string_helper.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataOperationError = @import("data_file_writer.zig").DataOperationError;

/// Add a new tag to the data file
pub fn cmd(args: *ArgumentParser) !void {
    if (args.*.payload == null) {
        try globals.printer.errMissingTagNameToAdd();
        return;
    }
    const name = args.*.payload.?;

    // check name length
    if (name.len > std.math.maxInt(u6)) {
        try globals.printer.errNameTooLong(name);
        return;
    }

    // check for invalid characters in the tag name
    if (!string_helper.isValidTagName(name)) {
        try globals.printer.errNameTagInvalidChara();
        return;
    }

    const priority = if (args.*.priority) |p| p else dt.StatusTag.someday;

    if (globals.dfw.addTagToFile(name, priority)) |new_tag_id| {
        _ = new_tag_id;
        try globals.printer.createdTag(name);
    } else |err| {
        switch (err) {
            DataOperationError.TooManyTags => try globals.printer.errTooManyTags(),
            DataOperationError.TagWithThisNameAlreadyExisting => try globals.printer.errNameTagAlreadyExisting(name),
            else => return err,
        }
    }
}

/// Display help text for this command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt add-tag <tag_name> [OPTIONS]{s}
        \\
        \\Creates a new tag.
        \\
        \\The tag name can only contain ASCII letters, numbers and the '_' or '-'
        \\characters. If no priority is specified, 'someday' is used by default.
        \\
        \\Options:
        \\  {s}-p{s}, {s}--priority{s}         Can be 'now', 'soon' or 'someday'
        \\
        \\Examples:
        \\  {s}mtlt add-tag "myCoolTag"{s}
        \\      Create a new tag called 'myCoolTag' with priority 'someday'.
        \\
        \\  {s}mtlt add-tag "1-also-good" -p now{s}
        \\      Create a new tag called '1-also-good' with priority 'now'.
        \\
        \\  {s}mtlt add-tag "_it_works" -p soon{s}
        \\      Create a new tag called '_it_works' with priority 'soon'.
        \\
    , .{
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}

test "add tag in starter file without specifying priority" {
    var ex_file = try it_helper.getStarterFile();
    try ex_file.tags.insert(0, .{ .id = 4, .status = dt.StatusTag.someday, .name = "testtag" });
    var args: ArgumentParser = .{ .payload = "testtag", .priority = null };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getStarterFile(),
        .ex_file = ex_file,
    });
}

test "add tag in starter file with priority someday" {
    var ex_file = try it_helper.getStarterFile();
    try ex_file.tags.insert(0, .{ .id = 4, .status = dt.StatusTag.someday, .name = "testtag" });
    var args: ArgumentParser = .{ .payload = "testtag", .priority = dt.StatusTag.someday };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getStarterFile(),
        .ex_file = ex_file,
    });
}

test "add tag in starter file with priority soon" {
    var ex_file = try it_helper.getStarterFile();
    try ex_file.tags.insert(0, .{ .id = 4, .status = dt.StatusTag.soon, .name = "testsoon" });
    var args: ArgumentParser = .{ .payload = "testsoon", .priority = dt.StatusTag.soon };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getStarterFile(),
        .ex_file = ex_file,
    });
}

test "add tag in starter file with priority now" {
    var ex_file = try it_helper.getStarterFile();
    try ex_file.tags.insert(0, .{ .id = 4, .status = dt.StatusTag.now, .name = "testnow" });
    var args: ArgumentParser = .{ .payload = "testnow", .priority = dt.StatusTag.now };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getStarterFile(),
        .ex_file = ex_file,
    });
}

test "add tag in a file where the max tag ID is reached" {
    var ac_file = try it_helper.getStarterFile();
    try ac_file.tags.insert(0, .{ .id = 65535, .status = dt.StatusTag.now, .name = "maxIdTag" });
    var args: ArgumentParser = .{ .payload = "overboardIdTag", .priority = null };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_stderr = "The maximum number of tags in the data file is reached.\nDeleting existing tags will not help. You will need to start a new data file.\n",
    });
}

test "add already existing tag" {
    var args: ArgumentParser = .{ .payload = "soon" };
    var buf_ex_stderr: [512]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "A tag with the name {s}soon{s} already exists\n", .{ ansi.colemp, ansi.colres });

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getStarterFile(),
        .ex_stderr = ex_stderr,
    });
}

test "add tag but missing payload" {
    var args: ArgumentParser = .{};

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getStarterFile(),
        .ex_stderr = "Missing the name of the tag to create\n",
    });
}

test "add tag with a name too long" {
    const tag_name = "oeifjsoehusiehfweiopiouhsevioujseoijfosiefoijseovijseoifjoseijesff";
    var args: ArgumentParser = .{ .payload = tag_name, .priority = null };
    var buf_ex_stderr: [512]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "The name \"{s}\" is too long.\n", .{tag_name});

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getStarterFile(),
        .ex_stderr = ex_stderr,
    });
}

test "add tag with an invalid name" {
    var args: ArgumentParser = .{ .payload = "invalid tag" };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getStarterFile(),
        .ex_stderr = "The tag name can only contain ascii letters, numbers or the '-' or '_' character.\n",
    });
}
