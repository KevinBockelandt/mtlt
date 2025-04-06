//! Used to generate a data file containing randomly generated test data

const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const std = @import("std");
const time_helper = @import("time_helper.zig");

const fs = std.fs;
const little_end = std.builtin.Endian.little;

const random_words = [_][]const u8{ "cloud", "cool", "water", "chair", "positively", "lovely", "great", "amazing", "door", "road", "gold", "silver", "on", "a", "nice", "day", "feeling", "product", "awesome", "dog", "cat", "bird", "fish", "sunny", "but", "for", "that" };

// contains statistics about the generation of the data file
const StatsGen = struct {
    time_start: i64,
    num_bytes_written_tag_section: u64,
    num_bytes_written_thing_section: u64,
    num_bytes_written_total: u64,
    num_tags_associated: u32,
    num_timers_written: u32,
};

const ParamGen = struct {
    num_tags: u16,
    min_size_tag_name: u7,
    max_size_tag_name: u7,
    num_things: u19,
    min_size_thing_name: u8,
    max_size_thing_name: u8,
    // max percent of things with a kickoff set
    percent_kickoff: u8,
    // max offsets between now and the kickoff to set
    max_offset_kickoff: u16,
    // max percent of things with an estimation set
    percent_estimation: u8,
    // maximum time estimated necessary to complete the thing (in minutes)
    max_estimated_time_necessary: u17,
    // max percent of difference between estimation and time actually taken
    max_offset_estimation_actual: u8,
    max_tags_per_thing: u6,
    max_timers_per_thing: u11,
    max_timers_duration: u11,
    max_offset_between_timers: u32,
    // max percent of things with status open
    percent_open: u8,
};

// generate an empty file
const param_gen_zero = ParamGen{
    .num_tags = 0,
    .min_size_tag_name = 1,
    .max_size_tag_name = 30,
    .num_things = 0,
    .min_size_thing_name = 5,
    .max_size_thing_name = 50,
    .percent_kickoff = 0,
    .max_offset_kickoff = 0,
    .percent_estimation = 50,
    .max_estimated_time_necessary = 0,
    .max_offset_estimation_actual = 0,
    .max_tags_per_thing = 3,
    .max_timers_per_thing = 5,
    .max_timers_duration = 500,
    .max_offset_between_timers = 20000,
    .percent_open = 0,
};

// generate a file with a few elements mainly stuff happening now
const param_gen_minimal = ParamGen{
    .num_tags = 3,
    .min_size_tag_name = 2,
    .max_size_tag_name = 6,
    .num_things = 3,
    .min_size_thing_name = 5,
    .max_size_thing_name = 20,
    .percent_kickoff = 50,
    .max_offset_kickoff = 3000,
    .percent_estimation = 50,
    .max_estimated_time_necessary = 200,
    .max_offset_estimation_actual = 20,
    .max_tags_per_thing = 2,
    .max_timers_per_thing = 4,
    .max_timers_duration = 50,
    .max_offset_between_timers = 200,
    .percent_open = 80,
};

// generate a file with enough elements to test a bit of everything
const param_gen_enough = ParamGen{
    .num_tags = 10,
    .min_size_tag_name = 2,
    .max_size_tag_name = 6,
    .num_things = 10,
    .min_size_thing_name = 5,
    .max_size_thing_name = 20,
    .percent_kickoff = 50,
    .max_offset_kickoff = 3000,
    .percent_estimation = 50,
    .max_estimated_time_necessary = 200,
    .max_offset_estimation_actual = 20,
    .max_tags_per_thing = 2,
    .max_timers_per_thing = 4,
    .max_timers_duration = 50,
    .max_offset_between_timers = 200,
    .percent_open = 50,
};

// generate a file with the maximum content possible
const param_gen_maximal = ParamGen{
    .num_tags = 65000,
    .min_size_tag_name = 1,
    .max_size_tag_name = 100,
    .num_things = 500000,
    .min_size_thing_name = 5,
    .max_size_thing_name = 200,
    .percent_kickoff = 50,
    .max_offset_kickoff = 1500000,
    .percent_estimation = 50,
    .max_estimated_time_necessary = 1000,
    .max_offset_estimation_actual = 80,
    .max_tags_per_thing = 2,
    .max_timers_per_thing = 4,
    .max_timers_duration = 50,
    .max_offset_between_timers = 200,
    .percent_open = 50,
};

