const ansi = @import("ansi_codes.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const std = @import("std");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataParsingError = @import("data_file_reader.zig").DataParsingError;

/// Toggle the status of a tag
pub fn cmd(args: *ArgumentParser) !void {
    if (globals.dfw.toggleTagStatus(args.*.payload.?)) |new_status| {
        if (new_status == dt.StatusTag.closed) {
            try globals.printer.toggledTagClosed(args.*.payload.?);
        } else {
            try globals.printer.toggledTagOpenned(@tagName(new_status), args.*.payload.?);
        }
    } else |err| {
        switch (err) {
            DataParsingError.TagNotFound => try globals.printer.errTagNotFoundName(args.*.payload.?),
            else => try globals.printer.errUnexpectedToggleTag(err),
        }
    }
}

/// Print out help for the toggle-tag command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt toggle-tag <tag_name>{s}
        \\
        \\Toggles the status of a tag between open and closed.
        \\
        \\Examples:
        \\  {s}mtlt toggle-tag theTag{s}
        \\      Toggle status of the tag called 'theTag'.
        \\
    , .{
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}
