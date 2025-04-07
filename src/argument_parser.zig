const std = @import("std");

const ansi = @import("ansi_codes.zig");
const base62_helper = @import("base62_helper.zig");
const dt = @import("data_types.zig");
const dfr = @import("data_file_reader.zig");
const globals = @import("globals.zig");
const table_printer = @import("table_printer.zig");
const time_helper = @import("time_helper.zig");
const string_helper = @import("string_helper.zig");

const little_end = std.builtin.Endian.little;
const colemp = ansi.col_emphasis;
const colres = ansi.col_reset;

var buf_str_id: [4]u8 = undefined;

/// Potential types of errors during argument parsing
pub const ArgumentParsingError = error{
    UnexpectedArgument,
    UnknownFlag,
    CannotParseDuration,
    CannotParseDivisions,
    // flags already parsed
    DivisionsAlreadyParsed,
    DurationAlreadyParsed,
    DurationLessAlreadyParsed,
    DurationMoreAlreadyParsed,
    EmptyAlreadyParsed,
    EndLessAlreadyParsed,
    EstimationAlreadyParsed,
    ExcludeTagsAlreadyParsed,
    KickoffAlreadyParsed,
    KickoffLessAlreadyParsed,
    KickoffMoreAlreadyParsed,
    LimitAlreadyParsed,
    NameAlreadyParsed,
    NoTagsAlreadyParsed,
    PriorityAlreadyParsed,
    RemainLessAlreadyParsed,
    RemainMoreAlreadyParsed,
    StartAlreadyParsed,
    StartLessAlreadyParsed,
    StartMoreAlreadyParsed,
    TagsAlreadyParsed,
    // related to the parsed data
    NoDuration,
    SeveralDurationArgs,
    StartLessAndMore,
};

/// Potential types of command line arguments currently parsed
const ArgType = enum(u8) {
    divisions,
    duration,
    duration_less,
    duration_more,
    empty,
    end_less,
    estimation,
    exclude_tags,
    kickoff,
    kickoff_less,
    kickoff_more,
    limit,
    name,
    no_tags,
    priority,
    remain_less,
    remain_more,
    start,
    start_less,
    start_more,
    tags,
    unknown,
    unknown_flag,
};

/// Potential types of command line arguments currently parsed
const ArgParserState = enum(u8) {
    expecting_divisions,
    expecting_duration,
    expecting_duration_less,
    expecting_duration_more,
    expecting_end_less,
    expecting_estimation,
    expecting_exclude_tags,
    expecting_kickoff,
    expecting_kickoff_less,
    expecting_kickoff_more,
    expecting_limit,
    expecting_name,
    expecting_priority,
    expecting_remain_less,
    expecting_remain_more,
    expecting_start_less,
    expecting_start_more,
    expecting_tags,
    not_expecting,
};

// Display an error received from the parsing of a duration string
fn displayDurationError(t: type, err: std.fmt.ParseIntError) !void {
    switch (err) {
        std.fmt.ParseIntError.Overflow => try globals.printer.errDurationTooBig(t),
        std.fmt.ParseIntError.InvalidCharacter => try globals.printer.errDurationInvalidCharacter(),
    }

    return ArgumentParsingError.CannotParseDuration;
}

/// Return the type of a command line argument
fn getArgType(arg: []const u8) ArgType {
    if (arg.len < 1) {
        return ArgType.empty;
    }

    if (std.mem.eql(u8, arg, "--divisions")) {
        return ArgType.divisions;
    } else if (std.mem.eql(u8, arg, "--end-less")) {
        return ArgType.end_less;
    } else if (std.mem.eql(u8, arg, "--exclude-tags")) {
        return ArgType.exclude_tags;
    } else if (std.mem.eql(u8, arg, "--no-tags")) {
        return ArgType.no_tags;
    } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--duration")) {
        return ArgType.duration;
    } else if (std.mem.eql(u8, arg, "-dl") or std.mem.eql(u8, arg, "--duration-less")) {
        return ArgType.duration_less;
    } else if (std.mem.eql(u8, arg, "-dm") or std.mem.eql(u8, arg, "--duration-more")) {
        return ArgType.duration_more;
    } else if (std.mem.eql(u8, arg, "-e") or std.mem.eql(u8, arg, "--estimation")) {
        return ArgType.estimation;
    } else if (std.mem.eql(u8, arg, "-k") or std.mem.eql(u8, arg, "--kickoff")) {
        return ArgType.kickoff;
    } else if (std.mem.eql(u8, arg, "-km") or std.mem.eql(u8, arg, "--kickoff-more")) {
        return ArgType.kickoff_more;
    } else if (std.mem.eql(u8, arg, "-kl") or std.mem.eql(u8, arg, "--kickoff-less")) {
        return ArgType.kickoff_less;
    } else if (std.mem.eql(u8, arg, "-l") or std.mem.eql(u8, arg, "--limit")) {
        return ArgType.limit;
    } else if (std.mem.eql(u8, arg, "-n") or std.mem.eql(u8, arg, "--name")) {
        return ArgType.name;
    } else if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--priority")) {
        return ArgType.priority;
    } else if (std.mem.eql(u8, arg, "-rl") or std.mem.eql(u8, arg, "--remain-less")) {
        return ArgType.remain_less;
    } else if (std.mem.eql(u8, arg, "-rm") or std.mem.eql(u8, arg, "--remain-more")) {
        return ArgType.remain_more;
    } else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--start")) {
        return ArgType.start;
    } else if (std.mem.eql(u8, arg, "-sl") or std.mem.eql(u8, arg, "--start-less")) {
        return ArgType.start_less;
    } else if (std.mem.eql(u8, arg, "-sm") or std.mem.eql(u8, arg, "--start-more")) {
        return ArgType.start_more;
    } else if (std.mem.eql(u8, arg, "-t") or std.mem.eql(u8, arg, "--tags")) {
        return ArgType.tags;
    } else if (arg[0] == '-') {
        return ArgType.unknown_flag;
    } else {
        return ArgType.unknown;
    }
}

/// Display the content of a nullable int (for debug purposes)
fn printNullableInt(T: type, to_print: T, text: []const u8) void {
    if (to_print) |val| {
        std.debug.print(" - {s}: {d}\n", .{ text, val });
    } else {
        std.debug.print(" - {s}: NULL\n", .{text});
    }
}