// TEST
const param_gen_test = ParamGen{
    .num_tags = 30,
    .min_size_tag_name = 2,
    .max_size_tag_name = 6,
    .num_things = 60,
    .min_size_thing_name = 5,
    .max_size_thing_name = 20,
    .percent_kickoff = 70,
    .max_offset_kickoff = 3000,
    .percent_estimation = 70,
    .max_estimated_time_necessary = 1000,
    .max_offset_estimation_actual = 20,
    .max_tags_per_thing = 2,
    .max_timers_per_thing = 4,
    .max_timers_duration = 50,
    .max_offset_between_timers = 200,
    .percent_open = 80,
};

// conveniance variable to select a generation profile easily
//const pgen = param_gen_zero;
const pgen = param_gen_minimal;
//const pgen = param_gen_enough;
//const pgen = param_gen_maximal;
//const pgen = param_gen_test;

/// Generates a random string using a predefined list of words
fn generateRandomString(rand: std.Random, buf: []u8, add_spaces: bool) []u8 {
    var i: usize = 0;

    while (i < buf.len) {
        const random_index = rand.uintAtMost(u8, random_words.len - 1);
        // std.debug.print("random index: {d}\n", .{random_index});
        const word = random_words[random_index];
        var j: usize = 0;

        while ((j < word.len) and (i < buf.len)) {
            buf.ptr[i] = word.ptr[j];
            i += 1;
            j += 1;
        }

        // add a space character if there is space for it
        if (i < buf.len and add_spaces) {
            buf.ptr[i] = ' ';
            i += 1;
        }
    }

    return buf[0..];
}

/// Generates the tags and write them in the data file
fn generateTags(rand: std.Random, w: anytype, stats_gen: *StatsGen) !void {
    var buf_random_name: [128]u8 = undefined;
    var num_tags_generated: u16 = 0;

    var generated_names = std.ArrayList([]u8).init(globals.allocator);
    defer generated_names.deinit();

    while (num_tags_generated < pgen.num_tags) {
        // generate the fixed part of the tag
        var lgt_name: u7 = rand.uintAtMost(u7, pgen.max_size_tag_name - pgen.min_size_tag_name) + pgen.min_size_tag_name;
        const status: u1 = rand.uintAtMost(u1, 1);
        const id: u16 = @intCast(pgen.num_tags - num_tags_generated);

        // generate the variable part of the tag
        var name = generateRandomString(rand, buf_random_name[0..lgt_name], false);
        var already_generated = true;

        while (already_generated) {
            already_generated = false;
            for (generated_names.items) |stored_name| {
                if (std.mem.eql(u8, stored_name, name)) {
                    already_generated = true;
                    std.debug.print("Tag name \"{s}\" already generated\n", .{name});
                    lgt_name = rand.uintAtMost(u7, pgen.max_size_tag_name - pgen.min_size_tag_name) + pgen.min_size_tag_name;
                    name = generateRandomString(rand, buf_random_name[0..lgt_name], false);
                    break;
                }
            }
        }

        try generated_names.append(try globals.allocator.dupe(u8, name));

        // write data to the file
        var to_write: u24 = lgt_name;
        to_write = to_write << 1 | status;
        to_write = to_write << 16 | id;
        _ = try w.writeInt(u24, to_write, little_end);
        _ = try w.write(name);

        // update working variables
        num_tags_generated += 1;
        const num_bytes_written = 1 + 2 + name.len;
        stats_gen.*.num_bytes_written_total += num_bytes_written;
        stats_gen.*.num_bytes_written_tag_section += num_bytes_written;
    }

    for (0..generated_names.items.len) |i| {
        globals.allocator.free(generated_names.items[i]);
    }
}

/// Generates the tags for a specific thing
fn generateTagsForThing(num_tags_to_generate: u8, rand: std.Random, w: anytype) !void {
    var idx_tags_for_this_thing: u8 = 0;
    var tags_for_this_thing: [pgen.max_tags_per_thing]u16 = undefined;

    // generate a list of tags associated to this thing
    var num_tags_generated: u5 = 0;
    while (num_tags_generated < num_tags_to_generate and num_tags_generated < pgen.num_tags) {
        var tag_id_try = rand.uintAtMost(u16, pgen.num_tags);
        if (tag_id_try == 0) tag_id_try = 1;
        var is_in_array = false;

        // check the try is not already in the array
        for (tags_for_this_thing) |t| {
            if (tag_id_try == t) {
                is_in_array = true;
            }
        }

        // if the try is not already in the array, we can use it
        if (is_in_array == false) {
            tags_for_this_thing[idx_tags_for_this_thing] = tag_id_try;
            try w.writeInt(u16, tag_id_try, little_end);
            num_tags_generated += 1;
            idx_tags_for_this_thing += 1;
        }
    }
}

