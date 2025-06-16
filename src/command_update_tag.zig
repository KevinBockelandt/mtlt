const std = @import("std");

const ansi = @import("ansi_codes.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const it_helper = @import("integration_tests_helper.zig");
const string_helper = @import("string_helper.zig");
const th = @import("time_helper.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataOperationError = @import("data_file_writer.zig").DataOperationError;
const DataParsingError = @import("data_file_reader.zig").DataParsingError;

/// Update the name of a tag
pub fn cmd(args: *ArgumentParser) !void {
    if (args.*.payload == null) {
        try globals.printer.errUpdateTagMissingCurName();
        return;
    }

    const cur_name = args.*.payload.?;

    var was_something_updated = false;

    // Update the priority of the tag if it's appropriate
    if (args.*.priority != null) {
        try globals.dfw.updateTagPriority(cur_name, args.*.priority.?);
        try globals.printer.updatedTagPriority(cur_name, args.*.priority.?);
        was_something_updated = true;
    }

    // Update the name of the tag if it's appropriate
    if (args.*.name != null) {
        const new_name = args.*.name.?;

        // check for invalid characters in the tag name
        if (!string_helper.isValidTagName(new_name)) {
            try globals.printer.errNameTagInvalidChara();
            return;
        }

        // udpate the tag name
        if (globals.dfw.updateTagName(cur_name, new_name)) |_| {
            try globals.printer.updatedTagName(cur_name, new_name);
        } else |err| {
            switch (err) {
                DataParsingError.TagNotFound => try globals.printer.errTagNotFoundName(cur_name),
                DataOperationError.NameTooLong => try globals.printer.errNameTooLong(new_name),
                DataOperationError.TagWithThisNameAlreadyExisting => try globals.printer.errNameTagAlreadyExisting(new_name),
                else => return err,
            }
        }

        was_something_updated = true;
    }

    if (!was_something_updated) {
        try globals.printer.updatedTagNothing(cur_name);
    }
}

/// Print out help for the update-tag command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt update-tag <tag_name> [OPTIONS]{s}
        \\
        \\Updates the name and / or priority of a tag.
        \\
        \\The tag names can only contain ASCII letters, numbers and the '_' or '-'
        \\characters.
        \\
        \\Options:
        \\  {s}-n{s}, {s}--name{s}      New name of the tag
        \\  {s}-p{s}, {s}--priority{s}  New priority. Can be "next", "soon" or "someday"
        \\
        \\Examples:
        \\  {s}mtlt update-tag old_name -n new_name{s}
        \\      Update the tag called "old_name" to change it to "new_name".
        \\
        \\  {s}mtlt update-tag reallyUrgent -p next{s}
        \\      Update the tag called "reallyUrgent" to set it's priority to "next".
        \\
    , .{
        ansi.colemp, ansi.colres,
        ansi.colid,  ansi.colres,
        ansi.colid,  ansi.colres,
        ansi.colid,  ansi.colres,
        ansi.colid,  ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}

test "update tag - tag id not specified" {
    const cur_time = th.curTimestamp();
    var args: ArgumentParser = .{ .name = "new_name" };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_stderr = "The current name of the tag to udpate is missing.\nThe format of the command can be seen with \"mtlt help update-tag\".\n",
    });
}

test "update tag - new name ok" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.tags.items[0].name = "new_tag_name";
    var args: ArgumentParser = .{ .payload = "next", .name = "new_tag_name" };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = ex_file,
        .ex_stderr = "",
    });
}

test "update tag - new name too long" {
    const cur_time = th.curTimestamp();
    const tag_name = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    var args: ArgumentParser = .{ .payload = "next", .name = tag_name };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_stderr = "The name \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\" is too long.\n",
    });
}

test "update tag - new name invalid" {
    const cur_time = th.curTimestamp();
    var args: ArgumentParser = .{ .payload = "next", .name = "invalid@name" };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_stderr = "The tag name can only contain ascii letters, numbers or the '-' or '_' character.\n",
    });
}

test "update tag - new name already existing" {
    const cur_time = th.curTimestamp();
    var args: ArgumentParser = .{ .payload = "next", .name = "soon" };

    var buf_ex_stderr: [128]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "A tag with the name {s}soon{s} already exists\n", .{ ansi.colemp, ansi.colres });

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_stderr = ex_stderr,
    });
}

test "update tag - new priority" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.tags.items[1].status = dt.StatusTag.next;

    var args: ArgumentParser = .{ .payload = "soon", .priority = .next };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = ex_file,
        .ex_stderr = "",
    });
}

test "update tag - new priority from closed" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.tags.items[0].status = dt.StatusTag.someday;

    var ac_file = try it_helper.getSmallFile(cur_time);
    ac_file.tags.items[0].status = dt.StatusTag.closed;

    var args: ArgumentParser = .{ .payload = "next", .priority = .someday };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stderr = "",
    });
}

test "update tag - updating nothing" {
    const cur_time = th.curTimestamp();
    var args: ArgumentParser = .{ .payload = "next" };

    var buf_ex_stdout: [128]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "Nothing was updated on the tag {s}next{s}.\n", .{ ansi.colemp, ansi.colres });

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = try it_helper.getSmallFile(cur_time),
        .ex_stderr = "",
        .ex_stdout = ex_stdout,
    });
}
