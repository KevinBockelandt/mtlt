const std = @import("std");

const ansi = @import("ansi_codes.zig");
const base62_helper = @import("base62_helper.zig");
const dt = @import("data_types.zig");
const dfr = @import("data_file_reader.zig");
const globals = @import("globals.zig");
const table_printer = @import("table_printer.zig");
const time_helper = @import("time_helper.zig");

const CellAlignment = @import("table_printer.zig").CellAlignment;
const ArgumentParser = @import("argument_parser.zig").ArgumentParser;

const little_end = std.builtin.Endian.little;

/// Array list of things we will include in the report
var things_to_sort: std.ArrayList(dt.ThingToSort) = undefined;
/// If we should exclude all thing with any associated tag
var filter_no_tags: bool = false;
/// Tags that should be included in the report
var filter_tag_id_in: std.ArrayList(u16) = undefined;
/// Tags that should be excluded from the report
var filter_tag_id_out: std.ArrayList(u16) = undefined;
/// String used to filter the name of the things
var filter_name: ?[]const u8 = null;
/// Target filter above which we keep the things
var filter_target_above: ?u25 = undefined;
/// Target filter below which we keep the things
var filter_target_below: ?u25 = undefined;
/// true if we need to include things with no target
var filter_include_no_target: bool = false;
/// Remaining time filter above which we keep the things
var filter_remain_above: ?u16 = undefined;
/// Remaining time filter below which we keep the things
var filter_remain_below: ?u16 = undefined;
/// true if we need to include things with no estimation
var filter_include_no_estimation: bool = false;

