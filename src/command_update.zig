const std = @import("std");

const ansi = @import("ansi_codes.zig");
const base62_helper = @import("base62_helper.zig");
const command_start = @import("command_start.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const time_helper = @import("time_helper.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataParsingError = @import("data_file_reader.zig").DataParsingError;

/// Update a thing
pub fn cmd(args: *ArgumentParser) !void {
    var buf_str_id: [4]u8 = undefined;

    if (args.*.payload == null) {
        try globals.printer.errIdThingMissing();
        return;
    }

    const cur_time = time_helper.curTimestamp();

    // format the arguments properly
    const kickoff = if (args.*.kickoff) |t| if (t == 0) t else t + cur_time else null;
    const id_num = try base62_helper.b62ToB10(args.*.payload.?);
    const id_str = args.*.payload.?;

    // create the array list for the tags to update
    var created_tags = std.ArrayList(dt.Tag).init(globals.allocator);
    defer created_tags.deinit();

    if (globals.dfw.updateThing(.{
        .id = id_num,
        .kickoff = kickoff,
        .estimation = args.*.estimation,
        .name = args.*.name,
        .tags = args.*.tags,
    }, &created_tags)) |_| {} else |err| {
        switch (err) {
            DataParsingError.ThingNotFound => try globals.printer.errThingNotFoundStr(args.*.payload.?),
            else => try globals.printer.errUnexpectedUpdatingThing(err),
        }
    }

    // get the name of the thing
    const thing_data = try globals.dfr.getFixedPartThing(id_num);
    const thing_name = try globals.allocator.alloc(u8, thing_data.lgt_name);
    defer globals.allocator.free(thing_name);
    _ = try globals.data_file.reader().read(thing_name);

    try globals.printer.updatedThing(thing_name, id_str);

    for (created_tags.items) |ct| {
        try globals.printer.createdTag(ct.name);
    }

    // if wanted and possible, start the current timer on the updated thing right away
    if (args.*.should_start) {
        if (thing_data.status == @intFromEnum(dt.StatusThing.closed)) {
            const str_id = base62_helper.b10ToB62(&buf_str_id, thing_data.id);
            try globals.printer.cantStartIfClosed(str_id);
            return;
        }

        try command_start.start_id(id_num, thing_name);
    }
}

/// Print out help for the update command
pub fn help() !void {
    try std.io.getStdOut().writer().print("TODO help update\n", .{});
}
