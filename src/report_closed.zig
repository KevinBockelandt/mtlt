const std = @import("std");

const ansi = @import("ansi_codes.zig");
const base62_helper = @import("base62_helper.zig");
const dt = @import("data_types.zig");
const dfr = @import("data_file_reader.zig");
const globals = @import("globals.zig");
const table_printer = @import("table_printer.zig");
const th = @import("time_helper.zig");
const user_feedback = @import("user_feedback.zig");

const CellAlignment = @import("table_printer.zig").CellAlignment;
const ArgumentParser = @import("argument_parser.zig").ArgumentParser;

const colpos = ansi.col_positive_dur;
const colneg = ansi.col_negative_dur;
const colres = ansi.col_reset;

const little_end = std.builtin.Endian.little;

/// Array list of things we will include in the report
var things_to_display: std.ArrayList(dt.Thing) = undefined;

/// Process the raw data of a thing to add it to the list of things
fn addThingToList(thing: dt.Thing, arr: *std.ArrayList(dt.Thing)) void {
    if (thing.closure > 0) {
        const dup_thing = thing.dupe();
        arr.*.append(dup_thing) catch |err| {
            std.debug.print("ERROR: while trying to add a tag to a list during parsing: {}\n", .{err});
        };
    }
}

/// Display a report of the open things
pub fn closedReport(args: *ArgumentParser) !void {
    // TODO add necessary filters

    // create a list of all the things to display
    things_to_display = std.ArrayList(dt.Thing).init(globals.allocator);
    defer things_to_display.deinit();

    try globals.dfr.parseThings(.{ .AddThingToArrayList = .{
        .func = addThingToList,
        .thing_array = &things_to_display,
    } });

    if (things_to_display.items.len < 1) {
        _ = try std.io.getStdOut().writer().write("There are no things to list\n");
        return;
    }

    const things_to_display_slice = try things_to_display.toOwnedSlice();
    defer globals.allocator.free(things_to_display_slice);

    // compute the number of items to display
    var idx_end_slice = things_to_display_slice.len;
    if (args.*.limit == null and idx_end_slice > globals.default_report_limit) {
        idx_end_slice = globals.default_report_limit;
    } else if (args.*.limit != null and idx_end_slice > args.*.limit.? and args.*.limit.? != 0) {
        idx_end_slice = args.*.limit.?;
    }

    try displayTableReport(things_to_display_slice[0..idx_end_slice]);

    // display an additional line after the table regarding number of things
    var buf_missing_things: [256]u8 = undefined;
    const nbr_missing_things: usize = things_to_display_slice.len - idx_end_slice;

    const str_missing_things = if (nbr_missing_things == 0)
        try std.fmt.bufPrint(&buf_missing_things, "{s}{d}{s} things shown", .{ ansi.coltit, idx_end_slice, ansi.colres })
    else
        try std.fmt.bufPrint(&buf_missing_things, "{s}{d}{s} things shown - {s}{d}{s} things not shown because of the display limit", .{ ansi.coltit, idx_end_slice, ansi.colres, ansi.coltit, nbr_missing_things, ansi.colres });

    try std.io.getStdOut().writer().print("\n{s}\n", .{str_missing_things});

    // free memory
    for (things_to_display_slice) |thing| {
        thing.deinit();
    }
}

