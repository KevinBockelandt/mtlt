const ansi = @import("ansi_codes.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const it_helper = @import("integration_tests_helper.zig");
const std = @import("std");
const string_helper = @import("string_helper.zig");
const th = @import("time_helper.zig");
const cli_helper = @import("cli_helper.zig");
const data_file_printer = @import("data_file_printer.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataParsingError = @import("data_file_reader.zig").DataParsingError;
const DataOperationError = @import("data_file_writer.zig").DataOperationError;

const little_end = std.builtin.Endian.little;

/// Delete a thing from the data file
pub fn cmd(args: *ArgumentParser) !void {
    if (args.*.payload == null) {
        try globals.printer.errMissingTagName();
    }

    const tag_name = args.*.payload.?;

    // check that the tag name is valid
    if (!string_helper.isValidTagName(tag_name)) {
        try globals.printer.errInvalidTagId();
        return;
    }

    // check that the tag exist in the date file
    _ = globals.dfr.getPosTag(tag_name) catch |err| {
        switch (err) {
            DataParsingError.TagNotFound => try globals.printer.errTagNotFoundName(tag_name),
            else => try globals.printer.errUnexpected(err),
        }
        return;
    };

    // get confirmation if necessary
    if (!args.auto_confirm) {
        try globals.printer.confirmDeleteTag(tag_name);
        if (try cli_helper.confirm() == false) return;
    }

    try globals.dfw.deleteTagFromFile(tag_name);
    try globals.printer.deletedTag(tag_name);
}

/// Print out help for the delete command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt delete-tag <id>{s}
        \\
        \\Deletes a tag permanently from the data file.
        \\
        \\Examples:
        \\  {s}mtlt delete urgent{s}
        \\      Delete the tag with name 'urgent'.
        \\
        \\  {s}mtlt delete cool-tag{s}
        \\      Delete the tag with name 'cool-tag'.
        \\
    , .{
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}

test "delete tag without a tag name" {
    const cur_time = th.curTimestamp();

    var buf_ex_stderr: [128]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "Missing the name to tag to operate on.\n", .{});

    var args = ArgumentParser{ .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = try it_helper.getSmallFile(cur_time),
        .ex_stderr = ex_stderr,
    });
}

test "delete tag for a non existing tag in data file" {
    const cur_time = th.curTimestamp();

    var buf_ex_stderr: [128]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "Tag with the name {s}nonexisting{s} not found\n", .{ ansi.colemp, ansi.colres });

    var args = ArgumentParser{ .payload = "nonexisting", .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = try it_helper.getSmallFile(cur_time),
        .ex_stderr = ex_stderr,
    });
}

test "delete tag for an invalid tag name" {
    const cur_time = th.curTimestamp();

    var buf_ex_stderr: [128]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "The provided tag ID is invalid.\n", .{});

    var args = ArgumentParser{ .payload = "invalid.id", .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = try it_helper.getSmallFile(cur_time),
        .ex_stderr = ex_stderr,
    });
}

test "delete tag OK simple" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);

    var buf_ex_stdout: [128]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "The tag {s}next{s} was deleted\n", .{ ansi.colemp, ansi.colres });

    _ = ex_file.tags.orderedRemove(0);
    globals.allocator.free(ex_file.things.items[1].tags);
    ex_file.things.items[1].tags = &[_]u16{};

    var args = ArgumentParser{ .payload = "next", .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
    });
}

test "delete tag OK complex" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getMediumFile(cur_time);
    const ac_file = try ex_file.clone();

    // remove the "next" tag from the file
    _ = ex_file.tags.orderedRemove(30);

    ex_file.things.items[10].tags = &[_]u16{};
    ex_file.things.items[20].tags = &[_]u16{};

    var tag_2 = try globals.allocator.alloc(u16, 1);
    tag_2[0] = 2;

    ex_file.things.items[30].tags = tag_2[0..];
    ex_file.things.items[40].tags = tag_2[0..];

    var tag_2_1 = try globals.allocator.alloc(u16, 2);
    tag_2_1[0] = 2;
    tag_2_1[1] = 1;
    ex_file.things.items[50].tags = tag_2_1[0..];

    var buf_ex_stdout: [128]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "The tag {s}next{s} was deleted\n", .{ ansi.colemp, ansi.colres });

    var args = ArgumentParser{ .payload = "next", .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
    });
}
