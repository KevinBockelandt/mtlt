const std = @import("std");

// all the characters used in the base-62 encoding
const base62Characters = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

pub const Base62Error = error{
    InputStringTooBig,
};

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
        std.debug.print("Error cannot parse this b62 ID: {s}\n", .{input});
        return Base62Error.InputStringTooBig;
    }

    // a u19 cannot get over 2COF
    if (input.len == 4 and
        ((input[0] > '2') or
        (input[0] == '2' and input[1] > 'C') or
        (input[0] == '2' and input[1] == 'C' and input[2] > 'O') or
        (input[0] == '2' and input[1] == 'C' and input[2] == 'O' and input[3] > 'F')))
    {
        return Base62Error.InputStringTooBig;
    }

    for (input, 0..input.len) |char, index| {
        const power: u19 = @intCast(input.len - index - 1);
        const value = getBase62Value(char);
        result += value * std.math.pow(u19, 62, power);
    }

    return result;
}

// TODO check if there not a more efficient way to do this.
// look-up table? hash map?
fn getBase62Value(char: u8) u19 {
    if (char >= '0' and char <= '9') {
        return char - '0';
    } else if (char >= 'A' and char <= 'Z') {
        return (char - 'A') + 10;
    } else if (char >= 'a' and char <= 'z') {
        return (char - 'a') + 36;
    } else {
        @panic("Invalid base62 character");
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
    var buf = [1]u8{'0'};
    try std.testing.expect(try b62ToB10(&buf) == 0);
}

test "b62ToB10: input 1Cg" {
    var buf = [3]u8{ '1', 'C', 'g' };
    try std.testing.expect(try b62ToB10(&buf) == 4630);
}

test "b62ToB10: input 1d33" {
    var buf = [4]u8{ '1', 'd', '3', '3' };
    try std.testing.expect(try b62ToB10(&buf) == 388433);
}

test "b62ToB10: input 3211" {
    var buf = [4]u8{ '3', '2', '1', '1' };
    try std.testing.expect(b62ToB10(&buf) == Base62Error.InputStringTooBig);
}

test "b62ToB10: input 2CP1" {
    var buf = [4]u8{ '2', 'C', 'P', '1' };
    try std.testing.expect(b62ToB10(&buf) == Base62Error.InputStringTooBig);
}

test "b62ToB10: input Z" {
    var buf = [1]u8{'Z'};
    try std.testing.expect(try b62ToB10(&buf) == 35);
}
