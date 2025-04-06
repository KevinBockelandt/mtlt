const std = @import("std");

const ansi = @import("ansi_codes.zig");
const base62_helper = @import("base62_helper.zig");
const dfr = @import("data_file_reader.zig");
const globals = @import("globals.zig");
const command_stop = @import("command_stop.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;

var buf_str_id: [4]u8 = undefined;

/// Start a timer on a thing
pub fn cmd(args: *ArgumentParser) !void {
    // get the current timer contained in the data file
    const cur_timer = try globals.dfr.getCurrentTimer();

    // if there is no argument
    if (args.*.payload == null) {
        // and no previous current timer
        if (cur_timer.id_thing == 0) {
            try globals.printer.errIdThingMissing();
            return;
        } else {
            // start a timer on the same ID than the previous one
            const cur_fpt = try globals.dfr.getFixedPartThing(cur_timer.id_thing);
            const cur_thing_name = try globals.allocator.alloc(u8, cur_fpt.lgt_name);
            defer globals.allocator.free(cur_thing_name);
            _ = try globals.data_file.reader().readAll(cur_thing_name);
            try start_id(cur_timer.id_thing, cur_thing_name);
        }
    } else {
        const arg_id: u19 = if (args.*.payload == null) 0 else try base62_helper.b62ToB10(args.*.payload.?);
        const arg_fpt = try globals.dfr.getFixedPartThing(arg_id);
        const arg_thing_name = try globals.allocator.alloc(u8, arg_fpt.lgt_name);
        defer globals.allocator.free(arg_thing_name);
        _ = try globals.data_file.reader().read(arg_thing_name);
        try start_id(arg_id, arg_thing_name);
    }
}

/// Start a timer on a thing with the specified ID
pub fn start_id(id: u19, thing_name: []const u8) !void {
    const cur_timer = try globals.dfr.getCurrentTimer();
    const str_id = base62_helper.b10ToB62(&buf_str_id, id);

    // If there is no previous current timer and we have an ID to start on
    if (cur_timer.id_thing == 0 and id != 0) {
        try globals.dfw.startCurrentTimer(id);
        try globals.printer.startedTimer(str_id, thing_name);
        return;
    }

    // If there is already a cur timer running on another ID
    if (cur_timer.id_thing != 0 and cur_timer.id_thing != id and cur_timer.start != 0) {
        // create an empty default arg parser just to pass to `stop` that requires one
        var arg_parser = ArgumentParser{};
        try command_stop.cmd(&arg_parser);
        try globals.dfw.startCurrentTimer(id);
        try globals.printer.startedTimer(str_id, thing_name);
        return;
    }

    // If there is a stopped previous current timer
    if (cur_timer.id_thing != 0 and cur_timer.id_thing != id and cur_timer.start == 0) {
        try globals.dfw.startCurrentTimer(id);
        try globals.printer.startedTimer(str_id, thing_name);
        return;
    }

    // If there is already a current timer running with the same ID
    if (cur_timer.id_thing != 0 and cur_timer.id_thing == id and cur_timer.start != 0) {
        try globals.printer.timerAlreadyRunning(str_id, thing_name);
        return;
    }

    // If there is a stopped previous current timer with the same ID
    if (cur_timer.id_thing != 0 and cur_timer.id_thing == id and cur_timer.start == 0) {
        try globals.dfw.startCurrentTimer(id);
        try globals.printer.startedTimer(str_id, thing_name);
        return;
    }
}

/// Print out help for the start command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt start [thing_id]{s}
        \\
        \\Starts a timer on the given thing.
        \\
        \\If no ID is provided, it starts a timer on the current thing. You can see
        \\what the current thing is by using {s}mtlt{s} without any sub-command.
        \\
        \\If a timer is already running, it will be stopped before the new one starts.
        \\
        \\Examples:
        \\  {s}mtlt start{s}
        \\      Starts a timer on the current thing.
        \\
        \\  {s}mtlt start 8I{s}
        \\      Starts a timer on the thing with id '8I'.
        \\
    , .{
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}
