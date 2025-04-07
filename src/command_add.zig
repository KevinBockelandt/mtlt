const std = @import("std");

const ansi = @import("ansi_codes.zig");
const base62_helper = @import("base62_helper.zig");
const command_start = @import("command_start.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const time_helper = @import("time_helper.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;

/// Add a new thing to the data file
pub fn cmd(args: *ArgumentParser) !void {
    var buf_str_id: [4]u8 = undefined;

    if (args.*.payload == null) {
        try globals.printer.errNameThingMissing();
        return;
    }

    // format the arguments properly
    const kickoff = if (args.*.kickoff) |t| t + time_helper.curTimestamp() else 0;
    const estimation = if (args.*.estimation) |e| e else 0;

    var infos_creation = dt.ThingCreated{};
    infos_creation.created_tags = std.ArrayList([]u8).init(globals.allocator);
    defer infos_creation.created_tags.deinit();

    try globals.dfw.addThingToFile(args.*.payload.?, kickoff, estimation, args.*.tags.items, &infos_creation);

    // display infos about the creation of the thing
    const str_id = base62_helper.b10ToB62(&buf_str_id, infos_creation.id);
    try globals.printer.createdThing(args.*.payload.?, str_id);

    if (args.*.kickoff != null) {
        try globals.printer.reportKickoff(args.*.kickoff.?, &ansi.colposdur);
    }

    for (infos_creation.created_tags.items) |tag| {
        try globals.printer.createdTag(tag);
    }

    // if wanted, start the current timer on the created thing right away
    if (args.*.should_start) {
        try command_start.start_id(infos_creation.id, args.*.payload.?);
    }
}

/// Display help text for this command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt add <thing_name> [OPTIONS]{s}
        \\
        \\Creates a new thing.
        \\
        \\Options:
        \\  {s}-e{s}, {s}--estimation{s}         How many steps will it take to complete
        \\  {s}-k{s}, {s}--kickoff{s}            When should the thing start
        \\  {s}-s{s}, {s}--start{s}              Start a timer on the thing right away
        \\  {s}-t{s}, {s}--tags{s}               Tags associated to this thing
        \\
        \\Examples:
        \\  {s}mtlt add "myCoolThing"{s}
        \\      Create a new thing called 'myCoolThing' without additional data.
        \\
        \\  {s}mtlt add "new_thing" -t tag1 tag2 -e 20{s}
        \\      Create a new thing called 'new_thing' with the associated tags 'tag1'
        \\      and 'tag2' and an estimation of 20 steps.
        \\
        \\  {s}mtlt add "# the name can contain anything@@" -k 10 -s{s}
        \\      Create a new thing called '# the name can contain anything@@' with a
        \\      theoric kickoff in 10 steps and start a timer right away on it even
        \\      though it's contradictory with the theoric kickoff.
        \\
    , .{
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}
