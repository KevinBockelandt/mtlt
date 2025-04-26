const ansi = @import("ansi_codes.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const std = @import("std");
const th = @import("time_helper.zig");
const it_helper = @import("integration_tests_helper.zig");
const string_helper = @import("string_helper.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataParsingError = @import("data_file_reader.zig").DataParsingError;

/// Toggle the status of a tag
pub fn cmd(args: *ArgumentParser) !void {
    if (args.*.payload == null) {
        try globals.printer.errMissingTagName();
        return;
    }

    const tag_name = args.*.payload.?;

    // check name length
    if (tag_name.len > std.math.maxInt(u6)) {
        try globals.printer.errNameTooLong(tag_name);
        return;
    }

    // check for invalid characters in the tag name
    if (!string_helper.isValidTagName(tag_name)) {
        try globals.printer.errNameTagInvalidChara();
        return;
    }

    // if tag name ok, try to toggle the tag
    if (globals.dfw.toggleTagStatus(tag_name)) |new_status| {
        if (new_status == dt.StatusTag.closed) {
            try globals.printer.toggledTagClosed(tag_name);
        } else {
            try globals.printer.toggledTagOpenned(@tagName(new_status), tag_name);
        }
    } else |err| {
        switch (err) {
            DataParsingError.TagNotFound => try globals.printer.errTagNotFoundName(tag_name),
            else => try globals.printer.errUnexpectedToggleTag(err),
        }
    }
}

/// Print out help for the toggle-tag command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt toggle-tag <tag_name>{s}
        \\
        \\Toggles the status of a tag between open and closed. When a tag
        \\goes from closed to open it is automatically assigned the {s}someday{s}
        \\priority.
        \\
        \\Examples:
        \\  {s}mtlt toggle-tag theTag{s}
        \\      Toggle status of the tag called 'theTag'.
        \\
    , .{
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}

test "toggle tag - no specified tag name" {
    const cur_time = th.curTimestamp();

    var buf_ex_stderr: [128]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "Missing the name of the tag to operate on.\n", .{});

    var args = ArgumentParser{};

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = try it_helper.getSmallFile(cur_time),
        .ex_stderr = ex_stderr,
        .ex_stdout = "",
    });
}

test "toggle tag - specified tag name invalid" {
    const cur_time = th.curTimestamp();

    var buf_ex_stderr: [128]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "The tag name can only contain ascii letters, numbers or the '-' or '_' character.\n", .{});

    var args = ArgumentParser{ .payload = "abc def" };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = try it_helper.getSmallFile(cur_time),
        .ex_stderr = ex_stderr,
        .ex_stdout = "",
    });
}

test "toggle tag - specified tag name too long" {
    const cur_time = th.curTimestamp();
    const tag_name = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

    var buf_ex_stderr: [128]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "The name \"{s}\" is too long.\n", .{tag_name});

    var args = ArgumentParser{ .payload = tag_name };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = try it_helper.getSmallFile(cur_time),
        .ex_stderr = ex_stderr,
        .ex_stdout = "",
    });
}

test "toggle tag - specified tag name non existing" {
    const cur_time = th.curTimestamp();

    var buf_ex_stderr: [128]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "Tag with the name {s}tofind{s} not found\n", .{ ansi.colemp, ansi.colres });

    var args = ArgumentParser{ .payload = "tofind" };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = try it_helper.getSmallFile(cur_time),
        .ex_stderr = ex_stderr,
        .ex_stdout = "",
    });
}

test "toggle tag - specified tag name ok - to close" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.tags.items[0].status = dt.StatusTag.closed;

    var buf_ex_stdout: [128]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "Tag {s}now{s} is now {s}closed{s}.\n", .{ ansi.colemp, ansi.colres, ansi.colemp, ansi.colres });

    var args = ArgumentParser{ .payload = "now" };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}

test "toggle tag - specified tag name ok - to someday" {
    const cur_time = th.curTimestamp();
    var ac_file = try it_helper.getSmallFile(cur_time);
    ac_file.tags.items[1].status = dt.StatusTag.closed;
    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.tags.items[1].status = dt.StatusTag.someday;

    var buf_ex_stdout: [128]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "Tag {s}soon{s} is now {s}open{s} with priority {s}someday{s}.\n", .{ ansi.colemp, ansi.colres, ansi.colemp, ansi.colres, ansi.colemp, ansi.colres });

    var args = ArgumentParser{ .payload = "soon" };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}