/// Generate timers for a specific thing
fn generateTimersForThing(num_timers_to_generate: u11, cur_time: u25, rand: std.Random, w: anytype, time_taken: u24) !void {
    if (num_timers_to_generate == 0) {
        return;
    }

    var num_timers_generated: u11 = num_timers_to_generate;

    // make sure we can fit the full duration of the thing into the given number of timers
    const full_duration: u64 = if (time_taken / num_timers_to_generate > std.math.maxInt(u11))
        num_timers_to_generate * std.math.maxInt(u11)
    else
        time_taken;

    while (num_timers_generated > 0) {
        const raw_int_to_write = dt.getIntFromTimer(.{
            .id = num_timers_generated,
            .duration = @intCast(full_duration / num_timers_to_generate),
            .start = cur_time + rand.uintAtMost(u25, pgen.max_offset_between_timers),
        });

        try w.writeInt(u48, raw_int_to_write, little_end);
        num_timers_generated -= 1;
    }
}

/// Generate all the things in the file
fn generateThings(rand: std.Random, w: anytype, stats_gen: *StatsGen) !void {
    var cur_id: u19 = pgen.num_things + 1;
    const cur_time = time_helper.curTimestamp();

    var buf_random_name: [256]u8 = undefined;

    for (0..pgen.num_things) |_| {
        const name_size = rand.uintAtMost(u8, pgen.max_size_thing_name - pgen.min_size_thing_name) + pgen.min_size_thing_name;
        const name = generateRandomString(rand, buf_random_name[0..name_size], true);

        cur_id -= 1;
        var num_tags: u6 = if (pgen.max_tags_per_thing < pgen.num_tags) pgen.max_tags_per_thing else @intCast(pgen.num_tags);
        num_tags = rand.uintAtMost(u6, num_tags);
        const num_timers = rand.uintAtMost(u11, pgen.max_timers_per_thing);

        // determine the status of the thing
        const rand_status = rand.uintAtMost(u8, 100);
        const status = if (rand_status <= pgen.percent_open)
            @intFromEnum(dt.StatusThing.open)
        else
            @intFromEnum(dt.StatusThing.closed);

        // get the current timestamp
        const creation = cur_time;

        // compute the kickoff based on the current time and an offset
        var kickoff: u25 = 0;
        if (rand.uintAtMost(u8, 100) <= pgen.percent_kickoff) {
            const off_kickoff = rand.uintAtMost(u16, pgen.max_offset_kickoff);
            kickoff = if (rand.boolean())
                cur_time + @as(u25, @intCast(off_kickoff))
            else
                cur_time - @as(u25, @intCast(off_kickoff));
        }

        // compute the closure offset and it's direction
        const ref_closure = if (kickoff > 0) kickoff else cur_time;
        const closure: u25 = if (status == @intFromEnum(dt.StatusThing.closed)) ref_closure else 0;

        var estimation: u17 = 0;
        if (rand.uintAtMost(u8, 100) <= pgen.percent_estimation) {
            estimation = rand.uintAtMost(u17, pgen.max_estimated_time_necessary);
        }

        // compute the time actually taken by all the timers based on the estimation and an offset in percent
        const per_off_time_taken: i16 = @intCast(pgen.max_offset_estimation_actual);
        const coef_off_time_taken = rand.intRangeAtMost(i16, -per_off_time_taken, per_off_time_taken);
        const diff_time_taken: i32 = @divTrunc(@as(i32, @intCast(estimation)) * @as(i32, @intCast(coef_off_time_taken)), 100);
        // TODO check this. The values for time_taken are weird
        const time_taken: u24 = if (diff_time_taken > 0)
            estimation + @as(u24, @intCast(diff_time_taken))
        else
            estimation - @as(u24, @intCast(@abs(diff_time_taken)));

        // actually write the fixed data in the file
        var to_write: u136 = name_size;
        to_write = to_write << 19 | cur_id;
        to_write = to_write << 11 | num_timers;
        to_write = to_write << 6 | num_tags;
        to_write = to_write << 1 | status;
        to_write = to_write << 25 | creation;
        to_write = to_write << 25 | kickoff;
        to_write = to_write << 16 | estimation;
        to_write = to_write << 25 | closure;

        // std.debug.print("{b:0>136} name size\n", .{name_size});
        // std.debug.print("{b:0>136} cur_id\n", .{cur_id});
        // std.debug.print("{b:0>136} num_timers\n", .{num_timers});
        // std.debug.print("{b:0>136} num_tags\n", .{num_tags});
        // std.debug.print("{b:0>136} status\n", .{status});
        // std.debug.print("{b:0>136} creation\n", .{creation});
        // std.debug.print("{b:0>136} kickoff\n", .{kickoff});
        // std.debug.print("{b:0>136} estimation\n", .{estimation});
        // std.debug.print("{b:0>136} closure\n", .{closure});
        // std.debug.print("{b:0>136} to_write\n", .{to_write});
        // std.debug.print("\n", .{});

        _ = try w.writeInt(u136, to_write, little_end);
        _ = try w.write(name);

        var num_bytes_written = 17 + name.len;
        stats_gen.*.num_bytes_written_total += num_bytes_written;
        stats_gen.*.num_bytes_written_thing_section += num_bytes_written;

        try generateTagsForThing(@intCast(num_tags), rand, w);
        num_bytes_written = 2 * num_tags;
        stats_gen.*.num_bytes_written_total += num_bytes_written;
        stats_gen.*.num_bytes_written_thing_section += num_bytes_written;
        stats_gen.*.num_tags_associated += num_tags;

        try generateTimersForThing(@intCast(num_timers), cur_time, rand, w, time_taken);
        num_bytes_written = 6 * num_timers;
        stats_gen.*.num_bytes_written_total += num_bytes_written;
        stats_gen.*.num_bytes_written_thing_section += num_bytes_written;
        stats_gen.*.num_timers_written += num_timers;
    }
}

