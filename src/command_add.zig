const std = @import("std");

const ansi = @import("ansi_codes.zig");
const base62_helper = @import("base62_helper.zig");
const command_start = @import("command_start.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const time_helper = @import("time_helper.zig");
const user_feedback = @import("user_feedback.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;

/// Add a new thing to the data file
pub fn cmd(args: *ArgumentParser) !void {
    var buf_str_id: [4]u8 = undefined;
    const w = std.io.getStdOut().writer();

    if (args.*.payload == null) {
        _ = try w.write("Error: could not parse the name of the thing\n");
        return;
    }

    // format the arguments properly
    const target = if (args.*.target) |t| t + time_helper.curTimestamp() else 0;
    const estimation = if (args.*.estimation) |e| e else 0;

    var infos_creation = dt.ThingCreated{};
    infos_creation.created_tags = std.ArrayList([]u8).init(globals.allocator);
    defer infos_creation.created_tags.deinit();

    try globals.dfw.addThingToFile(args.*.payload.?, target, estimation, args.*.tags.items, &infos_creation);

    // display infos about the creation of the thing
    const str_id = base62_helper.b10ToB62(&buf_str_id, infos_creation.id);

    try w.print("Created {s}\"{s}\"{s} with ID {s}{s}{s}", .{ ansi.colemp, args.*.payload.?, ansi.colres, ansi.colid, str_id, ansi.colres });
    if (args.*.target != null) {
        var str_target: [20]u8 = undefined;
        const slice_str_target = try time_helper.formatDuration(&str_target, args.*.target.?);
        try w.print(" and a target in {s}{s}{s}\n", .{ ansi.colemp, slice_str_target, ansi.colres });
    } else {
        try w.print("\n", .{});
    }

    for (infos_creation.created_tags.items) |tag| {
        try user_feedback.createdTag(tag);
    }

    // if wanted, start the current timer on the created thing right away
    if (args.*.should_start) {
        try command_start.start_id(infos_creation.id, args.*.payload.?);
    }
}

/// Display help text for this command
pub fn help() !void {
    const w = std.io.getStdOut().writer();

    try w.print(
        \\TODO help for add
    , .{});
}
