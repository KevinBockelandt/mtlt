const std = @import("std");
const globals = @import("globals.zig");

const little_end = std.builtin.Endian.little;

// length (in bytes) of fixed length data in the tags of the data file
pub const lgt_fixed_tag = 3;
// length (in bytes) of fixed length data in the things of the data file
pub const lgt_fixed_thing = 17;
// length (in bytes) of fixed length data in a timer
pub const lgt_fixed_timer = 6;
// length (in bytes) of the current timer section of the data file
pub const lgt_fixed_current_timer = 7;

/// Potential statuses a Tag or Thing can be in
pub const Status = enum(u1) {
    ongoing = 0,
    closed = 1,
};

/// Describes the structure of the current timer section of the data file
pub const CurrentTimer = struct {
    id_thing: u19,
    id_last_timer: u11,
    start: u25,
};

/// Durations in the application
pub const Duration = struct {
    minutes: u32 = 0,
    hours: u32 = 0,
};

/// The structure of a tag element in the data file
pub const Tag = struct {
    id: u16,
    status: Status = Status.ongoing,
    name: []const u8,

    pub fn deinit(self: *const Tag, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

/// The fixed part of a tag
pub const FixedPartTag = struct {
    lgt_name: u7 = 0,
    status: u1 = 0,
    id: u16 = 0,
};

/// The fixed part of a thing
pub const FixedPartThing = struct {
    lgt_name: u8 = 0,
    id: u19 = 0,
    num_timers: u11 = 0,
    num_tags: u6 = 0,
    status: u1 = 0,
    creation: u25 = 0,
    target: u25 = 0,
    estimation: u16 = 0,
    closure: u25 = 0,
};

/// The variable part of a thing
pub const VariablePartThing = struct {
    name: []const u8 = undefined,
    tags: []u16 = undefined,
    timers: []Timer = undefined,
};

/// Describes the structure of a thing element in the data file
pub const Thing = struct {
    id: u19 = 0,
    creation: u25 = 0,
    target: u25 = 0,
    estimation: u16 = 0,
    closure: u25 = 0,
    status: Status = Status.ongoing,
    name: []const u8 = undefined,
    tags: []u16 = undefined,
    timers: []Timer = undefined,

    pub fn deinit(self: *const Thing, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.tags);
        allocator.free(self.timers);
    }
};

/// The complete content of a data file
pub const FullData = struct {
    tags: std.ArrayList(Tag) = undefined,
    things: std.ArrayList(Thing) = undefined,
    cur_timer: CurrentTimer = .{
        .id_thing = 0,
        .id_last_timer = 0,
        .start = 0,
    },

    pub fn init(self: *FullData) void {
        self.tags = std.ArrayList(Tag).init(globals.allocator);
        self.things = std.ArrayList(Thing).init(globals.allocator);
    }

    pub fn deinit(self: *FullData) void {
        globals.allocator.free(self.tags);
        globals.allocator.free(self.things);
    }
};

/// Association of a tag and a sorting coefficient
pub const TagToSort = struct {
    tag: Tag = undefined,
    num_ongoing_things_associated: u24 = 0,
    num_closed_things_associated: u24 = 0,
    coef: u64 = 0,

    pub fn deinit(self: *const TagToSort, allocator: std.mem.Allocator) void {
        self.tag.deinit(allocator);
    }
};

/// Association of a thing and a sorting coefficient
pub const ThingToSort = struct {
    thing: Thing = undefined,
    coef: u64 = 0,

    pub fn deinit(self: *const ThingToSort, allocator: std.mem.Allocator) void {
        self.thing.deinit(allocator);
    }
};

/// What needs to be displayed to the user regarding a thing creation operation
pub const ThingCreated = struct {
    id: u19 = 0,
    created_tags: std.ArrayList([]u8) = undefined,
};

/// What needs to be updated in a thing
pub const ThingToUpdate = struct {
    id: u19 = 0,
    target: ?u25 = null,
    estimation: ?u16 = null,
    name: ?[]const u8 = null,
    tags: std.ArrayList([]u8) = undefined,
};

/// The structure of a timer element in the data file
pub const Timer = struct {
    id: u11,
    duration: u12,
    start: u25,
};

/// What needs to be updated in a timer
pub const TimerToUpdate = struct {
    id: u11,
    duration: ?u12 = null,
    duration_off: ?u12 = null,
    add_duration_off: bool = false,
    start_off: ?u25 = null,
    add_start_off: bool = false,
};

// masks used to extract data from the fixed part of a thing
const mask_fpt_id = 0b0000000011111111111111111110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;
const mask_fpt_num_timers = 0b0000000000000000000000000001111111111100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;
const mask_fpt_num_tags = 0b0000000000000000000000000000000000000011111100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;
const mask_fpt_status = 0b0000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;
const mask_fpt_creation = 0b0000000000000000000000000000000000000000000001111111111111111111111111000000000000000000000000000000000000000000000000000000000000000000;
const mask_fpt_target = 0b0000000000000000000000000000000000000000000000000000000000000000000000111111111111111111111111100000000000000000000000000000000000000000;
const mask_fpt_estimation = 0b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000011111111111111110000000000000000000000000;
const mask_fpt_closure = 0b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001111111111111111111111111;

/// return the data contained in a u136 corresponding to the fixed part of a thing
pub fn getThingFixedPartFromInt(data: u136) FixedPartThing {
    return FixedPartThing{
        .lgt_name = @intCast(data >> 128), // 136 - 8 = 128
        .id = @intCast((data & mask_fpt_id) >> 109), // 128 - 19 = 109
        .num_timers = @intCast((data & mask_fpt_num_timers) >> 98), // 109 - 11 = 98
        .num_tags = @intCast((data & mask_fpt_num_tags) >> 92), // 98 - 6 - 92
        .status = @intCast((data & mask_fpt_status) >> 91), // 92 - 1 = 91
        .creation = @intCast((data & mask_fpt_creation) >> 66), // 91 - 25 = 66
        .target = @intCast((data & mask_fpt_target) >> 41), // 66 - 25 = 41
        .estimation = @intCast((data & mask_fpt_estimation) >> 25), // 41 - 16 - 25
        .closure = @intCast(data & mask_fpt_closure),
    };
}

// masks used to extract data from a tag
const mask_tag_status = 0b000000010000000000000000;
const mask_tag_id = 0b000000001111111111111111;

/// return the data contained in a u24 corresponding to a tag
pub fn getTagFixedPartFromInt(data: u24) FixedPartTag {
    return FixedPartTag{
        .lgt_name = @intCast(data >> 17),
        .status = @intCast((data & mask_tag_status) >> 16),
        .id = @intCast(data & mask_tag_id),
    };
}

// masks used to extract data from a timer
const mask_timer_duration = 0b000000000001111111111110000000000000000000000000;
const mask_timer_start = 0b000000000000000000000001111111111111111111111111;

/// return the data contained in a u48 corresponding to a timer
pub fn getTimerFromInt(data: u48) Timer {
    return Timer{
        .id = @intCast(data >> 37),
        .duration = @intCast((data & mask_timer_duration) >> 25),
        .start = @intCast(data & mask_timer_start),
    };
}

// masks used to extract data from the current timer
const mask_cur_timer_last_timer_id = 0b00000000000000000001111111111100000000000000000000000000;
const mask_cur_timer_start = 0b00000000000000000000000000000011111111111111111111111110;

/// return the data contained in a u48 corresponding to a timer
pub fn getCurrentTimerFromInt(data: u56) CurrentTimer {
    return CurrentTimer{
        .id_thing = @intCast(data >> 37),
        .id_last_timer = @intCast((data & mask_cur_timer_last_timer_id) >> 26),
        .start = @intCast((data & mask_cur_timer_start) >> 1),
    };
}

/// Get a u24 corresponding to the fixed part of a tag
pub fn getIntFromTagFixedPart(fpt: FixedPartTag) u24 {
    var to_ret: u24 = fpt.lgt_name;
    to_ret = to_ret << 1 | fpt.status;
    to_ret = to_ret << 16 | fpt.id;
    return to_ret;
}

/// Get a u136 corresponding to the fixed part of a thing
pub fn getIntFromThingFixedPart(fpt: FixedPartThing) u136 {
    var to_ret: u136 = fpt.lgt_name;
    to_ret = to_ret << 19 | fpt.id;
    to_ret = to_ret << 11 | fpt.num_timers;
    to_ret = to_ret << 6 | fpt.num_tags;
    to_ret = to_ret << 1 | fpt.status;
    to_ret = to_ret << 25 | fpt.creation;
    to_ret = to_ret << 25 | fpt.target;
    to_ret = to_ret << 16 | fpt.estimation;
    to_ret = to_ret << 25 | fpt.closure;
    return to_ret;
}

/// Get a u48 corresponding to the data of a timer
pub fn getIntFromTimer(timer: Timer) u48 {
    var to_ret: u48 = timer.id;
    to_ret = to_ret << 12 | timer.duration;
    to_ret = to_ret << 25 | timer.start;
    return to_ret;
}

/// Get a u56 corresponding to the data of the current timer
pub fn getIntFromCurrentTimer(cur_timer: CurrentTimer) u56 {
    var to_ret: u56 = cur_timer.id_thing;
    to_ret = to_ret << 11 | cur_timer.id_last_timer;
    to_ret = to_ret << 25 | cur_timer.start;
    to_ret = to_ret << 1;
    return to_ret;
}