/// Setup the table printer to display the data to the user
fn displayTableReport(things: []dt.Thing) !void {
    const num_cols: u8 = 7;
    const cur_time = th.curTimestamp();

    // used to display various numbers and values as strings
    var buf_id_base62: [4]u8 = undefined;
    var buf_creation_str: [64]u8 = undefined;
    var buf_closure_str: [64]u8 = undefined;
    var buf_time_spent_str: [64]u8 = undefined;
    var buf_estimation_str: [64]u8 = undefined;

    // the array of data we want to display as a table
    var to_display = try globals.allocator.alloc([]table_printer.Cell, things.len + 1);
    defer globals.allocator.free(to_display);

    // setup the header of the table
    to_display[0] = try globals.allocator.alloc(table_printer.Cell, num_cols);
    defer globals.allocator.free(to_display[0]);

    to_display[0][0] = .{ .content = "ID", .alignment = .left, .front_col = .title, .back_col = .gray };
    to_display[0][1] = .{ .content = "Name", .alignment = .left, .front_col = .title, .back_col = .gray };
    to_display[0][2] = .{ .content = "Created", .alignment = .left, .front_col = .title, .back_col = .gray };
    to_display[0][3] = .{ .content = "Closed", .alignment = .left, .front_col = .title, .back_col = .gray };
    to_display[0][4] = .{ .content = "Time Spent", .alignment = .left, .front_col = .title, .back_col = .gray };
    to_display[0][5] = .{ .content = "Estimation", .alignment = .left, .front_col = .title, .back_col = .gray };
    to_display[0][6] = .{ .content = "Tags", .alignment = .left, .front_col = .title, .back_col = .gray };

    // setup the data of the table based on the list of things we want to display
    for (things, 1..things.len + 1) |thing, i| {
        to_display[i] = try globals.allocator.alloc(table_printer.Cell, num_cols);
        const line_back_col: ?table_printer.CellBackCol = if (i % 2 != 0) null else .gray;

        // ID column
        const base62_id = base62_helper.b10ToB62(&buf_id_base62, thing.id);
        to_display[i][0] = .{
            .content = try globals.allocator.dupe(u8, base62_id),
            .alignment = .right,
            .front_col = .id,
            .back_col = line_back_col,
        };

        // NAME column
        to_display[i][1] = .{
            .content = thing.name,
            .alignment = .left,
            .front_col = null,
            .back_col = line_back_col,
        };

        // CREATED column
        const offset_creation_min: i64 = @as(i64, @intCast(thing.creation)) - @as(i64, @intCast(cur_time));
        const offset_creation_step = try th.getStepsFromMinutes(u25, @intCast(@abs(offset_creation_min)));
        const offset_creation_str = try std.fmt.bufPrint(&buf_creation_str, "{s}{d}{s} ago", .{ ansi.coldurntr, offset_creation_step, ansi.colres });

        to_display[i][2] = .{
            .content = try globals.allocator.dupe(u8, offset_creation_str),
            .alignment = .right,
            .front_col = null,
            .back_col = line_back_col,
        };

        // CLOSED column
        const offset_closure_min: i64 = @as(i64, @intCast(thing.closure)) - @as(i64, @intCast(cur_time));
        const offset_closure_step = try th.getStepsFromMinutes(u25, @intCast(@abs(offset_closure_min)));
        const offset_closure_str = try std.fmt.bufPrint(&buf_closure_str, "{s}{d}{s} ago", .{ ansi.coldurntr, offset_closure_step, ansi.colres });

        to_display[i][3] = .{
            .content = try globals.allocator.dupe(u8, offset_closure_str),
            .alignment = .right,
            .front_col = null,
            .back_col = line_back_col,
        };

        // get necessary infos on timers
        var total_time_spent: u64 = 0;
        for (thing.timers) |timer| {
            total_time_spent += timer.duration;
        }

        // TIME SPENT column
        const str_time_spent_str = try std.fmt.bufPrint(&buf_time_spent_str, "{s}{d}{s}", .{ ansi.coldurntr, total_time_spent, ansi.colres });
        to_display[i][4] = .{
            .content = try globals.allocator.dupe(u8, str_time_spent_str),
            .alignment = .right,
            .front_col = null,
            .back_col = line_back_col,
        };

        // ESTIMATION column
        if (thing.estimation > 0) {
            const nbr_estimation_dur: i64 = @as(i64, @intCast(thing.estimation)) - @as(i64, @intCast(total_time_spent));

            if (nbr_estimation_dur >= 0) {
                const str_estimation_str = try std.fmt.bufPrint(&buf_estimation_str, "{s}{d}{s} below", .{ ansi.colposdur, nbr_estimation_dur, ansi.colres });
                to_display[i][5] = .{
                    .content = try globals.allocator.dupe(u8, str_estimation_str),
                    .alignment = .left,
                    .front_col = null,
                    .back_col = line_back_col,
                };
            } else {
                const str_estimation_str = try std.fmt.bufPrint(&buf_estimation_str, "{s}{d}{s} over", .{ ansi.colnegdur, nbr_estimation_dur, ansi.colres });
                to_display[i][5] = .{
                    .content = try globals.allocator.dupe(u8, str_estimation_str),
                    .alignment = .left,
                    .front_col = null,
                    .back_col = line_back_col,
                };
            }
        } else {
            to_display[i][5] = .{
                .content = try globals.allocator.dupe(u8, "-"),
                .alignment = .left,
                .front_col = null,
                .back_col = line_back_col,
            };
        }

        // TAGS column
        // TODO check the max lenght of content here
        var buf_tags: [1024]u8 = undefined;
        var idx_buf_tags: usize = 0;
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
                        try user_feedback.errTagNotFoundId(tag_id);
                    } else {
                        try user_feedback.errUnexpectedGetTagName(tag_id, err);
                    }
                }
            }
        } else {
            buf_tags[0] = '-';
            idx_buf_tags = 1;
        }

        to_display[i][6] = .{
            .content = try globals.allocator.dupe(u8, buf_tags[0..idx_buf_tags]),
            .alignment = .left,
            .front_col = null,
            .back_col = line_back_col,
        };
    }

    try table_printer.printTable(to_display);

    // Free memory for all that we allocated
    for (1..things.len + 1) |i| {
        globals.allocator.free(to_display[i][0].content);
        globals.allocator.free(to_display[i][2].content);
        globals.allocator.free(to_display[i][3].content);
        globals.allocator.free(to_display[i][4].content);
        globals.allocator.free(to_display[i][5].content);
        globals.allocator.free(to_display[i][6].content);
        globals.allocator.free(to_display[i]);
    }
}

/// Print out help for the closed command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\TODO help for closed command
    , .{});
}