pub fn main() !void {
    defer globals.deinitMemAllocator();

    var stats_gen = StatsGen{
        .time_start = std.time.milliTimestamp(),
        .num_bytes_written_tag_section = 0,
        .num_bytes_written_thing_section = 0,
        .num_bytes_written_total = 0,
        .num_tags_associated = 0,
        .num_timers_written = 0,
    };

    const f = try std.fs.cwd().createFile(globals.default_data_file_path, .{});
    defer f.close();
    const w = f.writer();

    // initialize random number generator
    var prng = std.Random.DefaultPrng.init(0);
    const rand = prng.random();

    // here we write empty data at the beginning of the file in order to
    // reserve that space. It will contain the total amount of bytes taken
    // by the tag section in the file.
    try w.writeInt(u64, 0, little_end);
    stats_gen.num_bytes_written_total += 8;
    stats_gen.num_bytes_written_tag_section += 8;

    // write number of tags at the beginning of file
    try w.writeInt(u16, pgen.num_tags, little_end);
    stats_gen.num_bytes_written_total += 2;
    stats_gen.num_bytes_written_tag_section += 2;

    // generate tags
    try generateTags(rand, w, &stats_gen);

    // write number of things at the beginning of the things section
    try w.writeInt(u24, pgen.num_things, little_end);
    stats_gen.num_bytes_written_total += 3;

    // generate things
    try generateThings(rand, w, &stats_gen);

    // generate current timer
    try w.writeInt(u56, 0, little_end);
    stats_gen.num_bytes_written_total += 7;

    // go back to start of the file to write the total number of
    // bytes contained in the tag section
    try std.fs.File.seekTo(f, 0);
    try w.writeInt(u64, stats_gen.num_bytes_written_tag_section, little_end);

    const durationInMs = std.time.milliTimestamp() - stats_gen.time_start;

    std.debug.print("\n------------------------------\n", .{});
    std.debug.print("Stats on generation:\n", .{});
    std.debug.print("------------------------------\n\n", .{});
    std.debug.print("  Duration in ms              : {d}\n", .{durationInMs});
    std.debug.print("  Total bytes written         : {d}\n", .{stats_gen.num_bytes_written_total});
    std.debug.print("  Tag section bytes written   : {d}\n", .{stats_gen.num_bytes_written_tag_section});
    std.debug.print("  Thing section bytes written : {d}\n", .{stats_gen.num_bytes_written_thing_section});
    std.debug.print("  # of tags written           : {d}\n", .{pgen.num_tags});
    std.debug.print("  # of things written         : {d}\n", .{pgen.num_things});
    std.debug.print("  # of tags associated        : {d}\n", .{stats_gen.num_tags_associated});
    std.debug.print("  # of timers written         : {d}\n", .{stats_gen.num_timers_written});
}
