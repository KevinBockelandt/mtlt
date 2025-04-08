const std = @import("std");

const ansi = @import("ansi_codes.zig");
const globals = @import("globals.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataOperationError = @import("data_file_writer.zig").DataOperationError;
const DataParsingError = @import("data_file_reader.zig").DataParsingError;

/// Update the name of a tag
pub fn cmd(args: *ArgumentParser) !void {
    if (args.*.payload == null) {
        try globals.printer.errUpdateTagMissingOldName();
        return;
    }

    var was_something_updated = false;

    // Update the priority of the tag if it's appropriate
    if (args.*.priority != null) {
        try globals.dfw.updateTagPriority(args.*.payload.?, args.*.priority.?);
        try globals.printer.updatedTagPriority(args.*.payload.?, args.*.priority.?);
        was_something_updated = true;
    }

    // Update the name of the tag if it's appropriate
    if (args.*.name != null) {
        if (globals.dfw.updateTagName(args.*.payload.?, args.*.name.?)) |_| {
            try globals.printer.updatedTagName(args.*.payload.?, args.*.name.?);
        } else |err| {
            switch (err) {
                DataParsingError.TagNotFound => try globals.printer.errTagNotFoundName(args.*.payload.?),
                DataOperationError.NameTooLong => try globals.printer.errNameTagLong(args.*.name.?),
                DataOperationError.TagWithThisNameAlreadyExisting => try globals.printer.errNameTagAlreadyExisting(args.*.name.?),
                else => return err,
            }
        }

        was_something_updated = true;
    }

    if (!was_something_updated) {
        try globals.printer.updatedTagNothing(args.*.payload.?);
    }
}

/// Print out help for the update-tag command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt update-tag <old_name> -n <new_name>{s}
        \\
        \\Updates the name of a tag
        \\
        \\The tag names can only contain ASCII letters, numbers and the '_' or '-'
        \\characters
        \\
        \\Options:
        \\  {s}-n{s}, {s}--name{s}            New name of the tag
        \\
        \\Examples:
        \\  {s}mtlt update-tag old_name -n new_name{s}
        \\      Update the tag called 'old_name' to change it to 'new_name'.
        \\
        \\  {s}mtlt update-tag withTypo -n withoutTypo{s}
        \\      Update the tag called 'withTypo' to change it to 'withoutTypo'.
        \\
    , .{
        ansi.colemp, ansi.colres,
        ansi.colid,  ansi.colres,
        ansi.colid,  ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}
