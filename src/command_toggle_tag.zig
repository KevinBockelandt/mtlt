const std = @import("std");
const ansi = @import("ansi_codes.zig");
const globals = @import("globals.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataParsingError = @import("data_file_reader.zig").DataParsingError;

/// Toggle the status of a tag
pub fn cmd(args: *ArgumentParser) !void {
    const w = std.io.getStdOut().writer();

    if (globals.dfw.toggleTagStatus(args.*.payload.?)) |new_status| {
        try w.print("Status set to {s}{s}{s} for the tag {s}{s}{s}\n", .{ ansi.colemp, @tagName(new_status), ansi.colres, ansi.colemp, args.*.payload.?, ansi.colres });
    } else |err| {
        if (err == DataParsingError.TagNotFound) {
            try w.print("Error: No tag found for the name {s}{s}{s}\n", .{ ansi.colemp, args.*.payload.?, ansi.colres });
        } else {
            return err;
        }
    }
}

/// Print out help for the toggle-tag command
pub fn help() !void {
    try std.io.getStdOut().writer().print("TODO help toggle-tag\n", .{});
}