/// Process the raw data of a thing to add it to the list of things
fn addThingToList(data: []const u8) void {
    const raw_fpt = std.mem.readInt(u136, data[0..dt.lgt_fixed_thing], little_end);
    const fpt = dt.getThingFixedPartFromInt(raw_fpt);

    if (fpt.status == @intFromEnum(dt.Status.ongoing)) {
        // potentially apply the no tags filter
        if (filter_no_tags and fpt.num_tags > 0) {
            return;
        }

        var to_add = dt.Thing{
            .id = fpt.id,
            .target = fpt.target,
            .estimation = fpt.estimation,
            .closure = fpt.closure,
            .status = @enumFromInt(fpt.status),
        };

        // filter on the target
        var ok_filter_target = false;

        // if there is no filter for the target we let everything pass
        if (filter_target_above == null and filter_target_below == null and filter_include_no_target == false) {
            ok_filter_target = true;
        }

        if (filter_target_above) |target_limit| {
            if (to_add.target > target_limit + time_helper.curTimestamp()) {
                ok_filter_target = true;
            }
        }
        if (filter_target_below) |target_limit| {
            if (to_add.target != 0 and to_add.target < target_limit + time_helper.curTimestamp()) {
                ok_filter_target = true;
            }
        }
        if (filter_include_no_target and to_add.target == 0) {
            ok_filter_target = true;
        }

        if (!ok_filter_target) {
            return;
        }

        // get the array of tag ids associated to the thing
        to_add.tags = globals.allocator.alloc(u16, fpt.num_tags) catch unreachable;
        var cur_idx_tag = dt.lgt_fixed_thing + fpt.lgt_name;
        var filter_tag_found: bool = false;

        for (0..fpt.num_tags) |i| {
            const tag_to_add_id = std.mem.readInt(u16, data[cur_idx_tag..][0..2], little_end);

            // if we are looking for specific tags, check that this thing contains one
            if (filter_tag_id_in.items.len > 0 and filter_tag_found == false) {
                for (filter_tag_id_in.items) |filter_tag| {
                    if (filter_tag == tag_to_add_id) {
                        filter_tag_found = true;
                    }
                }
            }

            // if we are excluding tags, check this thing does not contain one
            if (filter_tag_id_out.items.len > 0) {
                for (filter_tag_id_out.items) |filter_tag| {
                    if (filter_tag == tag_to_add_id) {
                        globals.allocator.free(to_add.tags);
                        return;
                    }
                }
            }

            to_add.tags[i] = tag_to_add_id;
            cur_idx_tag += 2;
        }

        if (filter_tag_id_in.items.len > 0 and filter_tag_found == false) {
            globals.allocator.free(to_add.tags);
            return;
        }

        // get the name of the thing
        const s_idx_name = dt.lgt_fixed_thing;
        const e_idx_name = dt.lgt_fixed_thing + fpt.lgt_name;
        to_add.name = globals.allocator.dupe(u8, data[s_idx_name..e_idx_name]) catch unreachable;

        // apply filter on the name if there is one
        if (filter_name) |to_find| {
            if (!std.mem.containsAtLeast(u8, to_add.name, 1, to_find)) {
                globals.allocator.free(to_add.tags);
                globals.allocator.free(to_add.name);
                return;
            }
        }

        // get the array of timers associated to the thing
        to_add.timers = globals.allocator.alloc(dt.Timer, fpt.num_timers) catch unreachable;
        var cur_idx_timer = cur_idx_tag;
        var total_time_spent: u64 = 0;

        for (0..fpt.num_timers) |i| {
            const raw_timer_int = std.mem.readInt(u48, data[cur_idx_timer..][0..6], little_end);
            const timer = dt.getTimerFromInt(raw_timer_int);

            to_add.timers[i] = .{
                .id = timer.id,
                .duration = timer.duration,
                .start = timer.start,
            };

            total_time_spent += timer.duration;
            cur_idx_timer += 6;
        }

        // filter on the estimation / remaining time
        var ok_filter_remain = false;

        // if there is no filter for estimation / remaining time we let everything pass
        if (filter_remain_above == null and filter_remain_below == null and filter_include_no_estimation == false) {
            ok_filter_remain = true;
        }

        if (filter_remain_above) |remain_limit| {
            if (to_add.estimation != 0 and
                to_add.estimation > total_time_spent and
                (to_add.estimation - total_time_spent) >= remain_limit)
            {
                ok_filter_remain = true;
            }
        }
        if (filter_remain_below) |remain_limit| {
            if (to_add.estimation != 0 and
                to_add.estimation > total_time_spent and
                (to_add.estimation - total_time_spent) <= remain_limit)
            {
                ok_filter_remain = true;
            }
        }
        if (filter_include_no_estimation and to_add.estimation == 0) {
            ok_filter_remain = true;
        }

        if (!ok_filter_remain) {
            globals.allocator.free(to_add.tags);
            globals.allocator.free(to_add.name);
            globals.allocator.free(to_add.timers);
            return;
        }

        things_to_sort.append(.{
            .thing = to_add,
            .coef = computeSortingCoef(fpt, to_add),
        }) catch unreachable;
    }
}

/// compute the sorting coef for a given thing
fn computeSortingCoef(fpt: dt.FixedPartThing, thing: dt.Thing) u64 {
    var total_score: u64 = 0;

    if (fpt.target != 0) {
        total_score += @as(u64, (std.math.maxInt(u25) - fpt.target)) * 100;
    }

    const max16 = std.math.maxInt(u16);

    if (fpt.estimation != 0) {
        if (computeTimeLeft(thing)) |tl| {
            if (tl > 0 and tl < max16) {
                total_score += max16 - @as(u16, @intCast(tl));
            } else if (tl < 0) {
                total_score += @abs(tl) + max16;
            }
        } else |_| {}
    }

    return total_score;
}

/// Compare 2 things_to_sort according to their associated coef used for sorting
fn compareThings(_: void, a: dt.ThingToSort, b: dt.ThingToSort) bool {
    return a.coef > b.coef;
}

