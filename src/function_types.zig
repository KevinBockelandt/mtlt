const std = @import("std");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const ArgumentParser = @import("argument_parser.zig").ArgumentParser;

const AddTagToArrayList = fn (dt.Tag, *std.ArrayList(dt.Tag)) void;
const AddTagToSortToArrayList = fn (dt.Tag, *std.ArrayList(dt.TagToSort)) void;

pub const TagParsingCallbacks = union(enum) {
    AddTagToArrayList: struct {
        func: *const AddTagToArrayList,
        tag_array: *std.ArrayList(dt.Tag),
    },
    AddTagToSortToArrayList: struct {
        func: *const AddTagToSortToArrayList,
        tag_array: *std.ArrayList(dt.TagToSort),
    },
};

const AddThingToArrayList = fn (dt.Thing, *std.ArrayList(dt.Thing)) void;
const AddThingToSortToArrayList = fn (dt.Thing, *std.ArrayList(dt.ThingToSort)) void;
const CheckThingForTagAssociation = fn (dt.Thing, u16, *u24, *u24) void;
const GetPosThingAssociatedToTag = fn (dt.Thing, u16, *std.ArrayList(usize), usize) void;

pub const ThingParsingCallbacks = union(enum) {
    AddThingToSortToArrayList: struct {
        func: *const AddThingToSortToArrayList,
        thing_array: *std.ArrayList(dt.ThingToSort),
    },
    AddThingToArrayList: struct {
        func: *const AddThingToArrayList,
        thing_array: *std.ArrayList(dt.Thing),
    },
    CheckThingForTagAssociation: struct {
        func: *const CheckThingForTagAssociation,
        tag_id: u16,
        num_open: *u24,
        num_closed: *u24,
    },
    GetPosThingAssociatedToTag: struct {
        func: *const GetPosThingAssociatedToTag,
        tag_id: u16,
        pos_array: *std.ArrayList(usize),
    },
};
