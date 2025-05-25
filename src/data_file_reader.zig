const std = @import("std");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const time_helper = @import("time_helper.zig");
const ft = @import("function_types.zig");

const little_end = std.builtin.Endian.little;

pub const DataParsingError = error{
    TagNotFound,
    ThingNotFound,
};

// amount of data we read from the file at once
pub const lgt_buf_read_from_file = 2024;

fn addTagToList(tag: dt.Tag, arr: *std.ArrayList(dt.Tag)) void {
    const dup_tag = tag.dupe();

    arr.*.append(dup_tag) catch |err| {
        std.debug.print("ERROR: while trying to add a tag to a list during parsing: {}\n", .{err});
    };
}

fn addThingToList(thing: dt.Thing, arr: *std.ArrayList(dt.Thing)) void {
    const dup_thing = thing.dupe();

    arr.*.append(dup_thing) catch |err| {
        std.debug.print("ERROR: while trying to add a thing to a list during parsing: {}\n", .{err});
    };
}

/// Structure used to parse the data file
pub const DataFileReader = struct {
    /// contains what is read from the file
    buf_read_from_file: [lgt_buf_read_from_file]u8 = undefined,
    /// number of bytes read from the file and present in buf_read_from_file
    num_bytes_read_from_file: usize = 0,
    /// same as num_bytes_read_from_file but this number is not reset with a new read from the file
    total_num_bytes_read_from_file: usize = 0,
    /// number of bytes we already processed from buf_read_from_file
    idx_buf_read_from_file: usize = 0,
    /// contains the item we are currently working on
    buf_cur_item: [65536]u8 = undefined,
    /// used to keep track of how much the buffer for the current item is filled
    idx_buf_cur_item: usize = 0,

    /// Get the required amount of bytes from the file into buf_cur_item
    fn getCurItem(self: *DataFileReader, size: usize) void {
        self.idx_buf_cur_item = 0;
        const left_in_buf_read_from_file_before = self.num_bytes_read_from_file - self.idx_buf_read_from_file;

        // if there is enough data left in the buf_read_from_file, we just use it
        if (left_in_buf_read_from_file_before >= size) {
            const start_brff = self.idx_buf_read_from_file;
            const end_brff = self.idx_buf_read_from_file + size;

            std.mem.copyForwards(u8, self.buf_cur_item[0..size], self.buf_read_from_file[start_brff..end_brff]);
            self.idx_buf_read_from_file += size;
            self.idx_buf_cur_item += size;
        } else {
            // if there is not enough data left in the buf_read_from_file, we need
            // to use what we can and read again in the data file to get the rest
            const start_brff = self.idx_buf_read_from_file;
            const end_brff = self.num_bytes_read_from_file;

            std.mem.copyForwards(u8, self.buf_cur_item[0..left_in_buf_read_from_file_before], self.buf_read_from_file[start_brff..end_brff]);
            const left_to_copy = size - left_in_buf_read_from_file_before;

            // read again from the data file
            self.num_bytes_read_from_file = globals.data_file.reader().readAll(&self.buf_read_from_file) catch |err| {
                std.debug.panic("getCurItem - Impossible to read data file: {}", .{err});
            };
            self.total_num_bytes_read_from_file += self.num_bytes_read_from_file;

            // check if we read enough to complete the current item and if
            // there are still data to read from the file later
            if (self.num_bytes_read_from_file < (size - left_in_buf_read_from_file_before)) {
                std.debug.panic("getCurItem - Not enough data left in the file", .{});
            }

            self.idx_buf_read_from_file = 0;

            // add what was missing to the current item
            std.mem.copyForwards(u8, self.buf_cur_item[left_in_buf_read_from_file_before..size], self.buf_read_from_file[0..left_to_copy]);
            self.idx_buf_read_from_file += left_to_copy;
            self.idx_buf_cur_item += size;
        }
    }

    /// Return the current timer section of the data file
    /// Put the cursor position back where it was after
    pub fn getCurrentTimer(self: *DataFileReader) !dt.CurrentTimer {
        _ = self;
        const cur_pos = try globals.data_file.getPos();

        try globals.data_file.seekFromEnd(-dt.lgt_fixed_current_timer);
        const raw_cur_timer_int = try globals.data_file.reader().readInt(u56, little_end);

        try globals.data_file.seekTo(cur_pos);
        return dt.getCurrentTimerFromInt(raw_cur_timer_int);
    }

    /// Return the fixed part the specified tag
    /// Leaves the data file cursor at the position after the returned fixed part
    pub fn getFixedPartTag(self: *DataFileReader, name: []const u8) !dt.FixedPartTag {
        if (self.getPosTag(name)) |tag_pos| {
            try globals.data_file.seekTo(tag_pos);
        } else |err| {
            return err;
        }

        const raw_fpt_int = try globals.data_file.reader().readInt(u24, little_end);
        return dt.getTagFixedPartFromInt(raw_fpt_int);
    }

    /// Return the fixed part the specified tag
    /// Leaves the data file cursor at the position after the returned fixed part
    pub fn getFixedPartTagFromId(self: *DataFileReader, id: u16) !dt.FixedPartTag {
        if (self.getPosTagFromId(id)) |tag_pos| {
            try globals.data_file.seekTo(tag_pos);
        } else |err| {
            return err;
        }

        const raw_fpt_int = try globals.data_file.reader().readInt(u24, little_end);
        return dt.getTagFixedPartFromInt(raw_fpt_int);
    }

    /// Return the fixed part the specified thing
    /// Leaves the data file cursor at the position after the returned fixed part
    pub fn getFixedPartThing(self: *DataFileReader, id: u19) !dt.FixedPartThing {
        if (self.getPosThing(id)) |thing_pos| {
            try globals.data_file.seekTo(thing_pos);
        } else |err| {
            return err;
        }

        const raw_fpt_int = try globals.data_file.reader().readInt(u136, little_end);
        return dt.getThingFixedPartFromInt(raw_fpt_int);
    }

    /// Return the starting position of the tag with the specified name
    /// Put the cursor position back where it was after
    pub fn getPosTag(self: *DataFileReader, name: []const u8) !u64 {
        const cur_pos = try globals.data_file.getPos();

        try globals.data_file.seekTo(0);
        const r = globals.data_file.reader();

        _ = try r.readInt(u64, little_end);
        const num_tags_in_file = try r.readInt(u16, little_end);

        self.idx_buf_read_from_file = 0;
        self.num_bytes_read_from_file = 0;
        self.total_num_bytes_read_from_file = 0;

        const pos_first_tag = try globals.data_file.getPos();

        for (0..num_tags_in_file) |_| {
            const start_pos_tag: usize = if (self.total_num_bytes_read_from_file > 0)
                pos_first_tag + (self.total_num_bytes_read_from_file - (self.num_bytes_read_from_file - self.idx_buf_read_from_file))
            else
                try globals.data_file.getPos();

            // get the fixed part of the tag
            self.getCurItem(dt.lgt_fixed_tag);

            // extract data from the fixed part
            const int_fpt = std.mem.readInt(u24, self.buf_cur_item[0..dt.lgt_fixed_tag], little_end);
            const fpt = dt.getTagFixedPartFromInt(int_fpt);
            self.getCurItem(fpt.lgt_name);

            // stop here if it's the correct ID
            if (std.mem.eql(u8, name, self.buf_cur_item[0..fpt.lgt_name])) {
                return start_pos_tag;
            }
        }

        try globals.data_file.seekTo(cur_pos);
        return DataParsingError.TagNotFound;
    }

    /// Return the starting position of the tag with the specified id
    /// Put the cursor position back where it was after
    pub fn getPosTagFromId(self: *DataFileReader, id: u16) !u64 {
        const cur_pos = try globals.data_file.getPos();

        try globals.data_file.seekTo(0);
        const r = globals.data_file.reader();

        _ = try r.readInt(u64, little_end);
        const num_tags_in_file = try r.readInt(u16, little_end);

        self.idx_buf_read_from_file = 0;
        self.num_bytes_read_from_file = 0;
        self.total_num_bytes_read_from_file = 0;

        const pos_first_tag = try globals.data_file.getPos();

        for (0..num_tags_in_file) |_| {
            const start_pos_tag: usize = if (self.total_num_bytes_read_from_file > 0)
                pos_first_tag + (self.total_num_bytes_read_from_file - (self.num_bytes_read_from_file - self.idx_buf_read_from_file))
            else
                try globals.data_file.getPos();

            // get the fixed part of the tag
            self.getCurItem(dt.lgt_fixed_tag);

            // extract data from the fixed part
            const int_fpt = std.mem.readInt(u24, self.buf_cur_item[0..dt.lgt_fixed_tag], little_end);
            const fpt = dt.getTagFixedPartFromInt(int_fpt);
            self.getCurItem(fpt.lgt_name);

            // stop here if it's the correct ID
            if (fpt.id == id) {
                return start_pos_tag;
            }
        }

        try globals.data_file.seekTo(cur_pos);
        return DataParsingError.TagNotFound;
    }

    /// Return the starting position of the thing with the specified ID
    /// Put the cursor position back where it was after
    pub fn getPosThing(self: *DataFileReader, id: u19) !u64 {
        const cur_pos = try globals.data_file.getPos();

        try globals.data_file.seekTo(0);
        const r = globals.data_file.reader();

        const lgt_tag_section = try r.readInt(u64, little_end);
        try globals.data_file.seekTo(lgt_tag_section);
        const num_things_in_file: u24 = try r.readInt(u24, little_end);

        self.idx_buf_read_from_file = 0;
        self.num_bytes_read_from_file = 0;
        self.total_num_bytes_read_from_file = 0;

        const pos_first_thing = try globals.data_file.getPos();

        for (0..num_things_in_file) |_| {
            const start_pos_thing: usize = if (self.total_num_bytes_read_from_file > 0)
                pos_first_thing + (self.total_num_bytes_read_from_file - (self.num_bytes_read_from_file - self.idx_buf_read_from_file))
            else
                try globals.data_file.getPos();

            // get the fixed part of the thing
            self.getCurItem(dt.lgt_fixed_thing);

            // extract data from the fixed part
            const int_fpt = std.mem.readInt(u136, self.buf_cur_item[0..dt.lgt_fixed_thing], little_end);
            const fpt = dt.getThingFixedPartFromInt(int_fpt);

            // stop here if it's the correct ID
            if (fpt.id == id) {
                return start_pos_thing;
            }

            const lgt_variable_thing: u16 = fpt.lgt_name + fpt.num_tags * 2 + fpt.num_timers * 6;
            self.getCurItem(lgt_variable_thing);
        }

        try globals.data_file.seekTo(cur_pos);
        return DataParsingError.ThingNotFound;
    }

    /// Get the name of a tag from it's ID
    /// Put the cursor position back where it was after
    pub fn getTagNameFromId(self: *DataFileReader, buf_name: []u8, id: u16) ![]const u8 {
        const cur_pos = try globals.data_file.getPos();
        const r = globals.data_file.reader();

        if (self.getPosTagFromId(id)) |tag_pos| {
            try globals.data_file.seekTo(tag_pos);

            const raw_fpt_int = try r.readInt(u24, little_end);
            const fpt = dt.getTagFixedPartFromInt(raw_fpt_int);

            const lgt_read_name = try r.read(buf_name[0..fpt.lgt_name]);

            try globals.data_file.seekTo(cur_pos);
            return buf_name[0..lgt_read_name];
        } else |err| {
            try globals.data_file.seekTo(cur_pos);
            return err;
        }
    }

    // Return the highest priority among the tags associated to a thing
    // Put the cursor position back where it was after
    pub fn getHighestPriorityOfThing(self: *DataFileReader, tag_ids: []const u16) !u2 {
        const cur_pos = try globals.data_file.getPos();

        var highest_prio: u2 = 0;
        for (tag_ids) |t_id| {
            const fpt = try self.getFixedPartTagFromId(t_id);
            if (fpt.status > highest_prio) {
                highest_prio = fpt.status;
            }
        }

        try globals.data_file.seekTo(cur_pos);
        return highest_prio;
    }

    /// Populate the given array list with all the tag IDs associated to the specified thing
    /// Put the cursor position back where it was after
    pub fn getTagsOfThing(self: *DataFileReader, id: u19, tags: *std.ArrayList(u16)) !void {
        const cur_pos = try globals.data_file.getPos();

        if (self.getPosThing(id)) |pos_thing| {
            try globals.data_file.seekTo(pos_thing);
            const fpt_int = try globals.data_file.reader().readInt(u136, little_end);
            const fpt = dt.getThingFixedPartFromInt(fpt_int);

            _ = self.getCurItem(fpt.lgt_name);

            for (0..fpt.num_tags) |_| {
                self.getCurItem(2);
                try tags.*.append(std.mem.readInt(u16, self.buf_cur_item[0..2], little_end));
            }
        } else |err| {
            try globals.data_file.seekTo(cur_pos);
            return err;
        }

        try globals.data_file.seekTo(cur_pos);
    }

    /// Get the full infos on the specified thing. Caller owns memory for "name", "tags" and "timers"
    /// Put the cursor position back where it was after
    pub fn getThing(self: *DataFileReader, id: u19) !dt.Thing {
        const cur_pos = try globals.data_file.getPos();
        const fpt = try self.getFixedPartThing(id);

        var to_ret = dt.Thing{
            .id = fpt.id,
            .creation = fpt.creation,
            .kickoff = fpt.kickoff,
            .estimation = fpt.estimation,
            .closure = fpt.closure,
            .status = @enumFromInt(fpt.status),
            .name = undefined,
            .tags = undefined,
            .timers = undefined,
        };

        const lgt_var_data = fpt.lgt_name + fpt.num_tags * 2 + fpt.num_timers * 6;
        const var_data = try globals.allocator.alloc(u8, lgt_var_data);
        defer globals.allocator.free(var_data);
        _ = try globals.data_file.readAll(var_data);

        const vpt = try getThingVariablePartFromData(self, fpt.lgt_name, fpt.num_timers, fpt.num_tags, var_data);

        to_ret.name = vpt.name;
        to_ret.tags = vpt.tags;
        to_ret.timers = vpt.timers;

        try globals.data_file.seekTo(cur_pos);
        return to_ret;
    }

    /// Get the variable thing infos from the specified data
    /// Caller owns memory for the returned data
    pub fn getThingVariablePartFromData(self: *DataFileReader, lgt_name: u8, num_timers: u11, num_tags: u6, data: []const u8) !dt.VariablePartThing {
        _ = self;

        var to_ret: dt.VariablePartThing = .{
            .name = try globals.allocator.dupe(u8, data[0..lgt_name]),
            .tags = undefined,
            .timers = undefined,
        };

        // get the array of tag ids associated to the thing
        to_ret.tags = try globals.allocator.alloc(u16, num_tags);
        var cur_idx_tag = lgt_name;

        for (0..num_tags) |i| {
            to_ret.tags[i] = std.mem.readInt(u16, data[cur_idx_tag..][0..2], little_end);
            cur_idx_tag += 2;
        }

        // get the array of timers associated to the thing
        to_ret.timers = globals.allocator.alloc(dt.Timer, num_timers) catch unreachable;
        var cur_idx_timer = cur_idx_tag;

        for (0..num_timers) |i| {
            const raw_timer_int = std.mem.readInt(u48, data[cur_idx_timer..][0..6], little_end);
            const timer = dt.getTimerFromInt(raw_timer_int);

            to_ret.timers[i] = .{
                .id = timer.id,
                .duration = timer.duration,
                .start = timer.start,
            };

            cur_idx_timer += 6;
        }

        return to_ret;
    }

    /// Parse the tags section of the data file and callback a function with the content of each tag
    /// Put the cursor position back where it was after
    pub fn parseTags(self: *DataFileReader, cb: ft.TagParsingCallbacks) !void {
        const cur_pos = try globals.data_file.getPos();

        try globals.data_file.seekTo(0);
        const r = globals.data_file.reader();

        self.idx_buf_read_from_file = 0;
        self.num_bytes_read_from_file = 0;

        _ = try r.readInt(u64, little_end);

        // get the number of tags present in the data file
        const num_tags_in_file: u16 = try r.readInt(u16, little_end);

        for (0..num_tags_in_file) |_| {
            // get the fixed part of the tag
            self.getCurItem(dt.lgt_fixed_tag);
            const int_fpt = std.mem.readInt(u24, self.buf_cur_item[0..dt.lgt_fixed_tag], little_end);
            const fpt = dt.getTagFixedPartFromInt(int_fpt);
            self.getCurItem(fpt.lgt_name);

            const tag: dt.Tag = .{
                .id = fpt.id,
                .status = @enumFromInt(fpt.status),
                .name = self.buf_cur_item[0..fpt.lgt_name],
            };

            switch (cb) {
                .AddTagToArrayList => |cb_handler| {
                    cb_handler.func(tag, cb_handler.tag_array);
                },
                .AddTagToSortToArrayList => |cb_handler| {
                    cb_handler.func(tag, cb_handler.tag_array);
                },
            }
        }

        try globals.data_file.seekTo(cur_pos);
    }

    /// Parse the things section of the data file and callback a function with the content of each thing
    /// Put the cursor position back where it was after
    pub fn parseThings(self: *DataFileReader, cb: ft.ThingParsingCallbacks) !void {
        const cur_pos = try globals.data_file.getPos();

        try globals.data_file.seekTo(0);
        const r = globals.data_file.reader();

        self.idx_buf_read_from_file = 0;
        self.num_bytes_read_from_file = 0;
        self.total_num_bytes_read_from_file = 0;

        const lgt_tag_section = try r.readInt(u64, little_end);
        try globals.data_file.seekTo(lgt_tag_section);
        const num_things_in_file: u24 = try r.readInt(u24, little_end);

        const pos_first_thing = try globals.data_file.getPos();

        for (0..num_things_in_file) |_| {
            const start_pos_thing: usize = if (self.total_num_bytes_read_from_file > 0)
                pos_first_thing + (self.total_num_bytes_read_from_file - (self.num_bytes_read_from_file - self.idx_buf_read_from_file))
            else
                try globals.data_file.getPos();

            // get the fixed part of the thing
            self.getCurItem(dt.lgt_fixed_thing);
            const int_fpt = std.mem.readInt(u136, self.buf_cur_item[0..dt.lgt_fixed_thing], little_end);
            const fpt = dt.getThingFixedPartFromInt(int_fpt);

            // get the variable part of the thing
            const lgt_variable_thing: usize = fpt.lgt_name + @as(usize, fpt.num_tags) * 2 + @as(usize, fpt.num_timers) * 6;
            self.getCurItem(lgt_variable_thing);

            const vpt = try getThingVariablePartFromData(self, fpt.lgt_name, fpt.num_timers, fpt.num_tags, self.buf_cur_item[0..lgt_variable_thing]);

            const thing: dt.Thing = .{
                .id = fpt.id,
                .creation = fpt.creation,
                .kickoff = fpt.kickoff,
                .estimation = fpt.estimation,
                .closure = fpt.closure,
                .status = @enumFromInt(fpt.status),
                .name = vpt.name,
                .tags = vpt.tags,
                .timers = vpt.timers,
            };

            switch (cb) {
                .AddThingToSortToArrayList => |cb_handler| {
                    cb_handler.func(thing, cb_handler.thing_array);
                },
                .AddThingToArrayList => |cb_handler| {
                    cb_handler.func(thing, cb_handler.thing_array);
                },
                .CheckThingForTagAssociation => |cb_handler| {
                    cb_handler.func(thing, cb_handler.tag_id, cb_handler.num_open, cb_handler.num_closed);
                },
                .GetPosThingAssociatedToTag => |cb_handler| {
                    cb_handler.func(thing, cb_handler.tag_id, cb_handler.pos_array, start_pos_thing);
                },
            }

            thing.deinit();
        }

        try globals.data_file.seekTo(cur_pos);
    }

    /// Parse the entire data file
    pub fn getFullData(self: *DataFileReader) !dt.FullData {
        var fd: dt.FullData = .{};
        fd.init();

        try self.parseTags(.{ .AddTagToArrayList = .{
            .func = addTagToList,
            .tag_array = &fd.tags,
        } });

        try self.parseThings(.{ .AddThingToArrayList = .{
            .func = addThingToList,
            .thing_array = &fd.things,
        } });

        fd.cur_timer = try self.getCurrentTimer();

        return fd;
    }
};