pub const ArgumentParser = struct {
    /// the main thing regarding the command (an id to work on, the name of a thing to add, etc.)
    payload: ?[]const u8 = null,
    divisions: ?u4 = null, // --divisions
    duration: ?u12 = null, // --duration
    duration_less: ?u12 = null, // --duration-less
    duration_more: ?u12 = null, // --duration-more
    end_less: ?u25 = null, // --end-less
    estimation: ?u16 = null, // --estimation
    excluded_tags: std.ArrayList([]u8) = undefined, // --exclude-tags
    kickoff: ?u25 = null, // --kickoff
    kickoff_less: ?u25 = null, // --kickoff-less
    kickoff_more: ?u25 = null, // --kickoff-more
    limit: ?u32 = null, // --limit
    name: ?[]const u8 = null, // --name
    no_tags: bool = false, // --no-tags
    priority: ?dt.StatusTag = null, // --priority
    remain_less: ?u16 = null, // --remain-less
    remain_more: ?u16 = null, // --remain-more
    should_start: bool = false, // --start
    start_less: ?u25 = null, // --start-less
    start_more: ?u25 = null, // --start-more
    tags: std.ArrayList([]u8) = undefined, // --tags

    current_state: ArgParserState = ArgParserState.not_expecting,

    divisions_already_parsed: bool = false,
    duration_already_parsed: bool = false,
    duration_less_already_parsed: bool = false,
    duration_more_already_parsed: bool = false,
    end_less_already_parsed: bool = false,
    estimation_already_parsed: bool = false,
    excluded_tags_already_parsed: bool = false,
    kickoff_already_parsed: bool = false,
    kickoff_less_already_parsed: bool = false,
    kickoff_more_already_parsed: bool = false,
    limit_already_parsed: bool = false,
    name_already_parsed: bool = false,
    priority_already_parsed: bool = false,
    payload_already_parsed: bool = false,
    remain_less_already_parsed: bool = false,
    remain_more_already_parsed: bool = false,
    should_start_already_parsed: bool = false,
    start_less_already_parsed: bool = false,
    start_more_already_parsed: bool = false,
    tags_already_parsed: bool = false,

    divisions_flag_already_parsed: bool = false,
    duration_flag_already_parsed: bool = false,
    duration_less_flag_already_parsed: bool = false,
    duration_more_flag_already_parsed: bool = false,
    end_less_flag_already_parsed: bool = false,
    estimation_flag_already_parsed: bool = false,
    excluded_tags_flag_already_parsed: bool = false,
    kickoff_flag_already_parsed: bool = false,
    kickoff_less_flag_already_parsed: bool = false,
    kickoff_more_flag_already_parsed: bool = false,
    limit_flag_already_parsed: bool = false,
    name_flag_already_parsed: bool = false,
    priority_flag_already_parsed: bool = false,
    remain_less_flag_already_parsed: bool = false,
    remain_more_flag_already_parsed: bool = false,
    should_flag_start_already_parsed: bool = false,
    start_less_flag_already_parsed: bool = false,
    start_more_flag_already_parsed: bool = false,
    tags_flag_already_parsed: bool = false,

    at_least_1_arg_parsed_after_flag: bool = false,

    /// Switch the parser to the expecting_tags state
    fn switchExpectingTags(self: *ArgumentParser) !void {
        if (!self.tags_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_tags;
            self.tags_flag_already_parsed = true;
        } else {
            try globals.printer.errMultipleFlagsShortLong("-t", "--tags");
            return ArgumentParsingError.TagsAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_tags state
    fn switchExpectingExcludeTags(self: *ArgumentParser) !void {
        if (!self.excluded_tags_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_exclude_tags;
            self.excluded_tags_flag_already_parsed = true;
        } else {
            try globals.printer.errMultipleFlagsLong("--exclude-tags");
            return ArgumentParsingError.ExcludeTagsAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_divisions state
    fn switchExpectingDivisions(self: *ArgumentParser) !void {
        if (!self.divisions_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_divisions;
            self.divisions_flag_already_parsed = true;
        } else {
            try globals.printer.errMultipleFlagsLong("--divisions");
            return ArgumentParsingError.DivisionsAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_estimation state
    fn switchExpectingEstimation(self: *ArgumentParser) !void {
        if (!self.estimation_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_estimation;
            self.estimation_flag_already_parsed = true;
        } else {
            try globals.printer.errMultipleFlagsShortLong("-e", "--estimation");
            return ArgumentParsingError.EstimationAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_remain_less state
    fn switchExpectingRemainLess(self: *ArgumentParser) !void {
        if (!self.remain_less_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_remain_less;
            self.remain_less_flag_already_parsed = true;
        } else {
            try globals.printer.errMultipleFlagsShortLong("-rl", "--remain-less");
            return ArgumentParsingError.RemainLessAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_remain_more state
    fn switchExpectingRemainMore(self: *ArgumentParser) !void {
        if (!self.remain_more_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_remain_more;
            self.remain_more_flag_already_parsed = true;
        } else {
            try globals.printer.errMultipleFlagsShortLong("-rm", "--remain-more");
            return ArgumentParsingError.RemainMoreAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_kickoff state
    fn switchExpectingKickoff(self: *ArgumentParser) !void {
        if (!self.kickoff_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_kickoff;
            self.kickoff_flag_already_parsed = true;
        } else {
            try globals.printer.errMultipleFlagsShortLong("-t", "--kickoff");
            return ArgumentParsingError.KickoffAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_kickoff_more state
    fn switchExpectingKickoffMore(self: *ArgumentParser) !void {
        if (!self.kickoff_more_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_kickoff_more;
            self.kickoff_more_flag_already_parsed = true;
        } else {
            try globals.printer.errMultipleFlagsShortLong("-tm", "--kickoff-more");
            return ArgumentParsingError.KickoffMoreAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_kickoff_less state
    fn switchExpectingKickoffLess(self: *ArgumentParser) !void {
        if (!self.kickoff_less_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_kickoff_less;
            self.kickoff_less_flag_already_parsed = true;
        } else {
            try globals.printer.errMultipleFlagsShortLong("-tl", "--kickoff-less");
            return ArgumentParsingError.KickoffLessAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_start_more state
    fn switchExpectingStartMore(self: *ArgumentParser) !void {
        if (!self.start_more_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_start_more;
            self.start_more_flag_already_parsed = true;
        } else {
            try globals.printer.errMultipleFlagsShortLong("-sm", "--start-more");
            return ArgumentParsingError.StartMoreAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_start_less state
    fn switchExpectingStartLess(self: *ArgumentParser) !void {
        if (!self.start_less_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_start_less;
            self.start_less_flag_already_parsed = true;
        } else {
            try globals.printer.errMultipleFlagsShortLong("-sl", "--start-less");
            return ArgumentParsingError.StartLessAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_duration state
    fn switchExpectingDuration(self: *ArgumentParser) !void {
        if (!self.duration_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_duration;
            self.duration_flag_already_parsed = true;
        } else {
            try globals.printer.errMultipleFlagsShortLong("-d", "--duration");
            return ArgumentParsingError.DurationAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_duration_more state
    fn switchExpectingDurationMore(self: *ArgumentParser) !void {
        if (!self.duration_more_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_duration_more;
            self.duration_more_flag_already_parsed = true;
        } else {
            try globals.printer.errMultipleFlagsShortLong("-dm", "--duration-more");
            return ArgumentParsingError.DurationMoreAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_duration_less state
    fn switchExpectingDurationLess(self: *ArgumentParser) !void {
        if (!self.duration_less_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_duration_less;
            self.duration_less_flag_already_parsed = true;
        } else {
            try globals.printer.errMultipleFlagsShortLong("-dl", "--duration-less");
            return ArgumentParsingError.DurationLessAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_end_less state
    fn switchExpectingEndLess(self: *ArgumentParser) !void {
        if (!self.end_less_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_end_less;
            self.end_less_flag_already_parsed = true;
        } else {
            try globals.printer.errMultipleFlagsLong("--end-less");
            return ArgumentParsingError.EndLessAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_limit_state
    fn switchExpectingLimit(self: *ArgumentParser) !void {
        if (!self.limit_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_limit;
            self.limit_flag_already_parsed = true;
        } else {
            try globals.printer.errMultipleFlagsShortLong("-l", "--limit");
            return ArgumentParsingError.LimitAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_priority
    fn switchExpectingPriority(self: *ArgumentParser) !void {
        if (!self.priority_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_priority;
            self.priority_flag_already_parsed = true;
        } else {
            try globals.printer.errMultipleFlagsShortLong("-p", "--priority");
            return ArgumentParsingError.PriorityAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_name state
    fn switchExpectingName(self: *ArgumentParser) !void {
        if (!self.name_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_name;
            self.name_flag_already_parsed = true;
        } else {
            try globals.printer.errMultipleFlagsShortLong("-n", "--name");
            return ArgumentParsingError.NameAlreadyParsed;
        }
    }

    /// Called when encountering an unexpected argument
    fn unexpectedArgument(self: *ArgumentParser, arg: []const u8) !void {
        _ = self;
        try globals.printer.errUnexpectedArgument(arg);
        return ArgumentParsingError.UnexpectedArgument;
    }

    /// Swith the internal state of the parser according to an argument type
    fn switchToState(self: *ArgumentParser, arg_type: ArgType, arg: []const u8) !void {
        switch (arg_type) {
            ArgType.empty => {},
            ArgType.divisions => try self.switchExpectingDivisions(),
            ArgType.duration => try self.switchExpectingDuration(),
            ArgType.duration_less => try self.switchExpectingDurationLess(),
            ArgType.duration_more => try self.switchExpectingDurationMore(),
            ArgType.end_less => try self.switchExpectingEndLess(),
            ArgType.estimation => try self.switchExpectingEstimation(),
            ArgType.exclude_tags => try self.switchExpectingExcludeTags(),
            ArgType.kickoff => try self.switchExpectingKickoff(),
            ArgType.kickoff_less => try self.switchExpectingKickoffLess(),
            ArgType.kickoff_more => try self.switchExpectingKickoffMore(),
            ArgType.limit => try self.switchExpectingLimit(),
            ArgType.name => try self.switchExpectingName(),
            ArgType.priority => try self.switchExpectingPriority(),
            ArgType.remain_less => try self.switchExpectingRemainLess(),
            ArgType.remain_more => try self.switchExpectingRemainMore(),
            ArgType.start_less => try self.switchExpectingStartLess(),
            ArgType.start_more => try self.switchExpectingStartMore(),
            ArgType.tags => try self.switchExpectingTags(),
            ArgType.unknown => {},
            else => try self.unexpectedArgument(arg),
        }
    }

    pub fn init(self: *ArgumentParser) void {
        self.tags = std.ArrayList([]u8).init(globals.allocator);
        self.excluded_tags = std.ArrayList([]u8).init(globals.allocator);
    }

    pub fn deinit(self: *ArgumentParser) void {
        self.tags.deinit();
        self.excluded_tags.deinit();
    }

    /// Parse the list of arguments to check validity and extract relevant infos
    pub fn parse(self: *ArgumentParser, args: [][:0]u8) !void {
        for (args[0..]) |arg| {
            const cur_arg_type = getArgType(arg);

            // those argument types are handled independently of the current state of the parser
            switch (cur_arg_type) {
                ArgType.unknown_flag => {
                    try globals.printer.errUnexpectedFlag(arg);
                    return ArgumentParsingError.UnknownFlag;
                },
                ArgType.start => {
                    self.should_start = true;
                    self.current_state = ArgParserState.not_expecting;
                    continue;
                },
                ArgType.no_tags => {
                    self.no_tags = true;
                    self.current_state = ArgParserState.not_expecting;
                    continue;
                },
                else => {},
            }

            try self.switchToState(cur_arg_type, arg);

            // handle the argument differently depending on the state the parser is currently in
            switch (self.current_state) {
                ArgParserState.expecting_divisions => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (std.fmt.parseInt(u4, arg, 10)) |parsed_divisions| {
                            self.divisions = @intCast(parsed_divisions);
                            self.divisions_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else |err| {
                            switch (err) {
                                std.fmt.ParseIntError.InvalidCharacter => try globals.printer.errDivisionInvalidCharacter(),
                                std.fmt.ParseIntError.Overflow => try globals.printer.errDivisionTooBig(),
                            }
                            return ArgumentParsingError.CannotParseDivisions;
                        }
                    }
                },
                ArgParserState.expecting_duration => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (self.duration_already_parsed) {
                            try globals.printer.errOptionAlreadyParsed("Duration", arg);
                            return ArgumentParsingError.DurationAlreadyParsed;
                        } else if (std.fmt.parseInt(u12, arg, 10)) |parsed_duration| {
                            self.duration = @intCast(parsed_duration);
                            self.duration_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else |err| {
                            try displayDurationError(u12, err);
                        }
                    }
                },
                ArgParserState.expecting_duration_more => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (self.duration_more_already_parsed) {
                            try globals.printer.errOptionAlreadyParsed("Duration more", arg);
                            return ArgumentParsingError.DurationMoreAlreadyParsed;
                        } else if (std.fmt.parseInt(u12, arg, 10)) |parsed_duration| {
                            self.duration_more = @intCast(parsed_duration);
                            self.duration_more_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else |err| {
                            try displayDurationError(u12, err);
                        }
                    }
                },
                ArgParserState.expecting_duration_less => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (self.duration_less_already_parsed) {
                            try globals.printer.errOptionAlreadyParsed("Duration less", arg);
                            return ArgumentParsingError.DurationLessAlreadyParsed;
                        } else if (std.fmt.parseInt(u12, arg, 10)) |parsed_duration| {
                            self.duration_less = @intCast(parsed_duration);
                            self.duration_less_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else |err| {
                            try displayDurationError(u12, err);
                        }
                    }
                },
                ArgParserState.expecting_end_less => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (self.end_less_already_parsed) {
                            try globals.printer.errOptionAlreadyParsed("End less", arg);
                            return ArgumentParsingError.EndLessAlreadyParsed;
                        } else if (std.fmt.parseInt(u25, arg, 10)) |parsed_end| {
                            self.end_less = @intCast(parsed_end);
                            self.end_less_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else |err| {
                            try displayDurationError(u25, err);
                        }
                    }
                },
                ArgParserState.expecting_estimation => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (self.estimation_already_parsed) {
                            try globals.printer.errOptionAlreadyParsed("Estimation", arg);
                            return ArgumentParsingError.EstimationAlreadyParsed;
                        } else if (std.fmt.parseInt(u16, arg, 10)) |parsed_estimation| {
                            self.estimation = @intCast(parsed_estimation);
                            self.estimation_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else |err| {
                            try displayDurationError(u16, err);
                        }
                    }
                },
                ArgParserState.expecting_remain_more => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (self.remain_more_already_parsed) {
                            try globals.printer.errOptionAlreadyParsed("Remain more", arg);
                            return ArgumentParsingError.RemainMoreAlreadyParsed;
                        } else if (std.fmt.parseInt(u16, arg, 10)) |parsed_remain| {
                            self.remain_more = @intCast(parsed_remain);
                            self.remain_more_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else |err| {
                            try displayDurationError(u16, err);
                        }
                    }
                },
                ArgParserState.expecting_remain_less => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (self.remain_less_already_parsed) {
                            try globals.printer.errOptionAlreadyParsed("Remain less", arg);
                            return ArgumentParsingError.RemainLessAlreadyParsed;
                        } else if (std.fmt.parseInt(u16, arg, 10)) |parsed_remain| {
                            self.remain_less = @intCast(parsed_remain);
                            self.remain_less_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else |err| {
                            try displayDurationError(u16, err);
                        }
                    }
                },
                ArgParserState.expecting_exclude_tags => {
                    if (cur_arg_type == ArgType.unknown) {
                        try self.excluded_tags.append(arg);
                    }
                },
                ArgParserState.expecting_limit => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (self.limit_already_parsed) {
                            try globals.printer.errOptionAlreadyParsed("Limit", arg);
                            return ArgumentParsingError.LimitAlreadyParsed;
                        } else if (std.fmt.parseInt(u32, arg, 10)) |parsed_limit| {
                            self.limit = @intCast(parsed_limit);
                            self.limit_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else |err| {
                            try displayDurationError(u32, err);
                        }
                    }
                },
                ArgParserState.expecting_name => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (!self.name_already_parsed) {
                            self.name = arg;
                            self.name_already_parsed = true;
                        } else {
                            try self.unexpectedArgument(arg);
                        }
                    }
                },
                ArgParserState.expecting_priority => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (self.priority_already_parsed) {
                            try globals.printer.errOptionAlreadyParsed("Priority", arg);
                            return ArgumentParsingError.PriorityAlreadyParsed;
                        } else if (std.mem.eql(u8, arg, "someday")) {
                            self.priority = dt.StatusTag.someday;
                            self.priority_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else if (std.mem.eql(u8, arg, "soon")) {
                            self.priority = dt.StatusTag.soon;
                            self.priority_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else if (std.mem.eql(u8, arg, "now")) {
                            self.priority = dt.StatusTag.now;
                            self.priority_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else {
                            try globals.printer.errInvalidPriority();
                        }
                    }
                },
                ArgParserState.expecting_start_less => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (self.start_less_already_parsed) {
                            try globals.printer.errOptionAlreadyParsed("Start less", arg);
                            return ArgumentParsingError.StartLessAlreadyParsed;
                        } else if (std.fmt.parseInt(u25, arg, 10)) |parsed_start| {
                            self.start_less = @intCast(parsed_start);
                            self.start_less_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else |err| {
                            try displayDurationError(u25, err);
                        }
                    }
                },
                ArgParserState.expecting_start_more => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (self.start_more_already_parsed) {
                            try globals.printer.errOptionAlreadyParsed("Start more", arg);
                            return ArgumentParsingError.StartMoreAlreadyParsed;
                        } else if (std.fmt.parseInt(u25, arg, 10)) |parsed_start| {
                            self.start_more = @intCast(parsed_start);
                            self.start_more_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else |err| {
                            try displayDurationError(u25, err);
                        }
                    }
                },
                ArgParserState.expecting_tags => {
                    if (cur_arg_type == ArgType.unknown) {
                        try self.tags.append(arg);
                    }
                },
                ArgParserState.expecting_kickoff => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (self.kickoff_already_parsed) {
                            try globals.printer.errOptionAlreadyParsed("Kickoff", arg);
                            return ArgumentParsingError.KickoffAlreadyParsed;
                        } else if (std.fmt.parseInt(u25, arg, 10)) |parsed_kickoff| {
                            self.kickoff = @intCast(parsed_kickoff);
                            self.kickoff_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else |err| {
                            try displayDurationError(u25, err);
                        }
                    }
                },
                ArgParserState.expecting_kickoff_more => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (self.kickoff_more_already_parsed) {
                            try globals.printer.errOptionAlreadyParsed("Kickoff more", arg);
                            return ArgumentParsingError.KickoffMoreAlreadyParsed;
                        } else if (std.fmt.parseInt(u25, arg, 10)) |parsed_kickoff| {
                            self.kickoff_more = @intCast(parsed_kickoff);
                            self.kickoff_more_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else |err| {
                            try displayDurationError(u25, err);
                        }
                    }
                },
                ArgParserState.expecting_kickoff_less => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (self.kickoff_less_already_parsed) {
                            try globals.printer.errOptionAlreadyParsed("Kickoff less", arg);
                            return ArgumentParsingError.KickoffLessAlreadyParsed;
                        } else if (std.fmt.parseInt(u25, arg, 10)) |parsed_kickoff| {
                            self.kickoff_less = @intCast(parsed_kickoff);
                            self.kickoff_less_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else |err| {
                            try displayDurationError(u25, err);
                        }
                    }
                },
                ArgParserState.not_expecting => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (!self.payload_already_parsed) {
                            const idx_last = string_helper.getIdxLastNonSpace(arg);
                            self.payload = arg[0 .. idx_last + 1];
                            self.payload_already_parsed = true;
                        } else {
                            try self.unexpectedArgument(arg);
                        }
                    }
                },
            }
        }

        // perform some checks on the parsed data
        if (self.no_tags and self.tags.items.len != 0 and self.excluded_tags.items.len != 0) {
            try globals.printer.errContradictionAllTagsFlags();
            self.tags.clearRetainingCapacity();
            self.excluded_tags.clearRetainingCapacity();
        } else if (self.no_tags and self.tags.items.len != 0) {
            try globals.printer.errContradictionNoTagsTags();
            self.tags.clearRetainingCapacity();
        } else if (self.no_tags and (self.tags.items.len != 0 or self.excluded_tags.items.len != 0)) {
            try globals.printer.errContradictionNoTagsExcludedTags();
            self.excluded_tags.clearRetainingCapacity();
        }
    }

    /// Print the parsed content (for debug puproses)
    pub fn print(self: *ArgumentParser) void {
        std.debug.print("Content of argument parser:\n", .{});

        if (self.payload) |p| {
            std.debug.print(" - Payload: {s}\n", .{p});
        } else {
            std.debug.print(" - Payload: NULL\n", .{});
        }

        if (self.name) |n| {
            std.debug.print(" - Name: {s}\n", .{n});
        } else {
            std.debug.print(" - Name: NULL\n", .{});
        }

        if (self.priority) |p| {
            std.debug.print(" - Priority: {s}\n", .{@tagName(p)});
        } else {
            std.debug.print(" - Priority: NULL\n", .{});
        }

        printNullableInt(?u4, self.divisions, "Divisions");
        printNullableInt(?u12, self.duration, "Duration");
        printNullableInt(?u12, self.duration_less, "Duration Less");
        printNullableInt(?u12, self.duration_more, "Duration More");
        printNullableInt(?u25, self.end_less, "End Less");
        printNullableInt(?u16, self.estimation, "Estimation");
        printNullableInt(?u25, self.kickoff, "Kickoff");
        printNullableInt(?u25, self.kickoff_less, "Kickoff Less");
        printNullableInt(?u25, self.kickoff_more, "Kickoff More");
        printNullableInt(?u16, self.remain_less, "Remain Less");
        printNullableInt(?u16, self.remain_more, "Remain More");
        printNullableInt(?u25, self.start_less, "Start Less");
        printNullableInt(?u25, self.start_more, "Start More");

        if (self.tags.items.len == 0) {
            std.debug.print(" - Tags: EMPTY\n", .{});
        }
        for (self.tags.items) |t| {
            std.debug.print(" - Tags: {s}\n", .{t});
        }

        if (self.excluded_tags.items.len == 0) {
            std.debug.print(" - Excluded Tags: EMPTY\n", .{});
        }
        for (self.excluded_tags.items) |t| {
            std.debug.print(" - Excluded Tags: {s}\n", .{t});
        }

        std.debug.print(" - Should start: {}\n", .{self.should_start});
        std.debug.print(" - No tags: {}\n", .{self.no_tags});
    }

    /// Check that parsed arguments do not contain several types of duration flags
    pub fn checkOnlyOneTypeDurationArg(self: *ArgumentParser) !void {
        if ((self.duration != null and self.duration_less != null) or
            (self.duration != null and self.duration_more != null))
        {
            try globals.printer.errContradictionDurationDurationOffset();
            return ArgumentParsingError.SeveralDurationArgs;
        }

        if (self.duration_less != null and self.duration_more != null) {
            try globals.printer.errContradictionAddRemoveDuration();
            return ArgumentParsingError.SeveralDurationArgs;
        }
    }

    /// Check that parsed arguments do not contain simultaneously duration less and more
    pub fn checkNoDurationLessAndMore(self: *ArgumentParser) !void {
        if (self.duration_less != null and self.duration_more != null) {
            try globals.printer.errContradictionAddRemoveDuration();
            return ArgumentParsingError.DurationLessAndMore;
        }
    }

    /// Check that parsed arguments do not contain simultaneously start offset less and more
    pub fn checkNoStartLessAndMore(self: *ArgumentParser) !void {
        if (self.start_less != null and self.start_more != null) {
            try globals.printer.errContradictionAddRemoveStartTime();
            return ArgumentParsingError.StartLessAndMore;
        }
    }

    /// Check there is a duration argument parsed in the command
    pub fn checkDurationPresence(self: *ArgumentParser) !u12 {
        if (self.duration) |dur| {
            return dur;
        } else {
            try globals.printer.errDurationMissing();
            return ArgumentParsingError.NoDuration;
        }
    }

    /// Compare this instance with another. True if they hold the same data
    pub fn compare(self: *ArgumentParser, other: *ArgumentParser) bool {
        if (self.payload == null and other.payload != null) {
            return false;
        } else if (self.payload != null and other.payload == null) {
            return false;
        } else if (self.payload == null and other.payload == null) {} else {
            if (!std.mem.eql(u8, self.payload.?, other.payload.?)) return false;
        }

        if (self.divisions != other.divisions) return false;
        if (self.duration != other.duration) return false;
        if (self.duration_less != other.duration_less) return false;
        if (self.duration_more != other.duration_more) return false;
        if (self.end_less != other.end_less) return false;
        if (self.estimation != other.estimation) return false;
        if (self.kickoff != other.kickoff) return false;
        if (self.kickoff_less != other.kickoff_less) return false;
        if (self.kickoff_more != other.kickoff_more) return false;
        if (self.limit != other.limit) return false;

        if (self.name == null and other.name != null) {
            return false;
        } else if (self.name != null and other.name == null) {
            return false;
        } else if (self.name == null and other.name == null) {} else {
            if (!std.mem.eql(u8, self.name.?, other.name.?)) return false;
        }

        if (self.no_tags != other.no_tags) return false;
        if (self.priority != other.priority) return false;
        if (self.remain_less != other.remain_less) return false;
        if (self.remain_more != other.remain_more) return false;
        if (self.should_start != other.should_start) return false;
        if (self.start_less != other.start_less) return false;
        if (self.start_more != other.start_more) return false;

        if (self.excluded_tags.items.len != other.excluded_tags.items.len) return false;
        for (0..self.excluded_tags.items.len) |i| {
            if (!std.mem.eql(u8, self.excluded_tags.items[i], other.excluded_tags.items[i])) return false;
        }

        if (self.tags.items.len != other.tags.items.len) return false;
        for (0..self.tags.items.len) |i| {
            if (!std.mem.eql(u8, self.tags.items[i], other.tags.items[i])) return false;
        }

        return true;
    }
};

const TestData = struct {
    args: []const []const u8,
    ex_stdout: ?[]const u8 = null,
    ex_stderr: ?[]const u8 = null,
    ex_state: *ArgumentParser,
    ex_err: ?anyerror = null,
};

fn performTest(td: TestData) !void {
    try globals.printer.init();
    defer globals.printer.deinit();

    // the actual parser instance to test
    var arg_parser = ArgumentParser{};
    arg_parser.init();
    defer arg_parser.deinit();

    // create the array of args to parse
    const args = try globals.allocator.alloc([:0]u8, td.args.len);
    for (0..td.args.len) |i| {
        args[i] = try globals.allocator.dupeZ(u8, td.args[i]);
    }
    defer globals.allocator.free(args);

    // if we expect an error, check it's the correct one
    if (td.ex_err) |ex_err| {
        arg_parser.parse(args) catch |ac_err| {
            std.testing.expectEqual(ac_err, ex_err) catch |err| {
                std.debug.print("ac_err: {}\n", .{ac_err});
                std.debug.print("ex_err: {}\n", .{ex_err});
                return err;
            };
        };
    } else {
        try arg_parser.parse(args);
    }

    // if there should be something on the stdout
    if (td.ex_stdout) |ex_stdout| {
        const ac_stdout = globals.printer.out_buff[0..globals.printer.cur_pos_out_buff];
        std.testing.expect(std.mem.eql(u8, ac_stdout, ex_stdout)) catch |err| {
            std.debug.print("ac_stdout: {s}\n", .{ac_stdout});
            std.debug.print("ex_stdout: {s}\n", .{ex_stdout});
            return err;
        };
    }

    // if there should be something on the stderr
    if (td.ex_stderr) |ex_stderr| {
        const ac_stderr = globals.printer.err_buff[0..globals.printer.cur_pos_err_buff];
        std.testing.expect(std.mem.eql(u8, ac_stderr, ex_stderr)) catch |err| {
            std.debug.print("ac_stderr: {s}\n", .{ac_stderr});
            std.debug.print("ex_stderr: {s}\n", .{ex_stderr});
            return err;
        };
    }

    std.testing.expect(arg_parser.compare(td.ex_state)) catch |err| {
        arg_parser.print();
        td.ex_state.print();
        return err;
    };
}

// ---------------------------------------------------------
// TEST PAYLOAD
// ---------------------------------------------------------

test "Payload \"nice weather outside\"" {
    var ex_state = ArgumentParser{};
    ex_state.payload = "nice weather outside";

    try performTest(.{
        .args = &.{"nice weather outside"},
        .ex_state = &ex_state,
    });
}

test "Payload \"#nice weat@@er  \"" {
    var ex_state = ArgumentParser{};
    ex_state.payload = "#nice weat@@er";

    try performTest(.{
        .args = &.{"#nice weat@@er  "},
        .ex_state = &ex_state,
    });
}

test "Payload already parsed" {
    var ex_state = ArgumentParser{};
    ex_state.payload = "nice";
    ex_state.estimation = 4;

    try performTest(.{
        .args = &.{ "nice", "-e", "4", "cool" },
        .ex_state = &ex_state,
        .ex_err = ArgumentParsingError.UnexpectedArgument,
        .ex_stderr = "Unexpected argument: \"cool\".\n",
    });
}

// ---------------------------------------------------------
// TEST DIVISIONS
// ---------------------------------------------------------

test "Divisions OK case" {
    var ex_state = ArgumentParser{};
    ex_state.divisions = 10;

    try performTest(.{
        .args = &.{ "--divisions", "10" },
        .ex_state = &ex_state,
    });
}

test "Division number contains invalid characters" {
    var ex_state = ArgumentParser{};
    ex_state.current_state = ArgParserState.expecting_divisions;

    try performTest(.{
        .args = &.{ "--divisions", "4A0" },
        .ex_state = &ex_state,
        .ex_err = ArgumentParsingError.CannotParseDivisions,
        .ex_stderr = "Division number contains invalid characters.\n",
    });
}

test "Division number too big" {
    var ex_state = ArgumentParser{};
    ex_state.current_state = ArgParserState.expecting_divisions;

    try performTest(.{
        .args = &.{ "--divisions", "20" },
        .ex_state = &ex_state,
        .ex_err = ArgumentParsingError.CannotParseDivisions,
        .ex_stderr = "Division number too big. Maximum is: 15.\n",
    });
}

test "Divisions already parsed" {
    var ex_state = ArgumentParser{};
    ex_state.current_state = ArgParserState.not_expecting;
    ex_state.divisions = 10;

    try performTest(.{
        .args = &.{ "--divisions", "10", "--divisions", "5" },
        .ex_state = &ex_state,
        .ex_err = ArgumentParsingError.DivisionsAlreadyParsed,
        .ex_stderr = "There can be only one \"--divisions\" flag.\n",
    });
}

// ---------------------------------------------------------
// TEST DURATION
// ---------------------------------------------------------

test "Duration OK case short" {
    var ex_state = ArgumentParser{};
    ex_state.duration = 34;

    try performTest(.{
        .args = &.{ "-d", "34" },
        .ex_state = &ex_state,
    });
}

test "Duration OK case long" {
    var ex_state = ArgumentParser{};
    ex_state.duration = 34;

    try performTest(.{
        .args = &.{ "--duration", "34" },
        .ex_state = &ex_state,
    });
}

test "Duration invalid characters" {
    var ex_state = ArgumentParser{};
    ex_state.current_state = ArgParserState.expecting_duration;

    try performTest(.{
        .args = &.{ "--duration", "3H4" },
        .ex_state = &ex_state,
        .ex_err = ArgumentParsingError.CannotParseDuration,
        .ex_stderr = "Duration number contains invalid characters.\n",
    });
}

test "Duration number too big" {
    var ex_state = ArgumentParser{};
    ex_state.current_state = ArgParserState.expecting_duration;

    try performTest(.{
        .args = &.{ "--duration", "5000" },
        .ex_state = &ex_state,
        .ex_err = ArgumentParsingError.CannotParseDuration,
        .ex_stderr = "Duration number too big. Maximum is: 4095.\n",
    });
}

test "Duration already parsed" {
    var ex_state = ArgumentParser{};
    ex_state.current_state = ArgParserState.not_expecting;
    ex_state.duration = 38;

    try performTest(.{
        .args = &.{ "--duration", "38", "-d", "5" },
        .ex_state = &ex_state,
        .ex_err = ArgumentParsingError.DurationAlreadyParsed,
        .ex_stderr = "There can be only one \"-d\" or \"--duration\" flag.\n",
    });
}

// ---------------------------------------------------------
// TEST DURATION-LESS
// ---------------------------------------------------------

test "Duration-less OK case short" {
    var ex_state = ArgumentParser{};
    ex_state.duration_less = 34;

    try performTest(.{
        .args = &.{ "-dl", "34" },
        .ex_state = &ex_state,
    });
}

test "Duration-less OK case long" {
    var ex_state = ArgumentParser{};
    ex_state.duration_less = 34;

    try performTest(.{
        .args = &.{ "--duration-less", "34" },
        .ex_state = &ex_state,
    });
}

test "Duration-less invalid characters" {
    var ex_state = ArgumentParser{};
    ex_state.current_state = ArgParserState.expecting_duration_less;

    try performTest(.{
        .args = &.{ "-dl", "3H4" },
        .ex_state = &ex_state,
        .ex_err = ArgumentParsingError.CannotParseDuration,
        .ex_stderr = "Duration number contains invalid characters.\n",
    });
}

test "Duration-less number too big" {
    var ex_state = ArgumentParser{};
    ex_state.current_state = ArgParserState.expecting_duration_less;

    try performTest(.{
        .args = &.{ "--duration-less", "5000" },
        .ex_state = &ex_state,
        .ex_err = ArgumentParsingError.CannotParseDuration,
        .ex_stderr = "Duration number too big. Maximum is: 4095.\n",
    });
}

test "Duration-less already parsed" {
    var ex_state = ArgumentParser{};
    ex_state.current_state = ArgParserState.not_expecting;
    ex_state.duration_less = 38;

    try performTest(.{
        .args = &.{ "--duration-less", "38", "-dl", "5" },
        .ex_state = &ex_state,
        .ex_err = ArgumentParsingError.DurationLessAlreadyParsed,
        .ex_stderr = "There can be only one \"-dl\" or \"--duration-less\" flag.\n",
    });
}

// ---------------------------------------------------------
// TEST DURATION-MORE
// ---------------------------------------------------------

test "Duration-more OK case short" {
    var ex_state = ArgumentParser{};
    ex_state.duration_more = 34;

    try performTest(.{
        .args = &.{ "-dm", "34" },
        .ex_state = &ex_state,
    });
}

test "Duration-more OK case long" {
    var ex_state = ArgumentParser{};
    ex_state.duration_more = 34;

    try performTest(.{
        .args = &.{ "--duration-more", "34" },
        .ex_state = &ex_state,
    });
}

test "Duration-more invalid characters" {
    var ex_state = ArgumentParser{};
    ex_state.current_state = ArgParserState.expecting_duration_more;

    try performTest(.{
        .args = &.{ "-dm", "3H4" },
        .ex_state = &ex_state,
        .ex_err = ArgumentParsingError.CannotParseDuration,
        .ex_stderr = "Duration number contains invalid characters.\n",
    });
}

test "Duration-more number too big" {
    var ex_state = ArgumentParser{};
    ex_state.current_state = ArgParserState.expecting_duration_more;

    try performTest(.{
        .args = &.{ "--duration-more", "5000" },
        .ex_state = &ex_state,
        .ex_err = ArgumentParsingError.CannotParseDuration,
        .ex_stderr = "Duration number too big. Maximum is: 4095.\n",
    });
}

test "Duration-more already parsed" {
    var ex_state = ArgumentParser{};
    ex_state.current_state = ArgParserState.not_expecting;
    ex_state.duration_more = 38;

    try performTest(.{
        .args = &.{ "--duration-more", "38", "-dm", "5" },
        .ex_state = &ex_state,
        .ex_err = ArgumentParsingError.DurationMoreAlreadyParsed,
        .ex_stderr = "There can be only one \"-dm\" or \"--duration-more\" flag.\n",
    });
}

// ---------------------------------------------------------
// TEST END-LESS
// ---------------------------------------------------------

// ok case
// TODO end-less number contains invalid characters
// TODO end-less number too big (u25)
// TODO end-less already parsed
// TODO end-less-flag already parsed

// ---------------------------------------------------------
// TEST ESTIMATION
// ---------------------------------------------------------

// ok case
// TODO estimation number contains invalid characters
// TODO estimation number too big (u16)
// TODO estimation already parsed
// TODO estimation-flag already parsed

// ---------------------------------------------------------
// TEST EXCLUDED-TAGS
// ---------------------------------------------------------

// ok case
// TODO trim trailing spaces
// TODO excluded-tags-flag but no tag after
// TODO excluded-tags-flag already parsed
// TODO multiple same tags

// ---------------------------------------------------------
// TEST KICKOFF
// ---------------------------------------------------------

// ok case
// TODO kickoff number contains invalid characters
// TODO kickoff number too big (u25)
// TODO kickoff already parsed
// TODO kickoff-flag already parsed

// ---------------------------------------------------------
// TEST KICKOFF-LESS
// ---------------------------------------------------------

// ok case
// TODO kickoff-less number contains invalid characters
// TODO kickoff-less number too big (u25)
// TODO kickoff-less already parsed
// TODO kickoff-less-flag already parsed

// ---------------------------------------------------------
// TEST KICKOFF-MORE
// ---------------------------------------------------------

// ok case
// TODO kickoff-more number contains invalid characters
// TODO kickoff-more number too big (u25)
// TODO kickoff-more already parsed
// TODO kickoff-more-flag already parsed

// ---------------------------------------------------------
// TEST LIMIT
// ---------------------------------------------------------

test "Limit OK case long" {
    var ex_state = ArgumentParser{};
    ex_state.limit = 53;

    try performTest(.{
        .args = &.{ "--limit", "53" },
        .ex_state = &ex_state,
    });
}

// TODO limit number contains invalid characters
// TODO limit number too big (u32)
// TODO limit already parsed
// TODO limit-flag already parsed

// ---------------------------------------------------------
// TEST NAME
// ---------------------------------------------------------

// ok case
// TODO trim trailing spaces
// TODO limit already parsed
// TODO limit-flag already parsed

// ---------------------------------------------------------
// TEST NO-TAGS
// ---------------------------------------------------------

test "No-tags OK case" {
    var ex_state = ArgumentParser{};
    ex_state.payload = "coucou";
    ex_state.no_tags = true;

    try performTest(.{
        .args = &.{ "coucou", "--no-tags" },
        .ex_state = &ex_state,
    });
}

test "--no-tags has priority on --tags" {
    var ex_state = ArgumentParser{};
    ex_state.no_tags = true;
    ex_state.current_state = ArgParserState.expecting_tags;

    try performTest(.{
        .args = &.{ "--no-tags", "-t", "test" },
        .ex_state = &ex_state,
        .ex_err = ArgumentParsingError.CannotParseDuration,
        .ex_stdout = "Warning: you specified the --no-tags flag along the --tags flag.\nSince these are contradictory only the --no-tags flag will be taken into account\n",
    });
}

// TODO --no-tags has priority on --exclude-tags
// TODO --no-tags has priority on --tags and --exclude-tags
// TODO flag already parsed (is ok)

// ---------------------------------------------------------
// TEST PRIORITY
// ---------------------------------------------------------

test "Priority OK case short now" {
    var ex_state = ArgumentParser{};
    ex_state.priority = dt.StatusTag.now;

    try performTest(.{
        .args = &.{ "-p", "now" },
        .ex_state = &ex_state,
    });
}

// TODO ok case someday
// TODO ok case soon
// TODO invalid option
// TODO priority already parsed
// TODO priority-flag already parsed

// ---------------------------------------------------------
// TEST REMAIN-LESS
// ---------------------------------------------------------

// ok case
// TODO remain-less number contains invalid characters
// TODO remain-less number too big (u16)
// TODO remain-less already parsed
// TODO remain-less-flag already parsed

// ---------------------------------------------------------
// TEST REMAIN-MORE
// ---------------------------------------------------------

// ok case
// TODO remain-more number contains invalid characters
// TODO remain-more number too big (u16)
// TODO remain-more already parsed
// TODO remain-more-flag already parsed

// ---------------------------------------------------------
// TEST SHOULD-START
// ---------------------------------------------------------

// TODO ok case
// TODO flag already parsed (is ok)

// ---------------------------------------------------------
// TEST START-LESS
// ---------------------------------------------------------

// ok case
// TODO start-less number contains invalid characters
// TODO start-less number too big (u25)
// TODO start-less already parsed
// TODO start-less-flag already parsed

// ---------------------------------------------------------
// TEST START-MORE
// ---------------------------------------------------------

// ok case
// TODO start-more number contains invalid characters
// TODO start-more number too big (u25)
// TODO start-more already parsed
// TODO start-more-flag already parsed

// ---------------------------------------------------------
// TEST TAGS
// ---------------------------------------------------------

test "Tags OK case short single tag" {
    var ex_state = ArgumentParser{};
    ex_state.init();
    ex_state.deinit();
    try ex_state.tags.append(try globals.allocator.dupeZ(u8, "test"));

    try performTest(.{
        .args = &.{ "-t", "test" },
        .ex_state = &ex_state,
    });
}

test "Tags OK case long multiple tag" {
    var ex_state = ArgumentParser{};
    ex_state.init();
    ex_state.deinit();
    try ex_state.tags.append(try globals.allocator.dupeZ(u8, "tag1"));
    try ex_state.tags.append(try globals.allocator.dupeZ(u8, "othertag"));

    try performTest(.{
        .args = &.{ "--tags", "tag1", "othertag" },
        .ex_state = &ex_state,
    });
}

// TODO do we check tag name size here?
// TODO do we trim trailing spaces here?
// TODO tags already parsed

// ---------------------------------------------------------
// TEST GENERIC
// ---------------------------------------------------------

// TODO unknown flag

// test "Multiple payload" {
// TODO
// var ex_state = ArgumentParser{};
// ex_state.current_state = ArgParserState.not_expecting;
// ex_state.divisions = 10;
//
// try performTest(.{
//     .args = &.{ "payload", "--divisions", "10", "5" },
//     .ex_state = &ex_state,
//     .ex_err = ArgumentParsingError.DivisionsAlreadyParsed,
//     .ex_stderr = "Divisions already parsed. Please remove: \"5\".\n",
// });
// }
