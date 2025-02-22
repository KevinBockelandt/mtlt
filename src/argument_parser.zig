const std = @import("std");

const ansi = @import("ansi_codes.zig");
const base62_helper = @import("base62_helper.zig");
const data_types = @import("data_types.zig");
const dfr = @import("data_file_reader.zig");
const globals = @import("globals.zig");
const table_printer = @import("table_printer.zig");
const time_helper = @import("time_helper.zig");

const little_end = std.builtin.Endian.little;
const colemp = ansi.col_emphasis;
const colres = ansi.col_reset;

var buf_str_id: [4]u8 = undefined;

/// Potential types of errors during argument parsing
pub const ArgumentParsingError = error{
    UnexpectedArgument,
    UnknownFlag,
    CannotParseDuration,
    // flags already parsed
    DivisionsAlreadyParsed,
    DurationAlreadyParsed,
    DurationLessAlreadyParsed,
    DurationMoreAlreadyParsed,
    EmptyAlreadyParsed,
    EndLessAlreadyParsed,
    EstimationAlreadyParsed,
    RemainMoreAlreadyParsed,
    RemainLessAlreadyParsed,
    ExcludeTagsAlreadyParsed,
    LimitAlreadyParsed,
    NameAlreadyParsed,
    NoTagsAlreadyParsed,
    StartAlreadyParsed,
    StartLessAlreadyParsed,
    StartMoreAlreadyParsed,
    TagsAlreadyParsed,
    TargetAlreadyParsed,
    TargetMoreAlreadyParsed,
    TargetLessAlreadyParsed,
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
    remain_more,
    remain_less,
    exclude_tags,
    limit,
    name,
    no_tags,
    start,
    start_less,
    start_more,
    tags,
    target,
    target_more,
    target_less,
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
    expecting_remain_more,
    expecting_remain_less,
    expecting_exclude_tags,
    expecting_limit,
    expecting_name,
    expecting_start_less,
    expecting_start_more,
    expecting_tags,
    expecting_target,
    expecting_target_more,
    expecting_target_less,
    not_expecting,
};

// Display an error received from the parsing of a duration string
fn displayDurationError(dur: []const u8, err: anyerror) !void {
    const w = std.io.getStdOut().writer();

    switch (err) {
        time_helper.TimeError.EmptyDuration => _ = try w.write("Error: the duration is empty\n"),
        time_helper.TimeError.InvalidDurationString => try w.print("Error: the duration string \"{s}\" is invalid\n", .{dur}),
        time_helper.TimeError.DurationTooGreat => try w.print("Error: the duration \"{s}\" is too big\n", .{dur}),
        std.fmt.ParseIntError.Overflow => try w.print("Error: the duration string \"{s}\" contains a number that is too big\n", .{dur}),
        else => {
            try w.print("Unexpected error while parsing the duration {s}\n", .{dur});
            try w.print("{}", .{err});
        },
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
    } else if (std.mem.eql(u8, arg, "-a") or std.mem.eql(u8, arg, "--tags")) {
        return ArgType.tags;
    } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--duration")) {
        return ArgType.duration;
    } else if (std.mem.eql(u8, arg, "-dl") or std.mem.eql(u8, arg, "--duration-less")) {
        return ArgType.duration_less;
    } else if (std.mem.eql(u8, arg, "-dm") or std.mem.eql(u8, arg, "--duration-more")) {
        return ArgType.duration_more;
    } else if (std.mem.eql(u8, arg, "-e") or std.mem.eql(u8, arg, "--estimation")) {
        return ArgType.estimation;
    } else if (std.mem.eql(u8, arg, "-l") or std.mem.eql(u8, arg, "--limit")) {
        return ArgType.limit;
    } else if (std.mem.eql(u8, arg, "-n") or std.mem.eql(u8, arg, "--name")) {
        return ArgType.name;
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
    } else if (std.mem.eql(u8, arg, "-t") or std.mem.eql(u8, arg, "--target")) {
        return ArgType.target;
    } else if (std.mem.eql(u8, arg, "-tm") or std.mem.eql(u8, arg, "--target-more")) {
        return ArgType.target_more;
    } else if (std.mem.eql(u8, arg, "-tl") or std.mem.eql(u8, arg, "--target-less")) {
        return ArgType.target_less;
    } else if (arg[0] == '-') {
        return ArgType.unknown_flag;
    } else {
        return ArgType.unknown;
    }
}

/// Display the content of a nullable int (for debug purposes)
fn printNullableInt(to_print: ?type, text: []const u8) void {
    if (to_print) |val| {
        std.debug.print(" - {s}: {d}\n", .{ text, val });
    } else {
        std.debug.print(" - {s}: NULL\n", .{text});
    }
}