/// Display a report of the ongoing things
pub fn ongoingReport(args: ArgumentParser) !void {
    // create the list of tags used as filter
    filter_tag_id_in = std.ArrayList(u16).init(globals.allocator);
    defer filter_tag_id_in.deinit();

    for (args.tags.items) |tag_name| {
        const fpt = try globals.dfr.getFixedPartTag(tag_name);
        try filter_tag_id_in.append(fpt.id);
    }

    filter_tag_id_out = std.ArrayList(u16).init(globals.allocator);
    defer filter_tag_id_out.deinit();

    for (args.excluded_tags.items) |tag_name| {
        const fpt = try globals.dfr.getFixedPartTag(tag_name);
        try filter_tag_id_out.append(fpt.id);
    }

    // store the potential filters
    filter_name = args.name;
    filter_no_tags = args.no_tags;
    filter_target_above = args.target_more;
    filter_target_below = args.target_less;
    if (args.target) |target| {
        filter_include_no_target = if (target == 0) true else false;
    }
    filter_remain_above = args.remain_more;
    filter_remain_below = args.remain_less;
    if (args.estimation) |estim| {
        filter_include_no_estimation = if (estim == 0) true else false;
    }

    // create a list of all the things to display
    things_to_sort = std.ArrayList(dt.ThingToSort).init(globals.allocator);
    defer things_to_sort.deinit();
    try globals.dfr.parseThings(addThingToList);

    if (things_to_sort.items.len < 1) {
        _ = try std.io.getStdOut().writer().write("There are no things to list\n");
        return;
    }

    // sort the list of things
    const things_to_sort_slice = try things_to_sort.toOwnedSlice();
    defer globals.allocator.free(things_to_sort_slice);
    std.mem.sort(dt.ThingToSort, things_to_sort_slice, {}, compareThings);

    // compute the number of items to display
    var idx_end_slice = things_to_sort_slice.len;
    if (args.limit == null and idx_end_slice > globals.default_report_limit) {
        idx_end_slice = globals.default_report_limit;
    } else if (args.limit != null and idx_end_slice > args.limit.? and args.limit.? != 0) {
        idx_end_slice = args.limit.?;
    }

    try displayTableReport(things_to_sort_slice[0..idx_end_slice]);

    for (things_to_sort_slice) |thing_to_sort| {
        globals.allocator.free(thing_to_sort.thing.name);
        globals.allocator.free(thing_to_sort.thing.tags);
        globals.allocator.free(thing_to_sort.thing.timers);
    }
}

/// Compute the remaining time for a particular thing
fn computeTimeLeft(thing: dt.Thing) !i64 {
    var time_spent_already: u32 = 0;
    for (thing.timers) |timer| {
        time_spent_already += timer.duration;
    }

    // check there is not a current timer for this thing
    const cur_timer = try globals.dfr.getCurrentTimer();
    if (cur_timer.id_thing == thing.id and cur_timer.start != 0) {
        const dur_cur_timer = time_helper.curTimestamp() - cur_timer.start;
        time_spent_already += dur_cur_timer;
    }

    return @as(i64, thing.estimation) - @as(i64, time_spent_already);
}

fn displayCurrentTimerReport() !void {
    const w = std.io.getStdOut().writer();
    const cur_time = time_helper.curTimestamp();
    const cur_timer = try globals.dfr.getCurrentTimer();

    if (cur_timer.id_thing != 0 and cur_timer.start != 0) {
        // get the name of  the current thing
        const cur_thing = try globals.dfr.getFixedPartThing(cur_timer.id_thing);
        const pos_cur_thing = try globals.dfr.getPosThing(cur_timer.id_thing);
        try globals.data_file.seekTo(pos_cur_thing + dt.lgt_fixed_thing);

        var buf_thing_name = try globals.allocator.alloc(u8, cur_thing.lgt_name);
        defer globals.allocator.free(buf_thing_name);
        const idx_buf_thing_name = try globals.data_file.reader().read(buf_thing_name[0..cur_thing.lgt_name]);

        var buf_str_id: [4]u8 = undefined;
        var buf_dur_id: [10]u8 = undefined;

        var duration: u9 = 0;
        const temp_dur: u25 = cur_time - cur_timer.start;

        if (temp_dur > std.math.maxInt(u9)) {
            std.debug.print("Error: the current timer has a duration of {d} minutes\n", .{temp_dur});
        } else {
            duration = @intCast(temp_dur);
        }

        const str_thing_id = base62_helper.b10ToB62(&buf_str_id, cur_timer.id_thing);

        try w.print("> timer for {s}{s}{s} - \"{s}{s}{s}\" running since {s}{s}{s}\n\n", .{
            ansi.col_id,
            str_thing_id,
            ansi.col_reset,
            ansi.col_emphasis,
            buf_thing_name[0..idx_buf_thing_name],
            ansi.col_reset,
            ansi.col_emphasis,
            try time_helper.formatDuration(&buf_dur_id, duration),
            ansi.col_reset,
        });
    } else {
        try w.print("> no timer currently running\n\n", .{});
    }
}

