const std = @import("std");
const dt = @import("data_types.zig");
const dfr = @import("data_file_reader.zig");
const globals = @import("globals.zig");
const time_helper = @import("time_helper.zig");

pub const DataOperationError = error{
    TagWithThisNameAlreadyExisting,
    NameTooLong,
    TooManyTags,
    TagAlreadyPresent,
    TooManyThings,
    TooManyTimers,
    TimerNotFound,
    DurationBelowMin,
    DurationAboveMax,
};

const little_end = std.builtin.Endian.little;
const lgt_buf_read_from_file: usize = 2048;

/// Generate an empty template for the data file
pub fn generateEmptyDataFile() !void {
    // length of the tag section
    try globals.data_file.writer().writeInt(u64, 10, little_end);
    // number of tags in the file
    try globals.data_file.writer().writeInt(u16, 0, little_end);
    // number of things in the file
    try globals.data_file.writer().writeInt(u24, 0, little_end);
    // current timer
    try globals.data_file.writer().writeInt(u56, 0, little_end);
}

/// Handle all operations related to writing in the data file
pub const DataFileWriter = struct {
    /// contains what is read from the file
    buf_read_from_file: [lgt_buf_read_from_file]u8 = undefined,
    /// number of bytes read from the file and present in buf_read_from_file
    num_bytes_read_from_file: usize = 0,
    /// number of bytes we already processed from buf_read_from_file
    idx_buf_read_from_file: usize = 0,

    /// Write into the data file at the given position
    fn addToFile(self: *DataFileWriter, to_write: []const u8, pos: usize) !void {
        try globals.data_file.seekTo(0);
        var bytes_left_to_copy: usize = pos;
        var can_read_again_from_file: bool = true;
        var num_bytes_written: usize = 0;

        // in this first loop we are copying everything from the data file to a
        // backup data file until the given position
        while (can_read_again_from_file) {
            self.num_bytes_read_from_file = try globals.data_file.reader().readAll(&self.buf_read_from_file);

            // if we read enough to reach the given position
            if (self.num_bytes_read_from_file >= bytes_left_to_copy) {
                num_bytes_written = try globals.back_data_file.write(self.buf_read_from_file[0..bytes_left_to_copy]);
                can_read_again_from_file = false;
            } else {
                num_bytes_written = try globals.back_data_file.write(self.buf_read_from_file[0..self.num_bytes_read_from_file]);
                bytes_left_to_copy -= self.num_bytes_read_from_file;
            }
        }

        // at this point, we can add to the content to write to the backup file
        try globals.back_data_file.writeAll(to_write);

        // in this last part, we copy the rest of the data file in to the backup file
        try globals.data_file.seekTo(pos);

        can_read_again_from_file = true;
        while (can_read_again_from_file) {
            self.num_bytes_read_from_file = try globals.data_file.reader().readAll(&self.buf_read_from_file);
            num_bytes_written = try globals.back_data_file.write(self.buf_read_from_file[0..self.num_bytes_read_from_file]);

            if (self.num_bytes_read_from_file < lgt_buf_read_from_file) {
                can_read_again_from_file = false;
            }
        }

        // finally we delete the current data file and rename the backup file so that
        // it becomes the new data file
        try globals.swapDataFiles();
    }

    /// Remove some data from the data file at the given position
    fn removeFromFile(self: *DataFileWriter, num_bytes_to_remove: usize, pos: usize) !void {
        try globals.data_file.seekTo(0);
        var bytes_left_to_copy: usize = pos;
        var can_read_again_from_file: bool = true;

        // in this first loop we are copying everything from the data file to a
        // backup data file until the given position
        while (can_read_again_from_file) {
            self.num_bytes_read_from_file = try globals.data_file.reader().readAll(&self.buf_read_from_file);

            // if we read enough to reach the given position
            if (self.num_bytes_read_from_file >= bytes_left_to_copy) {
                _ = try globals.back_data_file.write(self.buf_read_from_file[0..bytes_left_to_copy]);
                can_read_again_from_file = false;
            } else {
                _ = try globals.back_data_file.write(self.buf_read_from_file[0..self.num_bytes_read_from_file]);
                bytes_left_to_copy -= self.num_bytes_read_from_file;
            }
        }

        // skip the amount of data to erase and copy the rest of the data file in to the backup file
        try globals.data_file.seekTo(pos + num_bytes_to_remove);

        can_read_again_from_file = true;
        while (can_read_again_from_file) {
            self.num_bytes_read_from_file = try globals.data_file.reader().readAll(&self.buf_read_from_file);
            _ = try globals.back_data_file.write(self.buf_read_from_file[0..self.num_bytes_read_from_file]);

            if (self.num_bytes_read_from_file < lgt_buf_read_from_file) {
                can_read_again_from_file = false;
            }
        }

        // finally we delete the current data file and rename the backup file so that
        // it becomes the new data file
        try globals.swapDataFiles();
    }

    /// Add a tag at the start of the tag section of the data file
    pub fn addTagToFile(self: *DataFileWriter, name: []const u8) !u16 {
        if (name.len > std.math.maxInt(u7)) {
            return DataOperationError.NameTooLong;
        }

        const r = globals.data_file.reader();
        try globals.data_file.seekTo(0);

        const total_bytes_tag_section = try r.readInt(u64, little_end);
        const num_tags_in_file = try r.readInt(u16, little_end);

        // read the first tag of the file (most recent) to get the current greatest id
        const raw_fpt = try r.readInt(u24, little_end);
        const fpt = dt.getTagFixedPartFromInt(raw_fpt);

        var new_tag_id = fpt.id;
        if (new_tag_id >= std.math.maxInt(u16)) {
            return DataOperationError.TooManyTags;
        }
        new_tag_id += 1;

        // check that there is not already a tag with this name
        if (globals.dfr.getPosTag(name)) |_| {
            return DataOperationError.TagWithThisNameAlreadyExisting;
        } else |err| {
            if (err != dfr.DataParsingError.TagNotFound) {
                return err;
            }

            // prepare data to add in the file
            var buf_to_write: [256]u8 = undefined;
            const total_bytes_tag = dt.lgt_fixed_tag + name.len;

            const raw_int_fixed_part = dt.getIntFromTagFixedPart(.{
                .lgt_name = @intCast(name.len),
                .status = @intFromEnum(dt.Status.ongoing),
                .id = new_tag_id,
            });

            std.mem.writeInt(u24, buf_to_write[0..3], raw_int_fixed_part, little_end);
            std.mem.copyForwards(u8, buf_to_write[3..total_bytes_tag], name);

            // we insert at 10 because it's the spot of the first tag in the data file
            try self.addToFile(buf_to_write[0..total_bytes_tag], 10);

            // rewrite the data at the beginning to account for the additional data
            try globals.data_file.seekTo(0);
            try globals.data_file.writer().writeInt(u64, total_bytes_tag_section + total_bytes_tag, little_end);
            try globals.data_file.writer().writeInt(u16, num_tags_in_file + 1, little_end);

            return new_tag_id;
        }
    }

    /// Add a thing at the start of the thing section of the data file
    pub fn addThingToFile(self: *DataFileWriter, name: []const u8, target: u25, estimation: u16, tags: [][]u8, res: *dt.ThingCreated) !void {
        // make sure there is not too many tags
        // TODO need to make sure that the tag names are not too long
        // TODO make sure that there are no duplicates in the tag list
        if (tags.len > std.math.maxInt(u6)) {
            return DataOperationError.TooManyTags;
        }

        // make sure the name is not too long
        if (name.len > std.math.maxInt(u8)) {
            return DataOperationError.NameTooLong;
        }

        var r = globals.data_file.reader();

        // make sure a tag already exists for all the tag names received
        // create those who do not
        var buf_tag_ids: [std.math.maxInt(u6)]u16 = undefined;
        var num_buf_tag_ids: u6 = 0;

        for (tags) |t_name| {
            if (globals.dfr.getPosTag(t_name)) |pos_tag| {
                // get the ID of the tag and add it to the list
                try globals.data_file.seekTo(pos_tag);
                const fpt = dt.getTagFixedPartFromInt(try r.readInt(u24, little_end));
                buf_tag_ids[num_buf_tag_ids] = fpt.id;
                num_buf_tag_ids += 1;
            } else |err| {
                // create the tag if it doesn't already exists and add it to the list
                if (err == dfr.DataParsingError.TagNotFound) {
                    const t_id = try self.addTagToFile(t_name);
                    buf_tag_ids[num_buf_tag_ids] = t_id;
                    num_buf_tag_ids += 1;

                    // add the name of the created tag to the return infos
                    try res.*.created_tags.append(t_name);
                } else {
                    return err;
                }
            }
        }

        try globals.data_file.seekTo(0);
        r = globals.data_file.reader();

        var total_bytes_tag_section = try r.readInt(u64, little_end);
        try globals.data_file.seekTo(total_bytes_tag_section);
        const num_things_in_file = try r.readInt(u24, little_end);

        var new_id: u19 = 1;

        if (num_things_in_file > 0) {
            const raw_most_recent_thing = try r.readInt(u136, little_end);
            const most_recent_thing = dt.getThingFixedPartFromInt(raw_most_recent_thing);

            if (most_recent_thing.id >= std.math.maxInt(u19)) {
                return DataOperationError.TooManyThings;
            }
            new_id = most_recent_thing.id + 1;
        }

        const num_tags: u6 = num_buf_tag_ids;
        res.*.id = new_id;

        const raw_int_fpt = dt.getIntFromThingFixedPart(.{
            .lgt_name = @intCast(name.len),
            .id = new_id,
            .num_timers = 0,
            .num_tags = num_tags,
            .status = @intFromEnum(dt.Status.ongoing),
            .creation = time_helper.curTimestamp(),
            .target = target,
            .estimation = estimation,
            .closure = 0,
        });

        // create and populate a buffer that we will use to add the thing's data to the file
        var buf_to_write: [1024]u8 = undefined;
        std.mem.writeInt(u136, buf_to_write[0..dt.lgt_fixed_thing], raw_int_fpt, little_end);

        // add the name to the buffer
        const s_idx_name = dt.lgt_fixed_thing;
        const e_idx_name = s_idx_name + name.len;
        std.mem.copyForwards(u8, buf_to_write[s_idx_name..e_idx_name], name);

        // add all the tag ids to the buffer
        var s_idx_tag = e_idx_name;

        for (buf_tag_ids[0..num_buf_tag_ids]) |tag| {
            std.mem.writeInt(u16, buf_to_write[s_idx_tag..][0..2], tag, little_end);
            s_idx_tag += 2;
        }

        // add the data to the data file
        try globals.data_file.seekTo(0);
        total_bytes_tag_section = try r.readInt(u64, little_end);
        try self.addToFile(buf_to_write[0..s_idx_tag], total_bytes_tag_section + 3);

        // go back to rewrite the current number of things
        try globals.data_file.seekTo(total_bytes_tag_section);
        try globals.data_file.writer().writeInt(u24, num_things_in_file + 1, little_end);
    }

    /// Add a new timer to a thing
    pub fn addTimerToThing(self: *DataFileWriter, id_thing: u19, start: u25, duration: u12) !u11 {
        const r = globals.data_file.reader();

        if (globals.dfr.getPosThing(id_thing)) |thing_pos| {
            try globals.data_file.seekTo(thing_pos);

            // get the current fixed data for the thing
            var raw_fpt_int = try r.readInt(u136, little_end);
            var fpt = dt.getThingFixedPartFromInt(raw_fpt_int);

            // get the ID to use for the new timer
            try globals.data_file.seekBy(fpt.lgt_name + (fpt.num_tags * 2));
            var new_timer_id: u11 = 1;
            if (fpt.num_timers > 0) {
                const raw_timer_int = try r.readInt(u48, little_end);
                const most_recent_timer = dt.getTimerFromInt(raw_timer_int);

                // check we can increment the ID for this new timer
                if (most_recent_timer.id >= std.math.maxInt(u11)) {
                    return DataOperationError.TooManyTimers;
                }
                new_timer_id = most_recent_timer.id + 1;

                // go back at the start of the timers part
                try globals.data_file.seekBy(-dt.lgt_fixed_timer);
            }

            // insert the new timer at the start of the timers list
            const int_new_timer = dt.getIntFromTimer(.{
                .id = new_timer_id,
                .duration = duration,
                .start = start,
            });

            // TODO can probably be done with toBytes
            var buf_id: [6]u8 = undefined;
            std.mem.writeInt(u48, buf_id[0..6], int_new_timer, little_end);
            try self.addToFile(buf_id[0..], try globals.data_file.getPos());

            // udpate the number of timers associated to this thing
            fpt.num_timers += 1;
            try globals.data_file.seekTo(thing_pos);
            raw_fpt_int = dt.getIntFromThingFixedPart(fpt);
            try globals.data_file.writer().writeInt(u136, raw_fpt_int, little_end);

            return new_timer_id;
        } else |err| {
            return err;
        }
    }

    /// Delete the tag with the specified name from the data file
    pub fn deleteTagFromFile(self: *DataFileWriter, name: []const u8) !void {
        const r = globals.data_file.reader();
        try globals.data_file.seekTo(0);

        const total_bytes_tag_section = try r.readInt(u64, little_end);
        const num_tags_in_file = try r.readInt(u16, little_end);

        if (globals.dfr.getPosTag(name)) |tag_pos| {
            try globals.data_file.seekTo(tag_pos);

            // extract fixed data from the tag
            const raw_fpt = try r.readInt(u24, little_end);
            const fpt = dt.getTagFixedPartFromInt(raw_fpt);
            const total_bytes_tag = dt.lgt_fixed_tag + fpt.lgt_name;

            // actually remove this tag from the file
            try self.removeFromFile(total_bytes_tag, tag_pos);

            // rewrite the data at the beginning to account the change
            try globals.data_file.seekTo(0);
            try globals.data_file.writer().writeInt(u64, total_bytes_tag_section - total_bytes_tag, little_end);
            try globals.data_file.writer().writeInt(u16, num_tags_in_file - 1, little_end);
        } else |err| {
            return err;
        }
    }

    /// Delete the thing with the specified id from the data file
    pub fn deleteThingFromFile(self: *DataFileWriter, id: u19) !void {
        const r = globals.data_file.reader();
        try globals.data_file.seekTo(0);

        const total_bytes_tag_section = try r.readInt(u64, little_end);
        try globals.data_file.seekTo(total_bytes_tag_section);
        const num_things_in_file = try r.readInt(u24, little_end);

        if (globals.dfr.getPosThing(id)) |thing_pos| {
            try globals.data_file.seekTo(thing_pos);

            // extract fixed data from the thing
            const raw_fpt = try r.readInt(u136, little_end);
            const fpt = dt.getThingFixedPartFromInt(raw_fpt);
            const total_bytes_thing = dt.lgt_fixed_thing + fpt.lgt_name + (fpt.num_tags * 2) + (fpt.num_timers * 6);

            // actually remove this thing from the file
            try self.removeFromFile(total_bytes_thing, thing_pos);

            // rewrite the number of things in the file
            try globals.data_file.seekTo(total_bytes_tag_section);
            try globals.data_file.writer().writeInt(u24, num_things_in_file - 1, little_end);
        } else |err| {
            return err;
        }
    }

    /// Delete the specified timer from the data file
    pub fn deleteTimerFromFile(self: *DataFileWriter, id_thing: u19, id_timer: u11) !void {
        var fpt = try globals.dfr.getFixedPartThing(id_thing);
        const pos_thing = try globals.data_file.getPos() - dt.lgt_fixed_thing;

        const start_pos_timers = pos_thing + dt.lgt_fixed_thing + fpt.lgt_name + fpt.num_tags * 2;
        try globals.data_file.seekTo(start_pos_timers);

        // go through all timers to look for the one to delete
        for (0..fpt.num_timers) |_| {
            const timer = dt.getTimerFromInt(try globals.data_file.reader().readInt(u48, little_end));

            if (timer.id == id_timer) {
                // remove the timer
                const start_pos_timer = try globals.data_file.getPos() - dt.lgt_fixed_timer;
                try self.removeFromFile(dt.lgt_fixed_timer, start_pos_timer);

                // rewrite the number of timers on the thing
                fpt.num_timers -= 1;
                const new_raw_fpt = dt.getIntFromThingFixedPart(fpt);

                try globals.data_file.seekTo(pos_thing);
                try globals.data_file.writer().writeInt(u136, new_raw_fpt, little_end);

                return;
            }
        }

        // if we reach this point we did not found the timer to update
        return DataOperationError.TimerNotFound;
    }

    /// Update the current timer section of the data file
    pub fn startCurrentTimer(self: *DataFileWriter, id_thing: u19) !void {
        _ = self;
        try globals.data_file.seekFromEnd(-dt.lgt_fixed_current_timer);

        const cur_timer = try globals.dfr.getCurrentTimer();

        const to_write = dt.getIntFromCurrentTimer(.{
            .id_thing = id_thing,
            .id_last_timer = cur_timer.id_last_timer,
            .start = time_helper.curTimestamp(),
        });

        try globals.data_file.writer().writeInt(u56, to_write, little_end);
    }

    /// Update the current timer section of the data file
    pub fn stopCurrentTimer(self: *DataFileWriter, input: dt.TimerToUpdate) !dt.Timer {
        const cur_time = time_helper.curTimestamp();
        var timer = try globals.dfr.getCurrentTimer();
        var duration = @as(u12, @intCast(cur_time - timer.start));

        // if there is an specific duration to set
        if (input.duration) |dur| {
            duration = dur;
        }

        // if there is a duration offset we need to apply
        if (input.duration_off) |dur_off| {
            if (input.add_duration_off) {
                // check the offset is not too much
                if ((std.math.maxInt(u12) - duration) < dur_off) {
                    return DataOperationError.DurationAboveMax;
                } else {
                    duration += dur_off;
                }
            } else {
                // check the offset is not too much
                if (duration < dur_off) {
                    return DataOperationError.DurationBelowMin;
                } else {
                    duration -= dur_off;
                }
            }
        }

        // if there is a start offset we need to apply
        if (input.start_off) |start_off| {
            if (input.add_start_off) {
                // check the offset is not too much
                // potentially this timer will start in the future
                if ((std.math.maxInt(u25) - timer.start) < start_off) {
                    return DataOperationError.DurationAboveMax;
                } else {
                    timer.start += start_off;
                }
            } else {
                // check the offset is not too much
                if (timer.start < start_off) {
                    return DataOperationError.DurationBelowMin;
                } else {
                    timer.start -= start_off;
                }
            }
        }

        // Add the timer to the associated thing
        const id_added_timer: u11 = try self.addTimerToThing(timer.id_thing, timer.start, duration);

        const to_write = dt.getIntFromCurrentTimer(.{
            .id_thing = timer.id_thing,
            .id_last_timer = id_added_timer,
            .start = 0,
        });

        try globals.data_file.seekFromEnd(-dt.lgt_fixed_current_timer);
        try globals.data_file.writer().writeInt(u56, to_write, little_end);

        return .{
            .id = id_added_timer,
            .duration = duration,
            .start = timer.start,
        };
    }

    /// Reset id of last current timer
    pub fn resetIdLastCurrentTimer(self: *DataFileWriter, id_thing: u19, start: u25) !void {
        _ = self;

        try globals.data_file.seekFromEnd(-dt.lgt_fixed_current_timer);
        const to_write = dt.getIntFromCurrentTimer(.{
            .id_thing = id_thing,
            .id_last_timer = 0,
            .start = start,
        });
        try globals.data_file.writer().writeInt(u56, to_write, little_end);
    }

    /// Update the status of the tag with the given ID
    pub fn toggleTagStatus(self: *DataFileWriter, name: []const u8) !dt.Status {
        _ = self;
        const r = globals.data_file.reader();

        if (globals.dfr.getPosTag(name)) |tag_pos| {
            try globals.data_file.seekTo(tag_pos);
            const tag_fixed_part = try r.readInt(u24, little_end);
            const fpt = dt.getTagFixedPartFromInt(tag_fixed_part);

            try globals.data_file.seekBy(-dt.lgt_fixed_tag);
            try globals.data_file.writer().writeInt(u24, tag_fixed_part ^ 0b000000010000000000000000, little_end);

            return @enumFromInt(fpt.status ^ 1);
        } else |err| {
            return err;
        }
    }

    /// Update the status of the thing with the given ID
    pub fn toggleThingStatus(self: *DataFileWriter, id: u19) !dt.Status {
        _ = self;
        var fpt = try globals.dfr.getFixedPartThing(id);

        fpt.status ^= 1;
        fpt.closure = time_helper.curTimestamp();

        // rewrite the data
        const raw_fpt_int = dt.getIntFromThingFixedPart(fpt);
        fpt = dt.getThingFixedPartFromInt(raw_fpt_int);

        try globals.data_file.seekBy(-dt.lgt_fixed_thing);
        try globals.data_file.writer().writeInt(u136, raw_fpt_int, little_end);

        return @enumFromInt(fpt.status);
    }

    /// Update the name of a tag
    pub fn updateTagName(self: *DataFileWriter, old_name: []const u8, new_name: []const u8) !void {
        const w = globals.data_file.writer();

        if (new_name.len > std.math.maxInt(u7)) {
            return DataOperationError.NameTooLong;
        }

        if (globals.dfr.getFixedPartTag(old_name)) |fpt| {
            var new_fpt = fpt;

            // udpate the lgt of the tag name
            new_fpt.lgt_name = @intCast(new_name.len);
            try globals.data_file.seekBy(-dt.lgt_fixed_tag);

            const raw_int_fpt = dt.getIntFromTagFixedPart(new_fpt);
            try w.writeInt(u24, raw_int_fpt, little_end);

            // rewrite the name of the tag
            if (new_name.len > old_name.len) {
                _ = try w.write(new_name[0..old_name.len]);
                const posWhereToAdd: usize = try globals.data_file.getPos();
                try self.addToFile(new_name[old_name.len..new_name.len], posWhereToAdd);
            } else {
                _ = try w.write(new_name);
                const posWhereToRemove: usize = try globals.data_file.getPos();
                try self.removeFromFile(old_name.len - new_name.len, posWhereToRemove);
            }

            // udpate the number of bytes of the tag section
            try globals.data_file.seekTo(0);
            const nbts = try globals.data_file.reader().readInt(u64, little_end);
            try globals.data_file.seekTo(0);

            const new_nbts: u64 = if (new_name.len >= old_name.len)
                nbts + (new_name.len - old_name.len)
            else
                nbts - (old_name.len - new_name.len);

            try globals.data_file.writer().writeInt(u64, new_nbts, little_end);
        } else |err| {
            return err;
        }
    }

    /// Update the infos of a thing
    // TODO the whole thing makes way too much operations. Could be optimized
    pub fn updateThing(self: *DataFileWriter, input: dt.ThingToUpdate, output: *std.ArrayList(dt.Tag)) !void {
        // Check that all tags exist, if not create them
        for (input.tags.items) |t| {
            if (globals.dfr.getPosTag(t)) |_| {} else |err| {
                if (err == dfr.DataParsingError.TagNotFound) {
                    // need to create the tag
                    const id_new_tag = try self.addTagToFile(t);
                    try output.append(.{
                        .id = id_new_tag,
                        .name = t,
                    });
                } else {
                    std.debug.print("ERROR while looking for a tag during updateThing\n", .{});
                }
            }
        }

        // TODO need to make sure there are no duplicates in the tag list

        // get the list of tags currently associated to the thing
        var current_tags = std.ArrayList(u16).init(globals.allocator);
        defer current_tags.deinit();
        try globals.dfr.getTagsOfThing(input.id, &current_tags);

        // this will contain the new list of tags that need to be associated to the thing
        var new_tags = std.ArrayList(u16).init(globals.allocator);
        defer new_tags.deinit();

        // for each tag on the input, add or remove it from the thing
        for (input.tags.items) |in_tag| {
            const infos_tag = try globals.dfr.getFixedPartTag(in_tag);
            var is_tag_already_associated = false;

            for (current_tags.items) |cur_tag| {
                if (cur_tag == infos_tag.id) {
                    is_tag_already_associated = true;
                }
            }

            if (!is_tag_already_associated) {
                try new_tags.append(infos_tag.id);
            }
        }

        // for each tag already present, re-use it if not in the input list
        for (current_tags.items) |cur_tag| {
            var is_tag_in_input = false;

            for (input.tags.items) |in_tag| {
                const infos_tag = try globals.dfr.getFixedPartTag(in_tag);
                if (cur_tag == infos_tag.id) {
                    is_tag_in_input = true;
                }
            }

            if (!is_tag_in_input) {
                try new_tags.append(cur_tag);
            }
        }

        var fpt = try globals.dfr.getFixedPartThing(input.id);
        const pos_thing = try globals.dfr.getPosThing(input.id);

        var old_lgt_name: usize = 0;

        // update the fixed part data
        fpt.target = if (input.target) |t| t else fpt.target;
        fpt.estimation = if (input.estimation) |e| e else fpt.estimation;

        // update number of tags
        if (new_tags.items.len < std.math.maxInt(u6)) {
            fpt.num_tags = @intCast(new_tags.items.len);
        } else {
            return DataOperationError.TooManyTags;
        }

        // update length of the name
        if (input.name) |n| {
            if (n.len > std.math.maxInt(u8)) {
                return DataOperationError.NameTooLong;
            }
            old_lgt_name = fpt.lgt_name;
            fpt.lgt_name = @intCast(n.len);
        }

        // rewrite the data
        const raw_fpt_int = dt.getIntFromThingFixedPart(fpt);
        fpt = dt.getThingFixedPartFromInt(raw_fpt_int);

        try globals.data_file.seekTo(pos_thing);
        try globals.data_file.writer().writeInt(u136, raw_fpt_int, little_end);
        try globals.data_file.seekTo(pos_thing + dt.lgt_fixed_thing);

        // rewrite the name of the thing
        if (input.name) |n| {
            if (fpt.lgt_name > old_lgt_name) {
                _ = try globals.data_file.writer().write(n[0..old_lgt_name]);
                const pos_where_to_add: usize = pos_thing + dt.lgt_fixed_thing + old_lgt_name;
                try self.addToFile(input.name.?[old_lgt_name..fpt.lgt_name], pos_where_to_add);
            } else {
                _ = try globals.data_file.writer().write(n);
                const pos_where_to_remove: usize = pos_thing + dt.lgt_fixed_thing + fpt.lgt_name;
                try self.removeFromFile(old_lgt_name - fpt.lgt_name, pos_where_to_remove);
            }
        }

        // rewrite the list of tag IDs
        const pos_start_tag_ids = pos_thing + dt.lgt_fixed_thing + fpt.lgt_name;

        if (input.tags.items.len > 0) {
            if (new_tags.items.len > current_tags.items.len) {
                const lgt_diff = (new_tags.items.len - current_tags.items.len) * 2;
                const to_add = try globals.allocator.alloc(u8, lgt_diff);
                defer globals.allocator.free(to_add);
                try self.addToFile(to_add, pos_start_tag_ids);
            } else {
                const lgt_diff = (current_tags.items.len - new_tags.items.len) * 2;
                try self.removeFromFile(lgt_diff, pos_start_tag_ids);
            }

            try globals.data_file.seekTo(pos_start_tag_ids);
            for (new_tags.items) |new_tag| {
                try globals.data_file.writer().writeInt(u16, new_tag, little_end);
            }
        }
    }

    /// Update the timer of a thing
    pub fn updateTimer(self: *DataFileWriter, input: dt.TimerToUpdate, id_thing: u19) !void {
        _ = self;

        const thing = try globals.dfr.getThing(id_thing);
        defer thing.deinit();
        const pos_thing = try globals.dfr.getPosThing(id_thing);

        const start_pos_timers = pos_thing + dt.lgt_fixed_thing + thing.name.len + thing.tags.len * 2;
        try globals.data_file.seekTo(start_pos_timers);

        // go through all timers to look for the one to update
        for (0..thing.timers.len) |_| {
            var timer = dt.getTimerFromInt(try globals.data_file.reader().readInt(u48, little_end));

            if (timer.id == input.id) {
                // if there is an specific duration to set
                if (input.duration) |dur| {
                    timer.duration = dur;
                }

                // if there is a duration offset we need to apply
                if (input.duration_off) |dur_off| {
                    if (input.add_duration_off) {
                        // check the offset is not too much
                        if ((std.math.maxInt(u12) - timer.duration) < dur_off) {
                            return DataOperationError.DurationAboveMax;
                        } else {
                            timer.duration += dur_off;
                        }
                    } else {
                        // check the offset is not too much
                        if (timer.duration < dur_off) {
                            return DataOperationError.DurationBelowMin;
                        } else {
                            timer.duration -= dur_off;
                        }
                    }
                }

                // if there is a start offset we need to apply
                if (input.start_off) |start_off| {
                    if (input.add_start_off) {
                        // check the offset is not too much
                        // potentially this timer will start in the future
                        if ((std.math.maxInt(u25) - timer.start) < start_off) {
                            return DataOperationError.DurationAboveMax;
                        } else {
                            timer.start += start_off;
                        }
                    } else {
                        // check the offset is not too much
                        if (timer.start < start_off) {
                            return DataOperationError.DurationBelowMin;
                        } else {
                            timer.start -= start_off;
                        }
                    }
                }

                // write the new data for the timer over the old
                try globals.data_file.seekBy(-dt.lgt_fixed_timer);
                const raw_int_to_write = dt.getIntFromTimer(timer);
                try globals.data_file.writer().writeInt(u48, raw_int_to_write, little_end);
                return;
            }
        }

        // if we reach this point we did not found the timer to update
        return DataOperationError.TimerNotFound;
    }
};
