const std = @import("std");

const ansi = @import("ansi_codes.zig");
const id_helper = @import("id_helper.zig");
const dfr = @import("data_file_reader.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const table_printer = @import("table_printer.zig");
const th = @import("time_helper.zig");

const CellAlignment = @import("table_printer.zig").CellAlignment;
const ArgumentParser = @import("argument_parser.zig").ArgumentParser;

const little_end = std.builtin.Endian.little;

/// Display informations on the specified thing
pub fn infosReport(args: *ArgumentParser) !void {
    // get the current timer contained in the data file
    const cur_timer = try globals.dfr.getCurrentTimer();

    // ID of the thing to display infos about
    var id_thing: u19 = undefined;

    if (args.*.payload == null) {
        // and no previous current timer
        if (cur_timer.id_thing == 0) {
            try globals.printer.errMissingIdThing();
            return;
        } else {
            id_thing = cur_timer.id_thing;
        }
    } else {
        id_thing = try id_helper.b62ToB10(args.*.payload.?);
    }

    const thing_to_display = try globals.dfr.getThing(id_thing);
    defer thing_to_display.deinit();

    try displayTableReport(thing_to_display);
}

/// Setup the table printer to display the data of the thing
fn displayTableReport(thing: dt.Thing) !void {
    const w = std.io.getStdOut().writer();
    const cur_time = th.curTimestamp();

    // string for the thing ID
    var buf_id_thing: [4]u8 = undefined;
    const str_id_thing = id_helper.b10ToB62(&buf_id_thing, thing.id);

    // kickoff
    const offset_kickoff_min: i64 = @as(i64, @intCast(thing.kickoff)) - @as(i64, @intCast(cur_time));
    const offset_kickoff_steps = try th.getStepsFromMinutes(i32, offset_kickoff_min);

    // creation time
    const offset_creation_min: i64 = @as(i64, @intCast(thing.creation)) - @as(i64, @intCast(cur_time));
    const offset_creation_steps = try th.getStepsFromMinutes(i32, offset_creation_min);

    // closure time
    const offset_closure_min: i64 = @as(i64, @intCast(thing.closure)) - @as(i64, @intCast(cur_time));
    const offset_closure_steps = try th.getStepsFromMinutes(i32, offset_closure_min);

    // will contain the string for all the associated tags
    var buf_tags: [20000]u8 = undefined;
    var idx_buf_tags: usize = 0;
    // used to manipulate the tag names
    var buf_str_tag_name: [128]u8 = undefined;

    // create string for the tags
    // TODO should factorize this code
    if (thing.tags.len > 0) {
        for (thing.tags, 0..thing.tags.len) |tag_id, j| {
            if (globals.dfr.getTagNameFromId(&buf_str_tag_name, tag_id)) |name_to_add| {
                const e_idx_name = idx_buf_tags + name_to_add.len;
                std.mem.copyForwards(u8, buf_tags[idx_buf_tags..e_idx_name], name_to_add);

                // add a , between tag names. Except for the last one
                if (j != thing.tags.len - 1) {
                    std.mem.copyForwards(u8, buf_tags[e_idx_name..][0..2], ", ");
                    idx_buf_tags = e_idx_name + 2;
                } else {
                    idx_buf_tags = e_idx_name;
                }
            } else |err| {
                if (err == dfr.DataParsingError.TagNotFound) {
                    try globals.printer.errTagNotFoundId(tag_id);
                } else {
                    try globals.printer.errUnexpectedGetTagName(tag_id, err);
                }
            }
        }
    } else {
        buf_tags[0] = '-';
        idx_buf_tags = 1;
    }

    // create a table with all the timers
    var timers_table = try globals.allocator.alloc([]table_printer.Cell, thing.timers.len + 1);
    defer globals.allocator.free(timers_table);
    var total_spent_time: u64 = 0;

    const num_cols = 3;

    // setup the header of the table
    timers_table[0] = try globals.allocator.alloc(table_printer.Cell, num_cols);
    defer globals.allocator.free(timers_table[0]);
    timers_table[0][0] = .{ .content = "ID", .alignment = .left, .front_col = .title, .back_col = .gray };
    timers_table[0][1] = .{ .content = "Start", .alignment = .left, .front_col = .title, .back_col = .gray };
    timers_table[0][2] = .{ .content = "Duration", .alignment = .left, .front_col = .title, .back_col = .gray };

    // go through all timers to create the table to display
    for (thing.timers, 1..thing.timers.len + 1) |timer, i| {
        total_spent_time += timer.duration;
        const line_back_col: ?table_printer.CellBackCol = if (i % 2 != 0) null else .gray;

        timers_table[i] = try globals.allocator.alloc(table_printer.Cell, num_cols);

        // ID column
        var buf_id: [128]u8 = undefined;
        const str_id: []u8 = try std.fmt.bufPrint(&buf_id, "{s}-{d}", .{ str_id_thing, timer.id });
        timers_table[i][0] = .{
            .content = try globals.allocator.dupe(u8, str_id),
            .alignment = .right,
            .front_col = .id,
            .back_col = line_back_col,
        };

        // START column
        var buf_start_str: [128]u8 = undefined;
        const offset_start_min: i64 = @as(i64, @intCast(timer.start)) - @as(i64, @intCast(cur_time));
        const offset_start_steps = try th.getStepsFromMinutes(i32, offset_start_min);

        var str_start_str: []u8 = undefined;
        if (offset_start_min < 0) {
            str_start_str = try std.fmt.bufPrint(&buf_start_str, "{s}{d}{s} ago", .{ ansi.coldurntr, @abs(offset_start_steps), ansi.colres });
        } else {
            str_start_str = try std.fmt.bufPrint(&buf_start_str, "{s}{d}{s} hence", .{ ansi.coldurntr, @abs(offset_start_steps), ansi.colres });
        }

        timers_table[i][1] = .{
            .content = try globals.allocator.dupe(u8, str_start_str),
            .alignment = .left,
            .front_col = null,
            .back_col = line_back_col,
        };

        // DURATION column
        var buf_duration: [128]u8 = undefined;
        const str_duration = try std.fmt.bufPrint(&buf_duration, "{d}", .{timer.duration});
        timers_table[i][2] = .{
            .content = try globals.allocator.dupe(u8, str_duration),
            .alignment = .right,
            .front_col = .duration,
            .back_col = line_back_col,
        };
    }

    // time offset
    const time_offset: i64 = @as(i64, @intCast(total_spent_time)) - @as(i64, @intCast(thing.estimation));

    try w.print("{s}                ID{s} : {s}{s}{s}\n", .{ ansi.colemp, ansi.colres, ansi.colid, str_id_thing, ansi.colres });
    try w.print("{s}              Name{s} : {s}\n", .{ ansi.colemp, ansi.colres, thing.name });
    try w.print("{s}            Status{s} : {s}\n", .{ ansi.colemp, ansi.colres, @tagName(thing.status) });
    try w.print("{s}   Associated tags{s} : {s}\n", .{ ansi.colemp, ansi.colres, buf_tags[0..idx_buf_tags] });
    try w.print("\n", .{});
    try w.print("{s}     Creation time{s} : {d} steps ago\n", .{ ansi.colemp, ansi.colres, offset_creation_steps });
    if (thing.kickoff > 0) {
        if (offset_kickoff_steps > 0) {
            try w.print("{s}           Kickoff{s} : in {d}\n", .{ ansi.colemp, ansi.colres, offset_kickoff_steps });
        } else {
            try w.print("{s}           Kickoff{s} : {d} ago\n", .{ ansi.colemp, ansi.colres, offset_kickoff_steps });
        }
    } else {
        try w.print("{s}           Kickoff{s} :\n", .{ ansi.colemp, ansi.colres });
    }
    if (thing.closure > 0) {
        try w.print("{s}      Closure time{s} : {d} steps ago\n", .{ ansi.colemp, ansi.colres, offset_closure_steps });
    } else {
        try w.print("{s}      Closure time{s} :\n", .{ ansi.colemp, ansi.colres });
    }
    try w.print("\n", .{});
    try w.print("{s}Initial estimation{s} : {d} steps\n", .{ ansi.colemp, ansi.colres, thing.estimation });

    if (thing.estimation > 0) {
        if (time_offset > 0) {
            try w.print("{s}  Total time spent{s} : {d} steps ({s}{d} over{s} estimation)\n", .{ ansi.colemp, ansi.colres, total_spent_time, ansi.colnegdur, @abs(time_offset), ansi.colres });
        } else {
            try w.print("{s}  Total time spent{s} : {d} steps ({s}{d} under{s} estimation)\n", .{ ansi.colemp, ansi.colres, total_spent_time, ansi.colposdur, @abs(time_offset), ansi.colres });
        }
    } else {
        try w.print("{s}  Total time spent{s} : {d} steps\n", .{ ansi.colemp, ansi.colres, total_spent_time });
    }

    if (thing.timers.len > 0) {
        try w.print("{s}    List of timers{s} :\n\n", .{ ansi.colemp, ansi.colres });
        try table_printer.printTable(timers_table);
    } else {
        try w.print("{s}    List of timers{s} : -\n", .{ ansi.colemp, ansi.colres });
    }

    // Free memory for all that we allocated
    for (1..thing.timers.len + 1) |i| {
        globals.allocator.free(timers_table[i][0].content);
        globals.allocator.free(timers_table[i][1].content);
        globals.allocator.free(timers_table[i][2].content);
        globals.allocator.free(timers_table[i]);
    }
}

/// Print out help for the infos command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt infos [thing_id]{s}
        \\
        \\Displays all informations related to the specified thing.
        \\
        \\If no ID is provided, this command will act on the current thing. You can
        \\see what the current thing is by using {s}mtlt{s} without any sub-command.
        \\
        \\Examples:
        \\  {s}mtlt infos{s}
        \\      Display infos about the current thing.
        \\
        \\  {s}mtlt infos b5{s}
        \\      Display infos about the thing with id 'b5'.
        \\
    , .{
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}
