const std = @import("std");
const string_helper = @import("string_helper.zig");

// all the characters used in the base-62 encoding
const base62Characters = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

pub const Base62Error = error{
    TooBig,
    ContainsInvalidCharacters,
};

pub const IdError = error{
    InvalidTagName,
    InvalidTimerId,
    InvalidThingId,
    EmptyId,
};

/// ID for a tag, thing or timer
pub const Id = union(enum) {
    tag: []const u8,
    thing: u19,
    timer: struct {
        timer_part: u11,
        thing_part: u19,
    },
};

/// Parse an ID of undefined type
pub fn parseId(to_parse: []const u8) !Id {
    // Check that the ID to parse is not empty
    if (to_parse.len < 1) return IdError.EmptyId;

    // if we are parsing a tag name
    if (to_parse[0] == '#') {
        const tag_name = to_parse[1..];

        if (tag_name.len > std.math.maxInt(u6)) {
            return IdError.InvalidTagName;
        }

        if (!string_helper.isValidTagName(tag_name)) {
            return IdError.InvalidTagName;
        }

        return .{ .tag = tag_name };
    }

    var contains_at_sign: bool = false;
    for (to_parse) |c| {
        if (c == '@') {
            contains_at_sign = true;
            break;
        }
    }

    // if we are parsing a timer ID
    if (contains_at_sign) {
        var id_it = std.mem.splitSequence(u8, to_parse, "@");

        const str_timer_part = id_it.first();
        const str_thing_part = id_it.rest();
        var id_timer: Id = .{ .timer = .{ .timer_part = 0, .thing_part = 0 } };

        id_timer.timer.timer_part = std.fmt.parseInt(u11, str_timer_part, 10) catch |err| {
            switch (err) {
                error.Overflow => return IdError.InvalidTimerId,
                error.InvalidCharacter => return IdError.InvalidTimerId,
            }
        };
        id_timer.timer.thing_part = b62ToB10(str_thing_part) catch |err| {
            switch (err) {
                Base62Error.TooBig => return IdError.InvalidTimerId,
                Base62Error.ContainsInvalidCharacters => return IdError.InvalidTimerId,
            }
        };

        return id_timer;
    }

    // if we are parsing a thing ID
    if (b62ToB10(to_parse)) |id_thing| {
        return .{ .thing = id_thing };
    } else |_| {
        return IdError.InvalidThingId;
    }
}

/// Converts a decimal number into a base62 string
pub fn b10ToB62(buf: *[4]u8, input: u19) []const u8 {
    if (input == 0) {
        buf[0] = '0';
        return buf[0..1];
    }

    var varInput = input;
    var temp: [4]u8 = undefined;

    var idxMaxChar: u8 = 0;
    var remainder: u19 = undefined;

    // convert the input to base-62
    while (varInput > 0) {
        remainder = varInput % 62;
        temp[idxMaxChar] = base62Characters[remainder];
        varInput /= 62;
        idxMaxChar += 1;
    }

    // reverse the temp string into the output string
    for (temp, 0..) |character, index| {
        _ = character;
        if (index < idxMaxChar) {
            buf[index] = temp[idxMaxChar - index - 1];
        }
    }

    return buf[0..idxMaxChar];
}

/// Converts a base62 string into a decimal number
pub fn b62ToB10(input: []const u8) !u19 {
    var result: u19 = 0;

    if (input.len > 4) {
        return Base62Error.TooBig;
    }

    // a u19 cannot get over 2COF
    if (input.len == 4 and
        ((input[0] > '2') or
            (input[0] == '2' and input[1] > 'C') or
            (input[0] == '2' and input[1] == 'C' and input[2] > 'O') or
            (input[0] == '2' and input[1] == 'C' and input[2] == 'O' and input[3] > 'F')))
    {
        return Base62Error.TooBig;
    }

    for (input, 0..input.len) |char, index| {
        const power: u19 = @intCast(input.len - index - 1);
        const value = try getBase62Value(char);
        result += value * std.math.pow(u19, 62, power);
    }

    return result;
}

// TODO check if there not a more efficient way to do this.
// look-up table? hash map?
fn getBase62Value(char: u8) !u19 {
    if (char >= '0' and char <= '9') {
        return char - '0';
    } else if (char >= 'A' and char <= 'Z') {
        return (char - 'A') + 10;
    } else if (char >= 'a' and char <= 'z') {
        return (char - 'a') + 36;
    } else {
        return Base62Error.ContainsInvalidCharacters;
    }
}