pub const ArgumentParser = struct {
    /// the main thing regarding the command (an id to work on, the name of a thing to add, etc.)
    payload: ?[]const u8 = null,
    divisions: ?u8 = null, // --divisions
    duration: ?u12 = null, // --duration
    duration_less: ?u12 = null, // --duration-less
    duration_more: ?u12 = null, // --duration-more
    end_less: ?u25 = null, // --end-less
    estimation: ?u16 = null, // --estimation
    remain_more: ?u16 = null, // --remain-more
    remain_less: ?u16 = null, // --remain-less
    excluded_tags: std.ArrayList([]u8) = undefined, // --exclude-tags
    limit: ?u32 = null, // --limit
    name: ?[]const u8 = null, // --name
    no_tags: bool = false, // --no-tags
    should_start: bool = false, // --start
    start_less: ?u25 = null, // --start-less
    start_more: ?u25 = null, // --start-more
    tags: std.ArrayList([]u8) = undefined, // --tags
    target: ?u25 = null, // --target
    target_more: ?u25 = null, // --target-more
    target_less: ?u25 = null, // --target-less

    current_state: ArgParserState = ArgParserState.not_expecting,

    divisions_already_parsed: bool = false,
    duration_already_parsed: bool = false,
    duration_less_already_parsed: bool = false,
    duration_more_already_parsed: bool = false,
    end_less_already_parsed: bool = false,
    estimation_already_parsed: bool = false,
    excluded_tags_already_parsed: bool = false,
    limit_already_parsed: bool = false,
    name_already_parsed: bool = false,
    payload_already_parsed: bool = false,
    remain_less_already_parsed: bool = false,
    remain_more_already_parsed: bool = false,
    should_start_already_parsed: bool = false,
    start_less_already_parsed: bool = false,
    start_more_already_parsed: bool = false,
    tags_already_parsed: bool = false,
    target_already_parsed: bool = false,
    target_less_already_parsed: bool = false,
    target_more_already_parsed: bool = false,

    divisions_flag_already_parsed: bool = false,
    duration_flag_already_parsed: bool = false,
    duration_less_flag_already_parsed: bool = false,
    duration_more_flag_already_parsed: bool = false,
    end_less_flag_already_parsed: bool = false,
    estimation_flag_already_parsed: bool = false,
    excluded_tags_flag_already_parsed: bool = false,
    limit_flag_already_parsed: bool = false,
    name_flag_already_parsed: bool = false,
    no_tags_flag_already_parsed: bool = false,
    remain_less_flag_already_parsed: bool = false,
    remain_more_flag_already_parsed: bool = false,
    should_flag_start_already_parsed: bool = false,
    start_less_flag_already_parsed: bool = false,
    start_more_flag_already_parsed: bool = false,
    tags_flag_already_parsed: bool = false,
    target_flag_already_parsed: bool = false,
    target_less_flag_already_parsed: bool = false,
    target_more_flag_already_parsed: bool = false,

    at_least_1_arg_parsed_after_flag: bool = false,

    /// Switch the parser to the expecting_tags state
    fn switchExpectingTags(self: *ArgumentParser) !void {
        if (!self.tags_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_tags;
            self.tags_flag_already_parsed = true;
        } else {
            _ = try std.io.getStdOut().writer().write("Error: there can be only one \"-a\" or \"--tags\" flag\n");
            return ArgumentParsingError.TagsAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_tags state
    fn switchExpectingExcludeTags(self: *ArgumentParser) !void {
        if (!self.excluded_tags_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_exclude_tags;
            self.excluded_tags_flag_already_parsed = true;
        } else {
            _ = try std.io.getStdOut().writer().write("Error: there can be only one \"--exclude-tags\" flag\n");
            return ArgumentParsingError.ExcludeTagsAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_divisions state
    fn switchExpectingDivisions(self: *ArgumentParser) !void {
        if (!self.divisions_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_divisions;
            self.divisions_flag_already_parsed = true;
        } else {
            _ = try std.io.getStdOut().writer().write("Error: there can be only one \"--divisions\" flag\n");
            return ArgumentParsingError.DivisionsAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_estimation state
    fn switchExpectingEstimation(self: *ArgumentParser) !void {
        if (!self.estimation_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_estimation;
            self.estimation_flag_already_parsed = true;
        } else {
            _ = try std.io.getStdOut().writer().write("Error: there can be only one \"-e\" or \"--estimation\" flag\n");
            return ArgumentParsingError.EstimationAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_remain_less state
    fn switchExpectingRemainLess(self: *ArgumentParser) !void {
        if (!self.remain_less_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_remain_less;
            self.remain_less_flag_already_parsed = true;
        } else {
            _ = try std.io.getStdOut().writer().write("Error: there can be only one \"-ea\" or \"--remain-less\" flag\n");
            return ArgumentParsingError.RemainLessAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_remain_more state
    fn switchExpectingRemainMore(self: *ArgumentParser) !void {
        if (!self.remain_more_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_remain_more;
            self.remain_more_flag_already_parsed = true;
        } else {
            _ = try std.io.getStdOut().writer().write("Error: there can be only one \"-ea\" or \"--remain-more\" flag\n");
            return ArgumentParsingError.RemainMoreAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_target state
    fn switchExpectingTarget(self: *ArgumentParser) !void {
        if (!self.target_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_target;
            self.target_flag_already_parsed = true;
        } else {
            _ = try std.io.getStdOut().writer().write("Error: there can be only one \"-t\" or \"--target\" flag\n");
            return ArgumentParsingError.TargetAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_target_more state
    fn switchExpectingTargetMore(self: *ArgumentParser) !void {
        if (!self.target_more_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_target_more;
            self.target_more_flag_already_parsed = true;
        } else {
            _ = try std.io.getStdOut().writer().write("Error: there can be only one \"-ta\" or \"--target-more\" flag\n");
            return ArgumentParsingError.TargetMoreAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_target_less state
    fn switchExpectingTargetLess(self: *ArgumentParser) !void {
        if (!self.target_less_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_target_less;
            self.target_less_flag_already_parsed = true;
        } else {
            _ = try std.io.getStdOut().writer().write("Error: there can be only one \"-ta\" or \"--target-less\" flag\n");
            return ArgumentParsingError.TargetLessAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_start_more state
    fn switchExpectingStartMore(self: *ArgumentParser) !void {
        if (!self.start_more_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_start_more;
            self.start_more_flag_already_parsed = true;
        } else {
            _ = try std.io.getStdOut().writer().write("Error: there can be only one \"-sm\" or \"--start-more\" flag\n");
            return ArgumentParsingError.StartMoreAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_start_less state
    fn switchExpectingStartLess(self: *ArgumentParser) !void {
        if (!self.start_less_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_start_less;
            self.start_less_flag_already_parsed = true;
        } else {
            _ = try std.io.getStdOut().writer().write("Error: there can be only one \"-sl\" or \"--start-less\" flag\n");
            return ArgumentParsingError.StartLessAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_duration state
    fn switchExpectingDuration(self: *ArgumentParser) !void {
        if (!self.duration_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_duration;
            self.duration_flag_already_parsed = true;
        } else {
            _ = try std.io.getStdOut().writer().write("Error: there can be only one \"-d\" or \"--duration\" flag\n");
            return ArgumentParsingError.DurationAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_duration_more state
    fn switchExpectingDurationMore(self: *ArgumentParser) !void {
        if (!self.duration_more_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_duration_more;
            self.duration_more_flag_already_parsed = true;
        } else {
            _ = try std.io.getStdOut().writer().write("Error: there can be only one \"-dm\" or \"--duration-more\" flag\n");
            return ArgumentParsingError.DurationMoreAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_duration_less state
    fn switchExpectingDurationLess(self: *ArgumentParser) !void {
        if (!self.duration_less_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_duration_less;
            self.duration_less_flag_already_parsed = true;
        } else {
            _ = try std.io.getStdOut().writer().write("Error: there can be only one \"-dl\" or \"--duration-less\" flag\n");
            return ArgumentParsingError.DurationLessAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_end_less state
    fn switchExpectingEndLess(self: *ArgumentParser) !void {
        if (!self.end_less_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_end_less;
            self.end_less_flag_already_parsed = true;
        } else {
            _ = try std.io.getStdOut().writer().write("Error: there can be only one \"--end-less\" flag\n");
            return ArgumentParsingError.EndLessAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_limit_state
    fn switchExpectingLimit(self: *ArgumentParser) !void {
        if (!self.limit_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_limit;
            self.limit_flag_already_parsed = true;
        } else {
            _ = try std.io.getStdOut().writer().write("Error: there can be only one \"-l\" or \"--limit\" flag\n");
            return ArgumentParsingError.LimitAlreadyParsed;
        }
    }

    /// Switch the parser to the expecting_name state
    fn switchExpectingName(self: *ArgumentParser) !void {
        if (!self.name_flag_already_parsed) {
            self.current_state = ArgParserState.expecting_name;
            self.name_flag_already_parsed = true;
        } else {
            _ = try std.io.getStdOut().writer().write("Error: there can be only one \"-n\" or \"--name\" flag\n");
            return ArgumentParsingError.NameAlreadyParsed;
        }
    }

    /// Called when encountering an unexpected argument
    fn unexpectedArgument(self: *ArgumentParser, arg: []const u8) !void {
        _ = self;
        try std.io.getStdOut().writer().print("Error: unexpected argument: {s}\n", .{arg});
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
            ArgType.remain_more => try self.switchExpectingRemainMore(),
            ArgType.remain_less => try self.switchExpectingRemainLess(),
            ArgType.exclude_tags => try self.switchExpectingExcludeTags(),
            ArgType.limit => try self.switchExpectingLimit(),
            ArgType.name => try self.switchExpectingName(),
            ArgType.start_less => try self.switchExpectingStartLess(),
            ArgType.start_more => try self.switchExpectingStartMore(),
            ArgType.tags => try self.switchExpectingTags(),
            ArgType.target => try self.switchExpectingTarget(),
            ArgType.target_more => try self.switchExpectingTargetMore(),
            ArgType.target_less => try self.switchExpectingTargetLess(),
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
        const w = std.io.getStdOut().writer();

        for (args[0..]) |arg| {
            const cur_arg_type = getArgType(arg);

            // those argument types are handled independently of the current state of the parser
            switch (cur_arg_type) {
                ArgType.unknown_flag => {
                    try w.print("Error: unknown flag: {s}\n", .{arg});
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
                        if (self.divisions_already_parsed) {
                            try w.print("Error: division number already parsed. Please remove: \"{s}\"\n", .{arg});
                            return ArgumentParsingError.DivisionsAlreadyParsed;
                        } else if (std.fmt.parseInt(u8, arg, 10)) |parsed_divisions| {
                            self.divisions = @intCast(parsed_divisions);
                            self.divisions_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else |err| {
                            switch (err) {
                                std.fmt.ParseIntError.InvalidCharacter => try w.print("Error: division number contains invalid characters\n", .{}),
                                std.fmt.ParseIntError.Overflow => try w.print("Error: division number too big. Maximum is: {d}\n", .{std.math.maxInt(u8)}),
                            }
                            return err;
                        }
                    }
                },
                ArgParserState.expecting_duration => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (self.duration_already_parsed) {
                            _ = try w.print("Error: duration already parsed. Please remove: \"{s}\"\n", .{arg});
                            return ArgumentParsingError.DurationAlreadyParsed;
                        } else if (time_helper.parseDuration(arg, u12)) |parsed_duration| {
                            self.duration = @intCast(parsed_duration);
                            self.duration_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else |err| {
                            try displayDurationError(arg, err);
                        }
                    }
                },
                ArgParserState.expecting_duration_more => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (self.duration_more_already_parsed) {
                            _ = try w.print("Error: duration more already parsed. Please remove: \"{s}\"\n", .{arg});
                            return ArgumentParsingError.DurationMoreAlreadyParsed;
                        } else if (time_helper.parseDuration(arg, u12)) |parsed_duration| {
                            self.duration_more = @intCast(parsed_duration);
                            self.duration_more_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else |err| {
                            try displayDurationError(arg, err);
                        }
                    }
                },
                ArgParserState.expecting_duration_less => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (self.duration_less_already_parsed) {
                            _ = try w.print("Error: duration less already parsed. Please remove: \"{s}\"\n", .{arg});
                            return ArgumentParsingError.DurationLessAlreadyParsed;
                        } else if (time_helper.parseDuration(arg, u12)) |parsed_duration| {
                            self.duration_less = @intCast(parsed_duration);
                            self.duration_less_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else |err| {
                            try displayDurationError(arg, err);
                        }
                    }
                },
                ArgParserState.expecting_end_less => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (self.end_less_already_parsed) {
                            _ = try w.print("Error: end less already parsed. Please remove: \"{s}\"\n", .{arg});
                            return ArgumentParsingError.EndLessAlreadyParsed;
                        } else if (time_helper.parseDuration(arg, u25)) |parsed_end| {
                            self.end_less = @intCast(parsed_end);
                            self.end_less_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else |err| {
                            try displayDurationError(arg, err);
                        }
                    }
                },
                ArgParserState.expecting_estimation => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (self.estimation_already_parsed) {
                            _ = try w.print("Error: estimation already parsed. Please remove: \"{s}\"\n", .{arg});
                            return ArgumentParsingError.EstimationAlreadyParsed;
                        } else if (time_helper.parseDuration(arg, u16)) |parsed_estimation| {
                            self.estimation = @intCast(parsed_estimation);
                            self.estimation_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else |err| {
                            try displayDurationError(arg, err);
                        }
                    }
                },
                ArgParserState.expecting_remain_more => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (self.remain_more_already_parsed) {
                            _ = try w.print("Error: remain more already parsed. Please remove: \"{s}\"\n", .{arg});
                            return ArgumentParsingError.RemainMoreAlreadyParsed;
                        } else if (time_helper.parseDuration(arg, u16)) |parsed_remain| {
                            self.remain_more = @intCast(parsed_remain);
                            self.remain_more_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else |err| {
                            try displayDurationError(arg, err);
                        }
                    }
                },
                ArgParserState.expecting_remain_less => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (self.remain_less_already_parsed) {
                            _ = try w.print("Error: remain less already parsed. Please remove: \"{s}\"\n", .{arg});
                            return ArgumentParsingError.RemainLessAlreadyParsed;
                        } else if (time_helper.parseDuration(arg, u16)) |parsed_remain| {
                            self.remain_less = @intCast(parsed_remain);
                            self.remain_less_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else |err| {
                            try displayDurationError(arg, err);
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
                            _ = try w.print("Error: limit already parsed. Please remove: \"{s}\"\n", .{arg});
                            return ArgumentParsingError.LimitAlreadyParsed;
                        } else if (time_helper.parseDuration(arg, u32)) |parsed_limit| {
                            self.limit = @intCast(parsed_limit);
                            self.limit_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else |err| {
                            try displayDurationError(arg, err);
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
                ArgParserState.expecting_start_less => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (self.start_less_already_parsed) {
                            _ = try w.print("Error: start less already parsed. Please remove: \"{s}\"\n", .{arg});
                            return ArgumentParsingError.StartLessAlreadyParsed;
                        } else if (time_helper.parseDuration(arg, u25)) |parsed_start| {
                            self.start_less = @intCast(parsed_start);
                            self.start_less_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else |err| {
                            try displayDurationError(arg, err);
                        }
                    }
                },
                ArgParserState.expecting_start_more => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (self.start_more_already_parsed) {
                            _ = try w.print("Error: start more already parsed. Please remove: \"{s}\"\n", .{arg});
                            return ArgumentParsingError.StartMoreAlreadyParsed;
                        } else if (time_helper.parseDuration(arg, u25)) |parsed_start| {
                            self.start_more = @intCast(parsed_start);
                            self.start_more_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else |err| {
                            try displayDurationError(arg, err);
                        }
                    }
                },
                ArgParserState.expecting_tags => {
                    if (cur_arg_type == ArgType.unknown) {
                        try self.tags.append(arg);
                    }
                },
                ArgParserState.expecting_target => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (self.target_already_parsed) {
                            _ = try w.print("Error: target already parsed. Please remove: \"{s}\"\n", .{arg});
                            return ArgumentParsingError.TargetAlreadyParsed;
                        } else if (time_helper.parseDuration(arg, u25)) |parsed_target| {
                            self.target = @intCast(parsed_target);
                            self.target_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else |err| {
                            try displayDurationError(arg, err);
                        }
                    }
                },
                ArgParserState.expecting_target_more => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (self.target_more_already_parsed) {
                            _ = try w.print("Error: target more already parsed. Please remove: \"{s}\"\n", .{arg});
                            return ArgumentParsingError.TargetMoreAlreadyParsed;
                        } else if (time_helper.parseDuration(arg, u25)) |parsed_target| {
                            self.target_more = @intCast(parsed_target);
                            self.target_more_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else |err| {
                            try displayDurationError(arg, err);
                        }
                    }
                },
                ArgParserState.expecting_target_less => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (self.target_less_already_parsed) {
                            _ = try w.print("Error: target less already parsed. Please remove: \"{s}\"\n", .{arg});
                            return ArgumentParsingError.TargetLessAlreadyParsed;
                        } else if (time_helper.parseDuration(arg, u25)) |parsed_target| {
                            self.target_less = @intCast(parsed_target);
                            self.target_less_already_parsed = true;
                            self.current_state = ArgParserState.not_expecting;
                        } else |err| {
                            try displayDurationError(arg, err);
                        }
                    }
                },
                ArgParserState.not_expecting => {
                    if (cur_arg_type == ArgType.unknown) {
                        if (!self.payload_already_parsed) {
                            self.payload = arg;
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
            _ = try w.write("Warning: you specified the --no-tags flag along the --tags and --excluded-tags flags.\n");
            _ = try w.write("Since these are contradictory only the --no-tags flag will be taken into account\n");
            self.tags.clearRetainingCapacity();
            self.excluded_tags.clearRetainingCapacity();
        } else if (self.no_tags and self.tags.items.len != 0) {
            _ = try w.write("Warning: you specified the --no-tags flag along the --tags flag.\n");
            _ = try w.write("Since these are contradictory only the --no-tags flag will be taken into account\n");
            self.tags.clearRetainingCapacity();
        } else if (self.no_tags and (self.tags.items.len != 0 or self.excluded_tags.items.len != 0)) {
            _ = try w.write("Warning: you specified the --no-tags flag along the --excluded-tags flag.\n");
            _ = try w.write("Since these are contradictory only the --no-tags flag will be taken into account\n");
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

        printNullableInt(self.divisions, "Divisions");
        printNullableInt(self.duration, "Duration");
        printNullableInt(self.duration_less, "Duration Less");
        printNullableInt(self.duration_more, "Duration More");
        printNullableInt(self.end_less, "End Less");
        printNullableInt(self.estimation, "Estimation");
        printNullableInt(self.remain_more, "Remain More");
        printNullableInt(self.remain_less, "Remain Less");
        printNullableInt(self.start_less, "Start Less");
        printNullableInt(self.start_more, "Start More");
        printNullableInt(self.target, "Target");
        printNullableInt(self.target_more, "Target More");
        printNullableInt(self.target_less, "Target Less");

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
};

test "parse: \"nice weather outside\"" {
    var arg_parser = ArgumentParser{};
    arg_parser.init();
    defer arg_parser.init();

    const args = try globals.allocator.alloc([:0]u8, 1);
    args[0] = try globals.allocator.dupeZ(u8, "nice weather outside");

    try arg_parser.parse(args);

    try std.testing.expect(std.mem.eql(u8, arg_parser.payload.?, "nice weather outside"));
    try std.testing.expect(arg_parser.divisions == null);
    try std.testing.expect(arg_parser.duration == null);
    try std.testing.expect(arg_parser.duration_less == null);
    try std.testing.expect(arg_parser.duration_more == null);
    try std.testing.expect(arg_parser.end_less == null);
    try std.testing.expect(arg_parser.estimation == null);
    try std.testing.expect(arg_parser.remain_more == null);
    try std.testing.expect(arg_parser.remain_less == null);
    try std.testing.expect(arg_parser.excluded_tags.items.len == 0);
    try std.testing.expect(arg_parser.limit == null);
    try std.testing.expect(arg_parser.name == null);
    try std.testing.expect(arg_parser.no_tags == false);
    try std.testing.expect(arg_parser.should_start == false);
    try std.testing.expect(arg_parser.start_less == null);
    try std.testing.expect(arg_parser.start_more == null);
    try std.testing.expect(arg_parser.tags.items.len == 0);
    try std.testing.expect(arg_parser.target == null);
    try std.testing.expect(arg_parser.target_more == null);
    try std.testing.expect(arg_parser.target_less == null);
    globals.allocator.free(args);
}

test "parse: --divisions 34" {
    var arg_parser = ArgumentParser{};
    arg_parser.init();
    defer arg_parser.init();

    const args = try globals.allocator.alloc([:0]u8, 2);
    args[0] = try globals.allocator.dupeZ(u8, "--divisions");
    args[1] = try globals.allocator.dupeZ(u8, "34");

    try arg_parser.parse(args);

    try std.testing.expect(arg_parser.payload == null);
    try std.testing.expect(arg_parser.divisions.? == 34);
    try std.testing.expect(arg_parser.duration == null);
    try std.testing.expect(arg_parser.duration_less == null);
    try std.testing.expect(arg_parser.duration_more == null);
    try std.testing.expect(arg_parser.end_less == null);
    try std.testing.expect(arg_parser.estimation == null);
    try std.testing.expect(arg_parser.remain_more == null);
    try std.testing.expect(arg_parser.remain_less == null);
    try std.testing.expect(arg_parser.excluded_tags.items.len == 0);
    try std.testing.expect(arg_parser.limit == null);
    try std.testing.expect(arg_parser.name == null);
    try std.testing.expect(arg_parser.no_tags == false);
    try std.testing.expect(arg_parser.should_start == false);
    try std.testing.expect(arg_parser.start_less == null);
    try std.testing.expect(arg_parser.start_more == null);
    try std.testing.expect(arg_parser.tags.items.len == 0);
    try std.testing.expect(arg_parser.target == null);
    try std.testing.expect(arg_parser.target_more == null);
    try std.testing.expect(arg_parser.target_less == null);
    globals.allocator.free(args);
}

test "parse: --divisions 400" {
    var arg_parser = ArgumentParser{};
    arg_parser.init();
    defer arg_parser.init();

    const args = try globals.allocator.alloc([:0]u8, 2);
    args[0] = try globals.allocator.dupeZ(u8, "--divisions");
    args[1] = try globals.allocator.dupeZ(u8, "400");

    arg_parser.parse(args) catch |err| {
        try std.testing.expect(err == std.fmt.ParseIntError.Overflow);
    };

    try std.testing.expect(arg_parser.payload == null);
    try std.testing.expect(arg_parser.divisions == null);
    try std.testing.expect(arg_parser.duration == null);
    try std.testing.expect(arg_parser.duration_less == null);
    try std.testing.expect(arg_parser.duration_more == null);
    try std.testing.expect(arg_parser.end_less == null);
    try std.testing.expect(arg_parser.estimation == null);
    try std.testing.expect(arg_parser.remain_more == null);
    try std.testing.expect(arg_parser.remain_less == null);
    try std.testing.expect(arg_parser.excluded_tags.items.len == 0);
    try std.testing.expect(arg_parser.limit == null);
    try std.testing.expect(arg_parser.name == null);
    try std.testing.expect(arg_parser.no_tags == false);
    try std.testing.expect(arg_parser.should_start == false);
    try std.testing.expect(arg_parser.start_less == null);
    try std.testing.expect(arg_parser.start_more == null);
    try std.testing.expect(arg_parser.tags.items.len == 0);
    try std.testing.expect(arg_parser.target == null);
    try std.testing.expect(arg_parser.target_more == null);
    try std.testing.expect(arg_parser.target_less == null);
    globals.allocator.free(args);
}

test "parse: --divisions 4A0" {
    var arg_parser = ArgumentParser{};
    arg_parser.init();
    defer arg_parser.init();

    const args = try globals.allocator.alloc([:0]u8, 2);
    args[0] = try globals.allocator.dupeZ(u8, "--divisions");
    args[1] = try globals.allocator.dupeZ(u8, "4A0");

    arg_parser.parse(args) catch |err| {
        try std.testing.expect(err == std.fmt.ParseIntError.InvalidCharacter);
    };

    try std.testing.expect(arg_parser.payload == null);
    try std.testing.expect(arg_parser.divisions == null);
    try std.testing.expect(arg_parser.duration == null);
    try std.testing.expect(arg_parser.duration_less == null);
    try std.testing.expect(arg_parser.duration_more == null);
    try std.testing.expect(arg_parser.end_less == null);
    try std.testing.expect(arg_parser.estimation == null);
    try std.testing.expect(arg_parser.remain_more == null);
    try std.testing.expect(arg_parser.remain_less == null);
    try std.testing.expect(arg_parser.excluded_tags.items.len == 0);
    try std.testing.expect(arg_parser.limit == null);
    try std.testing.expect(arg_parser.name == null);
    try std.testing.expect(arg_parser.no_tags == false);
    try std.testing.expect(arg_parser.should_start == false);
    try std.testing.expect(arg_parser.start_less == null);
    try std.testing.expect(arg_parser.start_more == null);
    try std.testing.expect(arg_parser.tags.items.len == 0);
    try std.testing.expect(arg_parser.target == null);
    try std.testing.expect(arg_parser.target_more == null);
    try std.testing.expect(arg_parser.target_less == null);
    globals.allocator.free(args);
}

test "parse: -d 34:2" {
    var arg_parser = ArgumentParser{};
    arg_parser.init();
    defer arg_parser.init();

    const args = try globals.allocator.alloc([:0]u8, 2);
    args[0] = try globals.allocator.dupeZ(u8, "-d");
    args[1] = try globals.allocator.dupeZ(u8, "5:23");

    try arg_parser.parse(args);

    try std.testing.expect(arg_parser.payload == null);
    try std.testing.expect(arg_parser.divisions == null);
    try std.testing.expect(arg_parser.duration.? == 323);
    try std.testing.expect(arg_parser.duration_less == null);
    try std.testing.expect(arg_parser.duration_more == null);
    try std.testing.expect(arg_parser.end_less == null);
    try std.testing.expect(arg_parser.estimation == null);
    try std.testing.expect(arg_parser.remain_more == null);
    try std.testing.expect(arg_parser.remain_less == null);
    try std.testing.expect(arg_parser.excluded_tags.items.len == 0);
    try std.testing.expect(arg_parser.limit == null);
    try std.testing.expect(arg_parser.name == null);
    try std.testing.expect(arg_parser.no_tags == false);
    try std.testing.expect(arg_parser.should_start == false);
    try std.testing.expect(arg_parser.start_less == null);
    try std.testing.expect(arg_parser.start_more == null);
    try std.testing.expect(arg_parser.tags.items.len == 0);
    try std.testing.expect(arg_parser.target == null);
    try std.testing.expect(arg_parser.target_more == null);
    try std.testing.expect(arg_parser.target_less == null);
    globals.allocator.free(args);
}

test "parse: --limit 53" {
    var arg_parser = ArgumentParser{};
    arg_parser.init();
    defer arg_parser.init();

    const args = try globals.allocator.alloc([:0]u8, 2);
    args[0] = try globals.allocator.dupeZ(u8, "--limit");
    args[1] = try globals.allocator.dupeZ(u8, "53");

    try arg_parser.parse(args);

    try std.testing.expect(arg_parser.payload == null);
    try std.testing.expect(arg_parser.divisions == null);
    try std.testing.expect(arg_parser.duration == null);
    try std.testing.expect(arg_parser.duration_less == null);
    try std.testing.expect(arg_parser.duration_more == null);
    try std.testing.expect(arg_parser.end_less == null);
    try std.testing.expect(arg_parser.estimation == null);
    try std.testing.expect(arg_parser.remain_more == null);
    try std.testing.expect(arg_parser.remain_less == null);
    try std.testing.expect(arg_parser.excluded_tags.items.len == 0);
    try std.testing.expect(arg_parser.limit.? == 53);
    try std.testing.expect(arg_parser.name == null);
    try std.testing.expect(arg_parser.no_tags == false);
    try std.testing.expect(arg_parser.should_start == false);
    try std.testing.expect(arg_parser.start_less == null);
    try std.testing.expect(arg_parser.start_more == null);
    try std.testing.expect(arg_parser.tags.items.len == 0);
    try std.testing.expect(arg_parser.target == null);
    try std.testing.expect(arg_parser.target_more == null);
    try std.testing.expect(arg_parser.target_less == null);
    globals.allocator.free(args);
}

test "parse: coucou --no-tags" {
    var arg_parser = ArgumentParser{};
    arg_parser.init();
    defer arg_parser.init();

    const args = try globals.allocator.alloc([:0]u8, 2);
    args[0] = try globals.allocator.dupeZ(u8, "coucou");
    args[1] = try globals.allocator.dupeZ(u8, "--no-tags");

    try arg_parser.parse(args);

    try std.testing.expect(std.mem.eql(u8, arg_parser.payload.?, "coucou"));
    try std.testing.expect(arg_parser.divisions == null);
    try std.testing.expect(arg_parser.duration == null);
    try std.testing.expect(arg_parser.duration_less == null);
    try std.testing.expect(arg_parser.duration_more == null);
    try std.testing.expect(arg_parser.end_less == null);
    try std.testing.expect(arg_parser.estimation == null);
    try std.testing.expect(arg_parser.remain_more == null);
    try std.testing.expect(arg_parser.remain_less == null);
    try std.testing.expect(arg_parser.excluded_tags.items.len == 0);
    try std.testing.expect(arg_parser.limit == null);
    try std.testing.expect(arg_parser.name == null);
    try std.testing.expect(arg_parser.no_tags == true);
    try std.testing.expect(arg_parser.should_start == false);
    try std.testing.expect(arg_parser.start_less == null);
    try std.testing.expect(arg_parser.start_more == null);
    try std.testing.expect(arg_parser.tags.items.len == 0);
    try std.testing.expect(arg_parser.target == null);
    try std.testing.expect(arg_parser.target_more == null);
    try std.testing.expect(arg_parser.target_less == null);
    globals.allocator.free(args);
}

test "parse: --no-tags -a test" {
    var arg_parser = ArgumentParser{};
    arg_parser.init();
    defer arg_parser.init();

    const args = try globals.allocator.alloc([:0]u8, 3);
    args[0] = try globals.allocator.dupeZ(u8, "--no-tags");
    args[1] = try globals.allocator.dupeZ(u8, "-a");
    args[2] = try globals.allocator.dupeZ(u8, "test");

    try arg_parser.parse(args);

    try std.testing.expect(arg_parser.payload == null);
    try std.testing.expect(arg_parser.divisions == null);
    try std.testing.expect(arg_parser.duration == null);
    try std.testing.expect(arg_parser.duration_less == null);
    try std.testing.expect(arg_parser.duration_more == null);
    try std.testing.expect(arg_parser.end_less == null);
    try std.testing.expect(arg_parser.estimation == null);
    try std.testing.expect(arg_parser.remain_more == null);
    try std.testing.expect(arg_parser.remain_less == null);
    try std.testing.expect(arg_parser.excluded_tags.items.len == 0);
    try std.testing.expect(arg_parser.limit == null);
    try std.testing.expect(arg_parser.name == null);
    try std.testing.expect(arg_parser.no_tags == true);
    try std.testing.expect(arg_parser.should_start == false);
    try std.testing.expect(arg_parser.start_less == null);
    try std.testing.expect(arg_parser.start_more == null);
    try std.testing.expect(arg_parser.tags.items.len == 0);
    try std.testing.expect(arg_parser.target == null);
    try std.testing.expect(arg_parser.target_more == null);
    try std.testing.expect(arg_parser.target_less == null);
    globals.allocator.free(args);
}

// duration too big
// duration impossible to parse
// test both flags

// Tests to perform on the argument parser:

// - A test with a single type of argument for all the possible arguments
// - A test with everything
// - A test with contradicting flags
// - A test with several times the same flag

// try std.testing.expect(arg_parser.divisions.? == todo);
// try std.testing.expect(arg_parser.duration.? == todo);
// try std.testing.expect(arg_parser.duration_less.? == todo);
// try std.testing.expect(arg_parser.duration_more.? == todo);
// try std.testing.expect(arg_parser.end_less.? == todo);
// try std.testing.expect(arg_parser.estimation.? == todo);
// try std.testing.expect(arg_parser.remain_more.? == todo);
// try std.testing.expect(arg_parser.remain_less.? == todo);
// try std.testing.expect(arg_parser.excluded_tags.items.len == 0);
// try std.testing.expect(std.mem.eql(u8, arg_parser.name.?, todo));
// try std.testing.expect(arg_parser.no_tags == false);
// try std.testing.expect(arg_parser.should_start == false);
// try std.testing.expect(arg_parser.start_less.? == todo);
// try std.testing.expect(arg_parser.start_more.? == todo);
// try std.testing.expect(arg_parser.tags.items.len == 0);
// try std.testing.expect(arg_parser.target.? == todo);
// try std.testing.expect(arg_parser.target_more.? == todo);
// try std.testing.expect(arg_parser.target_less.? == todo);
