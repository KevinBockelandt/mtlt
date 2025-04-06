const std = @import("std");

const ansi = @import("ansi_codes.zig");
const globals = @import("globals.zig");
const user_feedback = @import("user_feedback.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataOperationError = @import("data_file_writer.zig").DataOperationError;
const DataParsingError = @import("data_file_reader.zig").DataParsingError;

/// Update the name of a tag
pub fn cmd(args: *ArgumentParser) !void {
    if (args.*.payload == null) {
        try user_feedback.errUpdateTagMissingOldName();
        return;
    }

    var was_something_updated = false;

    // Update the priority of the tag if it's appropriate
    if (args.*.priority != null) {
        try globals.dfw.updateTagPriority(args.*.payload.?, args.*.priority.?);
        try user_feedback.updatedTagPriority(args.*.payload.?, args.*.priority.?);
        was_something_updated = true;
    }

    // Update the name of the tag if it's appropriate
    if (args.*.name != null) {
        if (globals.dfw.updateTagName(args.*.payload.?, args.*.name.?)) |_| {
            try user_feedback.updatedTagName(args.*.payload.?, args.*.name.?);
        } else |err| {
            switch (err) {
                DataParsingError.TagNotFound => try user_feedback.errTagNotFoundName(args.*.payload.?),
                DataOperationError.NameTooLong => try user_feedback.errNameTagTooLong(args.*.name.?),
                DataOperationError.TagWithThisNameAlreadyExisting => try user_feedback.errNameTagAlreadyExisting(args.*.name.?),
                else => return err,
            }
        }

        was_something_updated = true;
    }

    if (!was_something_updated) {
        try user_feedback.updatedTagNothing(args.*.payload.?);
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