/// Setup the table printer to display the data to the user
fn displayTableReport(things: []dt.ThingToSort) !void {
    const num_cols: u8 = 5;
    const cur_time = time_helper.curTimestamp();

    // used to create strings that will be added to the data to display
    // TODO need to have a system to check that the tag names are not too much
    // TODO basically whatever we put in the buffer there needs to be a maximum
    var buf_str: [2048]u8 = undefined;
    var idx_buf_str: usize = 0;
    // used to manipulate the tag names
    var buf_str_tag_name: [128]u8 = undefined;
    // used to manipulate the id strings
    var buf_str_id: [4]u8 = undefined;

    try displayCurrentTimerReport();

    // the array of data we want to display as a table
    var to_display = try globals.allocator.alloc([]table_printer.Cell, things.len + 2);
    defer globals.allocator.free(to_display);

    // setup the header of the table
    to_display[0] = try globals.allocator.alloc(table_printer.Cell, num_cols);
    defer globals.allocator.free(to_display[0]);

    to_display[0][0] = .{ .content = "ID", .alignment = .right, .front_col = .title, .back_col = .gray };
    to_display[0][1] = .{ .content = "Target", .alignment = .right, .front_col = .title, .back_col = .gray };
    to_display[0][2] = .{ .content = "Remain", .alignment = .right, .front_col = .title, .back_col = .gray };
    to_display[0][3] = .{ .content = "Name", .alignment = .left, .front_col = .title, .back_col = .gray };
    to_display[0][4] = .{ .content = "Tags", .alignment = .left, .front_col = .title, .back_col = .gray };

    var total_time_left: i64 = 0;

    // setup the data of the table based on the list of things we want to display
    for (things, 1..things.len + 1) |thing_to_sort, i| {
        const thing = thing_to_sort.thing;
        to_display[i] = try globals.allocator.alloc(table_printer.Cell, num_cols);
        const line_back_col: ?table_printer.CellBackCol = if (i % 2 != 0) null else .gray;

        // create string for the ID
        const base62_id = base62_helper.b10ToB62(&buf_str_id, thing.id);
        var str_id: []u8 = undefined;
        str_id = try std.fmt.bufPrint(&buf_str, "{s}", .{base62_id});
        to_display[i][0] = .{
            .content = try globals.allocator.dupe(u8, str_id),
            .alignment = .right,
            .front_col = .id,
            .back_col = line_back_col,
        };

        // create string for the target
        if (thing.target == 0) {
            to_display[i][1] = .{
                .content = try globals.allocator.dupe(u8, "-"),
                .alignment = .right,
                .front_col = null,
                .back_col = line_back_col,
            };
        } else {
            const target_offset = @as(i64, thing.target) - @as(i64, cur_time);
            const str_target_offset = try time_helper.formatDuration(&buf_str, target_offset);

            to_display[i][1] = .{
                .content = try globals.allocator.dupe(u8, str_target_offset),
                .alignment = .right,
                .front_col = if (target_offset > 0) .positive else .negative,
                .back_col = line_back_col,
            };
        }

        // create string for the time left
        if (thing.estimation > 0) {
            const time_left = try computeTimeLeft(thing);
            total_time_left += time_left;
            const str_estimation_offset = try time_helper.formatDuration(&buf_str, time_left);

            to_display[i][2] = .{
                .content = try globals.allocator.dupe(u8, str_estimation_offset),
                .alignment = .right,
                .front_col = if (time_left > 0) .positive else .negative,
                .back_col = line_back_col,
            };
        } else {
            to_display[i][2] = .{
                .content = try globals.allocator.dupe(u8, "-"),
                .alignment = .right,
                .front_col = null,
                .back_col = line_back_col,
            };
        }

        // get the string for the name
        to_display[i][3] = .{
            .content = thing.name,
            .alignment = .left,
            .front_col = null,
            .back_col = line_back_col,
        };

        // create string for the tags
        if (thing.tags.len > 0) {
            idx_buf_str = 0;

            for (thing.tags, 0..thing.tags.len) |tag_id, j| {
                if (globals.dfr.getTagNameFromId(&buf_str_tag_name, tag_id)) |name_to_add| {
                    const e_idx_name = idx_buf_str + name_to_add.len;
                    std.mem.copyForwards(u8, buf_str[idx_buf_str..e_idx_name], name_to_add);

                    // add a , between tag names. Except for the last one
                    if (j != thing.tags.len - 1) {
                        std.mem.copyForwards(u8, buf_str[e_idx_name..][0..2], ", ");
                        idx_buf_str = e_idx_name + 2;
                    } else {
                        idx_buf_str = e_idx_name;
                    }
                } else |err| {
                    if (err == dfr.DataParsingError.TagNotFound) {
                        std.debug.print("Error: the tag with ID: {d} was not found\n", .{tag_id});
                    } else {
                        std.debug.print("Error: while getting name for tag {d} - {}\n", .{ tag_id, err });
                    }
                }
            }

            to_display[i][4] = .{
                .content = try globals.allocator.dupe(u8, buf_str[0..idx_buf_str]),
                .alignment = .left,
                .front_col = null,
                .back_col = line_back_col,
            };
        } else {
            to_display[i][4] = .{
                .content = try globals.allocator.dupe(u8, "-"),
                .alignment = .left,
                .front_col = null,
                .back_col = line_back_col,
            };
        }
    }

    // add 1 last line containing the totals
    const idx_last_line = things.len + 1;
    to_display[idx_last_line] = try globals.allocator.alloc(table_printer.Cell, num_cols);
    defer globals.allocator.free(to_display[idx_last_line]);

    var buf_total_id: [32]u8 = undefined;
    const str_total_id = try std.fmt.bufPrint(&buf_total_id, "{s}{d}", .{ ansi.coltit, things.len });
    to_display[idx_last_line][0] = .{
        .content = str_total_id,
        .alignment = .left,
        .front_col = null,
        .back_col = .gray,
    };

    to_display[idx_last_line][1] = .{
        .content = "",
        .alignment = .left,
        .front_col = null,
        .back_col = .gray,
    };

    var buf_total_remains_dur: [16]u8 = undefined;
    const str_total_remains_dur = try time_helper.formatDuration(&buf_total_remains_dur, total_time_left);
    to_display[idx_last_line][2] = .{
        .content = str_total_remains_dur,
        .alignment = .left,
        .front_col = null,
        .back_col = .gray,
    };

    to_display[idx_last_line][3] = .{
        .content = "",
        .alignment = .left,
        .front_col = null,
        .back_col = .gray,
    };
    to_display[idx_last_line][4] = .{
        .content = "",
        .alignment = .left,
        .front_col = null,
        .back_col = .gray,
    };

    try table_printer.printTable(to_display);

    // Free memory for all that we allocated
    for (1..things.len + 1) |i| {
        globals.allocator.free(to_display[i][0].content);
        globals.allocator.free(to_display[i][1].content);
        globals.allocator.free(to_display[i][2].content);
        globals.allocator.free(to_display[i][4].content);
        globals.allocator.free(to_display[i]);
    }
}
