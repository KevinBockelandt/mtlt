const std = @import("std");

const ansi = @import("ansi_codes.zig");
const base62_helper = @import("base62_helper.zig");
const command_start = @import("command_start.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const time_helper = @import("time_helper.zig");
const user_feedback = @import("user_feedback.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataParsingError = @import("data_file_reader.zig").DataParsingError;

/// Update a thing
pub fn cmd(args: *ArgumentParser) !void {
    const w = std.io.getStdOut().writer();
    var buf_str_id: [4]u8 = undefined;

    if (args.*.payload == null) {
        _ = try w.write("Error: could not parse the id of the thing to update\n");
        return;
    }

    const cur_time = time_helper.curTimestamp();

    // format the arguments properly
    const target = if (args.*.target) |t| if (t == 0) t else t + cur_time else null;
    const id_num = try base62_helper.b62ToB10(args.*.payload.?);
    const id_str = args.*.payload.?;

    // create the array list for the tags to update
    var created_tags = std.ArrayList(dt.Tag).init(globals.allocator);
    defer created_tags.deinit();

    if (globals.dfw.updateThing(.{
        .id = id_num,
        .target = target,
        .estimation = args.*.estimation,
        .name = args.*.name,
        .tags = args.*.tags,
    }, &created_tags)) |_| {} else |err| {
        switch (err) {
            DataParsingError.ThingNotFound => try user_feedback.errorThingNotFound(args.*.payload.?),
            else => std.debug.print("ERROR: {}\n", .{err}),
        }
    }

    // get the name of the thing
    const thing_data = try globals.dfr.getFixedPartThing(id_num);
    const thing_name = try globals.allocator.alloc(u8, thing_data.lgt_name);
    defer globals.allocator.free(thing_name);
    _ = try globals.data_file.reader().read(thing_name);

    try w.print("Updated thing {s}{s}{s} - {s}{s}{s}\n", .{ ansi.colid, id_str, ansi.colres, ansi.colemp, thing_name, ansi.colres });

    for (created_tags.items) |ct| {
        try user_feedback.createdTag(ct.name);
    }

    // if wanted and possible, start the current timer on the updated thing right away
    if (args.*.should_start) {
        if (thing_data.status == @intFromEnum(dt.Status.closed)) {
            const str_id = base62_helper.b10ToB62(&buf_str_id, thing_data.id);
            try w.print("Cannot start a timer on a closed thing\n", .{});
            try w.print("You can reopen the thing by using the following command: {s}mtlt toggle {s}{s}\n", .{ ansi.colemp, str_id, ansi.colres });
            return;
        }

        try command_start.start_id(id_num, thing_name);
    }
}

/// Print out help for the update command
pub fn help() !void {
    try std.io.getStdOut().writer().print("TODO help update\n", .{});
}