test "b10ToB62: input 0" {
    var buf: [4]u8 = undefined;
    const res = b10ToB62(&buf, 0);
    try std.testing.expect(std.mem.eql(u8, res, "0"));
}

test "b10ToB62: input 8" {
    var buf: [4]u8 = undefined;
    const res = b10ToB62(&buf, 8);
    try std.testing.expect(std.mem.eql(u8, res, "8"));
}

test "b10ToB62: input 8000" {
    var buf: [4]u8 = undefined;
    const res = b10ToB62(&buf, 8000);
    try std.testing.expect(std.mem.eql(u8, res, "252"));
}

test "b10ToB62: input max value" {
    var buf: [4]u8 = undefined;
    const res = b10ToB62(&buf, 524287);
    try std.testing.expect(std.mem.eql(u8, res, "2COF"));
}

test "b62ToB10: input 0" {
    try std.testing.expect(try b62ToB10("0") == 0);
}

test "b62ToB10: input 1Cg" {
    try std.testing.expect(try b62ToB10("1Cg") == 4630);
}

test "b62ToB10: input 1d33" {
    try std.testing.expect(try b62ToB10("1d33") == 388433);
}

test "b62ToB10: input 3211" {
    try std.testing.expect(b62ToB10("3211") == Base62Error.TooBig);
}

test "b62ToB10: input 2CP1" {
    try std.testing.expect(b62ToB10("2CP1") == Base62Error.TooBig);
}

test "b62ToB10: input Z" {
    try std.testing.expect(try b62ToB10("Z") == 35);
}

test "b62ToB10: input Zf&" {
    try std.testing.expect(b62ToB10("Zf&") == Base62Error.ContainsInvalidCharacters);
}

/// Compare 2 Ids to make sure they are the same
fn compareIds(ac: Id, ex: Id) bool {
    switch (ac) {
        .tag => return std.mem.eql(u8, ac.tag, ex.tag),
        .thing => return ac.thing == ex.thing,
        .timer => return ((ac.timer.timer_part == ex.timer.timer_part) and
            (ac.timer.thing_part == ex.timer.thing_part)),
    }
}

test "parseId: ok tag" {
    const ac_id = try parseId("#test");
    const ex_id: Id = .{ .tag = "test" };
    try std.testing.expect(compareIds(ac_id, ex_id));
}

test "parseId: ok thing" {
    const ac_id = try parseId("iC3");
    const ex_id: Id = .{ .thing = 169883 };
    try std.testing.expect(compareIds(ac_id, ex_id));
}

test "parseId: ok timer" {
    const ac_id = try parseId("2040@iC3");
    const ex_id: Id = .{ .timer = .{ .thing_part = 169883, .timer_part = 2040 } };
    try std.testing.expect(compareIds(ac_id, ex_id));
}

test "parseId: empty id" {
    try std.testing.expect(parseId("") == IdError.EmptyId);
}

test "parseId: thing id too big" {
    try std.testing.expect(parseId("qwert") == IdError.InvalidThingId);
}

test "parseId: thing id contaning spaces" {
    try std.testing.expect(parseId("qw e") == IdError.InvalidThingId);
}

test "parseId: tag too long" {
    const res = parseId("#testtesttesttestesttesttesttesttesttesttesttesttesttesttesttestesttesttest");
    try std.testing.expect(res == IdError.InvalidTagName);
}

test "parseId: tag with invalid characters" {
    try std.testing.expect(parseId("#oihje7;") == IdError.InvalidTagName);
}

test "parseId: tag containing spaces" {
    try std.testing.expect(parseId("#tag name") == IdError.InvalidTagName);
}

test "parseTimer: timer part containing invalid characters" {
    try std.testing.expect(parseId("b@iC3") == IdError.InvalidTimerId);
}

test "parseId: timer containing spaces" {
    try std.testing.expect(parseId("4@th ing") == IdError.InvalidTimerId);
}

test "parseTimer: timer part too big" {
    try std.testing.expect(parseId("2049@iC3") == IdError.InvalidTimerId);
}

test "parseTimer: thing part too big" {
    try std.testing.expect(parseId("2040@2COG") == IdError.InvalidTimerId);
}
