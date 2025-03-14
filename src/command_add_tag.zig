const std = @import("std");

const ansi = @import("ansi_codes.zig");
const dt = @import("data_types.zig");
const dfr = @import("data_file_reader.zig");
const globals = @import("globals.zig");
const string_helper = @import("string_helper.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataOperationError = @import("data_file_writer.zig").DataOperationError;

pub const CommandError = error{
    NoDuration,
    SeveralDurationArgs,
    StartLessAndMore,
};

/// Add a new tag to the data file
pub fn cmd(args: *ArgumentParser) !void {
    const w = std.io.getStdOut().writer();

    if (args.*.payload == null) {
        _ = try w.write("A name is needed for the tag to add.\n");
        return;
    }

    // check for invalid characters in the tag name
    for (args.*.payload.?) |c| {
        if (!string_helper.isValidTagNameChar(c)) {
            _ = try w.write("The tag name can only contain ascii letters, numbers or the '-' or '_' character\n");
            return;
        }
    }

    if (globals.dfw.addTagToFile(args.*.payload.?)) |new_tag_id| {
        _ = new_tag_id;
        try w.print("The tag {s}{s}{s} was created\n", .{ ansi.colemp, args.*.payload.?, ansi.colres });
    } else |err| {
        if (err == DataOperationError.NameTooLong) {
            try w.print("The name {s}\"{s}\"{s} is too long\n", .{ ansi.colemp, args.*.payload.?, ansi.colres });
        } else if (err == DataOperationError.TagWithThisNameAlreadyExisting) {
            try w.print("A tag with the name {s}{s}{s} already exists\n", .{ ansi.colemp, args.*.payload.?, ansi.colres });
        } else {
            return err;
        }
    }
}

/// Display help text for this command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt add-tag <tag_name>{s}
        \\
        \\Creates a new tag.
        \\
        \\The tag name can only contain ASCII letters, numbers and the '_' or '-'
        \\characters.
        \\
        \\Examples:
        \\  {s}mtlt add-tag "myCoolTag"{s}
        \\      Create a new tag called 'myCoolTag'.
        \\
        \\  {s}mtlt add-tag "1-also-good"{s}
        \\      Create a new tag called '1-also-good'.
        \\
        \\  {s}mtlt add-tag "_it_works"{s}
        \\      Create a new tag called '_it_works'.
        \\
    , .{
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}
