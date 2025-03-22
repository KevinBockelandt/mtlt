const std = @import("std");
const ansi = @import("ansi_codes.zig");
const globals = @import("globals.zig");
const user_feedback = @import("user_feedback.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataParsingError = @import("data_file_reader.zig").DataParsingError;

const little_end = std.builtin.Endian.little;

/// Delete a tag from the data file
pub fn cmd(args: *ArgumentParser) !void {
    if (args.*.payload == null) {
        try user_feedback.errMissingTagName();
        return;
    }

    if (globals.dfw.deleteTagFromFile(args.*.payload.?)) |_| {
        try user_feedback.deletedTag(args.*.payload.?);
    } else |err| {
        // TODO use a switch here
        if (err == DataParsingError.TagNotFound) {
            try user_feedback.errTagNotFoundName(args.*.payload.?);
        } else {
            return err;
        }
    }
}

/// Print out help for the delete tag command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt delete-tag <tag_name>{s}
        \\
        \\Deletes a tag permanently from the data file.
        \\
        \\Examples:
        \\  {s}mtlt delete-tag theTag{s}
        \\      Delete the tag called 'theTag'.
        \\
    , .{
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}
